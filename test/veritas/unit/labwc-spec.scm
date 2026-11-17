;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux labwc): the floating session's five files.
;;
;; Every one of them is read by a program that fails when it is wrong - an XML
;; file that is not XML is a menu that does not open, an autostart that starts
;; the bar twice draws it twice - so the tests pin the shape of each file and the
;; one policy that is this project's: floating windows by default, decorations in
;; the palette's colours.

;;; Code:

(define-module (veritas unit labwc-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux labwc)
  #:use-module (heks-linux palette)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (holds? text fragment)
  "Return #t when @var{text} contains @var{fragment}."
  (if (string-contains text fragment) #t #f))

(define (rc-suite)
  (suite "rc.xml"
    (test "The Document Is XML"
      (assert-true (holds? (labwc-rc-xml) "<?xml version=")
        #:name "The file starts with an XML declaration")
      (assert-true (holds? (labwc-rc-xml) "<labwc_config>")
        #:name "The document names the program's root element")
      (assert-true (holds? (labwc-rc-xml) "</labwc_config>")
        #:name "The document is closed"))
    (test "The Session States Its Policy"
      (assert-true (holds? (labwc-rc-xml) "<theme>")
        #:name "The theme is named")
      (assert-true (holds? (labwc-rc-xml) "<policy>")
        #:name "The placement policy is stated"))
    (test "The Palette Paints The Decorations"
      (assert-true (holds? (labwc-themerc)
                           (get-color (labwc-palette) 'background))
        #:name "The window background is the palette's"))
    (test "Every Binding Is Complete"
      (assert-true (if (every (lambda (binding)
                                (and (assq 'key binding)
                                     (assq 'cmd binding)
                                     (assq 'desc binding)))
                              (labwc-bindings))
                       #t #f)
        #:name "A binding is a chord, an action and a description"))
    (test "The Terminal Chord Survives The Second Session"
      (assert-true (holds? (format #f "~s" (map (lambda (binding)
                                                  (cdr (assq 'key binding)))
                                                (labwc-bindings)))
                           "W-t")
        #:name "Mod+t opens a terminal here too"))))

(define (theme-suite)
  (suite "themerc-override"
    (test "The Accent Follows The Palette"
      (assert-true (holds? (labwc-themerc)
                           (get-color (labwc-palette) 'primary))
        #:name "The accent is the palette's primary")
      (assert-true (holds? (labwc-themerc) "window.active.title.bg.color:")
        #:name "The active title has a colour"))
    (test "Radius And Gap Are Parameters"
      (parameterize ((labwc-corner-radius 12)
                     (labwc-gap 8))
        (assert-true (holds? (labwc-rc-xml) "<cornerRadius>12</cornerRadius>")
          #:name "The radius is rendered")
        (assert-true (holds? (labwc-rc-xml) "<gap>8</gap>")
          #:name "The gap is rendered")))))

(define (session-files-suite)
  (suite "Session files"
    (test "The Menu Is XML"
      (assert-true (holds? (labwc-menu-xml) "<menu id=")
        #:name "The menu is an XML document with a root menu")
      (assert-true (holds? (labwc-menu-xml) "<item label=")
        #:name "The menu offers entries"))
    (test "Autostart Starts The Shell Once"
      (assert-true (holds? (labwc-autostart) "whelk")
        #:name "The bar is started")
      (assert-equal #:expect 1
        #:got (length (filter (lambda (line)
                                (and (not (string-prefix? "#" line))
                                     (holds? line "whelk")))
                              (string-split (labwc-autostart) #\newline)))
        #:name "A shell started twice is two bars"))
    (test "The Environment Names The Session"
      (assert-true (holds? (labwc-environment) "XDG_CURRENT_DESKTOP")
        #:name "The session says which desktop it is"))
    (test "The Desktop Entry Can Be Selected"
      (assert-true (holds? (labwc-session-entry) "[Desktop Entry]")
        #:name "It is a desktop entry")
      (assert-true (holds? (labwc-session-entry) "Exec=labwc")
        #:name "It starts the compositor")
      (assert-true (holds? (labwc-session-entry) "Type=Application")
        #:name "It is an application"))))

(define (spec)
  (veritas-run
   (rc-suite)
   (theme-suite)
   (session-files-suite)))
