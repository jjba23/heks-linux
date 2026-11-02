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

;; The same question about a window rule: `open-fullscreen true' is written
;; once per application, so a fragment only tells when it belongs to the rule
;; that names the application.
(define (niri-app-rule-occurs? app-id fragment)
  (let* ((conf (render-niri-config))
         (start (string-contains conf
                                 (format #f "match app-id=\"^~a$\"" app-id))))
    (if (not start)
      #f
      (let ((end (min (string-length conf) (+ start 200))))
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

    (test "The Wide Applications Open At The Full Width, Bar And All"
      ;; Niri lays a new window into a column two-thirds wide, which is the
      ;; wrong shape for a browser page or a video editor.  The answer is
      ;; `maximized', not `fullscreen': the window takes every column of
      ;; pixels the layout has, and the bar is still drawn above it, so the
      ;; desktop it launches the next thing from is still there.
      (assert-true (niri-app-rule-occurs? "google-chrome"
                                          "open-maximized true")
        #:name "Chrome should open at the full width")
      (assert-true (niri-app-rule-occurs? "firefox" "open-maximized true")
        #:name "Firefox should open at the full width")
      (assert-true (niri-app-rule-occurs? "org.mozilla.firefox"
                                          "open-maximized true")
        #:name "So should the Flatpak, which announces its sandbox id")
      (assert-true (niri-app-rule-occurs? "org.kde.kdenlive"
                                          "open-maximized true")
        #:name "The video editor should open at the full width")
      (assert-true (niri-app-rule-occurs? "com.obsproject.Studio"
                                          "open-maximized true")
        #:name "The live mixer should open at the full width")
      (assert-true (niri-app-rule-occurs? "mpv" "open-maximized true")
        #:name "So should the video players")
      (assert-true (niri-app-rule-occurs? "org.gnome.Nautilus"
                                          "open-maximized true")
        #:name "A file manager should take the width and keep the bar")
      ;; Fullscreen is the other answer, and it is not this one: it covers
      ;; the layer surfaces too, so nothing this desktop installs opens in
      ;; it unless a machine asks for it by id.
      (assert-true (eq? #f (string-contains (render-niri-config)
                                            "open-fullscreen"))
        #:name "Nothing should open fullscreen by default")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-fullscreen-apps
                                                 '("my-app")))
                                   (render-niri-config))
                                 "open-fullscreen true")))
        #:name "But a machine should still be able to ask for it")
      ;; A dialog is not a column, and the vault is nobody else's business.
      (assert-true (niri-app-rule-occurs? "pavucontrol" "open-floating true")
        #:name "A mixer should float over the work it is changing")
      (assert-true (niri-app-rule-occurs? "1password"
                                          "block-out-from \"screen-capture\"")
        #:name "The vault should stay out of screenshots and screencasts")
      ;; An id is a pattern to Niri, so it is anchored: `obs' must not
      ;; claim a window that merely starts with the same letters.
      (assert-equal #:expect "\"^obs$\"" #:got (niri-app-id-pattern "obs")
        #:name "Application ids should be matched whole")
      ;; Every group is a setting, read when the file is rendered.
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-maximized-apps
                                                 '("my-app")))
                                   (render-niri-config))
                                 "match app-id=\"^my-app$\"")))
        #:name "The maximized list should be a setting")
      (assert-true (eq? #f
                        (string-contains
                         (parameterize ((niri-maximized-apps '())
                                        (niri-floating-apps '())
                                        (niri-private-apps '()))
                           (render-niri-config))
                         "open-maximized"))
        #:name
        "Emptying the lists should leave no rule that matches nothing")
      (assert-true (eq? #f
                        (string-contains
                         (parameterize ((niri-private-apps '()))
                           (render-niri-config))
                         "block-out-from"))
        #:name "A machine that wants its vault in screenshots should say so"))

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

    (test "The Menu Bar Casts No Shadow And Sips The Wallpaper"
      ;; A layer surface is clipped to its own rectangle, so a bar's own
      ;; box-shadow is thrown away; the compositor has to draw one.  It does not,
      ;; by default: a menu bar is the top of the screen and not a panel floating
      ;; over it, and what separates it from what is under it is the hairline its
      ;; own stylesheet draws.  A shadow there is measurably what breaks that
      ;; illusion - on a light palette it darkened the first fourteen pixels of
      ;; every window by up to 23%.  What the compositor does draw for the bar is
      ;; the vibrancy: the backdrop is saturated under the bar's thin veil.
      (assert-true (niri-conf-occurs? "match namespace=\"^waybar$\"")
        #:name "The bar should be matched by its layer namespace")
      (assert-true (not (niri-conf-occurs? "softness 10"))
        #:name "The bar should cast no shadow by default")
      (assert-true (parameterize ((niri-bar-shadow? #t))
                     (niri-conf-occurs? "softness 10"))
        #:name
        "A machine that wants the shadow back should get it, short and soft")
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
      ;; still has a menu bar with the material it asked for, and says so
      ;; explicitly.
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((heks-linux-blur? #f)
                                                (niri-bar-shadow? #t))
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
                                 (parameterize ((niri-bar-shadow? #t)
                                                (niri-bar-shadow-softness 4)
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
                                 (parameterize ((niri-bar-shadow? #t)
                                                (niri-bar-shadow-color
                                                 "#000000aa"))
                                   (render-niri-config))
                                 "#000000aa")))
        #:name "So should its colour")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-bar-shadow? #t)
                                                (niri-bar-shadow-offset-y 5))
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

    (test "The Notifications Get No Rule At All"
      ;; mako draws its banners on a layer surface sized for the whole stack, not
      ;; for the banner on screen, so a shadow or a blur applied to that surface
      ;; is drawn around a rectangle nobody can see: the first put a dark halo
      ;; around empty space, the second a grey box above and behind the banner.
      ;; Measured on the running desktop, then removed - the banner's own
      ;; hairline is its edge.
      (assert-equal #:expect #f
        #:got (niri-conf-occurs?
               "match namespace=\"^notifications$\"")
        #:name
        "No layer rule should match mako's banners")
      (assert-true (niri-conf-occurs? "match namespace=\"^rofi$\"")
        #:name
        "The launcher keeps its rule; only the banners lost theirs"))

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

    (test "The Dock Is Started Once Per Session"
      ;; Niri re-runs the whole startup list on every config reload, and
      ;; lambdock draws a layer surface per instance, so an unguarded
      ;; entry stacked a second dock on the first each time the config
      ;; file was rewritten.  The launch holds a lock in the session's
      ;; runtime directory for as long as the dock lives instead.
      (assert-true (niri-conf-occurs?
                    "spawn-sh-at-startup \"flock -n ${XDG_RUNTIME_DIR:-/tmp/heks-linux-$USER}/lambdock-session.lock lambdock")
        #:name "The dock should start under a lock held for its lifetime")
      (assert-true (not (niri-conf-occurs? "spawn-sh-at-startup \"lambdock"))
        #:name "The dock should never be started under its bare name")
      ;; A restart is not an exception: the dock the keybinding just
      ;; killed is still holding the lock while it dies, so the
      ;; replacement queues for it rather than failing inside that
      ;; window and leaving no dock at all.
      (assert-true (niri-conf-occurs?
                    "pkill lambdock || true; flock -w 2 ${XDG_RUNTIME_DIR:-/tmp/heks-linux-$USER}/lambdock-session.lock lambdock")
        #:name "Restarting the dock should queue for the same lock"))

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
                             (string-contains (parameterize ((niri-keyboard-options '("lv3:ralt_switch"
                                                                                      "esperanto:qwerty")))
                                                (render-niri-config))
                                              "options \"esperanto:qwerty,lv3:ralt_switch,ctrl:nocaps\"")))
        #:name
        "Extra XKB options should be comma-joined with ctrl:nocaps")
      (assert-true (not (eq? #f
                             (string-contains (parameterize ((niri-keyboard-options '("esperanto:qwerty")))
                                                (render-niri-config))
                                              "options \"esperanto:qwerty,ctrl:nocaps\"")))
        #:name
        "A single extra option should still compose with ctrl:nocaps")
      (assert-true (not (eq? #f
                             (string-contains (parameterize ((niri-caps-to-ctrl?
                                                              #f)
                                                             (niri-keyboard-options '("esperanto:qwerty")))
                                                (render-niri-config))
                                              "options \"esperanto:qwerty\"")))
        #:name "Without ctrl:nocaps the extra options stand alone")
      (assert-true (not (eq? #f
                             (string-contains (parameterize ((niri-keyboard-options '("ctrl:nocaps")))
                                                (render-niri-config))
                                              "options \"ctrl:nocaps\"")))
        #:name "Repeated configuration does not generate redundancies"))))

(define (spec)
  (veritas-run niri-suite))
