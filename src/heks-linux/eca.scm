;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; ECA in the terminal, from the configuration the editor already uses.
;;
;; heks-emacs drives ECA (Editor Code Assistant) from Emacs: a chat that reads
;; and edits the project and asks before it writes.  ECA is a server with many
;; clients, and every client speaks the same protocol and reads the same global
;; configuration, so the terminal client - @command{eca-cli} - is the same
;; assistant in the same project, rendered in the terminal instead of in a
;; buffer.
;;
;; Two things are needed for that, and neither is packaged by openSUSE or by
;; nixpkgs:
;;
;; - @file{~/.config/eca/config.json} - the providers and their models,
;;   rendered here so the terminal and Emacs cannot disagree about them.  The
;;   DeepSeek account is the personal one and its key is not in this file: the
;;   file holds the @code{${cmd:...}} that decrypts the key when a request is
;;   made.  GitHub Copilot needs no entry at all - ECA knows the provider and
;;   keeps its own login - which is why a machine at work needs no key here.
;; - @command{eca-cli} - the terminal client, one self-contained binary from
;;   the project's releases, installed at a pinned version into
;;   @file{~/.local/bin}.  It downloads and keeps its own ECA server, so the
;;   server heks-emacs starts is not a prerequisite for the terminal, and both
;;   read the same @file{config.json}.
;;
;; @code{maak install-eca} renders the config and installs the client; a home
;; reconfigure renders the config with the rest of the dotfiles, and leaves the
;; client alone because installing it downloads 26 MB.

;;; Code:

(define-module (heks-linux eca)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (eca-config-dir
            eca-config-filename
            eca-deepseek-api-url
            eca-deepseek-key-command
            eca-deepseek-models
            eca-cli-version
            eca-cli-dir
            eca-cli-filename
            eca-config
            eca-serialize-config
            eca-cli-asset
            eca-cli-asset-name
            eca-cli-url
            eca-cli-current?
            install-eca-config
            install-eca-cli
            install-eca))

(define s
  (scriba-auto-logger))

;; --- Where the two halves live ---

(define eca-config-dir
  (make-parameter (format #f "~a/.config/eca"
                          (or (getenv "HOME") "/tmp"))))

(define eca-config-filename
  (make-parameter "config.json"))

(define eca-cli-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define eca-cli-filename
  (make-parameter "eca-cli"))

;; --- The configuration both clients read ---

;; The personal account: a DeepSeek key, kept out of this file and out of the
;; repository.  `openai-chat' is DeepSeek's own API as ECA speaks it.
(define eca-deepseek-api-url
  (make-parameter "https://api.deepseek.com"))

;; The key is decrypted per request, the same file heks-emacs reads.  ECA
;; resolves `${cmd:...}' itself, so nothing here holds a secret and a
;; reconfigure never asks for a passphrase.
(define eca-deepseek-key-command
  (make-parameter
   "${cmd:gpg --batch -q -d $HOME/.config/heks/deepseek.key.gpg}"))

