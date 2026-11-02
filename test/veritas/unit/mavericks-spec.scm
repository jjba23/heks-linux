;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux mavericks): the program that installs the
;; typefaces this checkout carries.
;;
;; What can be tested here is the program and the artwork it reads, not the
;; desktop it lands on.  So these assert the properties that make the program
;; worth having and that a mistake would quietly break: that it is a POSIX shell
;; script with no bash in it, that it names every face the module promises and
;; that every one of those faces is actually in resources/mavericks/fonts, that
;; it copies nothing twice, that it reads from the checkout rather than from an
;; installation image, that it says whose artwork it is - and, for a program that
;; installs somebody else's material, that it downloads nothing at all.
;;
;; One test asserts an absence: the wallpapers of that system are not in this
;; repository and the program has no subcommand that installs them.  They are
;; thirty times the size of the faces, and a test is what keeps a later change
;; from quietly putting them back.

;; IMPORTANT contributor note:
;;
;; `assert-true' and friends are *pure constructors*: they return a closure that
;; the veritas runner later applies to a context.  When such a call sits in a
;; non-final position of a body (typically inside a `let'), its return value is
;; unused and Guile's optimizer deletes the call entirely, so the assertion
;; silently never runs.  Always pass assertions as direct arguments to `test', as
;; this file does.

;;; Code:

(define-module (veritas unit mavericks-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux mavericks)
  #:use-module (heks-linux prelude)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 textual-ports)
  #:export (spec))

(define (script-occurs? fragment)
  "Whether the generated program contains @var{fragment}."
  (not (eq? #f
            (string-contains (mavericks-script) fragment))))

(define (every-face-occurs? faces)
  "Whether every entry of @var{faces} is written into the program."
  (every script-occurs? faces))

(define (fonts-source-dir)
  "The directory of faces the module reads."
  (format #f "~a/fonts" (mavericks-assets-dir)))

(define (absent-faces faces)
  "The entries of @var{faces} that are not in the checkout's fonts directory."
  (remove (lambda (face)
            (file-exists? (format #f "~a/~a" (fonts-source-dir) face)))
          faces))

(define (files-of-type dir suffix)
  "The files directly inside @var{dir} whose name ends in @var{suffix}."
  (if (file-exists? dir)
      (filter (lambda (name) (string-suffix? suffix name))
              (scandir dir (lambda (name) (not (string-prefix? "." name)))))
      '()))

(define (scratch-dir name)
  "A throwaway directory named @var{name}, unique to this run."
  (format #f "/tmp/heks-mavericks-spec-~a/~a"
          (getpid) name))

(define (executable? path)
  "Whether @var{path} carries any execute bit."
  (not (zero? (logand (stat:perms (stat path)) #x49))))

(define mavericks-suite
  (suite "Mavericks Artwork Suite"
    (test "The Program Is A POSIX Shell Script"
      (assert-true (string-prefix? "#!/usr/bin/env sh"
                                   (mavericks-script))
        #:name "The program should run under any sh")
      (assert-equal #:expect #f
        #:got
        (string-contains (mavericks-script) "[[")
        #:name "It must not use bash test syntax")
      (assert-equal #:expect #f
        #:got
        (string-contains (mavericks-script) "$RANDOM")
        #:name "It must not read the bash-only RANDOM")
      (assert-true (script-occurs? "set -u")
        #:name "An unset variable should stop it, not expand to nothing"))

    (test "It Names Every Face The Module Promises"
      (assert-true (every-face-occurs? (mavericks-font-files))
        #:name "Every file the module lists should be in the program")
      (assert-true (every-face-occurs? (mavericks-font-families))
        #:name "And every family it promises")
      (assert-true (script-occurs? "LucidaGrande.ttc")
        #:name "The interface face should be the one the desktop is drawn in")
      (assert-true (script-occurs? "|.Keyboard|")
        #:name
        "The key glyph face keeps the dot its family name carries")
      (assert-true (not (null? (mavericks-font-families)))
        #:name "A program that installs no faces is not a program"))

    (test "The Faces Ship With The Checkout"
      ;; The faces are files in this repository, and the program is only worth
      ;; writing if they are: a promise in a table that names a file nobody
      ;; committed is a copy that silently installs six faces on one machine
      ;; and seven on another.
      (assert-equal #:expect '()
        #:got (absent-faces (mavericks-font-files))
        #:name "Every promised face should be in resources/mavericks/fonts")
      (assert-true (> (length (files-of-type (fonts-source-dir) ".ttf"))
                      0)
        #:name "The directory should hold more than the .ttc collections")
      (assert-true (file-exists? (format #f "~a/NOTICE"
                                        (mavericks-assets-dir)))
        #:name "With the notice that says whose artwork it is"))

    (test "The Wallpapers Do Not"
      ;; Deliberately absent: thirty times the size of the faces, and the
      ;; wallpaper collection already carries the pictures a person chose.  A
      ;; later change that vendors them again is a change this test refuses.
      (assert-equal #:expect #f
        #:got (file-exists? (format #f "~a/pictures"
                                    (mavericks-assets-dir)))
        #:name "resources/mavericks should carry no pictures")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "cmd_pictures")
        #:name "And the program should have no subcommand that installs them")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "PICTURES=")
        #:name "Nor a destination to install them into"))

    (test "It Reads The Checkout, Not An Installation Image"
      ;; The image was the old source, and a program that still looks for one
      ;; fails on every machine that never had OS X - which is most of them.
      (assert-true (script-occurs? (format #f "ASSETS='~a'"
                                           (mavericks-assets-dir)))
        #:name "The assets directory should be the one the module resolved")
      (assert-true (script-occurs? "\"$ASSETS/fonts\"")
        #:name "The faces should come out of the checkout")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "OS X Base System")
        #:name "No installation image should be named at all")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "bsdtar")
        #:name "So nothing has to unpack a package")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "MediaFiles.pkg")
        #:name "And no package is read"))

    (test "It Says Whose Artwork It Is"
      ;; These files are Apple's, not this project's.  A program that installs
      ;; them without saying so is how the distinction gets lost.
      (assert-true (script-occurs? "copyright Apple Inc.")
        #:name "The program should name the copyright holder")
      (assert-true (script-occurs? "NOTICE")
        #:name "And point at the notice beside the artwork")
      (assert-true (script-occurs? "status) cmd_status ;;")
        #:name "status is where a person asks, so it should answer this too"))

    (test "It Copies Nothing Twice"
      ;; A reconfigure runs this on a machine that has run it before, and
      ;; re-copying seven faces every time is a cost with nothing to show for
      ;; it.
      (assert-true (script-occurs? "already installed")
        #:name "A face that is there should be reported, not copied")
      (assert-true (script-occurs? "[ -f \"$FONTS/$file\" ]")
        #:name "The check that makes it idempotent"))

    (test "It Downloads Nothing"
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "curl")
        #:name "The checkout is the only source, so there is no downloader")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "wget")
        #:name "And no second downloader")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "http")
        #:name "Nothing to fetch, so no URL to fetch it from"))

    (test "Its Default Is The Help Text"
      ;; The alternative default is a program that installs Apple's faces on a
      ;; machine the first time it is typed by accident.
      (assert-true (script-occurs? "${1:-help}")
        #:name "No argument should print the usage, not run a subcommand")
      (assert-true (script-occurs? "usage >&2")
        #:name "An unknown subcommand should print it as an error")
      (assert-true (script-occurs? "fonts) cmd_fonts ;;")
        #:name "fonts should reach the font subcommand")
      (assert-true (script-occurs? "status) cmd_status ;;")
        #:name "status should reach the status subcommand"))

    (test "The Paths Are What The Machine Configured"
      (assert-equal #:expect #t
        #:got
        (parameterize ((mavericks-assets-dir "/tmp/the artwork")
                       (mavericks-fonts-dir "/tmp/the fonts"))
          (and (script-occurs? "ASSETS='/tmp/the artwork'")
            (script-occurs? "FONTS='/tmp/the fonts'")))
        #:name "Every path in the program should be the configured one"))

    (test "A Quote In A Path Stays One Shell Word"
      ;; A home directory with an apostrophe in it is not a reason for the
      ;; program to fail on its first assignment.
      (assert-true (parameterize ((mavericks-fonts-dir "/tmp/it's here"))
                     (script-occurs? "FONTS='/tmp/it'\\''s here'"))
        #:name "The quote should be closed, escaped and reopened"))

    (test "Installing Writes An Executable Program"
      (parameterize ((mavericks-script-dir (scratch-dir "bin")))
        (install-mavericks-config)
        (assert-true (file-exists? (format #f "~a/~a"
                                           (mavericks-script-dir)
                                           (mavericks-script-filename)))
          #:name "The program should be installed")
        (assert-true (executable? (format #f "~a/~a"
                                          (mavericks-script-dir)
                                          (mavericks-script-filename)))
          #:name "It should be executable, since the maak tasks run it")
        (assert-equal #:expect #t
          #:got
          (string-prefix? "#!/usr/bin/env sh"
                          (call-with-input-file
                           (format #f "~a/~a"
                                   (mavericks-script-dir)
                                   (mavericks-script-filename))
                           get-string-all))
          #:name "What was written should be the program")))))

(define (spec)
  (veritas-run mavericks-suite))
