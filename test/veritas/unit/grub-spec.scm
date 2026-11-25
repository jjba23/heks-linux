;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux grub).
;;
;; The boot menu is three files and each is checked here for the thing that
;; makes it worth having: the theme names the picture it draws and the keys under
;; it, the defaults are the timeout and the command line the install worked out,
;; and the entries are a *shell script* - grub-mkconfig runs it and takes what it
;; prints - so it is checked with the shell that runs it and then read for the
;; entries it promises.
;;
;; IMPORTANT contributor note:
;;
;; `assert-true' and friends are *pure constructors*: they return a closure the
;; veritas runner later applies to a context.  When such a call sits in a
;; non-final position of a body (inside a `let', say), Guile's optimizer deletes
;; the call and the assertion silently never runs.  Always pass assertions as
;; direct arguments to `test', as this file does.

;;; Code:

(define-module (veritas unit grub-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux grub)
  #:use-module (heks-linux identity)
  #:use-module (ice-9 format)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? haystack needle)
  "Return @code{#t} when @var{needle} occurs in the string @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

(define (write-temp name contents)
  "Write @var{contents} to a file in /tmp called @var{name}, and return its path."
  (let ((path (format #f "/tmp/heks-grub-spec-~a-~a" (getpid) name)))
    (call-with-output-file path (lambda (port) (display contents port)))
    path))

(define (shell-parses? contents)
  "Return @code{#t} when @var{contents} parses as the shell that will run it."
  (let ((path (write-temp "script" contents)))
    (zero? (status:exit-val (system* "sh" "-n" path)))))

(define (theme-cases)
  "Return the cases for the theme.

A theme is a file GRUB reads before it can draw anything, and every key in it is
one gfxmenu understands: the picture, the title, the menu, and the two labels
that name the keys a person does not know are there."
  (let ((theme (grub-theme)))
    (list (assert-equal #:expect "/boot/grub/themes/heks/theme.txt"
            #:got (grub-theme-path)
            #:name "The theme is on /boot, outside the encryption, where GRUB can read it")
          (assert-true (contains? theme "desktop-image: \"matrix.png\"")
            #:name "It draws the picture the payload carries")
          (assert-true (contains? theme (format #f "title-text: \"~a\""
                                                (string-upcase heks-name)))
            #:name "The title is the system's name")
          (assert-true (contains? theme "item_color = \"#39ff88\"")
            #:name "Phosphor green on black: the palette every other screen uses")
          (assert-true (contains? theme "selected_item_color")
            #:name "And the selected entry is inverted rather than a different ink")
          (assert-true (contains? theme "e edits an entry")
            #:name "The keys a boot menu never says are written under the menu")
          (assert-true (contains? theme "f firmware")
            #:name "Including the one that reaches the firmware")
          (assert-true (contains? theme "terminal-font")
            #:name "The command line and the pager use the same font as the menu"))))

(define (defaults-cases)
  "Return the cases for /etc/default/grub.

This is the file a machine's boot arguments live in, and the one grub-mkconfig
reads before it writes a single entry."
  (let ((defaults (grub-defaults #:cmdline "rd.luks.uuid=aaaa root=UUID=bbbb rw")))
    (list (assert-true (contains? defaults "GRUB_CMDLINE_LINUX_DEFAULT=\"rd.luks.uuid=aaaa root=UUID=bbbb rw\"")
            #:name "The command line the install worked out is the one it boots")
          (assert-true (contains? defaults "GRUB_TIMEOUT=5")
            #:name "Five seconds: enough to read the menu, short enough to boot")
          (assert-true (contains? defaults "GRUB_TIMEOUT_STYLE=menu")
            #:name "The menu is always shown, not hidden behind a keypress")
          (assert-true (contains? defaults "GRUB_DISABLE_SUBMENU=y")
            #:name "And it is flat: no second question between a person and the kernel")
          (assert-true (contains? defaults (format #f "GRUB_THEME=\"~a\""
                                                   (grub-theme-path)))
            #:name "The theme is named by the path it is installed at")
          (assert-true (contains? defaults "GRUB_COLOR_NORMAL=\"light-green/black\"")
            #:name "The text menu GRUB falls back to is the same palette")
          (assert-true (contains? defaults "GRUB_DISABLE_OS_PROBER=true")
            #:name "Nothing else on the disk is offered: this is not a dual-boot installer")
          (assert-true (contains? defaults "GRUB_DISABLE_RECOVERY=true")
            #:name "And GRUB's own recovery entry is off: `single' means nothing to runit"))))

(define (entry-cases)
  "Return the cases for 40_custom, the entries grub-mkconfig does not generate.

The script is shell whose *output* is GRUB script, so it is checked twice: that
the shell parses it, and that the entries it promises are the entries it writes."
  (let ((entries (grub-entries)))
    (list (assert-true (shell-parses? entries)
            #:name "The script grub-mkconfig runs parses as the shell that runs it")
          (assert-true (contains? entries "set -eu")
            #:name "And refuses to half-print a menu: a failure is not an empty one")
          (assert-true (contains? entries "findmnt -no SOURCE /boot")
            #:name "Where /boot is is asked at grub-mkconfig time, not guessed")
          (assert-true (contains? entries "search --no-floppy --fs-uuid")
            #:name "GRUB's root may be the ESP, so every entry searches for the kernel's")
          (assert-true (contains? entries "(verbose)")
            #:name "A verbose boot is one entry away")
          (assert-true (contains? entries "loglevel=7")
            #:name "Which is what the kernel's messages look like on the console")
          (assert-true (contains? entries "(with the splash)")
            #:name "And so is the splash the installer turns off by default")
          (assert-true (contains? entries "quiet splash")
            #:name "Which adds exactly the two words plymouth reads")
          (assert-true (contains? entries "s/[[:space:]]*plymouth\\.enable=0//g")
            #:name "Both take the daemon's switch off the line they inherit")
          (assert-true (contains? entries "(rescue shell)")
            #:name "A shell is the third")
          (assert-true (contains? entries "init=/bin/sh")
            #:name "Which asks the kernel for one instead of an init system")
          (assert-true (contains? entries "fwsetup")
            #:name "The firmware's own settings are a menu entry, guarded by whether there is firmware to ask")
          (assert-true (contains? entries "reboot")
            #:name "So is a restart")
          (assert-true (contains? entries "halt")
            #:name "And a power off")
          (assert-true (contains? entries "--hotkey m")
            #:name "The screen that says what this is has a key")
          (assert-true (contains? entries "01001 1101 0110 1011")
            #:name "It is the rain, in the same ink as the theme")
          (assert-true (contains? entries "e   edit this entry")
            #:name "And it says what the keys do, which is what a boot menu never does")
          (assert-true (contains? entries "heks-help")
            #:name "It points at the quickstart, which is on the machine offline")
          (assert-true (not (contains? entries "GRUB_CMDLINE_LINUX_DEFAULT=\"\""))
            #:name "The command line is read from the file, never copied into the script"))))

(define (spec)
  (veritas-run (suite "The boot menu"
                 (test "The Theme Is The Palette, And The Keys Under It"
                   (theme-cases))
                 (test "The Defaults Are The Timeout And The Command Line"
                   (defaults-cases))
                 (test "The Entries A Person Reaches For Are Generated"
                   (entry-cases)))))
