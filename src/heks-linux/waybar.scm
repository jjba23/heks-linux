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
  #:export (install-waybar-config waybar-css
                                  waybar-bar-bg
                                  waybar-power-menu
                                  waybar-power-button
                                  waybar-start-button
                                  waybar-audio-icon
                                  waybar-power-profiles
                                  waybar-battery-2
                                  waybar-battery
                                  waybar-clock
                                  waybar-taskbar
                                  waybar-backlight
                                  waybar-conf))

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

(define waybar-power-button
  `(custom/power (format . "sys")
                 (tooltip . #f)
                 (menu . "on-click")
                 (menu-file . "$HOME/.config/waybar/power_menu.xml")
                 (menu-actions (shutdown . "systemctl poweroff")
                               (reboot . "systemctl reboot")
                               (suspend . "systemctl suspend")
                               (hibernate . "systemctl hibernate"))))

(define* (waybar-start-button #:key (content "λ heks-linux"))
  `(custom/waybar-start-button (format unquote content)
                               (on-click . "pkill rofi || rofi -show drun")))

(define waybar-audio-icon
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

(define waybar-power-profiles
  `(power-profiles-daemon (format . "{icon}")
                          (tooltip-format . "Power profile: {profile}\nDriver: {driver}")
                          (tooltip . #t)
                          (format-icons (default . "\uf0e7 -")
                                        (performance . "\uf0e7 perf")
                                        (balanced . "\uf24e bal")
                                        (power-saver . "\uf06c eco"))))

(define waybar-battery-2
  `(#{battery#bat2}# (bat . "BAT2")))

(define waybar-battery
  `(battery (states (warning . 30)
                    (critical . 15))
            (format . "{capacity}% {icon}")
            (format-full . "{capacity}% {icon}")
            (format-charging . "{capacity}% \uf0e7")
            (format-plugged . "{capacity}% \uf0e7")
            (format-alt . "{time} {icon}")
            (format-icons . #("\uf244" "\uf243" "\uf242" "\uf241" "\uf240"))))

(define waybar-clock
  `(clock (on-click . "gnome-calendar")
          (format . "{:%H:%M - %a, %d %B %Y}")
          (tooltip-format . "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>")
          (interval . 60)))

(define* (waybar-taskbar)
  `(wlr/taskbar (format . "{icon} {title:.28}")
                (icon-size . 16)
                (icon-theme unquote
                            (get-icon-theme (heks-linux-palette)))
                (tooltip-format . "{title}")
                (on-click . "activate")
                (on-click-middle . "minimize")))

(define waybar-backlight
  `(backlight (format . "{percent}% {icon}")
              (format-icons . #("\ue38d" "\ue3d3" "\ue3d1" "\ue3cf" "\ue3ce" "\ue3cd" "\ue3ca" "\ue3c8" "\ue39b"))))

;; My WayBar configurations, defined in Guile Scheme, a status bar with a detailed, modular setup.
(define* (waybar-conf #:key palette)
  (let ((modules-left #(custom/waybar-start-button clock custom/media))
        (modules-right
                       #(niri/language pulseaudio power-profiles-daemon cpu memory backlight keyboard-state battery custom/power tray)))
    `((position . top) (height . 38)
      (modules-left unquote modules-left)
      (modules-center)
      (modules-right unquote modules-right)
      ,(waybar-start-button)
      (keyboard-state (numlock . #t)
                      (capslock . #t)
                      (format . "{name} {icon} ")
                      (format-icons (locked . "\uf023")
                                    (unlocked . "\uf09c")))
      (niri/mode (format . "<span style=\"italic\">{}</span>"))
      (tray (spacing . 4))
      ,waybar-clock
      (cpu (format . "\uf2db cpu: {usage}%")
           (tooltip . #f)
           (on-click . "gnome-system-monitor"))
      (memory (format . "\uf0c9 mem: {}%")
              (on-click . "gnome-system-monitor"))
      ,waybar-backlight
      ,waybar-battery
      ,waybar-battery-2
      ,waybar-power-profiles
      ,(waybar-taskbar)
      ,waybar-audio-icon
      ,waybar-power-button)))

(define* (waybar-bar-bg)
  `((background unquote
                (hex-to-rgba (get-color (heks-linux-palette)
                                        'background)
                             #:alpha 0.8))
    (border unquote
            (format #f "1px solid ~a"
                    (hex-to-rgba (get-color (heks-linux-palette)
                                            'background-l)
                                 #:alpha 0.9)))
    (color unquote
           (hex-to-rgba (get-color (heks-linux-palette)
                                   'text-l)
                        #:alpha 1))
    (font-family unquote
                 (format #f "FontAwesome, ~a"
                         (heks-linux-sans-font)))
    (margin-top . "5px")
    (margin-bottom . "5px")
    (margin-left . "13px")
    (margin-right . "13px")
    (font-size . "10pt")))

(define* (waybar-section-css)
  `((font-family unquote
                 (format #f "FontAwesome, ~a"
                         (heks-linux-sans-font)))))

;; Defines a CSS configuration for Heks-Linux Waybar using Scheme.
;; This configuration customizes various UI elements, such as background color,
;; padding, font styles, and colors, with dynamic values.

(define* (waybar-css)
  `((module (background . transparent)
            (font-family unquote
                         (format #f "FontAwesome, ~a"
                                 (heks-linux-sans-font)))
            (color unquote
                   (get-color (heks-linux-palette)
                              'text)))
    ("*" (padding . "2px 9px 2px 9px")
     (font-weight . 500))
    ("#custom-power" unquote
     (waybar-section-css))
    ("#battery" unquote
     (waybar-section-css))
    ("#backlight" unquote
     (waybar-section-css))
    ("#clock" unquote
     (waybar-section-css))
    ("#custom-waybar-start-button" unquote
     (append (waybar-section-css)
             `((margin . "3px") (border-radius . "6px")
               (background unquote
                           (get-color (heks-linux-palette)
                                      'background-l)))))
    ("#cpu" unquote
     (waybar-section-css))
    ("#memory" unquote
     (waybar-section-css))
    ("window" (margin-left . "4px")
     (margin-right . "4px"))
    ("window#waybar" unquote
     (waybar-bar-bg))))

(define (install-waybar-config)
  (with-output-to-file (format #f "~a/.config/waybar/config.jsonc"
                               (getenv "HOME"))
    (lambda ()
      (display (scm->json-string (waybar-conf #:palette (heks-linux-palette))
                                 #:pretty #t))))
  (with-output-to-file (format #f "~a/.config/waybar/style.css"
                               (getenv "HOME"))
    (lambda ()
      (display (mk-css-conf-lines (waybar-css)))))
  (with-output-to-file (format #f "~a/.config/waybar/power_menu.xml"
                               (getenv "HOME"))
    (lambda ()
      (sxml->xml waybar-power-menu))))

