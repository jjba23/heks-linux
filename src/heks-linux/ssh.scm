;;; heks-linux

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; heks-linux is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; heks-linux is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with heks-linux.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; The SSH client side, rendered from this repository instead of hand-edited in
;; @file{~/.ssh}:
;;
;; - @file{~/.ssh/config} - one @code{Host} block per machine, plus
;;   @code{AddKeysToAgent yes}.  That one option is what turns a
;;   passphrase-protected key into a single prompt: the first connection that
;;   uses the key hands it to the agent, and every later connection reuses it.
;; - @file{~/.config/environment.d/10-ssh-agent.conf} - @env{SSH_AUTH_SOCK} for
;;   every process the systemd user session starts.  Without it a terminal
;;   inherits whatever socket the process that started it had, and a terminal
;;   that outlives its parent keeps pointing at an agent that is gone -- which
;;   looks exactly like "the passphrase is asked again".
;; - @file{~/.config/systemd/user/ssh-agent.service} - only where the machine
;;   does not already ship @code{gcr-ssh-agent.socket}.  openSUSE does: that
;;   agent keeps the decrypted keys in the login keyring, so the passphrase is
;;   asked once ever rather than once per session.
;;
;; The hosts are data.  Add one to @code{ssh-hosts} and run
;; @code{maak install-ssh}; override them per machine in
;; @file{$XDG_CONFIG_HOME/heks-linux/ssh-settings.scm} (the same override file
;; every other surface reads) when a key or a host name differs.
;;
;; The installer never creates a key: it reports the ones an identity file
;; names but that do not exist, with the @code{ssh-keygen} line to make them,
;; because a silently missing key is what a first push failing looks like.

;;; Code:

(define-module (heks-linux ssh)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (srfi srfi-1)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (ssh-hosts
            ssh-config
            ssh-agent-provider
            ssh-agent-socket
            ssh-agent-unit
            ssh-agent-environment
            ssh-agent-service
            ssh-config-dir
            ssh-config-filename
            ssh-agent-environment-dir
            ssh-agent-environment-filename
            ssh-agent-service-dir
            ssh-agent-service-filename
            gcr-ssh-agent-available?
            install-ssh-config
            install-ssh!))

(define s
  (scriba-auto-logger))

(define %home-dir
  (or (getenv "HOME") "/tmp"))

;; XDG_CONFIG_HOME wins when it is set and not empty, the way the rest of the
;; tree resolves config directories.
(define %config-dir
  (let ((xdg (getenv "XDG_CONFIG_HOME")))
    (if (and xdg (not (string-null? xdg)))
        xdg
        (string-append %home-dir "/.config"))))

;; ====== Where the files go ======

(define ssh-config-dir
  (make-parameter (string-append %home-dir "/.ssh")))

(define ssh-config-filename
  (make-parameter "config"))

(define ssh-agent-environment-dir
  (make-parameter (string-append %config-dir "/environment.d")))

;; The @code{10-} prefix matters: environment.d files are read in name order and
;; this one only sets a variable, so it has to land before anything that reads
;; it.
(define ssh-agent-environment-filename
  (make-parameter "10-ssh-agent.conf"))

(define ssh-agent-service-dir
  (make-parameter (string-append %config-dir "/systemd/user")))

(define ssh-agent-service-filename
  (make-parameter "ssh-agent.service"))

;; ====== The agent ======

