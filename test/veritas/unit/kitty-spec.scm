;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux kitty).
;;
;; The assertions are deliberately narrow, and they answer two questions.  The
;; first is whether the generated file is Kitty's syntax at all: one setting per
;; line, and @code{map} lines whose action names exist in the release that reads
;; them.  The second is the promise the module's commentary makes - that no bare
;; Emacs chord is claimed, so Emacs and readline inside Kitty keep every one of
;; them, and that the terminal's commands are behind the Emacs-shaped prefix.

;;; Code:

(define-module (veritas unit kitty-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux kitty)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (rendered-kitty-config)
  "Render @file{kitty.conf} the way it is written to disk."
  (kitty-config))

(define (kitty-conf-occurs? fragment)
  (not (eq? #f
            (string-contains (rendered-kitty-config) fragment))))

(define (kitty-lines)
  "Return the non-comment, non-empty lines of the generated file."
  (filter (lambda (line)
            (and (not (string-null? line))
              (not (string-prefix? "#" line))))
          (string-split (rendered-kitty-config) #\newline)))

(define (setting-line key value)
  "Render one @code{key value} line the way the file spells it."
  (format #f "~a ~a" key value))

(define (colour-line key colour)
  "Render one colour assignment the way the file spells it."
  (format #f "~a ~a" key colour))

(define (settings-suite)
  (suite "Settings"
    (test "The File Is Self-Describing"
      (assert-true (kitty-conf-occurs?
                    "# ====== Heks-Linux Kitty configuration ======")
        #:name "The file carries a generated-file header")
      (assert-true (kitty-conf-occurs? "DO NOT EDIT!")
        #:name "The header says not to edit the file")
      (assert-true (kitty-conf-occurs? "src/heks-linux/kitty.scm")
        #:name "The header names the source of truth"))
    (test "Settings Follow The System"
      (assert-true (kitty-conf-occurs?
                    (setting-line "font_family" (heks-linux-mono-font)))
        #:name "The font is the environment's monospaced face")
      (assert-equal #:expect 100000
        #:got (assoc-ref (kitty-settings) 'scrollback_lines)
        #:name "Scrollback matches the other terminals")
      (assert-true (kitty-conf-occurs? (setting-line "font_size" 12))
        #:name "The font size matches the other terminals")
      (assert-true (kitty-conf-occurs? (setting-line "window_padding_width" 16))
        #:name "Padding is applied on every side")
      (assert-equal #:expect "/usr/bin/zsh"
        #:got (parameterize ((kitty-shell "/usr/bin/zsh"))
                (assoc-ref (kitty-settings) 'shell))
        #:name "The shell setting is the login shell's own path")
      ;; Kitty resolves a bare name on the PATH it inherits, and the dock's
      ;; children get the development profile's PATH: a bash built without
      ;; programmable completion, which opens a terminal that cannot complete a
      ;; word and prints `shopt: progcomp: invalid shell option name' on start.
      ;; A path absolute in the file is what no PATH can choose for the shell.
      (assert-equal #:expect #f
        #:got (parameterize ((kitty-shell #f))
                (assoc-ref (kitty-settings) 'shell))
        #:name "With no absolute path to offer, the setting is left to Kitty")
      (assert-true (kitty-conf-occurs? (setting-line "cursor_shape" "block"))
        #:name "A block cursor is Emacs's box cursor")
      (assert-true (kitty-conf-occurs? (setting-line "enable_audio_bell" "no"))
        #:name "The audible bell is off")
      (assert-true (kitty-conf-occurs?
                    (setting-line "confirm_os_window_close" 0))
        #:name "Closing the window asks nothing")
      (assert-true (kitty-conf-occurs?
                    (setting-line "background_opacity"
                                  (get-terminal-opacity
                                   (heks-linux-palette))))
        #:name "Opacity follows the palette's terminal-opacity"))
    (test "The Tab Bar Follows Its Switch"
      (assert-true (kitty-conf-occurs? (setting-line "tab_bar_style" "hidden"))
        #:name "The tab bar is hidden by default")
      (assert-equal #:expect #f
        #:got (parameterize ((kitty-tab-bar? #t))
                (kitty-conf-occurs? (setting-line "tab_bar_style" "hidden")))
        #:name "A machine that wants the strip gets Kitty's own style back"))))

(define (colours-suite)
  (suite "Colours"
    (test "Colours Follow The Palette"
      (assert-true (kitty-conf-occurs?
                    (colour-line "foreground"
                                 (get-color (heks-linux-palette) 'text)))
        #:name "The foreground follows the palette")
      (assert-true (kitty-conf-occurs?
                    (colour-line "background"
                                 (get-color (heks-linux-palette) 'background)))
        #:name "The background follows the palette")
      (assert-true (kitty-conf-occurs?
                    (colour-line "cursor"
                                 (get-color (heks-linux-palette) 'primary)))
        #:name "The cursor borrows the accent")
      (assert-true (kitty-conf-occurs?
                    (colour-line "selection_background"
                                 (assoc-ref (kitty-colors)
                                            'selection_background)))
        #:name "The selection band is rendered")
      (assert-true (kitty-conf-occurs?
                    (colour-line "selection_foreground"
                                 (assoc-ref (kitty-colors)
                                            'selection_foreground)))
        #:name "The selection ink is rendered")
      (assert-equal #:expect #f
        #:got (equal? (assoc-ref (kitty-colors) 'selection_background)
                      (get-color (heks-linux-palette) 'background-l))
        #:name "The selection is not the elevation tone that was invisible"))
    (test "The Selection Is Visible On Every Palette"
      ;; background-l is a shade away from background and read as a smudge.
      ;; The band is mixed from the text colour instead; these two floors are
      ;; what "visible" and "readable" mean here, and they are checked against
      ;; every shipped palette rather than the one this machine happens to wear.
      (for-each (lambda (name)
                  (parameterize ((heks-linux-palette name))
                    (let* ((colours (kitty-colors))
                           (band (assoc-ref colours 'selection_background))
                           (ink (assoc-ref colours 'selection_foreground))
                           (background (get-color name 'background)))
                      (assert-true (>= (contrast-ratio band background) 2.0)
                        #:name
                        (format #f "~a: the band stands out from the background"
                                name))
                      (assert-true (>= (contrast-ratio ink band) 4.5)
                        #:name
                        (format #f "~a: the selected text stays readable"
                                name)))))
                (palette-names)))))

(define (emacs-layer-suite)
  (suite "Emacs Layer"
    (test "The Prefix Is C-x One Modifier Up"
      (assert-true (kitty-conf-occurs? "map --new-mode emacs")
        #:name "Control+Shift+X opens the mode")
      (assert-true (kitty-conf-occurs? (format #f "~a" (kitty-emacs-prefix)))
        #:name "The prefix is the C-x key with Shift held"))
    (test "The Emacs Commands Keep Their Second Keys"
      (assert-true (kitty-conf-occurs? "map --mode emacs t new_tab")
        #:name "C-x t opens a tab")
      (assert-true (kitty-conf-occurs?
                    "map --mode emacs 2 launch --location=hsplit")
        #:name "C-x 2 splits below")
      (assert-true (kitty-conf-occurs?
                    "map --mode emacs 3 launch --location=vsplit")
        #:name "C-x 3 splits right")
      (assert-true (kitty-conf-occurs? "map --mode emacs o next_window")
        #:name "C-x o moves to the other window")
      (assert-true (kitty-conf-occurs? "map --mode emacs 0 close_window")
        #:name "C-x 0 closes the window")
      (assert-true (kitty-conf-occurs?
                    "map --mode emacs 1 close_other_windows_in_tab")
        #:name "C-x 1 leaves one window")
      (assert-true (kitty-conf-occurs? "map --mode emacs b next_tab")
        #:name "C-x b moves to the next tab, like switch-to-buffer")
      (assert-true (kitty-conf-occurs? "map --mode emacs k close_tab")
        #:name "C-x k closes the tab, like kill-buffer")
      (assert-true (kitty-conf-occurs? "map --mode emacs [ scroll_page_up")
        #:name "C-x [ pages the scrollback back")
      (assert-true (kitty-conf-occurs? "map --mode emacs ] scroll_page_down")
        #:name "C-x ] pages the scrollback forward")
      (assert-true (kitty-conf-occurs?
                    "map --mode emacs = change_font_size all +2.0")
        #:name "C-x = grows the font")
      (assert-true (kitty-conf-occurs?
                    "map --mode emacs - change_font_size all -2.0")
        #:name "C-x - shrinks the font")
      (assert-true (kitty-conf-occurs?
                    "map --mode emacs ctrl+0 change_font_size all 0")
        #:name "C-x C-0 resets the font"))
    (test "A Bare Plus Is Never A Trigger"
      ;; Kitty reads a plus as the modifier separator, so 'map ... + action'
      ;; is dropped with a warning.  Shift+equal is the chord a plus is typed
      ;; with, and it has to be spelled out.
      (assert-equal #:expect #f
        #:got (kitty-conf-occurs? "map --mode emacs + ")
        #:name "The plus is spelled shift+equal")
      (assert-true (kitty-conf-occurs?
                    "map --mode emacs shift+equal change_font_size all +2.0")
        #:name "Shift+equal grows the font too"))
    (test "The Layer Is One-Shot And Safe"
      (assert-true (kitty-conf-occurs? "--on-action=end")
        #:name "A bound key ends the layer, as C-x does")
      (assert-true (kitty-conf-occurs? "--on-unknown=passthrough_and_end")
        #:name "An unknown second key reaches the application and ends the mode")
      (assert-true (kitty-conf-occurs?
                    (format #f "--timeout ~a" (kitty-emacs-mode-timeout)))
        #:name "An abandoned prefix gives up on its own"))
    (test "One Opening Line And One Line Per Command"
      (assert-equal #:expect (+ 1 (length (kitty-emacs-keys)))
        #:got (length (filter (lambda (line)
                                (string-prefix? "map " line))
                              (kitty-lines)))
        #:name "The layer is one mode opener and one mapping per key"))))

(define (no-stolen-chords-suite)
  (suite "No Stolen Chords"
    (test "The Bare Emacs Chords Reach The Application"
      ;; WezTerm could hand a claimed chord back to the program in the pane;
      ;; Kitty cannot, so none of these may appear as a top-level map.
      (for-each (lambda (chord)
                  (assert-equal #:expect #f
                    #:got (kitty-conf-occurs? (format #f "map ~a " chord))
                    #:name (format #f "~a is left to the application" chord)))
                '("ctrl+a" "ctrl+e" "ctrl+k" "ctrl+y" "ctrl+w" "ctrl+c"
                  "ctrl+x" "ctrl+v" "alt+w" "alt+v")))
    (test "Kitty Reloads Without A Restart"
      (assert-true (kitty-conf-occurs? (format #f "~a" "maak install-kitty"))
        #:name "The header names the install task"))))

(define (spec)
  (veritas-run (settings-suite)
    (colours-suite)
    (emacs-layer-suite)
    (no-stolen-chords-suite)))
