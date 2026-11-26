;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux packages collection): the two packagings of the
;; collection's programs.
;;
;; The thing under test is not a renderer, it is an agreement.  whelk, Lambdock,
;; heks-toon and Maak are programs of their own, and each is packaged twice - once
;; for Void, once for Debian - so the failure this suite is written against is the
;; two drifting apart: a version bumped in one and not the other, a checksum that
;; no longer names the archive, a package this tree builds for one distribution
;; and not the other.  None of that is visible in a diff of either file alone.
;;
;; What it cannot prove is that the recipes build: that takes a Void checkout and
;; a Debian toolchain, and ~maak xbps-build~ / ~maak deb-build~ are the tasks that
;; ask.  What it can prove is that each recipe names what it needs, so the build
;; fails at its first fetch rather than an hour into a compile.

;;; Code:

(define-module (veritas unit collection-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux packages collection)
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contents path)
  "Return the whole of @var{path} as a string."
  (call-with-input-file path get-string-all))

(define (contains? haystack needle)
  "Return @code{#t} when @var{needle} occurs in @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

(define (hex-digest? text)
  "Return @code{#t} when @var{text} is a sha256 digest as sha256sum writes it."
  (and (string? text)
    (= (string-length text) 64)
    (if (every (lambda (character)
                 (or (char-numeric? character)
                   (memv character '(#\a #\b #\c #\d #\e #\f))))
               (string->list text))
      #t
      #f)))

(define (package-cases)
  (suite "What This Tree Packages"
    (test "Every Program Is Declared Once, Sorted"
      (let ((names (collection-package-names)))
        (assert-true (> (length names) 0)
          #:name "The collection is read from packaging/void, not from a list")
        (assert-equal #:expect (length names)
          #:got (length (delete-duplicates names))
          #:name "A package declared twice is a package once")
        (assert-equal #:expect names
          #:got (sort names string<?)
          #:name "The order is the order a person reads")))
    (test "The Desktop's Programs Are Among Them"
      ;; The point of the whole module: these three are what a session needs and
      ;; none of them is a Nix package any more.
      (for-each (lambda (name)
                  (assert-true (if (member name (collection-package-names)) #t #f)
                    #:name (string-append name " is a package this tree builds")))
                collection-desktop-names))
    (test "Every Package Names The Three Things A Build Needs"
      (for-each (lambda (package)
                  (let ((name (collection-package-name package)))
                    (assert-true (if (and (string? (collection-package-version package))
                                       (not (string-null?
                                             (collection-package-version package))))
                                   #t
                                   #f)
                      #:name (string-append name " names a version"))
                    (assert-true (if (and (string? (collection-package-archive package))
                                       (string-prefix?
                                        "https://"
                                        (collection-package-archive package)))
                                   #t
                                   #f)
                      #:name (string-append name " names an https archive"))
                    (assert-true (hex-digest? (collection-package-checksum package))
                      #:name (string-append name " names a sha256 digest"))))
                (collection-packages)))
    (test "The Archive Is The Release The Package Says It Is"
      ;; A URL that does not carry the version is a build that fetches one
      ;; release, unpacks it into a directory named after another, and reports
      ;; success either way.
      (for-each (lambda (package)
                  (assert-true (contains? (collection-package-archive package)
                                          (collection-package-version package))
                    #:name (string-append (collection-package-name package)
                                          "'s archive names its version")))
                (collection-packages)))))

(define (agreement-cases)
  (suite "The Two Packagings Agree"
    (test "The Debian Packaging Names The Same Release As The Void One"
      ;; This is the drift the module exists to prevent: `maak deb-build'
      ;; refuses on a disagreement, and the refusal is a sentence rather than a
      ;; package that installs 0.52 on Debian and 0.53 on Void.
      (assert-equal #:expect '()
        #:got (collection-disagreements)
        #:name "No package disagrees about its version"))
    (test "Every Package Has A Debian Control File"
      (for-each (lambda (package)
                  (let ((name (collection-package-name package)))
                    (assert-true (collection-debian-package? name)
                      #:name (string-append name " is packaged for Debian"))
                    (assert-true (contains? (contents
                                             (format #f "~a/control"
                                                     (collection-debian-path name)))
                                            (format #f "Package: ~a" name))
                      #:name (string-append name "'s control file names it"))))
                (collection-packages)))
    (test "Every Package Builds The Way Its Language Is Built"
      ;; The recipe is what a Void build and a Debian build share: a Rust program
      ;; is a cargo one, a C program with a Meson build is a meson one, and a
      ;; recipe that says otherwise fails at its first command.
      (assert-true (contains? (contents "packaging/void/whelk/template")
                              "cargo build --release")
        #:name "whelk is built with cargo")
      (assert-true (contains? (contents "packaging/void/lambdock/template")
                              "cargo")
        #:name "Lambdock is built with cargo")
      (assert-true (contains? (contents "packaging/void/heks-toon/template")
                              "build_style=meson")
        #:name "heks-toon is built with meson")
      (assert-true (contains? (contents "packaging/void/maak/template")
                              "guild compile")
        #:name "Maak's modules are byte-compiled at build time"))))

(define (install-cases)
  (suite "Installing What Was Built"
    (test "The Installer Is An Argument Vector"
      ;; A path is data, and data does not reach a shell.
      (assert-equal #:expect '("sudo" "apt-get" "install" "--yes" "dist/deb/a.deb")
        #:got (collection-install-argv 'apt '("dist/deb/a.deb"))
        #:name "Debian's installer takes the files as arguments")
      (assert-equal #:expect '("sudo" "xbps-install" "--yes" "dist/xbps/a.xbps")
        #:got (collection-install-argv 'xbps '("dist/xbps/a.xbps"))
        #:name "And so does Void's")
      (assert-error (lambda () (collection-install-argv 'zypper '("a.rpm")))
        #:name "A manager this tree does not package for is refused"))
    (test "The Runner Is Not Installed By The Runner"
      ;; `maak deb-build' builds Maak's package too, and a machine that already
      ;; runs it does not need a second copy from apt - the other three are what
      ;; a desktop is missing.
      (assert-equal #:expect '("dist/deb/heks-toon_0.3.9-1_amd64.deb"
                               "dist/deb/lambdock_2.3.2-1_amd64.deb"
                               "dist/deb/whelk_0.53.0-1_amd64.deb")
        #:got (collection-files-for-desktop
               '("dist/deb/maak_1.5.2-1_amd64.deb"
                 "dist/deb/heks-toon_0.3.9-1_amd64.deb"
                 "dist/deb/lambdock_2.3.2-1_amd64.deb"
                 "dist/deb/whelk_0.53.0-1_amd64.deb"))
        #:name "The desktop's three are installed, the runner is left alone"))
    (test "A Directory That Is Not There Is No Packages"
      (assert-equal #:expect '()
        #:got (collection-built-files 'apt #:directory "/nonexistent/heks")
        #:name "An unbuilt tree is a task that says so, not an error here"))
    (test "Only The Files The Manager Installs Are Listed"
      (let* ((directory (format #f "/tmp/heks-collection-spec-~a" (getpid)))
             (deb (format #f "~a/whelk_0.53.0-1_amd64.deb" directory)))
        (catch 'system-error (lambda () (mkdir directory)) (lambda (key . args) #f))
        (call-with-output-file deb (lambda (port) (display "" port)))
        (call-with-output-file (format #f "~a/README" directory)
                               (lambda (port) (display "" port)))
        (assert-equal #:expect (list deb)
          #:got (collection-built-files 'apt #:directory directory)
          #:name "A .deb is a package and a note beside it is not")))))

(define (spec)
  (veritas-run (package-cases) (agreement-cases) (install-cases)))
