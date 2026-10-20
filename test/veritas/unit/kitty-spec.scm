;;; heks-linux

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; heks-linux is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; heks-linux is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with heks-linux.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Unit tests for (heks-linux kitty).  kitty only understands its own
;; @code{key value} syntax, so the tests render the configuration through
;; @code{mk-kv-conf-lines} with the @code{spaced-conf-pair} template - the very
;; same call the installer makes.
;;
;; The binding assertions are deliberately about the key *names*: kitty silently
;; drops a @code{map} line whose key it does not recognise, so a typo here is a
;; shortcut that quietly stops working rather than an error the user would see.

;;; Code:

(define-module (veritas unit kitty-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux kitty)
  #:use-module (heks-linux prelude)
  #:export (spec))

(define (render-kitty-config)
  "Render the kitty configuration the way it is written to disk."
  (mk-kv-conf-lines (kitty-config) #:template spaced-conf-pair))

(define (kitty-conf-occurs? fragment)
  (not (eq? #f (string-contains (render-kitty-config) fragment))))

(define kitty-suite
  (suite "Kitty Terminal Suite"
         (test "Modifier Translation Uses Kitty Spelling"
               (assert-equal #:expect "ctrl+shift"
                             #:got (translate-kitty-mods "C-S")
                             #:name "Modifiers are joined with a plus sign")
               (assert-equal #:expect "alt+super"
                             #:got (translate-kitty-mods "M-s")
                             #:name "Alt and Super are spelled out")
               (assert-equal #:expect "ctrl+Custom"
                             #:got (translate-kitty-mods "C-Custom")
                             #:name "Unknown modifiers pass through"))

         (test "Bindings Render As Map Lines"
               (assert-equal #:expect "map ctrl+y paste_from_clipboard\n"
                             #:got (serialize-kitty-binding #:mods "C"
                                                            #:k "y"
                                                            #:action
                                                            'paste_from_clipboard)
                             #:name "A symbol action renders bare")
               (assert-equal #:expect
                             "map ctrl+shift+plus change_font_size all +2.0\n"
                             #:got (serialize-kitty-binding #:mods "C-S"
                                                            #:k "plus"
                                                            #:action
                                                            "change_font_size all +2.0")
                             #:name "A string action keeps its arguments"))

         (test "Generated File Declares Every Section"
               (assert-true (kitty-conf-occurs?
                             "# ====== Heks-Linux Kitty configuration ======")
                            #:name "The file carries a generated-file header")
               (assert-true (kitty-conf-occurs? "# --- Font ---")
                            #:name "A font section is emitted")
               (assert-true (kitty-conf-occurs? "# --- Key bindings ---")
                            #:name "A key-binding section is emitted")
               (assert-true (kitty-conf-occurs? "scrollback_lines 100000")
                            #:name "Scrollback is configured"))

         (test "Key Bindings Use Key Names Kitty Recognises"
               (assert-true (kitty-conf-occurs? "map ctrl+y paste_from_clipboard")
                            #:name "Control+Y pastes")
               (assert-true (kitty-conf-occurs? "map alt+w copy_to_clipboard")
                            #:name "Alt+W copies")
               (assert-true (kitty-conf-occurs?
                             "map ctrl+shift+equal change_font_size all +2.0")
                            #:name "Font size grows with ctrl+shift+equal")
               (assert-true (kitty-conf-occurs?
                             "map ctrl+shift+minus change_font_size all -2.0")
                            #:name "Font size shrinks with ctrl+shift+minus")
               (assert-true (kitty-conf-occurs? "map ctrl+shift+home scroll_home")
                            #:name "Ctrl+shift+home jumps to the top of the scrollback")
               (assert-true (kitty-conf-occurs? "map ctrl+shift+end scroll_end")
                            #:name "Ctrl+shift+end jumps to the bottom of the scrollback")
               (assert-true (kitty-conf-occurs?
                             "map ctrl+shift+page_down scroll_page_down")
                            #:name "Scrollback pages down with ctrl+shift+page_down"))

         (test "The Pager Keeps The Emacs Page Keys"
               ;; C-v / M-v belong to the pager (forw-screen / back-screen in
               ;; the shared lesskey file); kitty cannot make a binding
               ;; conditional on the alternate screen, so it must not claim
               ;; them at all.
               (assert-equal #:expect #f
                             #:got (kitty-conf-occurs? "map ctrl+v")
                             #:name "Control+V is not bound by the terminal")
               (assert-equal #:expect #f
                             #:got (kitty-conf-occurs? "map alt+v")
                             #:name "Alt+V is not bound by the terminal"))))

(define (spec)
  (veritas-run kitty-suite))
