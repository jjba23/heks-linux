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
;; Unit tests for (heks-linux alacritty).  The configuration is a list of text
;; lines that is joined into @file{alacritty.toml}, so the tests assert against
;; the joined text exactly like Alacritty's TOML parser will read it.
;;
;; The serializers and the key-binding table are pure procedures, which is why
;; the interesting behaviour can be checked without spawning a terminal.

;;; Code:

(define-module (veritas unit alacritty-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux alacritty)
  #:export (spec))

(define (render-alacritty-config)
  "Render the Alacritty configuration the way it is written to disk."
  (string-join (alacritty-config) "\n"))

(define (alacritty-conf-occurs? fragment)
  (not (eq? #f (string-contains (render-alacritty-config) fragment))))

(define (modifier-translation-suite)
  (suite "Modifier Translation"
         (test "Short Modifiers Use Alacritty Spelling"
               (assert-equal #:expect "Control|Shift"
                             #:got (translate-alacritty-mods "C-S")
                             #:name "Modifiers are joined with a vertical bar")
               (assert-equal #:expect "Alt|Super"
                             #:got (translate-alacritty-mods "M-s")
                             #:name "Alt and Super are spelled out")
               (assert-equal #:expect "Control|Custom"
                             #:got (translate-alacritty-mods "C-Custom")
                             #:name "Unknown modifiers pass through"))))

(define (setting-serialization-suite)
  (suite "Setting Serialization"
         (test "Settings Serialize To TOML"
               (assert-equal #:expect "live_config_reload = true"
                             #:got (serialize-alacritty-setting
                                    '(live_config_reload . #t))
                             #:name "Booleans render unquoted")
               (assert-equal #:expect "size = 12"
                             #:got (serialize-alacritty-setting
                                    '(size . 12))
                             #:name "Numbers render unquoted")
               (assert-equal #:expect "shell = \"bash\""
                             #:got (serialize-alacritty-setting
                                    '(shell . "bash"))
                             #:name "Strings are quoted")
               (assert-equal #:expect "padding = { x = 16, y = 16}"
                             #:got (serialize-alacritty-setting
                                    '(padding . "{ x = 16, y = 16}"))
                             #:name "Inline tables pass through verbatim"))))

(define (binding-serialization-suite)
  (suite "Binding Serialization"
         (test "Bindings Render As Inline TOML Tables"
               (assert-equal #:expect
                             "{ key = \"Y\", mods = \"Control\", action = \"Paste\"}"
                             #:got (serialize-alacritty-binding
                                    #:mods "C"
                                    #:k "Y"
                                    #:action 'Paste)
                             #:name "A binding is one inline table"))))

(define (generated-file-suite)
  (suite "Generated File"
         (test "Every Section Is Declared"
               (assert-true (alacritty-conf-occurs?
                             "# ====== Heks-Linux Alacritty configuration ======")
                            #:name "The file carries a generated-file header")
               (assert-true (alacritty-conf-occurs? "[general]")
                            #:name "A general section is emitted")
               (assert-true (alacritty-conf-occurs? "[keyboard]")
                            #:name "A keyboard section is emitted"))
         (test "Key Bindings Are Collected Into One Array"
               (assert-true (alacritty-conf-occurs? "bindings = [")
                            #:name "Bindings are rendered as a TOML array")
               (assert-true (alacritty-conf-occurs?
                             "{ key = \"Y\", mods = \"Control\", action = \"Paste\"}")
                            #:name "Control+Y pastes")
               (assert-true (alacritty-conf-occurs?
                             "{ key = \"Home\", mods = \"Shift\", action = \"ScrollToTop\"}")
                            #:name "Shift+Home jumps to the top of the scrollback"))))

(define (spec)
  (veritas-run (modifier-translation-suite)
               (setting-serialization-suite)
               (binding-serialization-suite)
               (generated-file-suite)))
