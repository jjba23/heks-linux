;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; One protocol for the package managers this configuration installs from.
;;
;; A backend answers the same few questions: what it is called, which packages
;; it declares, how a package's name is read, and whether a name is the shape
;; that manager accepts.  The installer is a procedure over the list, because
;; the managers do not agree on anything past that point - zypper takes every
;; name in one privileged command, Flatpak adds a remote first and then installs
;; one application at a time, and Nix consults the profile before it adds
;; anything at all.
;;
;; The name check is deliberately a shape check.  No test can tell you that
;; @code{texlive-juliamono-fonts} is a package Slowroll has; only installing it
;; can.  What the protocol can promise is that a name cannot be read as an
;; option, cannot be split into two arguments, and cannot reach a command line
;; it was not checked for - which is why every installer is handed an argument
;; vector rather than a shell line.
;;
;; Adding a distribution is one module that constructs a backend and implements
;; its installer.  The specs in @code{test/veritas/unit/packages-spec.scm} run
;; over every backend, so a new one is asked the same questions the three here
;; already answer.

;;; Code:

(define-module (heks-linux packages)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:export (package-backend package-backend?
                            package-backend-name
                            package-backend-packages
                            package-backend-package-name
                            package-backend-valid-package?
                            package-backend-install
                            package-name?
                            package-sorted-set
                            run-package-command))

;; A backend's `packages' field is a procedure, not a list: the category lists
;; are parameters, and a machine's override has to be observed at install time
;; rather than when the module was loaded.
(define-record-type <package-backend>
  (%make-package-backend name packages name-of name-valid? installer)
  package-backend?
  (name package-backend-name)
  (packages backend-packages)
  (name-of package-backend-name-of)
  (name-valid? package-backend-name-valid?)
  (installer backend-installer))

(define* (package-backend name #:key packages name-of name-valid? install)
  "Construct a package backend named @var{name}.

@var{packages} is a procedure returning the declared package values, so a
parameter changed after this module was loaded is still observed.  @var{name-of}
reads a package value's name as a string, @var{name-valid?} checks that string's
shape, and @var{install} takes the list and does the installing.

@example
(package-backend 'zypper
                 #:packages (lambda () (list \"niri\"))
                 #:name-of identity
                 #:name-valid? package-name?
                 #:install (lambda (packages) #t))
@end example"
  (unless (and (symbol? name)
            (procedure? packages)
            (procedure? name-of)
            (procedure? name-valid?)
            (procedure? install))
    (error "package-backend: incomplete backend:" name))
  (%make-package-backend name packages name-of name-valid? install))

(define (package-backend-packages backend)
  "Return the packages @var{backend} declares, read now."
  ((backend-packages backend)))

(define (package-backend-package-name backend package)
  "Return @var{package}'s name as @var{backend} spells it."
  ((package-backend-name-of backend) package))

(define (package-backend-valid-package? backend package)
  "Return whether @var{package}'s name has the shape @var{backend} accepts."
  ((package-backend-name-valid? backend)
   (package-backend-package-name backend package)))

(define (package-backend-install backend packages)
  "Install @var{packages} with @var{backend}."
  ((backend-installer backend) packages))

(define (package-name? name)
  "Return @code{#t} when @var{name} can be a distribution package name.

The check is deliberately shallow: a non-empty string that does not start with
a hyphen and holds only the characters package names use.  It catches the
mistakes that actually happen - an option pasted in as a package, a half-copied
entry with a space in it - and it means a name can never be read as an option.
It cannot tell you the distribution has the package; only installing it can."
  (and (string? name)
    (> (string-length name) 0)
    (not (char=? #\- (string-ref name 0)))
    (every (lambda (character)
             (or (char-alphabetic? character)
               (char-numeric? character)
               (memv character '(#\. #\- #\_ #\+ #\: #\/))))
           (string->list name))))

(define (package-sorted-set packages name-of)
  "Return @var{packages} with one declaration per name, sorted by name.

@var{name-of} reads a package's name, and the first declaration of a name wins.
Two lists that are meant to be the same list are two lists that will disagree,
so the sorted set is what every backend hands its installer and what the suite
reads back."
  (sort (delete-duplicates packages
                           (lambda (a b)
                             (string=? (name-of a) (name-of b))))
        (lambda (a b)
          (string<? (name-of a) (name-of b)))))

(define (run-package-command program args)
  "Run @var{args} with @var{program} and report whether it succeeded.

The arguments are a list, never a shell line: a package name that was checked
is passed as one argument, so there is nothing left for a shell to re-parse.  A
failure is logged with the command that produced it and answered with
@code{#f}, so the caller can carry on with the rest of a list."
  (format #t "\nExecuting command: ~a\n" (string-join (cons program args) " "))
  (let ((status (apply system* program args)))
    (cond
      [(eq? status #f)
       (format (current-error-port) "could not execute ~a\n"
               (string-join (cons program args) " "))
       #f]
      [(zero? status) #t]
      [else (format (current-error-port) "~a exited with status ~a: ~a\n"
                    program status (string-join args " "))
        #f])))