;; The models this account offers, in the order ECA lists them.  `deepseek-flash'
;; is the general model and `deepseek-v4-pro' the stronger one; heks-emacs names
;; the same two.
(define eca-deepseek-models
  (make-parameter '("deepseek-flash" "deepseek-v4-pro")))

(define (eca-config)
  "Return the ECA configuration as a Scheme association list.

The file is the global one: the terminal client and the Emacs client read it,
so a provider added or a model renamed reaches both.  An empty model option,
@code{'()}, is what guile-json renders as @code{\"{}\"}, which is what ECA
expects for a model that takes its defaults.

@example
(scm->json-string (eca-config) #:pretty #t)
@end example"
  (list (cons "providers"
              (list (cons "deepseek"
                          (list (cons "api" "openai-chat")
                                (cons "url" (eca-deepseek-api-url))
                                (cons "key" (eca-deepseek-key-command))
                                (cons "models"
                                      (map (lambda (model)
                                             (cons model '()))
                                           (eca-deepseek-models)))))))))

(define (eca-serialize-config)
  "Return the ECA configuration as the JSON text of @file{config.json}."
  (string-append (scm->json-string (eca-config)
                                   #:pretty #t)
                 "\n"))

;; --- The terminal client ---

;; The release the installer puts on disk.  It is pinned rather than taken from
;; `latest' so that two machines that ran the task hold the same client, and the
;; binary keeps its own ECA server current on its own.
(define eca-cli-version
  (make-parameter "0.1.107"))

(define (eca-cli-machine)
  "Return this machine's architecture as @command{uname -m} spells it."
  (string-trim-both (or (syscall "uname -m" #:silent? #t) "")))

(define (eca-cli-asset machine)
  "Return the ECA release asset for @var{machine}, as @command{uname} names it.

The releases are cut for the two architectures the desktop runs on, and the
asset name is the only thing about them that depends on the machine.

@example
(eca-cli-asset \"x86_64\")
@result{} \"eca-cli-linux-amd64.tar.gz\"
@end example"
  (format #f "eca-cli-linux-~a.tar.gz"
          (cond
            [(member machine '("x86_64" "amd64")) "amd64"]
            [(member machine '("aarch64" "arm64")) "aarch64"]
            [else (error "eca-cli-asset: unsupported machine:" machine)])))

(define (eca-cli-asset-name)
  "Return the ECA release asset this machine installs."
  (eca-cli-asset (eca-cli-machine)))

(define (eca-cli-url)
  "Return the download URL of the pinned @command{eca-cli} release.

@example
(eca-cli-url)
@end example"
  (format #f
          "https://github.com/editor-code-assistant/eca-cli/releases/download/~a/~a"
          (eca-cli-version) (eca-cli-asset-name)))

(define (eca-cli-binary)
  "Return the path the terminal client is installed at."
  (format #f "~a/~a" (eca-cli-dir) (eca-cli-filename)))

(define (eca-cli-run args)
  "Run @var{args}, reporting the command line, and return @code{#t} on success."
  (format #t "\nExecuting command: ~a\n"
          (string-join args " "))
  (let ((status (apply system* args)))
    (cond
      [(eq? status #f)
       (format (current-error-port) "could not execute ~a\n"
               (string-join args " ")) #f]
      [(zero? status)
       #t]
      [else (format (current-error-port) "~a exited with status ~a\n"
                    (car args) status) #f])))

(define (eca-cli-current?)
  "Return @code{#t} when the installed client already reports the pinned version.

An installed client is asked for its version instead of being downloaded again:
the download is 26 MB, and this answers the same question about a binary the
machine may have installed another way."
  (let ((binary (eca-cli-binary)))
    (and (file-exists? binary)
      (let ((reported (syscall (format #f "~a --version" binary)
                               #:silent? #t)))
        (and reported
          (not (eq? #f (string-contains reported (eca-cli-version))))
          #t)))))

;; --- Installing ---

(define (install-eca-config)
  "Write @file{config.json} to @code{eca-config-dir}.

Local overrides come from @code{$XDG_CONFIG_HOME/heks-linux/eca-settings.scm},
which is where a machine points the key command at its own key or adds a model.
The file is readable by its owner only: it names no secret, but which provider a
machine pays for is nobody else's business."
  (log-info s "Installing ECA configuration")
  (load-local-overrides '(heks-linux eca) 'eca-settings)
  (install-config-file! #:name (eca-config-filename)
                        #:dir (eca-config-dir)
                        #:contents (eca-serialize-config)
                        #:perms 384)
  (log-success s "Installed ECA configuration"))

(define (install-eca-cli)
  "Install @command{eca-cli} at the pinned version into @code{eca-cli-dir}.

The tarball holds one binary, which is moved into place with mode #o755 and the
download removed: nothing of the release is kept beside it, because the client
keeps its own server under @file{~/.cache/eca}."
  (load-local-overrides '(heks-linux eca) 'eca-settings)
  (let* ((work (format #f "~a/heks-eca-~a"
                       (or (getenv "TMPDIR") "/tmp") (getpid)))
         (tarball (format #f "~a/~a" work (eca-cli-asset-name)))
         (extracted (format #f "~a/eca-cli" work)))
    (cond
      [(eca-cli-current?)
       (log-info s "eca-cli ~a is already installed" (eca-cli-version))]
      [else
        (log-info s "Installing eca-cli ~a" (eca-cli-version))
        (ensure-directory-tree! (eca-cli-dir))
        (ensure-directory-tree! work)
        (unless (and (eca-cli-run (list "curl" "-fsSL" "-o" tarball (eca-cli-url)))
                  (eca-cli-run (list "tar" "-xzf" tarball "-C" work))
                  (eca-cli-run (list "install" "-m" "755" extracted
                                     (eca-cli-binary))))
          (when (file-exists? extracted)
            (delete-file extracted))
          (when (file-exists? tarball)
            (delete-file tarball))
          (rmdir work)
          (error "install-eca-cli: could not install eca-cli"
                 (eca-cli-version)))
        (delete-file extracted)
        (delete-file tarball)
        (rmdir work)
        (log-success s "Installed eca-cli ~a" (eca-cli-version))])))

(define (install-eca)
  "Install ECA for the terminal: the shared configuration and the client.

Rendering the configuration is the part a home reconfigure also does; the client
is installed here and only here, because it is a download a reconfigure should
not repeat."
  (install-eca-config)
  (install-eca-cli))
