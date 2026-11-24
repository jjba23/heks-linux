;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux boot), the plymouth theme the machine shows before
;; it can show anything else.
;;
;; The theme is two text files in plymouth's own language, so what can be
;; checked here is that they are the files plymouth needs, that every image in
;; them is drawn from a string - no artwork, and nothing of the distribution
;; under this one - and that the passphrase dialog asks in words rather than
;; printing the device path dracut hands it.
;;
;; What cannot be checked here is what it looks like: that takes a machine that
;; boots, and the first one that does is the one this ships to.

;;; Code:

(define-module (veritas unit boot-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux boot)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? text line)
  "Return #t when @var{text} has @var{line} in it."
  (not (eq? #f (string-contains text line))))

(define (theme-cases)
  (suite "The Splash Theme"
    (test "Plymouth Is Pointed At A Script Theme Called Heks"
      (let ((theme (plymouth-theme)))
        (assert-true (contains? theme "[Plymouth Theme]")
          #:name "It is a theme plymouth can read")
        (assert-true (contains? theme "Name=Heks")
          #:name "And it is named after this system")
        (assert-true (contains? theme "ModuleName=script")
          #:name "The plugin is the one that draws text, so there is no artwork to ship")
        (assert-true (contains? theme "ImageDir=/usr/share/plymouth/themes/heks")
          #:name "Its directory is the one the image installs it in")
        (assert-true (contains? theme "ScriptFile=/usr/share/plymouth/themes/heks/heks.script")
          #:name "And its script is the one the image installs beside it")))
    (test "Every Image Is Drawn From A String"
      ;; The theme is the first thing a machine shows, and it must not show
      ;; anything this tree cannot draw: no PNG, no Void artwork, no logo file
      ;; that may or may not be installed.
      (let ((script (plymouth-script)))
        (assert-true (not (contains? script ".png"))
          #:name "No image file is named")
        (assert-true (not (contains? script "special://logo"))
          #:name "And no logo is borrowed from the distribution underneath")))
    (test "It Says Which System Is Starting"
      (assert-true (contains? (plymouth-script) "Heks GNU/Linux")
        #:name "The name on the splash is this system's"))
    (test "The Daemon Is Told To Use It"
      (let ((config (plymouth-config)))
        (assert-true (contains? config "[Daemon]")
          #:name "plymouthd reads a daemon table")
        (assert-true (contains? config "Theme=heks")
          #:name "And the theme is this one, not fade-in")))
    (test "The Passphrase Is Asked In Words"
      ;; dracut passes `Password (/dev/sda3)` and no setting changes it, so a
      ;; theme that draws the string it is given is a box with a device path in
      ;; it.  This one asks its own question and ignores the argument.
      (let ((script (plymouth-script)))
        (assert-true (contains? script "Enter your disk passphrase")
          #:name "The dialog says what to type")
        (assert-true (not (contains? script "Image.Text(prompt"))
          #:name "And never draws the string dracut handed it")))
    (test "The Kernel Is Told To Splash"
      (assert-equal #:expect "splash"
        #:got plymouth-kernel-argument
        #:name "One word in the command line, which is what starts the daemon"))))

(define (quit-cases)
  (suite "Taking The Splash Away"
    (test "The Service Is A Shell Script"
      (assert-true (string-prefix? "#!/bin/sh" (plymouth-quit-service))
        #:name "runit starts a service by running its file"))
    (test "It Quits The Daemon"
      (assert-true (contains? (plymouth-quit-service) "plymouth --quit")
        #:name "The splash belongs to the initramfs and nothing else takes it away"))
    (test "It Does Not Become A Restart Loop"
      ;; runsv restarts a service whose program exits, and a quit that repeats
      ;; every second is a log full of nothing.
      (assert-true (contains? (plymouth-quit-service) "exec sleep infinity")
        #:name "The work is done once, and the service then sleeps"))))

(define (package-cases)
  (suite "The Packages"
    (test "Plymouth And Its Themes Travel With The Image"
      (assert-equal #:expect '("plymouth" "plymouth-data")
        #:got plymouth-packages
        #:name "The daemon, the plugins and the themes it reads"))))

(define (spec)
  (veritas-run (theme-cases) (quit-cases) (package-cases)))
