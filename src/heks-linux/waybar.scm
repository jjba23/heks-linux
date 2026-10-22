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

(define-module (heks-linux waybar)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux keybindings)
  #:use-module (heks-linux prelude)
  #:use-module (sxml simple)
  #:use-module (json)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (install-waybar-config waybar-css
                                  waybar-bar-bg
                                  waybar-power-menu
                                  waybar-mako-dnd
                                  waybar-border-radius
                                  waybar-power-button
                                  waybar-start-button
                                  waybar-keybindings
                                  waybar-media
                                  waybar-audio-icon
                                  waybar-power-profiles
                                  waybar-battery-2
                                  waybar-battery
                                  waybar-clock
                                  waybar-taskbar
                                  waybar-backlight
                                  waybar-conf
                                  waybar-config-dir
                                  waybar-config-filename
                                  waybar-style-filename
                                  waybar-power-menu-filename
                                  waybar-position
                                  waybar-height
                                  waybar-start-label
                                  waybar-modules-left
                                  waybar-modules-right
                                  waybar-font-size
                                  waybar-margin-top
                                  waybar-margin-bottom
                                  waybar-margin-left
                                  waybar-margin-right
                                  waybar-battery-warning
                                  waybar-battery-critical
                                  waybar-clock-format
                                  waybar-clock-interval))

(define s
  (scriba-auto-logger))

;; ===========================================
;; Configurable Waybar Parameters
;; ===========================================

