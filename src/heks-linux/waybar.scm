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
  #:use-module (heks-linux toon)
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
                                  waybar-mako-dnd
                                  waybar-border-radius
                                  waybar-power-button
                                  waybar-start-button
                                  waybar-keybindings
                                  waybar-media
                                  waybar-wallpaper
                                  waybar-palette
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
                                  waybar-media-menu-filename
                                  waybar-media-menu-dir
                                  waybar-media-menu
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
  ;; The macOS menu bar: the system label at the far left, then what is in
  ;; front of you.  Everything else is a status item and lives on the right.
  (make-parameter #(custom/waybar-start-button niri/window)))

(define waybar-modules-right
  ;; Status items, in the order macOS keeps them: the things you glance at
  ;; (now playing, do-not-disturb, the input language, the palette, help) come
  ;; first, then the hardware readouts, then the session buttons, and the clock
  ;; closes the row at the right edge.
  (make-parameter
   #(custom/media custom/mako-dnd niri/language custom/heks-palette
                  custom/heks-wallpaper custom/heks-keys cpu memory backlight
                  pulseaudio keyboard-state battery power-profiles-daemon
                  custom/power tray clock)))

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

;; The media popover lives next to the other generated scripts, not next to the
;; bar's configuration: it is a program the bar launches, and ~/.local/bin is
;; where the rest of them are.
(define waybar-media-menu-filename
  (make-parameter "heks-media-menu"))

