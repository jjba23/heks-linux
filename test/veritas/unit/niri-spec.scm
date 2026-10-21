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
;; Unit tests for (heks-linux niri).  The compositor configuration is a tree of
;; records that gets serialized to KDL, so these tests render the whole file to
;; a string and assert on the resulting text - exactly what niri parses.

;;; Code:

(define-module (veritas unit niri-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux niri)
  #:use-module (heks-linux prelude)
  #:export (spec))

(define (render-niri-config)
  "Serialize the full niri configuration to KDL text."
  (string-join (serialize-kdl (niri-config)) "\n"))

(define (niri-conf-occurs? fragment)
  (not (eq? #f (string-contains (render-niri-config) fragment))))

(define niri-suite
  (suite "Niri Configuration Suite"
         (test "Configuration Serializes To KDL"
               (assert-true (string-prefix? "// ====== Heks-Linux Niri configuration ======"
                                            (render-niri-config))
                #:name "The generated config should start with the Heks header")
               (assert-true (niri-conf-occurs? "input {")
                            #:name "An input block should be emitted")
               (assert-true (niri-conf-occurs? "binds {")
                            #:name "A binds block should be emitted"))

         (test "macOS And Omarchy Parity Bindings"
               (assert-true (niri-conf-occurs?
                             "Mod+space hotkey-overlay-title=\"Open Rofi spotlight application launcher\"")
                #:name "Super+Space should open the spotlight launcher")
               (assert-true (niri-conf-occurs? "Mod+Shift+space")
                #:name "Toggling floating mode should move to Super+Shift+Space")
               (assert-true (niri-conf-occurs? "Mod+Return")
                #:name "Super+Return should open a terminal, as in Omarchy")
               (assert-true (niri-conf-occurs? "Mod+Q")
                #:name "Super+Q should close the focused window")
               (assert-true (niri-conf-occurs? "Mod+V")
                #:name "Super+V should browse the clipboard history")
               (assert-true (niri-conf-occurs? "rofi -show theme")
                #:name "The theme picker should be reachable from a binding")
               (assert-true (niri-conf-occurs? "makoctl mode -t do-not-disturb")
                #:name "Do-not-disturb should be reachable from a binding"))

         (test "Clipboard History Is Recorded"
               (assert-true (niri-conf-occurs?
                             "wl-paste --type text --watch clipman store --no-persist")
                #:name
                "The clipboard watcher should be started with the session"))

         (test "Startup Scripts Exist Under ~/.local/bin"
               (assert-true (niri-conf-occurs? "write-heks-linux-dconf-settings")
                #:name
                "The startup entry must name the script that the dconf module installs")
               (assert-true (not (niri-conf-occurs? "write-heks-dconf-settings"))
                #:name
                "The stale, non-existent startup script name must be gone"))

         (test "Springy macOS Style Motion"
               (assert-true (niri-conf-occurs? "window-open {")
                            #:name "Window opening should be animated")
               (assert-true (niri-conf-occurs? "damping-ratio")
                            #:name "Animations should be spring driven")
               (assert-true (niri-conf-occurs? "workspace-switch")
                            #:name "Workspace switches should be animated"))

         (test "Rounded Windows And Soft Shadows"
               (assert-true (niri-conf-occurs? "geometry-corner-radius 12")
                            #:name "Windows should get a rounded corner radius")
               (assert-true (niri-conf-occurs? "shadow {")
                            #:name "Windows should cast a drop shadow"))

         (test "Natural Scrolling Follows Its Setting"
               (assert-true (not (niri-conf-occurs? "natural-scroll"))
                #:name
                "Natural scrolling should stay off while the setting is disabled")
               (assert-true
                (not (eq? #f (string-contains
                              (parameterize ((niri-natural-scroll? #t))
                                (render-niri-config))
                              "natural-scroll")))
                #:name
                "Enabling the setting should emit natural-scroll into the config"))

         (test "Extra Keyboard Options Are Composed With Caps To Ctrl"
               (assert-true (not (eq? #f
                                      (string-contains (parameterize ((niri-keyboard-options '
                                                                       ("lv3:ralt_switch"
                                                                        "esperanto:qwerty")))
                                                         (render-niri-config))
                                       "options \"esperanto:qwerty,lv3:ralt_switch,ctrl:nocaps\"")))
                #:name
                "Extra XKB options should be comma-joined with ctrl:nocaps")
               (assert-true (not (eq? #f
                                      (string-contains (parameterize ((niri-keyboard-options '
                                                                       ("esperanto:qwerty")))
                                                         (render-niri-config))
                                       "options \"esperanto:qwerty,ctrl:nocaps\"")))
                #:name
                "A single extra option should still compose with ctrl:nocaps")
               (assert-true (not (eq? #f
                                      (string-contains (parameterize ((niri-caps-to-ctrl?
                                                                       #f)
                                                                      (niri-keyboard-options '
                                                                       ("esperanto:qwerty")))
                                                         (render-niri-config))
                                       "options \"esperanto:qwerty\"")))
                #:name "Without ctrl:nocaps the extra options stand alone")
               (assert-true (not (eq? #f
                                      (string-contains (parameterize ((niri-keyboard-options '
                                                                       ("ctrl:nocaps")))
                                                         (render-niri-config))
                                       "options \"ctrl:nocaps\"")))
                #:name "Repeated configuration does not generate redundancies"))))

(define (spec)
  (veritas-run niri-suite))
