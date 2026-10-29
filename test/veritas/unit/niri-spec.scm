;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

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
  #:use-module (heks-linux rofi)
  #:use-module (heks-linux user-settings)
  #:export (spec))

(define (render-niri-config)
  "Serialize the full niri configuration to KDL text."
  (string-join (serialize-kdl (niri-config)) "\n"))

(define (niri-conf-occurs? fragment)
  (not (eq? #f (string-contains (render-niri-config) fragment))))

;; A fragment is only telling when it belongs to the rule it is read in: `blur
;; true' and `xray false' appear in several layer rules, so this looks just past
;; the namespace the rule opens with instead of anywhere in the file.
(define (niri-rule-occurs? namespace fragment)
  (let* ((conf (render-niri-config))
         (start (string-contains conf
                                 (format #f "match namespace=\"^~a$\""
                                         namespace))))
    (if (not start)
        #f
        (let ((end (min (string-length conf) (+ start 300))))
          (not (eq? #f (string-contains (substring conf start end)
                                        fragment)))))))

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
               (assert-true (niri-conf-occurs? "heks-toon palettes")
                #:name
                "The palette chooser should be reachable from a binding, on its own view")
               (assert-true (niri-conf-occurs? "makoctl mode -t do-not-disturb")
                #:name "Do-not-disturb should be reachable from a binding"))

         (test "The Reference Window Opens Focused And Blurred"
               ;; heks-toon maps its window without asking for activation, so
               ;; without this rule it opens behind whatever is focused and a
               ;; click on the bar looks like it did nothing.
               (assert-true (niri-conf-occurs?
                             "match app-id=\"^org.jointhefreeworld.heks-toon$\"")
                #:name "The window should be matched by its application id")
               (assert-true (niri-conf-occurs? "open-focused true")
                #:name "The window should be focused the moment it opens")
               (assert-true (niri-conf-occurs? "blur true")
                #:name "The compositor should blur what is behind the glass"))

         (test "WezTerm Is The Main Terminal"
               (assert-true (niri-conf-occurs?
                             "Mod+T hotkey-overlay-title=\"Launch WezTerm terminal emulator\"")
                #:name "Super+T should launch WezTerm")
               (assert-true (niri-conf-occurs? "spawn-sh \"wezterm\"")
                #:name "The terminal binding should spawn wezterm")
               (assert-true (not (niri-conf-occurs? "alacritty"))
                #:name "Alacritty must no longer be referenced")
               (assert-true (not (niri-conf-occurs? "kitty"))
                #:name "kitty must no longer be referenced"))

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

         (test "The Menu Bar Casts A Shadow And Sips The Wallpaper"
               ;; A layer surface is clipped to its own rectangle, so the bar's
               ;; own box-shadow is thrown away.  Niri draws the shadow the Mac
               ;; menu bar cast, and saturates the backdrop the bar's thin veil
               ;; lets through.
               (assert-true (niri-conf-occurs? "match namespace=\"^waybar$\"")
                #:name "The bar should be matched by its layer namespace")
               (assert-true (niri-conf-occurs? "softness 10")
                #:name "The bar's shadow should be short and soft")
               (assert-true (niri-conf-occurs? "saturation 1.8")
                #:name "The backdrop should be saturated under the bar's veil")
               ;; The menus that drop from the bar are the same kind of surface,
               ;; and float the same way - with a longer shadow, and corners
               ;; that match Rofi's own so the shadow does not poke out behind
               ;; a rounded panel.
               (assert-true (niri-conf-occurs? "match namespace=\"^rofi$\"")
                #:name "The menus should be matched by their layer namespace")
               (assert-true (niri-conf-occurs? "geometry-corner-radius 18")
                #:name "The menus' shadow should follow the panel's own corners")
               (assert-true (niri-conf-occurs? "xray false")
                #:name "A menu's glass should show the window it drops over")
               ;; The shadow is not a blur effect: a machine that turns blur off
               ;; still has a menu bar with a shadow, and says so explicitly.
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((heks-linux-blur? #f))
                                            (render-niri-config))
                                          "softness 10")))
                #:name "The bar should keep its shadow on a machine without blur")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((heks-linux-blur? #f))
                                            (render-niri-config))
                                          "blur false")))
                #:name "Turning blur off should tell the compositor, not just omit the rule")
               ;; Every number in that material is a setting too: the two
               ;; shadows, the vibrancy, and the corner the menus' shadow has to
               ;; share with the panel it belongs to.
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((niri-bar-shadow-softness 4)
                                                         (niri-menu-shadow-softness 6))
                                            (render-niri-config))
                                          "softness 4")))
                #:name "The bar's shadow softness should be a setting")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((niri-menu-shadow-softness 6))
                                            (render-niri-config))
                                          "softness 6")))
                #:name "So should the menus'")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((niri-bar-shadow-color
                                                          "#000000aa"))
                                            (render-niri-config))
                                          "#000000aa")))
                #:name "So should its colour")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((niri-bar-shadow-offset-y 5))
                                            (render-niri-config))
                                          "offset x=0 y=5")))
                #:name "So should where it falls")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((niri-layer-saturation 1.2))
                                            (render-niri-config))
                                          "saturation 1.2")))
                #:name "The vibrancy should be a setting")
               ;; One radius, two programs: the panel rounds its corners with
               ;; it, so the compositor rounds the shadow with the same number.
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((rofi-window-radius 10))
                                            (render-niri-config))
                                          "geometry-corner-radius 10")))
                #:name
                "The menus' shadow should follow the panel's own radius setting"))

         (test "The Dock's Launchpad Frosts What It Covers"
               ;; The launchpad is the dock's full screen overlay and its
               ;; backdrop is translucent, but a Wayland client cannot blur what
               ;; is behind its own surface: the frost is the compositor's,
               ;; asked for by the namespace lambdock gives the overlay.
               (assert-true (niri-conf-occurs?
                             "match namespace=\"^lambdock-launchpad$\"")
                #:name "The launchpad should be matched by its layer namespace")
               (assert-true (niri-rule-occurs? "lambdock-launchpad" "blur true")
                #:name "The compositor should frost the launchpad's backdrop")
               ;; Like the menus, and unlike the bar: the launchpad drops over
               ;; windows, so its glass shows the desktop it is covering.
               (assert-true (niri-rule-occurs? "lambdock-launchpad" "xray false")
                #:name "The launchpad's glass should show what it covers")
               ;; One switch, two halves of the look: the dock only leaves its
               ;; backdrop translucent when this desktop frosts its surfaces.
               (assert-true (parameterize ((heks-linux-blur? #f))
                              (niri-rule-occurs? "lambdock-launchpad"
                                                 "blur false"))
                #:name
                "Turning blur off should tell the compositor, not just omit the rule"))

         (test "The Session Starts The Machine's Password Manager"
               ;; The login line and the bar's key glyph are one setting: a
               ;; machine that changed one and not the other would start a vault
               ;; it cannot click.
               (assert-true (niri-conf-occurs?
                             (format #f "spawn-sh-at-startup \"~a ~a\""
                                     (heks-linux-password-command)
                                     (heks-linux-password-startup-args)))
                #:name
                "The session should start the password manager quietly")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((heks-linux-password-command
                                                          "keepassxc")
                                                         (heks-linux-password-startup-args
                                                          "--minimized"))
                                            (render-niri-config))
                                          "spawn-sh-at-startup \"keepassxc --minimized\"")))
                #:name "Another manager and its own quiet flag should come through")
               (assert-equal #:expect "keepassxc"
                             #:got
                             (parameterize ((heks-linux-password-command "keepassxc")
                                            (heks-linux-password-startup-args ""))
                               (niri-password-startup))
                             #:name
                             "A manager with no quiet start should start plainly")
               (assert-true (not (eq? #f (string-contains (render-niri-config)
                                                          "spawn-sh-at-startup \"1password --silent\"")))
                #:name
                "The default should be the distribution's 1password, not the Flatpak"))

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