(define waybar-position
  (make-parameter 'top))

(define waybar-height
  (make-parameter 38))

(define waybar-start-label
  (make-parameter "λ Heks GNU/Linux"))

(define waybar-modules-left
  (make-parameter #(custom/waybar-start-button clock custom/media)))

(define waybar-modules-right
  (make-parameter
                  #(custom/heks-keys custom/mako-dnd niri/language pulseaudio power-profiles-daemon cpu memory backlight keyboard-state battery custom/power tray)))

(define waybar-font-size
  (make-parameter "10pt"))

(define waybar-border-radius
  (make-parameter "0px"))

(define waybar-margin-top
  (make-parameter "6px"))

(define waybar-margin-bottom
  (make-parameter "0px"))

(define waybar-margin-left
  (make-parameter "12px"))

(define waybar-margin-right
  (make-parameter "12px"))

(define waybar-battery-warning
  (make-parameter 30))

(define waybar-battery-critical
  (make-parameter 15))

(define waybar-clock-format
  ;; menu-bar style: short date then time ("Sat 10 Oct  14:03").
  (make-parameter "{:%a %d %b  %H:%M}"))

(define waybar-clock-interval
  (make-parameter 60))

(define waybar-config-dir
  (make-parameter (format #f "~a/.config/waybar"
                          (or (getenv "HOME") "/tmp"))))

(define waybar-config-filename
  (make-parameter "config.jsonc"))

(define waybar-style-filename
  (make-parameter "style.css"))

(define waybar-power-menu-filename
  (make-parameter "power_menu.xml"))

;; ===========================================
;; Layout & Component Definitions
;; ===========================================

;; Waybar power menu, encoding XML as Scheme - SXML - s-expressions
(define waybar-power-menu
  '(*TOP* (*PI* xml "version=\"1.0\" encoding=\"UTF-8\"")
          (interface (object (@ (class "GtkMenu")
                                (id "menu"))
                             (child (object (@ (class "GtkMenuItem")
                                               (id "suspend"))
                                            (property (@ (name "label"))
                                                      "Suspend")))
                             (child (object (@ (class "GtkMenuItem")
                                               (id "hibernate"))
                                            (property (@ (name "label"))
                                                      "Hibernate")))
                             (child (object (@ (class "GtkMenuItem")
                                               (id "logout"))
                                            (property (@ (name "label"))
                                                      "Log Out")))
                             (child (object (@ (class "GtkSeparatorMenuItem")
                                               (id "delimiter1"))))
                             (child (object (@ (class "GtkMenuItem")
                                               (id "shutdown"))
                                            (property (@ (name "label"))
                                                      "Shutdown")))
                             (child (object (@ (class "GtkMenuItem")
                                               (id "reboot"))
                                            (property (@ (name "label"))
                                                      "Reboot")))))))

(define (waybar-power-button)
  "Return the session power button.
Its menu lives in @file{power_menu.xml} next to the bar configuration and covers
locking the session through to rebooting the machine."
  `(custom/power (format . "⏻")
                 (tooltip . #f)
                 (menu . "on-click")
                 (menu-file . "$HOME/.config/waybar/power_menu.xml")
                 (menu-actions (shutdown . "systemctl poweroff")
                               (reboot . "systemctl reboot")
                               (suspend . "systemctl suspend")
                               (hibernate . "systemctl hibernate")
                               (logout . "loginctl terminate-session $XDG_SESSION_ID"))))

(define* (waybar-start-button #:key (content (waybar-start-label)))
  "Return the launcher button at the left edge of the bar.
@var{content} is the label.  A left click opens the Rofi launcher and a right
click the Niri hotkey overlay."
  `(custom/waybar-start-button (format unquote content)
                               (tooltip . "Left: Launcher | Right: Hotkeys")
                               (on-click . "pkill rofi || rofi -show drun")
                               (on-click-right . "niri msg action show-hotkey-overlay")))

(define (waybar-keybindings)
  "Return the question-mark button that opens the keybinding reference.
The reference itself is rendered by @code{(heks-linux keybindings)}; the bar
only has to launch it.  A right click keeps the project page reachable now that
this is the bar's only question mark."
  `(custom/heks-keys (format . "?")
                     (tooltip . "Left: Every keyboard shortcut | Right: Heks Linux project page")
                     (on-click unquote
                               (keybindings-command))
                     (on-click-right . "xdg-open 'https://codeberg.org/jjba23/heks-linux'")))

(define (waybar-mako-dnd)
  "Do-not-disturb indicator. Renders @code{DND} while the mako
@code{do-not-disturb} mode is active and toggles it on click."
  `(custom/mako-dnd (format . "{}")
                    (tooltip . #t)
                    (interval . 3)
                    (exec . "makoctl mode 2>/dev/null | grep -q do-not-disturb && printf 'DND'")
                    (on-click . "makoctl mode -t do-not-disturb")))

(define (waybar-media)
  "Return the now-playing indicator.
Driven by @code{playerctl}: it shows the current title and artist, toggles
playback on click, and falls back to the word Silence when nothing is playing."
  `(custom/media (format . "\uf025 {}")
                 (interval . 2)
                 (exec . "playerctl metadata --format '{{title}} - {{artist}}' 2>/dev/null || echo 'Silence'")
                 (max-length . 35)
                 (tooltip . #f)
                 (on-click . "playerctl play-pause")))

(define (waybar-audio-icon)
  "Return the PulseAudio volume indicator.
Shows the volume, the active source and a Bluetooth badge when a headset is
connected, with a glyph that changes with the output device."
  `(pulseaudio (format . "{volume}% {icon} {format_source}")
               (format-bluetooth . "{volume}% {icon}\uf294 {format_source}")
               (format-bluetooth-muted . "\uf6a9 {icon}\uf294 {format_source}")
               (format-muted . "\uf6a9 {format_source}")
               (format-source . "{volume}% \uf130")
               (format-source-muted . "\uf131")
               (format-icons (headphone . "\uf025")
                             (hands-free . "\uf590")
                             (headset . "\uf590")
                             (phone . "\uf095")
                             (portable . "\uf095")
                             (car . "\uf1b9")
                             (default . #("\uf026" "\uf027" "\uf028")))
               (on-click . "pavucontrol")))

(define (waybar-power-profiles)
  "Return the power-profiles-daemon indicator.
Shows the active profile with a per-profile glyph and names the driver in its
tooltip."
  `(power-profiles-daemon (format . "{icon}")
                          (tooltip-format . "Power profile: {profile}\nDriver: {driver}")
                          (tooltip . #t)
                          (format-icons (default . "\uf0e7 -")
                                        (performance . "\uf0e7 perf")
                                        (balanced . "\uf24e bal")
                                        (power-saver . "\uf06c eco"))))

(define waybar-battery-2
  `(#{battery#bat2}# (bat . "BAT2")))

(define (waybar-battery)
  "Return the battery indicator.
The warning and critical thresholds come from the module parameters, and the
glyph changes while the machine is charging."
  `(battery (states (warning unquote
                             (waybar-battery-warning))
                    (critical unquote
                              (waybar-battery-critical)))
            (format . "{capacity}% {icon}")
            (format-full . "{capacity}% {icon}")
            (format-charging . "{capacity}% \uf0e7")
            (format-plugged . "{capacity}% \uf0e7")
            (format-alt . "{time} {icon}")
            (format-icons . #("\uf244" "\uf243" "\uf242" "\uf241" "\uf240"))))

(define (waybar-clock)
  "Return the clock.
Its format string and refresh interval are parameters, so the bar can show
seconds or a longer date without touching the renderer."
  `(clock (on-click . "gnome-calendar")
          (format unquote
                  (waybar-clock-format))
          (tooltip-format . "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>")
          (interval unquote
                    (waybar-clock-interval))))

(define* (waybar-taskbar)
  "Return the window taskbar.
Lists open windows with their icons and titles; a click activates a window and a
middle click minimizes it."
  `(wlr/taskbar (format . "{icon} {title:.28}")
                (icon-size . 16)
                (icon-theme unquote
                            (get-icon-theme (heks-linux-palette)))
                (tooltip-format . "{title}")
                (on-click . "activate")
                (on-click-middle . "minimize")))

(define (waybar-backlight)
  "Return the screen backlight indicator.
Shows the brightness percentage with a glyph that brightens as the value rises."
  `(backlight (format . "{percent}% {icon}")
              (format-icons . #("\uf186" "\uf6c4" "\uf185"))))

(define* (waybar-conf #:key palette)
  "WayBar configuration, defined in Guile Scheme, a status bar with a detailed, modular setup."
  `((position unquote
              (waybar-position))
    (height unquote
            (waybar-height))
    (modules-left unquote
                  (waybar-modules-left))
    (modules-center)
    (modules-right unquote
                   (waybar-modules-right))
    ,(waybar-start-button)
    ,(waybar-keybindings)
    ,(waybar-mako-dnd)
    ,(waybar-media)
    (keyboard-state (numlock . #t)
                    (capslock . #t)
                    (format . "{name} {icon} ")
                    (format-icons (locked . "\uf023")
                                  (unlocked . "\uf09c")))
    (niri/mode (format . "<span style=\"italic\">{}</span>"))
    (tray (spacing . 6))
    ,(waybar-clock)
    (cpu (format . "\uf2db {usage}%")
         (tooltip . #f)
         (on-click . "gnome-system-monitor"))
    (memory (format . "\uf0c9 {percentage}%")
            (on-click . "gnome-system-monitor"))
    ,(waybar-backlight)
    ,(waybar-battery)
    ,waybar-battery-2
    ,(waybar-power-profiles)
    ,(waybar-taskbar)
    ,(waybar-audio-icon)
    ,(waybar-power-button)))

(define* (waybar-bar-bg)
  "Return the bar's own styling attributes.
The background and border are palette colours rendered as @code{rgba()}, with the
background kept slightly translucent so the compositor blur shows through."
  `((background unquote
                (hex-to-rgba (get-color (heks-linux-palette)
                                        'background)
                             #:alpha 0.8))
    (border unquote
            (format #f "1px solid ~a"
                    (hex-to-rgba (get-color (heks-linux-palette)
                                            'background-l)
                                 #:alpha 0.4)))
    ;; macOS-style rounded floating bar.
    (border-radius unquote
                   (waybar-border-radius))
    (color unquote
           (get-color (heks-linux-palette)
                      'text-l))
    (margin-top unquote
                (waybar-margin-top))
    (margin-bottom unquote
                   (waybar-margin-bottom))
    (margin-left unquote
                 (waybar-margin-left))
    (margin-right unquote
                  (waybar-margin-right))
    (font-size unquote
               (waybar-font-size))))

(define* (waybar-css)
  "Defines a CSS configuration for Heks-Linux Waybar using Scheme."
  `((module (background . transparent)
            (font-family unquote
                         (format #f
                          "FontAwesome, 'Font Awesome 6 Free', 'Font Awesome 6 Brands', '~a'"
                          (heks-linux-sans-font)))
            (color unquote
                   (get-color (heks-linux-palette)
                              'text-l)))
    ("*" (padding . "0px")
     (font-weight . 600)
     (transition . "all 0.25s cubic-bezier(0.4, 0, 0.2, 1)"))

    ;; Global window structure
    ("window" (background . transparent))
    ("window#waybar" unquote
     (waybar-bar-bg))

    ;; Individual stylized module layout (Capsule Architecture)
    ("#custom-waybar-start-button" unquote
     `((margin . "4px") (padding . "2px 14px")
       (border-radius . "8px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text))
       (background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'background-l)
                                #:alpha 0.3))
       (border unquote
               (format #f "1px solid ~a"
                       (get-color (heks-linux-palette)
                                  'primary)))))

    ("#custom-waybar-start-button:hover" unquote
     `((background unquote
                   (get-color (heks-linux-palette)
                              'text))
       (color unquote
              (get-color (heks-linux-palette)
                         'background))
       (border unquote
               (format #f "1px solid ~a"
                       (get-color (heks-linux-palette)
                                  'primary)))))

    ("#custom-heks-keys" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'primary))
       (padding . "0px 10px")
       (margin . "4px 2px")
       (font-size . "12pt")
       (font-weight . 700)
       (border-radius . "6px")
       (background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'background-l)
                                #:alpha 0.3))))

    ("#custom-heks-keys:hover" unquote
     `((background unquote
                   (get-color (heks-linux-palette)
                              'primary))
       (color unquote
              (get-color (heks-linux-palette)
                         'background))))

    ("#clock" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'text))
       (padding . "0px 12px")
       (margin . "4px 0px")
       (border-left unquote
                    (format #f "2px dashed ~a"
                            (get-color (heks-linux-palette)
                                       'background-l)))))

    ("#custom-media" (padding . "0px 14px")
     (font-style . "italic"))

    ;; Hardware monitors group
    ("#cpu, #memory" unquote
     `((background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'background-l)
                                #:alpha 0.3))
       (padding . "0px 10px")
       (margin . "4px 2px")
       (border-radius . "4px")))

    ;; Control loops (Sliders fallback)
    ("#pulseaudio, #backlight" unquote
     `((background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'background-l)
                                #:alpha 0.3))
       (padding . "0px 10px")
       (margin . "4px 0px")))
    ("#pulseaudio" (border-radius . "6px 0px 0px 6px"))
    ("#backlight" (border-radius . "0px 6px 6px 0px")
     (margin-right . "6px"))

    ;; Battery states styling
    ("#battery" unquote
     `((background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'background-l)
                                #:alpha 0.3))
       (padding . "0px 12px")
       (margin . "4px 6px")
       (border-radius . "6px")))

    ("#battery.warning" unquote
     `((color . "#ff9e3b")))
    ("#battery.critical" unquote
     `((color . "#e82424") (animation . "blink 1s linear infinite")))

    ;; System Tray and Power
    ("#tray" (padding . "0px 8px"))
    ("#custom-mako-dnd" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'primary))
       (padding . "0px 6px")
       (font-weight . 700)))
    ("#custom-power" unquote
     `((margin . "4px 6px") (padding . "2px 12px")
       (border-radius . "6px")
       (background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'background-l)
                                #:alpha 0.3))
       (color unquote
              (get-color (heks-linux-palette)
                         'text-l))))
    ("#custom-power:hover" unquote
     `((background . "#e82424") (color . "#ffffff")))))

;; ===========================================
;; Installation
;; ===========================================

(define* (install-waybar-config)
  "Write @file{config.jsonc}, @file{style.css} and @file{power_menu.xml}.
Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/waybar-settings.scm} first.  Waybar has no hot
reload, so restart it after a change."
  (log-info s "Installing Waybar configuration")
  (load-local-overrides '(heks-linux waybar)
                        'waybar-settings)
  (install-config-file! #:name (waybar-config-filename)
                        #:dir (waybar-config-dir)
                        #:contents (scm->json-string (waybar-conf #:palette (heks-linux-palette))
                                                     #:pretty #t))
  (install-config-file! #:name (waybar-style-filename)
                        #:dir (waybar-config-dir)
                        #:contents (mk-css-conf-lines (waybar-css)))
  (install-config-file! #:name (waybar-power-menu-filename)
                        #:dir (waybar-config-dir)
                        #:contents (with-output-to-string (lambda ()
                                                            (sxml->xml
                                                             waybar-power-menu))))
  (log-success s "Installed Waybar configuration"))