(define waybar-media-menu-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

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
  "Return the question-mark button that opens the keyboard reference.
The reference is one view of heks-toon, which the bar only has to launch.  A
right click keeps the project page reachable now that this is the bar's only
question mark."
  `(custom/heks-keys (format . "?")
                     (tooltip . "Left: Every keyboard shortcut | Right: Heks Linux project page")
                     (on-click unquote
                               (toon-spawn-command (toon-keys-command)))
                     (on-click-right . "xdg-open 'https://codeberg.org/jjba23/heks-linux'")))

(define (waybar-palette)
  "Return the palette button: one glyph, in the palette's own accent.

Clicking it opens the palette chooser view of heks-toon, where every palette is
a card painted in its own colours; choosing one runs the same Rofi picker the
swatches come from, so a switch reads the same whichever way it was started.
The name of the palette moved into the tooltip when the bar learned to look like
a menu bar - a menu bar carries glyphs, not sentences - and the glyph is Font
Awesome's palette rather than a text label."
  `(custom/heks-palette (format . "\uf53f")
                        (tooltip unquote
                                 (format #f "Palette: ~a — click to switch"
                                         (heks-linux-palette)))
                        ;; Through a shell, like the reference and the wall
                        ;; chooser: Waybar spawns the command line as written,
                        ;; and `toon-spawn-command' is what asks the compositor
                        ;; for the activation a bar click cannot prove.
                        (on-click unquote
                                  (toon-spawn-command (toon-palettes-command)))))

(define (waybar-wallpaper)
  "Return the wallpaper button: one picture glyph, next to the palette.

Clicking it opens the wall chooser view of heks-toon, the collection with a
large preview of whatever is selected - the same window ~Mod+Shift+W~ opens.  It
sits beside the palette glyph because the two are the same kind of thing - the
two halves of how the desktop looks - so a menu bar answers the question of how
it looks from one place."
  `(custom/heks-wallpaper (format . "\uf03e")
                          (tooltip . "Wallpaper: browse the collection")
                          (on-click unquote
                                    (toon-spawn-command (toon-walls-command)))))

(define (waybar-mako-dnd)
  "Do-not-disturb indicator. Renders @code{DND} while the mako
@code{do-not-disturb} mode is active and toggles it on click."
  `(custom/mako-dnd (format . "{}")
                    (tooltip . #t)
                    (interval . 3)
                    (exec . "makoctl mode 2>/dev/null | grep -q do-not-disturb && printf 'DND'")
                    (on-click . "makoctl mode -t do-not-disturb")))

(define (waybar-media)
  "Return the now-playing button: one glyph, with the track in its tooltip.

Clicking it opens the media popover - a small Rofi menu of transport controls
that appears under the bar, the way Control Center's Now Playing does.  The bar
itself stays a row of glyphs, which is the whole point of moving the title out
of it: a menu bar names the app you are in, not the song you are playing."
  `(custom/media (format . "\uf025")
                 (interval . 2)
                 (exec . "playerctl metadata --format '{{title}} — {{artist}}' 2>/dev/null || echo 'Nothing playing'")
                 (max-length . 40)
                 (tooltip . #t)
                 (on-click . "pkill rofi || heks-media-menu")))

(define* (waybar-media-menu)
  "Render the media popover as a Bash script.

It is a Rofi dmenu menu rather than a GTK menu, so it wears the same glass as the
launcher, shows the track and the player state above the list, and can be driven
from the keyboard.  Every action goes through @command{playerctl}, which is what
the bar's glyph watches."
  (format #f "#!/usr/bin/env bash
# ====== Heks-Linux media popover ======
#
# auto-generated file, DO NOT EDIT!
#
# The transport controls behind the bar's music glyph.

set -u

track=$(playerctl metadata --format '{{title}} — {{artist}}' 2>/dev/null || true)
status=$(playerctl status 2>/dev/null || true)
[ -n \"$track\" ] || track='Nothing playing'
[ -n \"$status\" ] || status='Stopped'
# The message is pango markup, and a title is not.
headline=$(printf '%s · %s' \"$status\" \"$track\" | sed -e 's/[<>&]//g')

choice=$(printf '%s\\n' 'Play / Pause' 'Next track' 'Previous track' 'Stop' 'Open RMPC' \\
    | rofi -dmenu -i -no-custom -p 'Media' \\
        -mesg \"<span size='small'>$headline</span>\" \\
        -theme-str 'window { width: 24%; location: north; yoffset: 46px; }' \\
        -theme-str 'listview { lines: 5; dynamic: false; }' \\
        -theme-str 'inputbar { children: [ button-light-close, prompt, entry ]; }')

case \"$choice\" in
    'Play / Pause') playerctl play-pause ;;
    'Next track') playerctl next ;;
    'Previous track') playerctl previous ;;
    'Stop') playerctl stop ;;
    'Open RMPC') exec wezterm start -- rmpc ;;
    *) exit 0 ;;
esac
"))

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
    ,(waybar-palette)
    ,(waybar-wallpaper)
    ,(waybar-keybindings)
    ;; What is in front of you, the way a menu bar names the focused app.
    (niri/window (format . "{title}")
                 (max-length . 40)
                 (tooltip . #t))
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

(define (waybar-bar-gloss)
  "Return the light on the bar, the way Snow Leopard's menu bar had it.

A neutral white-to-black gradient rather than a palette colour: the Mac menu bar
was graphite in every theme, and a tinted gloss reads as a coloured strip taped
to the screen.  What the palette still decides is whether the gloss is light or
dark, so a light theme gets a white bar with a shade at its foot instead of a
white sheen on white."
  (if (is-dark-palette (heks-linux-palette))
      "linear-gradient(180deg, rgba(255, 255, 255, 0.15) 0%, rgba(255, 255, 255, 0.03) 46%, rgba(0, 0, 0, 0.22) 100%)"
      "linear-gradient(180deg, rgba(255, 255, 255, 0.96) 0%, rgba(255, 255, 255, 0.62) 46%, rgba(0, 0, 0, 0.06) 100%)"))

(define (waybar-bar-text-shadow)
  "Return the shadow under the bar's text.

This is the whole trick of the Mac menu bar: white text on a translucent strip is
unreadable over a bright wallpaper without a dark shadow, and black text on the
light variant needs the opposite one."
  (if (is-dark-palette (heks-linux-palette))
      "0 1px 1px rgba(0, 0, 0, 0.65)"
      "0 1px 0 rgba(255, 255, 255, 0.9)"))

(define* (waybar-bar-bg)
  "Return the bar's own styling attributes.

The bar is a translucent strip with a gloss, a lit top edge and a shaded foot -
the Snow Leopard menu bar - and its text carries a shadow so it survives a
wallpaper of any tone.  The palette still supplies the base colour and the
opacity, so the bar belongs to the theme it is wearing."
  (let ((dark? (is-dark-palette (heks-linux-palette))))
    `((background unquote
                  (hex-to-rgba (get-color (heks-linux-palette)
                                          'background)
                               #:alpha
                               (get-waybar-opacity (heks-linux-palette))))
      (background-image unquote (waybar-bar-gloss))
      (border-top unquote
                  (format #f "1px solid ~a"
                          (if dark?
                              "rgba(255, 255, 255, 0.18)"
                              "rgba(255, 255, 255, 1)")))
      (border-bottom unquote
                     (format #f "1px solid ~a"
                             (if dark?
                                 "rgba(0, 0, 0, 0.5)"
                                 "rgba(0, 0, 0, 0.12)")))
      (border-radius unquote
                     (waybar-border-radius))
      (box-shadow unquote
                  (if dark?
                      "0 1px 3px rgba(0, 0, 0, 0.45)"
                      "0 1px 2px rgba(0, 0, 0, 0.12)"))
      (color unquote
             (get-color (heks-linux-palette)
                        'text))
      (margin-top unquote
                  (waybar-margin-top))
      (margin-bottom unquote
                     (waybar-margin-bottom))
      (margin-left unquote
                   (waybar-margin-left))
      (margin-right unquote
                    (waybar-margin-right))
      (font-size unquote
                 (waybar-font-size)))))

(define* (waybar-css)
  "Defines a CSS configuration for Heks-Linux Waybar using Scheme."
  `((module (background . transparent)
            ;; inherited by every item: the Mac menu bar's text shadow
            (text-shadow unquote
                         (waybar-bar-text-shadow))
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
    ;; The macOS menu bar is a row of glyphs on a translucent strip: no chips,
    ;; no frames, no dividers.  The chips this bar used to draw are gone and the
    ;; palette's accent is spent on hover, which is where a menu bar spends it.
    ("#custom-waybar-start-button" unquote
     `((margin . "0px") (padding . "0px 14px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text))
       ;; GTK's CSS only accepts 100-900 in hundreds, so no 650 here.
       (font-weight . 700)))

    ("#custom-waybar-start-button:hover" unquote
     `((background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'text)
                                #:alpha 0.12))
       (border-radius . "6px")))

    ("#window" unquote
     `((margin . "0px")
       (padding . "0px 12px")
       (font-weight . 600)
       (color unquote
              (get-color (heks-linux-palette)
                         'text-l))))

    ("#custom-heks-keys" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'primary))
       (padding . "0px 11px")
       (margin . "0px")
       (font-size . "12pt")
       (font-weight . 700)))

    ("#custom-heks-keys:hover" unquote
     `((background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'text)
                                #:alpha 0.12))
       (border-radius . "6px")))

    ;; The appearance pair: the palette glyph and the wallpaper glyph are styled
    ;; together, because they are the same kind of button.
    ("#custom-heks-palette, #custom-heks-wallpaper" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'primary))
       (padding . "0px 11px")
       (margin . "0px")
       (font-size . "12pt")))

    ("#custom-heks-palette:hover, #custom-heks-wallpaper:hover" unquote
     `((background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'text)
                                #:alpha 0.12))
       (border-radius . "6px")))

    ("#clock" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'text))
       (padding . "0px 16px 0px 10px")
       (margin . "0px")))

    ("#custom-media" (padding . "0px 13px")
     (margin . "0px")
     (font-style . "italic"))

    ;; Hardware readouts: glyphs and a number, no background.
    ("#cpu, #memory" unquote
     `((padding . "0px 10px")
       (margin . "0px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text-l))))

    ("#pulseaudio, #backlight" unquote
     `((padding . "0px 10px")
       (margin . "0px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text-l))))

    ("#keyboard-state" (padding . "0px 10px") (margin . "0px"))

    ;; Battery states styling
    ("#battery" unquote
     `((padding . "0px 10px")
       (margin . "0px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text-l))))

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
       (padding . "0px 10px")
       (margin . "0px")
       (font-weight . 700)))
    ("#custom-power" unquote
     `((margin . "0px") (padding . "0px 12px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text-l))))
    ("#custom-power:hover" unquote
     `((background . "#e82424") (color . "#ffffff") (border-radius . "6px")))))

;; ===========================================
;; Installation
;; ===========================================

(define* (install-waybar-config)
  "Write @file{config.jsonc}, @file{style.css}, @file{power_menu.xml} and the
media popover script under @file{~/.local/bin}.

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
  (install-config-file! #:name (waybar-media-menu-filename)
                        #:dir (waybar-media-menu-dir)
                        #:contents (waybar-media-menu)
                        #:perms 493)
  (log-success s "Installed Waybar configuration"))
