;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Renders the Git configuration ecosystem in your home directory:
;;
;; - @file{~/.gitconfig} - shared settings plus the @code{includeIf} rules that
;;   switch identity based on the directory a repository lives in.
;; - @file{~/.gitconfig-personal.ini} and @file{~/.gitconfig-work.ini} - the two
;;   identities (name, e-mail, signing key).
;; - @file{~/.gitignore-global} - editor and build artefacts ignored everywhere.
;;
;; The interesting part is the @code{includeIf} mechanism: rather than guessing
;; who you are, Git picks the identity from the path.  Add a clause here when you
;; start keeping repositories somewhere new, e.g. a @file{~/Fork/} checkout.
;;
;; Note that the generated @file{.gitconfig} uses ~a = ~a~ formatting so the
;; @code{includeIf "gitdir:..."} keys can carry their leading whitespace, which
;; is what Git expects.

;;; Code:

(define-module (heks-linux git)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (gitignore-global gitconfig-personal
                             gitconfig-work
                             gitconfig
                             install-git-config
                             git-config-dir
                             gitconfig-filename
                             gitconfig-personal-filename
                             gitconfig-work-filename
                             gitignore-global-filename))

(define s
  (scriba-auto-logger))

;; Patterns ignored in every repository on the machine, regardless of the
;; repository's own @file{.gitignore}.  Mostly editor droppings and build output
;; from the languages used here (Scala/Metals, Haskell, Rust, devenv).
(define gitignore-global
  `("bloop" ".bloop"
    ".metals"
    ".stack-work"
    "target"
    "metals.sbt"
    ".direnv"
    "dist-newstyle"))

;; Identity used for every repository under @file{~/Hacking/}, @file{~/Fork/}
;; and @file{~/Scratch/}.  Override it in your own
;; @code{$XDG_CONFIG_HOME/heks-linux/git-settings.scm} - this module is the one
;; place in the tree where personal data is meaningfully hardcoded, and that is
;; what the override mechanism exists for.
(define gitconfig-personal
  `((user (name . "Josep Bigorra")
          (email . "jjbigorra@gmail.com")
          (signingkey . "24F46738CE114AF6"))))

;; Identity used for repositories under @file{~/Work/}.
(define gitconfig-work
  `((user (name . "Josep Bigorra")
          (email . "josepbigorraalgaba@vandebron.nl")
          (signingkey . "3B6D20502E380697"))))

(define gitconfig
  `((core (editor . "emacsclient")
          (excludesfile . "~/.gitignore-global"))
    (commit (gpgsign . "true"))
    (format (thread . "shallow"))
    (sendemail (thread . "no"))
    (pull (rebase . "false"))
    ("includeIf \"gitdir:~/Work/\"" ("  path" . "~/.gitconfig-work.ini"))
    ("includeIf \"gitdir:~/Hacking/\""
     ("  path" . "~/.gitconfig-personal.ini"))
    ("includeIf \"gitdir:~/Fork/\"" ("  path" . "~/.gitconfig-personal.ini"))
    ("includeIf \"gitdir:~/Scratch/\""
     ("  path" . "~/.gitconfig-personal.ini"))))

;; Git looks for these files in @file{$HOME}, so this defaults to your home
;; directory rather than to @file{~/.config}.
(define git-config-dir
  (make-parameter (format #f "~a"
                          (or (getenv "HOME") "/tmp"))))

;; Main configuration file; Git only reads this exact name.
(define gitconfig-filename
  (make-parameter ".gitconfig"))

;; Personal identity, pulled in by the @code{includeIf} rule for ~~/Hacking/~ etc.
(define gitconfig-personal-filename
  (make-parameter ".gitconfig-personal.ini"))

;; Work identity, pulled in by the @code{includeIf} rule for ~~/Work/~.
(define gitconfig-work-filename
  (make-parameter ".gitconfig-work.ini"))

;; Machine-wide ignore list, referenced by @code{core.excludesFile}.
(define gitignore-global-filename
  (make-parameter ".gitignore-global"))

(define (install-git-config)
  "Write the whole Git configuration ecosystem into @code{git-config-dir}.

Four files are written from one call.  Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/git-settings.scm} first."
  (log-info s "Installing Git configuration ecosystem")
  (load-local-overrides '(heks-linux git) 'git-settings)
  (install-config-file! #:name (gitconfig-filename)
                        #:dir (git-config-dir)
                        #:contents (mk-rec-kv-conf-lines gitconfig
                                    #:template spaced-equal-conf-pair))

  (install-config-file! #:name (gitconfig-personal-filename)
                        #:dir (git-config-dir)
                        #:contents (mk-rec-kv-conf-lines gitconfig-personal
                                    #:template spaced-equal-conf-pair))

  (install-config-file! #:name (gitconfig-work-filename)
                        #:dir (git-config-dir)
                        #:contents (mk-rec-kv-conf-lines gitconfig-work
                                    #:template spaced-equal-conf-pair))

  (install-config-file! #:name (gitignore-global-filename)
                        #:dir (git-config-dir)
                        #:contents (mk-lines gitignore-global))

  (log-success s "Installed Git configuration ecosystem"))
