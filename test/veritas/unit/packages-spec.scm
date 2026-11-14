;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for the package backend protocol in @code{(heks-linux packages)}
;; and for the three backends that implement it.
;;
;; A backend is a name, the packages it declares, a way to read a package's
;; name, a check on that name, and an installer.  What the suite can prove is
;; that shape: that a name is refused before it can reach a command line, that
;; the set is sorted and duplicate-free, and that every backend answers the
;; same questions.  What it cannot prove is that a name is a package the
;; distribution actually has - only installing it says that, which is why the
;; installers take argument vectors and report their own failures.

;;; Code:

(define-module (veritas unit packages-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux packages)
  #:use-module (heks-linux packages zypper)
  #:use-module (heks-linux packages flatpak)
  #:use-module (heks-linux packages nix)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define backends
  (list zypper-backend flatpak-backend nix-backend))

;; A backend whose package values are the names themselves, so the protocol's
;; name check can be asked about a malformed name directly.
(define names-backend
  (package-backend 'names
                   #:packages (lambda () '("ok"))
                   #:name-of identity
                   #:name-valid? package-name?
                   #:install (lambda (packages) packages)))

(define (backend-names backend)
  "Return the names @var{backend} declares, as the installer sees them."
  (map (lambda (package)
         (package-backend-package-name backend package))
       (package-backend-packages backend)))

(define (sorted? names)
  (or (null? names)
    (every string<=? names (cdr names))))

(define (protocol-cases)
  (suite "The Backend Protocol"
    (test "Every Backend Answers The Same Questions"
      (assert-true (every package-backend? backends)
        #:name
        "Each backend is a backend")
      (assert-true (every (lambda (backend)
                            (symbol? (package-backend-name backend)))
                          backends)
        #:name "Each backend has a symbolic name")
      (assert-true (every (lambda (backend)
                            (not (null? (package-backend-packages backend))))
                          backends)
        #:name "Each backend declares packages")
      (assert-true (procedure? package-backend-install)
        #:name "The protocol hands the list to a backend's installer")
      (assert-error (lambda ()
                      (package-backend 'incomplete
                                       #:packages (lambda () '())))
        #:name "A backend missing a field is refused"))
    (test "A Name Is Read The Way The Backend Spells It"
      (assert-equal #:expect "7zip"
        #:got (package-backend-package-name zypper-backend "7zip")
        #:name "A zypper name is returned as written")
      (assert-equal #:expect "org.gnome.Boxes"
        #:got (package-backend-package-name
               flatpak-backend
               (flatpak-app "org.gnome.Boxes"))
        #:name "A Flatpak name is its id")
      (assert-equal #:expect "nil"
        #:got (package-backend-package-name
               nix-backend
               (nix-package "nil"))
        #:name "A Nix name is its attribute"))))

(define (declaration-cases)
  (suite "Declarations"
    (test "Every Declared Package Passes Its Backend"
      (assert-true (every (lambda (backend)
                            (every (lambda (package)
                                     (package-backend-valid-package?
                                      backend
                                      package))
                                   (package-backend-packages backend)))
                          backends)
        #:name
        "Every backend should accept the names it declares"))
    (test "Each Set Is Sorted And Duplicate-Free"
      (assert-true (every (lambda (backend)
                            (let ((names (backend-names backend)))
                              (and (sorted? names)
                                (equal? (length names)
                                        (length (delete-duplicates names))))))
                          backends)
        #:name
        "Every backend's list should be sorted, with no name twice"))
    (test "A Malformed Name Is Refused"
      ;; A zypper name is its package value, so the protocol can be asked
      ;; directly; Flatpak and Nix refuse a malformed name at construction, so
      ;; their predicates are asked instead.
      (assert-equal #:expect #f
        #:got (package-backend-valid-package? names-backend "-O2")
        #:name "A name may not look like an option")
      (assert-equal #:expect #f
        #:got (package-backend-valid-package? names-backend "two words")
        #:name "A name has no whitespace")
      (assert-equal #:expect #f
        #:got (flatpak-app-id? "Boxes")
        #:name "A Flatpak id is reverse-DNS")
      (assert-equal #:expect #f
        #:got (nix-attribute? "nixpkgs#nil")
        #:name "A Nix attribute has no installable prefix"))))

(define (argument-cases)
  (suite "Argument Vectors"
    (test "The Zypper Installer Builds An Argument Vector"
      ;; Package names are data, so they are never put in a shell string: this
      ;; is the vector `system*' is handed, and a name that looked like an
      ;; option would be refused before it got here.
      (assert-equal #:expect
        '("sudo" "zypper" "--quiet" "--color" "install" "-y"
          "7zip" "niri")
        #:got (zypper-install-args '("7zip" niri))
        #:name
        "The installer passes the names as separate arguments")
      (assert-equal #:expect
        '("flatpak" "install" "--user" "--assumeyes"
          "flathub" "org.gnome.Boxes")
        #:got (flatpak-install-args
               (flatpak-app "org.gnome.Boxes"))
        #:name "A Flatpak install is an argument vector too")
      (assert-equal #:expect ".#nil"
        #:got (nix-installable (nix-package "nil"))
        #:name "A Nix installable is one string, built in one place"))
    (test "The Sorted Set Is Shared"
      (assert-equal #:expect '("a" "b" "c")
        #:got (map (lambda (package)
                     (package-backend-package-name
                      zypper-backend
                      package))
                   (package-sorted-set
                    (list "c" 'b "a" "b")
                    (lambda (package)
                      (if (symbol? package)
                        (symbol->string package)
                        package))))
        #:name
        "A set is deduplicated by name and sorted by name"))))

(define (spec)
  (veritas-run (protocol-cases)
    (declaration-cases)
    (argument-cases)))
