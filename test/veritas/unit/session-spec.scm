;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux session).  The list is what every compositor
;; starts, so the tests ask it the questions both sessions rely on: the
;; desktop's own programs are there once, the dock starts under its lock, the
;; password manager follows its setting, and the agent appears only where no
;; user manager starts it.  What reads a compositor's own protocol stays out.

;;; Code:

(define-module (veritas unit session-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux session)
  #:use-module (heks-linux services)
  #:use-module (heks-linux ssh)
  #:use-module (heks-linux user-settings)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (command-starting-with prefix)
  "Return the session command that starts with @var{prefix}, or @code{#f}."
  (find (lambda (command) (string-prefix? prefix command))
        (session-startup-programs)))

(define (command-starts-with? prefix)
  "Whether a session command starts with @var{prefix}."
  (not (eq? #f (command-starting-with prefix))))

(define (shell-parses? line)
  "Return @code{#t} when @var{line} parses as the shell that runs it.

Every startup entry is handed to @code{sh -c} by the compositor, and the line is
built by putting other people's words inside quotes: the welcome message is one
quoted argument per sentence, so a wrapper that forgot to escape a quote is a
login that prints a shell error instead of a greeting."
  (let ((path (format #f "/tmp/heks-session-spec-~a.sh" (getpid))))
    (call-with-output-file path (lambda (port) (display line port)))
    (zero? (status:exit-val (system* "sh" "-n" path)))))

(define (command-containing fragment)
  "Return the session command that contains @var{fragment}, or @code{#f}."
  (find (lambda (command) (not (eq? #f (string-contains command fragment))))
        (session-startup-programs)))

(define (command-count fragment)
  "Return how many session commands contain @var{fragment}."
  (count (lambda (command) (not (eq? #f (string-contains command fragment))))
         (session-startup-programs)))

(define session-suite
  (suite "Session Startup"
    (test "The Desktop Starts Once In Every Session"
      ;; One command that picks the shell rather than two that race: whelk when
      ;; the machine has it, Waybar when it does not, and never both.
      (assert-equal #:expect 1
        #:got (command-count "exec whelk")
        #:name "The shell is on the list once")
      (assert-equal #:expect 1
        #:got (command-count "exec waybar")
        #:name "With the bar both distributions carry behind it")
      (assert-true (command-starts-with? "sh -c 'if command -v whelk")
        #:name "And the choice is made at login, not when the file was written")
      (assert-true (command-starts-with? "xdg-user-dirs-update")
        #:name "The user directories are made once per session")
      (assert-true (command-starts-with?
                    "bash ~/.local/bin/write-gtk-dconf-settings")
        #:name "The dconf writer is shared"))

    (test "A Startup Runs Only When Its Program Is Here"
      ;; The list used to be the author's machine written into everybody's:
      ;; Cloudflare's client, a container service, a password manager, all
      ;; started unconditionally, so a machine without them logged an error at
      ;; every login.  Every optional line now asks the PATH first.
      (assert-true (not (eq? #f (command-containing "command -v emacs")))
        #:name "The editor daemon is asked for before it is started")
      (assert-true (not (eq? #f (command-containing "command -v podman")))
        #:name "So is the container service")
      (assert-equal #:expect #f
        #:got (command-containing "warp")
        #:name "And one person's VPN client is nobody's default")
      (assert-equal #:expect #f
        #:got (command-containing "sudo ")
        #:name "Nothing in the session's startup list asks for a password")
      ;; A machine adds its own programs by replacing the list, not by editing
      ;; this tree: one parameter, and the line that starts it stays conditional.
      (assert-true (not (eq? #f (parameterize ((heks-linux-session-startups
                                                '("my-thing --flag")))
                                  (command-containing
                                   "command -v my-thing >/dev/null 2>&1 && exec my-thing --flag"))))
        #:name "A machine's own startup is one line in its settings"))

    (test "Every Startup Line Is A Command The Shell Can Parse"
      ;; A wrapped line is quotes inside quotes, and the one entry that carries
      ;; its own single-quoted words - the welcome message - is what makes the
      ;; escaping worth a test: an unescaped apostrophe there is a greeting that
      ;; never appears and a shell error on the console instead.
      (assert-equal #:expect '()
        #:got (remove shell-parses? (session-startup-programs))
        #:name "The compositor hands each line to sh -c: each one has to parse")
      (assert-true (not (eq? #f (command-containing "'\\''")))
        #:name "The welcome message's quotes are escaped for the wrapper, not dropped"))

    (test "The Portal Answers With A Back End That Works Under Niri"
      ;; GNOME's portal back end is written for a GNOME session and segfaults on
      ;; the first question under Niri on Debian 13, taking every client waiting
      ;; on it with it.  The choice is a file, and this is its content.
      (assert-true (not (eq? #f (string-contains (session-portals-conf)
                                                 "default=gtk")))
        #:name "GTK's back end is the default: it wants a portal host, not a desktop")
      (assert-true (not (eq? #f (string-contains (session-portals-conf)
                                                 "Secret=gnome-keyring")))
        #:name "The secret service is the one a session with no GNOME still has")
      (assert-equal #:expect "niri-portals.conf"
        #:got (session-portals-filename)
        #:name "And the portal reads it under the session's own name"))

    (test "The Session's PATH Reaches What This Tree Installs"
      ;; A bar item that runs `~/.local/bin/heks-system-menu` answers "no such
      ;; file" when the session's PATH does not carry that directory - which is
      ;; what a Debian login hands the session: the distribution's PATH and
      ;; nothing else.
      (assert-true (not (eq? #f (string-contains (session-path-conf)
                                                 "PATH=${HOME}/.local/bin")))
        #:name "The programs this tree installs are on the session's PATH")
      (assert-true (not (eq? #f (string-contains (session-path-conf)
                                                 "${HOME}/.cargo/bin")))
        #:name "And so is what a person installs with cargo")
      (assert-equal #:expect "10-heks-path.conf"
        #:got (session-path-filename)
        #:name "Read from environment.d, where the manager and the session both look"))

    (test "The Dock Starts Under Its Session Lock"
      (let ((start (session-dock-command)))
        (assert-true (not (eq? #f (string-contains start "flock -n ")))
          #:name "A reload must not draw a second dock")
        (assert-true (not (eq? #f (string-contains start "lambdock-session.lock")))
          #:name "The lock is the session's own")
        (assert-true (not (eq? #f (string-contains start " lambdock")))
          #:name "The dock is what the lock guards"))
      (assert-true (not (eq? #f (string-contains (session-dock-command #:wait #t)
                                                 "flock -w 2 ")))
        #:name "A restart queues for the lock the dead dock still holds")
      (assert-equal #:expect #f
        #:got (member "lambdock" (session-startup-programs))
        #:name "The bare dock command is never on the list"))

    (test "A Session Can Ask For No Dock At All"
      ;; The stacking session's bar is a taskbar with the windows on it, so a
      ;; dock beside it is a second place to click the same window.  The dock is
      ;; a keyword on the list rather than a filter at the caller, so a session
      ;; says what it wants and the list stays the one description of a
      ;; desktop.
      (assert-equal #:expect 0
        #:got (count (lambda (command)
                       (and (string? command)
                         (not (eq? #f (string-contains command "lambdock")))))
                     (session-startup-programs #:dock? #f))
        #:name "No command on the list starts the dock")
      (assert-equal #:expect 1
        #:got (count (lambda (command)
                       (and (string? command)
                         (not (eq? #f (string-contains command "lambdock")))))
                     (session-startup-programs))
        #:name "And every other session keeps it"))

    (test "The Password Manager Follows Its Setting"
      (assert-equal #:expect "keepassxc --minimized"
        #:got (parameterize ((heks-linux-password-command "keepassxc")
                             (heks-linux-password-startup-args "--minimized"))
                (session-password-startup))
        #:name "Another manager and its own quiet flag should come through")
      (assert-equal #:expect "keepassxc"
        #:got (parameterize ((heks-linux-password-command "keepassxc")
                             (heks-linux-password-startup-args ""))
                (session-password-startup))
        #:name "A manager with no quiet start should start plainly")
      (assert-true (not (eq? #f (command-containing
                                 (format #f "exec ~a" (heks-linux-password-command)))))
        #:name "The list starts the manager the bar's key glyph opens"))

    (test "The Agent Is The Session's Only Without A User Manager"
      (assert-true (not (eq? #f
                             (member (ssh-agent-session-command)
                                     (session-startup-programs))))
        #:name "Runit has no user manager, so the session starts the agent")
      (assert-equal #:expect (ssh-agent-session-socket)
        #:got (assoc-ref (session-environment) "SSH_AUTH_SOCK")
        #:name "and names the socket the agent listens on")
      (assert-equal #:expect #f
        #:got (parameterize ((init-system 'systemd))
                (member (ssh-agent-session-command)
                        (session-startup-programs)))
        #:name "Systemd's user manager starts it instead")
      (assert-equal #:expect #f
        #:got (parameterize ((init-system 'systemd))
                (assoc-ref (session-environment) "SSH_AUTH_SOCK"))
        #:name "and environment.d exports the socket"))

    (test "A Compositor's Own Programs Stay With It"
      (assert-equal #:expect 0
        #:got (command-count "heks-window-notify")
        #:name "Niri's event watcher is not a desktop program")
      ;; Niri starts xwayland-satellite itself since 25.08, exports DISPLAY for
      ;; the session, and restarts the satellite when it dies.  A second copy
      ;; from the startup list races that one, and the copy niri did not start
      ;; leaves DISPLAY unset - so Rofi under Niri would be an X11 client with no
      ;; server after all.
      (assert-equal #:expect 0
        #:got (command-count "xwayland-satellite")
        #:name "The satellite is the compositor's to start, not the session's"))))

(define (spec)
  ;; The session's shape follows the init system, so the suite pins the one the
  ;; target runs; see (veritas unit services-spec) for why.
  (parameterize ((init-system 'runit))
    (veritas-run session-suite)))
