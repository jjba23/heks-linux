;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux mavericks): the program that takes the typefaces
;; and the desktop pictures out of an OS X installation image.
;;
;; What can be tested here is the program, not the image - the image is a
;; five-gigabyte file on somebody's disk.  So these assert the properties that
;; make the program worth having and that a mistake would quietly break: that it
;; is a POSIX shell script with no bash in it, that it names every face the
;; module promises and looks in both layouts an Apple installer has on disk, that
;; it reads the compression its payload actually uses instead of assuming one,
;; that it copies nothing twice, and - the one that matters most, for a program
;; that handles somebody else's artwork - that it downloads nothing at all.

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
  #:use-module (heks-linux wallpaper)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 textual-ports)
  #:export (spec))

(define (script-occurs? fragment)
  "Whether the generated program contains @var{fragment}."
  (not (eq? #f
            (string-contains (mavericks-script) fragment))))

(define (every-face-occurs? faces)
  "Whether every entry of @var{faces} is written into the program."
  (every script-occurs? faces))

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

    (test "It Looks Where An Apple Installer Keeps Things"
      ;; Two layouts: a USB installer's volume keeps the packages under
      ;; System/Installation, an Install ESD image keeps them at its root.
      ;; One configured path has to work for both.
      (assert-true (script-occurs? "System/Library/Fonts/Base")
        #:name "The faces live in the base system's fonts directory")
      (assert-true (script-occurs? "System/Installation/Packages")
        #:name "The packages live under System/Installation on a volume")
      (assert-true (script-occurs? "\"$IMAGE/Packages/")
        #:name "And at the root of an Install ESD image")
      (assert-true (script-occurs? (mavericks-picture-package))
        #:name "The package is the one the module names"))

    (test "It Reads The Payload In Whatever Compression It Finds"
      ;; The payload is a cpio archive behind a compressor, and which one
      ;; depends on the release.  Guessing bzip2 fails on the images that
      ;; write xz.
      (assert-true (script-occurs? "425a68")
        #:name "bzip2, which Mavericks writes")
      (assert-true (script-occurs? "fd377a585a00")
        #:name "xz, which later systems write")
      (assert-true (script-occurs? "1f8b")
        #:name "gzip, for the images that use it")
      (assert-true (script-occurs? "pbzx")
        #:name
        "The one compression it cannot read is named instead of guessed at"))

    (test "It Copies Nothing Twice"
      ;; A reconfigure runs this on a machine that has run it before, and
      ;; re-copying seven faces and fifty pictures every time is a cost
      ;; with nothing to show for it.
      (assert-true (script-occurs? "already installed")
        #:name "A face that is there should be reported, not copied")
      (assert-true (script-occurs? "[ -f \"$FONTS/$file\" ]")
        #:name "The check that makes it idempotent")
      (assert-true (script-occurs? "[ -e \"$PICTURES/$name\" ]")
        #:name "And the same check for the pictures"))

    (test "It Downloads Nothing"
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "curl")
        #:name "The image is the only source, so there is no downloader")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "wget")
        #:name "And no second downloader")
      (assert-equal #:expect #f
        #:got (string-contains (mavericks-script) "http")
        #:name "Nothing to fetch, so no URL to fetch it from"))

    (test "Its Default Is The Help Text"
      ;; The alternative default is a program that copies three hundred
      ;; megabytes of wallpaper the first time it is typed by accident.
      (assert-true (script-occurs? "${1:-help}")
        #:name "No argument should print the usage, not run a subcommand")
      (assert-true (script-occurs? "usage >&2")
        #:name "An unknown subcommand should print it as an error")
      (assert-true (script-occurs? "fonts) cmd_fonts ;;")
        #:name "fonts should reach the font subcommand")
      (assert-true (script-occurs? "pictures) cmd_pictures ;;")
        #:name "pictures should reach the picture subcommand")
      (assert-true (script-occurs? "status) cmd_status ;;")
        #:name "status should reach the status subcommand"))

    (test "The Paths Are What The Machine Configured"
      (assert-equal #:expect #t
        #:got
        (parameterize ((mavericks-image-dir "/tmp/the image")
                       (mavericks-fonts-dir "/tmp/the fonts")
                       (mavericks-pictures-dir "/tmp/the pictures")
                       (mavericks-picture-package "Other.pkg"))
          (and (script-occurs? "IMAGE='/tmp/the image'")
            (script-occurs? "FONTS='/tmp/the fonts'")
            (script-occurs? "PICTURES='/tmp/the pictures'")
            (script-occurs? "PACKAGE='Other.pkg'")))
        #:name "Every path in the program should be the configured one")
      (assert-true (script-occurs? "'MediaFiles.pkg'")
        #:name "The package is quoted as one shell word"))

    (test "A Quote In A Path Stays One Shell Word"
      ;; A home directory with an apostrophe in it is not a reason for the
      ;; program to fail on its first assignment.
      (assert-true (parameterize ((mavericks-fonts-dir "/tmp/it's here"))
                     (script-occurs? "FONTS='/tmp/it'\\''s here'"))
        #:name "The quote should be closed, escaped and reopened"))

    (test "The Pictures Land In The Wallpaper Collection"
      ;; The collection is what the wall view browses and what
      ;; heks-wallpaper all-list walks: a picture in it can be chosen, a
      ;; picture next to it cannot.
      (assert-true (string-prefix? (wallpaper-catalog-dir)
                                   (mavericks-pictures-dir))
        #:name
        "The pictures should be inside the collection, not beside it"))

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