(define (gcr-ssh-agent-available?)
  "Whether this machine ships the keyring-backed SSH agent.

openSUSE (through GNOME's keyring) provides @code{gcr-ssh-agent.socket}, which
stores the decrypted key in the login keyring.  That is the difference between
being asked for the passphrase once ever and once per session, so it is used
whenever it exists rather than replaced."
  (file-exists? "/usr/lib/systemd/user/gcr-ssh-agent.socket"))

;; @code{'gcr} or @code{'agent}.  A parameter so a machine can pin the choice in
;; @file{ssh-settings.scm} - and so the plain-agent path stays renderable (and
;; testable) on a machine that has the keyring one.
(define ssh-agent-provider
  (make-parameter (if (gcr-ssh-agent-available?) 'gcr 'agent)))

(define (ssh-agent-unit)
  "Return the systemd unit that provides the agent on this machine."
  (if (eq? (ssh-agent-provider) 'gcr)
      "gcr-ssh-agent.socket"
      "ssh-agent.service"))

;; ${XDG_RUNTIME_DIR} is expanded by systemd-environment-d-generator when the
;; file is read at login, so the same content works for any user or runtime
;; directory.
(define (ssh-agent-socket)
  "Return the socket every process in the session should look for."
  (if (eq? (ssh-agent-provider) 'gcr)
      "${XDG_RUNTIME_DIR}/gcr/ssh"
      "${XDG_RUNTIME_DIR}/ssh-agent.socket"))

;; ====== The hosts ======

;; Each entry is a flat plist of ssh_config keywords and values, written in the
;; order given; @code{Port} is only present where it is not 22.
;;
;; @code{IdentitiesOnly yes} on the two shared hosts keeps the agent from
;; offering a dozen keys before the right one: GitHub gives up after six.
(define ssh-hosts
  (make-parameter
   '(("Host" "personal.github.com"
      "HostName" "github.com"
      "User" "git"
      "IdentityFile" "~/.ssh/personal_github"
      "IdentitiesOnly" "yes")

     ("Host" "codeberg.org"
      "HostName" "codeberg.org"
      "User" "git"
      "IdentityFile" "~/.ssh/gitlab_prive"
      "IdentitiesOnly" "yes")

     ("Host" "wolk-jjba"
      "HostName" "178.105.172.226"
      "User" "joe"
      "Port" "2323"
      "IdentityFile" "~/.ssh/wolk_id")

     ("Host" "wolkenschlosslagerung"
      "HostName" "u600604.your-storagebox.de"
      "User" "u600604"
      "Port" "23"
      "IdentityFile" "~/.ssh/wolk_id"))))

;; The one global option that removes the repeated passphrase prompt.
(define ssh-global-options
  '(("AddKeysToAgent" . "yes")))

(define ssh-header-lines
  (list "# Generated by heks-linux - `maak install-ssh' rewrites this file."
        "# Edit src/heks-linux/ssh.scm, or ~/.config/heks-linux/ssh-settings.scm."
        ""))

(define (plist->pairs items)
  "Split @var{items} into @code{(key . value)} pairs.

The host table above is written flat because that is how an ssh config reads;
this is the one place that shape is turned back into pairs."
  (cond ((null? items) '())
        ((null? (cdr items))
         (error "ssh host entry with an odd number of fields" items))
        (else (cons (cons (car items) (cadr items))
                    (plist->pairs (cddr items))))))

(define (ssh-host-lines host)
  "Return the lines of one @code{Host} block.

@code{Host} and @code{Match} start in the first column, the options under them
are indented: both are accepted by ssh(1), but only one of them is what the
manual page shows and what everyone reads."
  (map (lambda (pair)
         (let ((keyword (car pair))
               (value (cdr pair)))
           (if (member keyword '("Host" "Match"))
               (format #f "~a ~a" keyword value)
               (format #f "     ~a ~a" keyword value))))
       (plist->pairs host)))

(define (ssh-config)
  "Return the whole @file{~/.ssh/config} as a string."
  (mk-lines
   (append ssh-header-lines
           (map (lambda (option)
                  (format #f "~a ~a" (car option) (cdr option)))
                ssh-global-options)
           (append-map (lambda (host)
                         (cons "" (ssh-host-lines host)))
                       (ssh-hosts)))))

(define (ssh-agent-environment)
  "Return the @file{environment.d} file that points a session at the agent."
  (mk-lines
   (list "# Generated by heks-linux - `maak install-ssh' rewrites this file."
         "#"
         "# Every process the systemd user session starts reads this, so a"
         "# terminal cannot inherit the socket of an agent that already died."
         (format #f "SSH_AUTH_SOCK=~a" (ssh-agent-socket)))))

(define (ssh-agent-service)
  "Return a plain @code{ssh-agent} user service, for machines without gcr."
  (mk-lines
   (list "[Unit]"
         "Description=SSH key agent"
         "Documentation=man:ssh-agent(1)"
         ""
         "[Service]"
         "Type=simple"
         "Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket"
         ;; /usr/bin/env rather than a path, because the agent comes from the
         ;; profile on some machines and from /usr/bin on others.
         "ExecStart=/usr/bin/env ssh-agent -D -a %t/ssh-agent.socket"
         ""
         "[Install]"
         "WantedBy=default.target")))

;; ====== Keys the config names ======

(define (expand-home path)
  "Expand a leading @code{~} in @var{path} to the home directory.

@code{file-exists?} does no such expansion, and a key that is named but missing
is the failure this check exists to report."
  (if (string-prefix? "~/" path)
      (string-append %home-dir (substring path 1))
      path))

(define (warn-about-missing-keys)
  "Report every @code{IdentityFile} in the config that does not exist.

The message names the command that makes the key, because that is the next
thing to type and a missing key otherwise shows up as a permission denied from
a host three layers away."
  (for-each
   (lambda (host)
     (let* ((pairs (plist->pairs host))
            (name (assoc-ref pairs "Host"))
            (identity (assoc-ref pairs "IdentityFile")))
       (when (and identity (not (file-exists? (expand-home identity))))
         (log-warning s "~a names ~a, which does not exist"
                      name identity)
         (log-info s "  make it with: ssh-keygen -t ed25519 -f ~a"
                   (expand-home identity)))))
   (ssh-hosts)))

;; ====== Installing ======

(define (install-ssh-config)
  "Write the SSH config, the agent environment and the agent unit.

Nothing is started here: @code{install-ssh!} does the @code{systemctl} part, so
that a plain render (what @code{maak home-reconfigure} does) stays a file write.

Machine overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/ssh-settings.scm} first."
  (log-info s "Installing SSH configuration")
  (load-local-overrides '(heks-linux ssh) 'ssh-settings)

  ;; ~/.ssh itself: 0700, because it holds identities.  `ensure-directory-tree!'
  ;; makes it with the umask otherwise, which is 0755 on most systems.
  (ensure-directory-tree! (ssh-config-dir))
  (chmod (ssh-config-dir) #o700)

  (install-config-file! #:name (ssh-config-filename)
                        #:dir (ssh-config-dir)
                        #:contents (ssh-config)
                        ;; 0600: the file names every identity on the machine.
                        #:perms 384)

  (install-config-file! #:name (ssh-agent-environment-filename)
                        #:dir (ssh-agent-environment-dir)
                        #:contents (ssh-agent-environment))

  (if (eq? (ssh-agent-provider) 'gcr)
      (log-info s "Using the keyring agent: gcr-ssh-agent.socket")
      (begin
        (log-info s "No gcr agent here, writing ssh-agent.service")
        (install-config-file! #:name (ssh-agent-service-filename)
                              #:dir (ssh-agent-service-dir)
                              #:contents (ssh-agent-service))))

  (warn-about-missing-keys))

(define (run-command . args)
  "Run @var{args} as a program and warn, rather than raise, on a failure.

Enabling an agent is not worth failing a reconfigure over: the config and the
environment file are already written, and the machine still has ssh."
  (log-info s "Running: ~{~a~^ ~}" args)
  (let ((status (apply system* args)))
    (unless (zero? status)
      (log-warning s "~a exited with status ~a" (car args) status))
    status))

(define (install-ssh!)
  "Install the SSH configuration and make sure the agent is enabled.

This is what @code{maak install-ssh} calls: the render, then
@code{systemctl --user daemon-reload} and @code{enable --now} on whichever agent
the machine has.  Both calls are idempotent, so re-running the task after
editing a host changes only what changed."
  (install-ssh-config)
  (run-command "systemctl" "--user" "daemon-reload")
  (run-command "systemctl" "--user" "enable" "--now" (ssh-agent-unit)))
