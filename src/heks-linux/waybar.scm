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
  #:use-module (heks-linux prelude)
  #:use-module (sxml simple)
  #:use-module (json)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (install-waybar-config waybar-css
                                  waybar-bar-bg
                                  waybar-power-menu
                                  waybar-power-button
                                  waybar-start-button
                                  waybar-info-button
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
                  #(custom/heks-info niri/language pulseaudio power-profiles-daemon cpu memory backlight keyboard-state battery custom/power tray)))

(define waybar-font-size
  (make-parameter "10pt"))

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
  (make-parameter "{:%H:%M - %a, %d %b}"))

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
  `(custom/power (format . "⏻")
                 (tooltip . #f)
                 (menu . "on-click")
                 (menu-file . "$HOME/.config/waybar/power_menu.xml")
                 (menu-actions (shutdown . "systemctl poweroff")
                               (reboot . "systemctl reboot")
                               (suspend . "systemctl suspend")
                               (hibernate . "systemctl hibernate"))))

(define* (waybar-start-button #:key (content (waybar-start-label)))
  `(custom/waybar-start-button (format unquote content)
                               (tooltip . "Left: Launcher | Right: Hotkeys")
                               (on-click . "pkill rofi || rofi -show drun")
                               (on-click-right . "niri msg action show-hotkey-overlay")))

(define (waybar-info-button)
  `(custom/heks-info (format . "\uf128")
                     (tooltip . "Left: Conjure Hotkeys | Right: Inspect Heks Grimoire")
                     (on-click . "niri msg action show-hotkey-overlay")
                     (on-click-right . "xdg-open 'https://codeberg.org/jjba23/heks-linux'")))

(define (waybar-media)
  `(custom/media (format . "\uf001 {}")
                 (interval . 2)
                 (exec . "playerctl metadata --format '{{title}} - {{artist}}' 2>/dev/null || echo 'Silence'")
                 (max-length . 35)
                 (tooltip . #f)
                 (on-click . "playerctl play-pause")))

(define (waybar-audio-icon)
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
  `(clock (on-click . "gnome-calendar")
          (format unquote
                  (waybar-clock-format))
          (tooltip-format . "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>")
          (interval unquote
                    (waybar-clock-interval))))

(define* (waybar-taskbar)
  `(wlr/taskbar (format . "{icon} {title:.28}")
                (icon-size . 16)
                (icon-theme unquote
                            (get-icon-theme (heks-linux-palette)))
                (tooltip-format . "{title}")
                (on-click . "activate")
                (on-click-middle . "minimize")))

(define (waybar-backlight)
  `(backlight (format . "{percent}% {icon}")
              (format-icons . #("\ue38d" "\ue3d3" "\ue3d1" "\ue3cf" "\ue3ce" "\ue3cd" "\ue3ca" "\ue3c8" "\ue39b"))))

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
    ,(waybar-info-button)
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
  `((background unquote
                (hex-to-rgba (get-color (heks-linux-palette)
                                        'background)
                             #:alpha 0.85))
    (border unquote
            (format #f "1px solid ~a"
                    (hex-to-rgba (get-color (heks-linux-palette)
                                            'background-l)
                                 #:alpha 0.4)))
    (border-radius . "12px")
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
                                #:alpha 0.5))
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

    ("#custom-heks-info" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'text-l))
       (padding . "0px 10px 0px 4px")
       (font-size . "13pt")
       (text-shadow unquote
                    (format #f "0 0 6px ~a"
                            (get-color (heks-linux-palette)
                                       'primary)))))

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
                                #:alpha 0.5))
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
                                #:alpha 0.5))
       (padding . "0px 12px")
       (margin . "4px 6px")
       (border-radius . "6px")))

    ("#battery.warning" unquote
     `((color . "#ff9e3b")))
    ("#battery.critical" unquote
     `((color . "#e82424") (animation . "blink 1s linear infinite")))

    ;; System Tray and Power
    ("#tray" (padding . "0px 8px"))
    ("#custom-power" unquote
     `((margin . "4px 6px") (padding . "2px 12px")
       (border-radius . "6px")
       (background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'background-l)
                                #:alpha 0.8))
       (color unquote
              (get-color (heks-linux-palette)
                         'text-l))))
    ("#custom-power:hover" unquote
     `((background . "#e82424") (color . "#ffffff")))))

;; ===========================================
;; Installation
;; ===========================================

(define* (install-waybar-config)
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
