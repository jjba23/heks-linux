;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Renders @file{~/.config/whelk/settings.scm}, the desktop shell's own
;; configuration: the bar, the launcher, the notification daemon, the network
;; and clipboard panels, the lock screen and the shell menu.
;;
;; The module exists because whelk took over four programs this tree used to
;; write a file for each: the bar, the launcher and its script modes, the
;; notifications and the lock screen.  whelk owns all four, and the file it reads
;; is a Guile program much like the ones this tree already renders.  So the
;; surfaces did not disappear, they moved into one configuration, and this is the
;; module that writes it.  The three modules that
;; wrote those files are removed rather than kept as a fallback nothing would
;; install: v1.53.1 is the last release that shipped them, and docs/desktop.org
;; says how to read them out of the history.
;;
;; The output is a *program*, not a data file, which is why the renderer is
;; different from its neighbours': the settings are built as an S-expression and
;; printed with @code{pretty-print}, so the spec can @code{read} the rendered
;; text back and assert on the tree rather than on a substring of a template.
;; The tree is what whelk evaluates; a substring is what a template hopes.
;;
;; What this module refuses to do: it does not start whelk (Niri's
;; @code{spawn-at-startup} does, so a session restart and a config reload take
;; the same path), and it does not write whelk's own preferences file under
;; @code{$XDG_STATE_HOME/whelk}.  Those are the GUI's overrides, applied after
;; this file on every load, and a renderer that wrote them would turn a live
;; change into a setting nobody can find again.

;;; Code:

(define-module (heks-linux whelk)
  #:declarative? #t
  #:use-module (ice-9 pretty-print)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux palette-picker)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux toon)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux wallpaper)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (whelk-config install-whelk-config
                         whelk-config-dir whelk-config-filename
                         whelk-bar-height whelk-window-radius
                         whelk-bar-radius
                         whelk-launcher-width whelk-launcher-height
                         whelk-launcher-icon-size whelk-launcher-font-scale
                         whelk-icon-font whelk-extra-css
                         whelk-bar-tint whelk-bar-neutral-light
                         whelk-bar-neutral-dark whelk-bar-base
                         whelk-bar-ink whelk-launcher-command
                         whelk-window-switcher-command whelk-lock-command
                         whelk-dnd-command whelk-clipboard-command
                         whelk-notifications-command whelk-network-command
                         whelk-power-menu-entries
                         make-whelk-power-menu-script
                         whelk-power-menu-command
                         whelk-power-menu-filename whelk-script-dir
                         whelk-media-command
                         whelk-stocks-symbols
                         whelk-weather-location
                         whelk-weather-latitude
                         whelk-weather-longitude
                         whelk-rows whelk-overflow-rows whelk-widgets))

(define s
  (scriba-auto-logger))

;; The bar's thickness, in pixels.  One value because two things need it: the
;; bar is drawn at it, and it is the height a floating panel has to clear to sit
;; under the bar rather than over it.  Whelk's own panels know where the
;; exclusive zone ends, but a notification the shell draws itself is anchored,
;; not stacked, so the number is repeated here rather than measured.
(define whelk-bar-height
  (make-parameter 32))

;; The corner radius of every whelk surface that is not the launcher, in pixels:
;; the bar, the panels that drop from it and the desktop's cards.  One value
;; because two programs need it - whelk rounds the surface with it and niri
;; rounds the blur and the shadow behind it with the same number
;; (@code{geometry-corner-radius} in @code{(heks-linux niri)}) - and a rule at
;; another radius leaves a square patch of blur showing past a rounded corner.
;; Ten is the radius the bar's material is written with.
(define whelk-bar-radius
  (make-parameter 10))

;; The corner radius of whelk's launcher, in pixels, as niri rounds the
;; launcher's *shadow* with it (@code{geometry-corner-radius} in
;; @code{(heks-linux niri)}).  A shadow drawn at a different radius from the
;; panel pokes out behind the corners, which is the one way a floating panel can
;; look broken.  Sixteen is whelk's own floor: a launcher rounds more than the
;; bar does, and a theme that asks for less is raised to it.
(define whelk-window-radius
  (make-parameter 16))

;; The launcher's starting geometry.  The shell centres a 660x640 card by
;; default; a menu-bar desktop has room for a little more, and 28px icons read
;; better next to an 11pt bar.  These are defaults: dragging the card's grip or
;; using its Icons and Text buttons writes GUI overrides, and the settings
;; window's Launcher page edits the same four values.
(define whelk-launcher-width
  (make-parameter 720))

(define whelk-launcher-height
  (make-parameter 680))

(define whelk-launcher-icon-size
  (make-parameter 28))

(define whelk-launcher-font-scale
  (make-parameter 110))

;; The face the bar's glyphs are drawn from.  Font Awesome Free is in the
;; distribution's font list, and whelk's icon set is written against it; a
;; machine that has nothing else still gets glyphs instead of boxes.
(define whelk-icon-font
  (make-parameter "Font Awesome 6 Free Solid"))

;; How much of the palette's own background survives in the bar, as a 0-1
;; fraction: 0 leaves the neutral menu-bar grey, 1 leaves the palette's colour
;; untouched, and the default moves halfway between them.
;;
;; A palette names a window background, and a window background is not a menu
;; bar: a beige or a blue-paper palette would turn the bar into a coloured strip
;; taped to the top of the screen.  Mixing the two keeps the bar recognisably the
;; palette's while letting the wallpaper's colour come through the translucency
;; rather than through the theme.  A machine that wants the palette exactly sets
;; 1; one that wants the reference's graphite sets 0.
(define whelk-bar-tint
  (make-parameter 0.5))

;; The two neutral greys the bar is made of, one per kind of palette: a menu bar
;; is a material rather than a theme, and the palette tints it instead of
;; recolouring it.  These are the ends that material can have.
(define whelk-bar-neutral-light
  (make-parameter "#f2f3f5"))

(define whelk-bar-neutral-dark
  (make-parameter "#1b1b1d"))

;; CSS written in place of the theme's own rule, so a machine can say anything
;; the keys above cannot.  Empty by default: the palette is the configuration,
;; and this is the escape hatch for the one property it cannot express.  whelk
;; takes a bar's @code{#:css} instead of the theme's, not on top of it, so the
;; empty value is rendered as @code{#f} and the theme keeps its rule.
(define whelk-extra-css
  (make-parameter ""))

;; --- The bar's material ---

(define* (whelk-bar-base #:key (palette (heks-linux-palette)))
  "Return the bar's own background colour for @var{palette}, without alpha.

@var{palette} is a name from the registry, defaulting to the one the desktop
wears.  Its @code{background} is moved @code{whelk-bar-tint} of the way toward
the neutral grey of its kind, so a warm palette stays warm and a cool one stays
cool while neither becomes a coloured strip.

@example
(whelk-bar-base #:palette 'nord)
@end example"
  (mix-colors (get-color palette 'background)
              (if (is-dark-palette palette)
                (whelk-bar-neutral-dark)
                (whelk-bar-neutral-light))
              #:weight (whelk-bar-tint)))

(define* (whelk-bar-ink #:key (palette (heks-linux-palette)))
  "Return the ink the bar's own text is drawn in on @var{palette}.

@var{palette} is a name from the registry, defaulting to the one the desktop
wears.  Its text colour is preferred, but it is measured against the bar's
actual background rather than the palette's: the two differ by
@code{whelk-bar-tint}, and a light palette tinted toward white can leave its own
quiet ink under the reading floor.  The accent is the second candidate because a
palette that cannot carry its own ink on its own bar is a palette whose accent
was picked to sit on that bar.

@example
(whelk-bar-ink #:palette 'rose-pine-dawn)
@end example"
  (readable-ink (whelk-bar-base #:palette palette)
                (list (get-color palette 'text)
                      (get-color palette 'primary))))

;; --- The commands the bar, the bindings and the shell menu spell ---
;;
;; One spelling each, because each is reached from three places: a module's
;; click on the bar, a keybinding in @code{(heks-linux niri)} and a row in the
;; session menu.  Whelk is a single-instance application, so the second launch
;; forwards its arguments to the first instead of starting a second shell.

(define (whelk-launcher-command)
  "Return the command that opens the launcher."
  "whelk --launcher")

(define (whelk-window-switcher-command)
  "Return the command that opens the launcher in its window mode."
  "whelk --launcher --launcher-mode=window")

(define (whelk-lock-command)
  "Return the command that locks every output."
  "whelk --lock")

(define (whelk-dnd-command)
  "Return the command that toggles do-not-disturb."
  "whelk --dnd")

(define (whelk-clipboard-command)
  "Return the command that opens the clipboard history."
  "whelk --clipboard")

(define (whelk-notifications-command)
  "Return the command that toggles the notification centre."
  "whelk --notifications")

(define* (whelk-network-command #:key (page "wifi"))
  "Return the command that opens the network panel on @var{page}.

@var{page} is @code{wifi} or @code{bluetooth}, the two halves of the panel.

@example
(whelk-network-command #:page \"bluetooth\")
@end example"
  (format #f "whelk --network ~a" page))

;; --- The session menu behind a keybinding ---
;; The shell menu on the bar carries the same rows, but a menu you have to
;; reach with the mouse is not the one you want at the end of a day.  Whelk's
;; @code{--menu} runs a command, reads the launcher's script protocol from it and
;; calls it back with @code{WHELK_RETV=1} and the chosen label, so the menu is a
;; generated Bash script - the same shape the launcher's power mode had, and
;; the reason it did not have to be rewritten.

(define (whelk-power-menu-entries)
  "Ordered list of session-menu entries, each as @code{(label icon command)}."
  (list (list "Lock" "system-lock-screen" (whelk-lock-command))
        ;; A session id that is not there would turn log out into a no-op, so
        ;; the user's own sessions are the fallback.
        (list "Log Out" "system-log-out"
              "if [ -n \"${XDG_SESSION_ID:-}\" ]; then loginctl terminate-session \"$XDG_SESSION_ID\"; else loginctl terminate-user \"$USER\"; fi")
        (list "Suspend" "system-suspend" "systemctl suspend")
        (list "Hibernate" "system-hibernate" "systemctl hibernate")
        (list "Reboot" "system-reboot" "systemctl reboot")
        (list "Shut Down" "system-shutdown" "systemctl poweroff")))

(define (make-whelk-power-menu-script)
  "Generate the Bash script behind @code{whelk --menu}.

Whelk calls it with @code{WHELK_RETV=0} to list the entries and with
@code{WHELK_RETV=1} and the chosen label as @code{$1} to run its action - the
protocol's accept value and row label."
  (format #f
          "#!/usr/bin/env bash

# ====== Heks-Linux session menu ======
#
# auto-generated file, DO NOT EDIT!
#
# Whelk's menu protocol: no argument lists the rows, the accepted row is passed
# as $1 to run its action.

case \"${WHELK_RETV:-0}\" in
  0)
~a    ;;
  1)
    case \"$1\" in
~a    esac
    ;;
esac
"
          (string-join (map (lambda (entry)
                              (format #f "    printf '~a\\0icon\\x1f~a\\n'\n"
                                      (list-ref entry 0)
                                      (list-ref entry 1)))
                            (whelk-power-menu-entries))
                       "")
          (string-join (map (lambda (entry)
                              (format #f "      \"~a\") ~a ;;\n"
                                      (list-ref entry 0)
                                      (list-ref entry 2)))
                            (whelk-power-menu-entries))
                       "")))

;; Where the generated scripts go, and what the power menu is called there.
(define whelk-script-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define whelk-power-menu-filename
  (make-parameter "heks-session-menu"))

(define (whelk-power-menu-command)
  "Return the command that opens the session menu from a keybinding."
  (format #f "whelk --menu ~a/~a"
          (whelk-script-dir)
          (whelk-power-menu-filename)))

;; --- The bar's rows ---

(define (whelk-icon icon)
  "Return the command that prints @var{icon}, for a module with nothing to poll.

A glyph is not a reading: there is nothing to sample and nothing to format, so
the command behind the module prints the glyph once and the module renders at
interval 0.  Whelk draws a @code{custom-module}'s first line of output, which is
why an icon needs a command at all rather than an icon key."
  (format #f "printf '~a'" icon))

(define (whelk-media-command)
  "Return the command that prints what is playing, or says nothing is.

The player is asked for one line of text, which is what the bar draws; a
machine with no player running gets the sentence rather than an empty tile."
  (string-append "playerctl metadata --format '{{title}} — {{artist}}'"
                 " 2>/dev/null || echo 'Nothing playing'"))

(define (whelk-rows)
  "Return the right half of the bar: the readings that stay on screen.

The order is the reference's, which is to say the order the bar this
replaces kept: what is playing and what is copied, the things this desktop opens,
the hardware, the network, the things that arrive, and then search and the clock
at the far right where a menu bar puts them.  Every row carries its two clicks;
none of them is a reading you can only look at.

What is read once in a while is not here: @code{whelk-overflow-rows} is the
shelf behind the chevron, and the split is the one whelk's own bar makes, so the
row that has to fit between the menu and the clock stays the row that gets used.

The rows take no palette: the bar carries one ink and one accent for all of
them, and a row that picked its own colour would be a row that stopped
following the theme."
  `((custom-module #:exec ,(whelk-media-command)
                   #:interval 2
                   #:max-length 40
                   #:icon "\uf025"
                   #:format "{icon}"
                   #:tooltip "Now playing: {text}
Click: open Orpheus · Right-click: play or pause · Middle: next track"
                   #:on-click "emacsclient -c -a '' --eval \"(progn (require 'orpheus) (orpheus))\""
                   #:on-click-right "playerctl play-pause"
                   #:on-click-middle "playerctl next")
    (clipboard-module #:icon "\uf328"
                      #:format "{icon}"
                      #:tooltip "Clipboard: {count} item(s)
Click: browse the history · Right-click: pause or clear")
    (custom-module #:exec ,(whelk-icon "\uf084")
                   #:interval 0
                   #:format "{icon}"
                   #:icon "\uf084"
                   #:tooltip "Passwords, passkeys and one-time codes
Click: open the password manager"
                   #:on-click ,(heks-linux-password-command))
    (dnd-module #:icon "\uf1f6"
                #:format "{icon}"
                #:tooltip "Do not disturb is on — click to let notifications through")
    (custom-module #:exec ,(whelk-icon "\uf030")
                   #:interval 0
                   #:format "{icon}"
                   #:icon "\uf030"
                   #:tooltip "Capture — screenshot, GIF or video
Click: choose what to take · Right-click: edit the last capture"
                   #:on-click "heks-capture choose"
                   #:on-click-right "heks-capture studio")
    (memory-module #:icon "\uf0c9"
                   #:format "{icon} {percentage}%"
                   #:interval 5
                   #:tooltip "RAM: {used} GiB of {total} GiB ({percentage}%)
Available: {avail} GiB
Swap: {swap-used} GiB of {swap-total} GiB
Click: btop"
                   #:on-click "kitty btop")
    (audio-module #:icon "\uf028"
                  #:muted-icon "\uf026"
                  #:format "{icon}"
                  #:muted-format "{icon}"
                  #:interval 2
                  #:tooltip "Volume: {volume}%
Click: mixer · Right-click: mute · Middle: mute the microphone · Scroll: volume"
                  #:on-click "pavucontrol"
                  #:on-click-right "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
                  #:on-click-middle "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
                  #:on-scroll-up "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
                  #:on-scroll-down "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
    (keyboard-module #:format "⇪"
                     #:interval 1
                     #:tooltip "Caps Lock is on")
    ;; Charging swaps the glyph rather than the reading: a percentage that
    ;; jumps aside for a bolt is a number that moves while it is being read.
    (battery-module #:icon "\uf240"
                    #:charging-icon "\uf0e7"
                    #:format "{icon} {capacity}%"
                    #:show-capacity-when-charging? #f
                    #:warning 30
                    #:critical 15
                    #:interval 30
                    #:tooltip "Battery: {capacity}% — {state}
Click: the session menu"
                    #:on-click ,(whelk-power-menu-command))
    (power-profile-module #:icon "\uf0e7"
                          #:format "{icon}"
                          #:interval 5
                          #:tooltip "Power profile: {profile}
Click: next profile"
                          #:on-click "powerprofilesctl cycle")
    ;; The network, read here rather than by an applet: nmcli and bluetoothctl
    ;; are the scripting surfaces those projects ship, and the panel they open
    ;; is the shell's own.
    (wifi-module #:icon "\uf1eb"
                 #:show-ssid? #f
                 #:disabled-format "{icon} off"
                 #:interval 5)
    (bluetooth-module #:icon "\uf293"
                      #:format "{icon}"
                      #:disabled-format "{icon} off"
                      #:interval 10
                      #:tooltip "Bluetooth: {count} device(s)
Click: devices")
    (tray-module #:spacing 6 #:max-items 6)
    ;; The bell: the centre on a click, do-not-disturb on a right click.
    (notifications-module #:icon "\uf0f3"
                          #:format "{icon}"
                          #:tooltip "Notifications: {count}
Click: centre · Right-click: do not disturb")
    (custom-module #:exec ,(whelk-icon "\uf002")
                   #:interval 0
                   #:format "{icon}"
                   #:icon "\uf002"
                   #:tooltip "Search applications
Click: the launcher · Right-click: switch windows"
                   #:on-click ,(whelk-launcher-command)
                   #:on-click-right ,(whelk-window-switcher-command))
    (clock-module #:format "%a %d %b  %H:%M"
                  #:interval 5
                  #:tooltip "{calendar}
Click: calendar · Right-click: copy the time"
                  #:on-click "gnome-calendar"
                  #:on-click-right "wl-copy \"$(date '+%Y-%m-%d %H:%M:%S')\"")))

(define (whelk-overflow-rows)
  "Return the modules kept behind the chevron at the end of the right half.

whelk's own bar keeps six modules here and so does this one: the load, the ways
into the desktop's own views, and the two dials that are set once in a while.
The list is built with the bar rather than on demand, so a module's reading keeps
updating and its clicks keep working while the shelf is shut; the chevron is what
decides whether it is on screen, and @code{#:overflow-expanded?} whether it starts
open.

Folding these away is what keeps the right half the width a menu bar has: a
tile for every program is a bar where the clock, the one reading that has to be
found without looking, ends up somewhere in the middle."
  `((cpu-module #:icon "\uf2db"
                #:format "{icon} {usage}%"
                #:interval 2
                #:tooltip "CPU: {usage}% of every core
Click: btop"
                #:on-click "kitty btop")
    (custom-module #:exec ,(whelk-icon "\uf518")
                   #:interval 0
                   #:format "{icon}"
                   #:icon "\uf518"
                   #:tooltip "Every keyboard shortcut
Click: the reference · Right-click: the documentation"
                   #:on-click ,(toon-spawn-command (toon-keys-command))
                   #:on-click-right
                   ,(toon-spawn-command (toon-docs-command)))
    ;; The wallpapers are whelk's own menu now: a click opens a card of
    ;; thumbnails beside the reading, and a click on one applies it, so nothing
    ;; about them leaves the shell.  Shuffle stays on the right click.
    (wallpaper-module #:icon "\uf03e"
                      #:format "{icon}"
                      #:tooltip "Wallpaper: pick one
Click: the wallpapers · Right-click: shuffle"
                      #:on-click-right "heks-wallpaper random")
    (custom-module #:exec ,(whelk-icon "\uf53f")
                   #:interval 0
                   #:format "{icon}"
                   #:icon "\uf53f"
                   #:tooltip "Palette: browse the palettes
Click: browse · Right-click: the quick picker"
                   #:on-click ,(toon-spawn-command (toon-palettes-command))
                   #:on-click-right ,(palette-picker-command))
    ;; The layout's label is a reading, so it is polled rather than printed
    ;; once: niri can switch it without this bar being told.
    (language-module #:codes ,(heks-linux-keyboard-layout)
                     #:interval 2
                     #:format " {text}"
                     #:tooltip "Keyboard layout: {text}
Click: next layout · Right-click: previous layout"
                     #:on-click "niri msg action switch-layout next"
                     #:on-click-right "niri msg action switch-layout prev")
    (backlight-module #:icon "\uf185"
                      #:format "{icon}"
                      #:interval 2
                      #:tooltip "Brightness: {percent}%
Click: brighter · Right-click: full · Scroll: adjust"
                      #:on-click "brightnessctl set 5%+"
                      #:on-click-right "brightnessctl set 100%"
                      #:on-scroll-up "brightnessctl set 5%+"
                      #:on-scroll-down "brightnessctl set 5%-")))

;; --- The desktop's cards ---

;; The stocks the card follows, as Yahoo Finance tickers.  whelk reads this
;; option as one line of *text* and splits it on commas, not as the list its
;; documentation shows: a list reaches the runtime as a Scheme list, the option
;; is not text, and the card silently keeps its built-in AAPL/MSFT/NVDA.  Six is
;; whelk's maximum, so this is six Euronext Amsterdam names, with Ahold
;; Delhaize first because it is the one this desktop was asked to follow.
(define whelk-stocks-symbols
  (make-parameter "AD.AS,ASML.AS,HEIA.AS,INGA.AS,PHIA.AS,ADYEN.AS"))

;; The weather card's place.  The location is the label the card prints; the
;; latitude and longitude are what Open-Meteo is actually asked about.  They are
;; strings for the same reason the tickers are: whelk reads them as text, and a
;; Scheme number is not text, so a numeric pair would leave the card pointing at
;; whelk's built-in San Francisco while printing whatever location it was given.
(define whelk-weather-location
  (make-parameter "Amsterdam"))

(define whelk-weather-latitude
  (make-parameter "52.3676"))

(define whelk-weather-longitude
  (make-parameter "4.9041"))

(define (whelk-widgets)
  "Return the desktop's cards, one @code{(desktop-widget ...)} form each.

The collection is whelk's Golden Gate set -- what its own desktop ships -- spelt
out here rather than asked for by name, because a card is the one part of the
shell a machine is meant to edit: its place, its size and its options are in this
file, so moving the clock is a number to change rather than a function to look
up.  A card left out is a card that is not drawn; the whole keyword left out is
an empty desktop.

The geometry is the default set's, laid down the left and the middle of a 1080p
screen, and the sizes are the ones a bare @code{(desktop-widget 'notes)} gets, so
the list below is exactly the desktop whelk draws with no settings file.  The
weather is Amsterdam and the stocks are the Euronext Amsterdam names this machine
follows; both come from parameters (@code{whelk-weather-location},
@code{whelk-weather-latitude}, @code{whelk-weather-longitude} and
@code{whelk-stocks-symbols}) and both are written as *text*, because whelk reads
those options as text and silently ignores a Scheme number or a list.  The clicks
point at GNOME's utilities, and every card also takes @code{title}, @code{css},
@code{tooltip} and the mouse actions.

The position is only where a card starts: the grip in its header drags it, and
what a machine moves is remembered per monitor under
@code{$XDG_STATE_HOME/whelk}, not written back into this file."
  `((desktop-widget 'clock
                    #:x 32 #:y 64
                    #:options '((style . analog)
                                (show-seconds? . #t)
                                (on-click . "gnome-clocks")))
    (desktop-widget 'calendar
                    #:x 280 #:y 64
                    #:options '((on-click . "gnome-calendar")))
    (desktop-widget 'weather
                    #:x 632 #:y 64
                    ;; The alist is built here and spliced in as a literal: the
                    ;; file is a program, and a bare list in a value position is
                    ;; a call whelk compiles, which rejects the whole settings
                    ;; file over one card's options.
                    #:options ',(list (cons 'location
                                            (whelk-weather-location))
                                      (cons 'latitude
                                            (whelk-weather-latitude))
                                      (cons 'longitude
                                            (whelk-weather-longitude))
                                      (cons 'units
                                            'metric)))
    (desktop-widget 'battery
                    #:x 32 #:y 320
                    #:options '((on-click . "gnome-power-statistics")))
    (desktop-widget 'notes
                    #:x 32 #:y 520
                    #:width 220
                    #:height 260
                    #:options '((title . "Notes")
                                (text . "Golden Gate widgets
Edit settings.scm to make this note yours.")))
    (desktop-widget 'reminders
                    #:x 280 #:y 416
                    #:options '((items . ("Review the release"
                                          "Water the plants"
                                          "Read the Guile manual"))))
    (desktop-widget 'world-clock
                    #:x 632 #:y 304
                    #:width 260
                    #:height 220
                    #:options '((cities . "Cupertino=America/Los_Angeles,London=Europe/London,Tokyo=Asia/Tokyo")))
    (desktop-widget 'stocks
                    #:x 632 #:y 536
                    #:width 300
                    #:height 220
                    #:options ',(list (cons 'symbols
                                            (whelk-stocks-symbols))))))

;; --- The settings file ---

(define* (whelk-settings #:key (palette (heks-linux-palette))
                         (sans-font (heks-linux-sans-font)))
  "Return the settings file as one S-expression.

@var{palette} names the palette the bar's four colours come from and
@var{sans-font} the face its text is set in; both default to what the desktop
wears.

The shape is whelk's, not this module's: @code{configure-shell!} takes the bars
and the shell menu, and a bar is a name, an edge, a thickness and the lists of
modules that fill it -- left, centre, right and the shelf behind the chevron.
Building it as a tree rather than as text is what lets the spec read the rendered
file back and ask it what the bar is made of.

@example
(whelk-settings #:palette 'nord)
@end example"
  `(configure-shell!
    #:bars
    (list (bar #:name 'main #:position 'top
               ;; A menu bar belongs on the top layer: niri keeps top-layer
               ;; surfaces fixed while the workspaces zoom out in its overview,
               ;; which is where a bar you can still read belongs.
               #:layer 'top
               ;; One bar, on every output, whatever their number: the two
               ;; conditions whelk offers -- a bar only while there is one
               ;; screen, or only while there is more than one -- are for a
               ;; machine that wants a different bar per monitor, and this one
               ;; does not.  A list of connector names here would pin the bar to
               ;; those outputs and leave the others bare.
               #:monitor "all"
               #:monitors '()
               #:when 'always
               #:height ,(whelk-bar-height)
               #:margin 0
               #:exclusive? #t
               #:spacing 6
               #:padding 12
               #:font ,sans-font
               #:font-size "11pt"
               #:icon-font ,(whelk-icon-font)
               ;; The material is the theme's, the colour is the palette's:
               ;; every colour the bar sets wins over the theme's, so the look
               ;; survives a palette switch and follows it.  The numbers below
               ;; are gloss-2007's own, written out so a machine changes one of
               ;; them here instead of choosing another theme for the whole bar:
               ;; the corner radius, the eighteen-pixel outer shadow, the top
               ;; highlight, the lower inner reflection and the accent glow.
               #:theme 'gloss-2007
               #:foreground ,(whelk-bar-ink #:palette palette)
               #:background ,(hex-to-rgba (whelk-bar-base #:palette palette)
                                          #:alpha
                                          (get-whelk-opacity palette))
               #:accent ,(get-color palette 'primary)
               #:border-color ,(hex-to-rgba (get-color palette 'text-l)
                                            #:alpha 0.15)
               ;; The palette's opacity is already in the background's alpha;
               ;; this multiplies it, so it stays at one rather than applying
               ;; the same translucency twice.
               #:opacity 1.0
               #:radius ,(whelk-bar-radius)
               #:blur 18
               #:shine 0.38
               #:reflection 0.10
               #:flare 0.12
               ;; The escape hatch, appended to nothing: whelk takes the bar's
               ;; #:css *instead of* the theme's own rule, so an empty string
               ;; would quietly drop the square slab gloss-2007 asks for.  #f
               ;; is what leaves the theme in charge, and a machine that writes
               ;; CSS here is telling the theme to stand aside.
               #:css ,(let ((css (whelk-extra-css)))
                        (if (string-null? css) #f css))
               #:launcher-width ,(whelk-launcher-width)
               #:launcher-height ,(whelk-launcher-height)
               #:launcher-icon-size ,(whelk-launcher-icon-size)
               #:launcher-font-scale ,(whelk-launcher-font-scale)
               ;; A menu bar's left half: the machine's own menu behind a mark,
               ;; then that application's File, Edit and View.  The window's name
               ;; is the one line a bar that wants it adds back.
               #:left (list (start-module)
                            (menu-module #:shortcuts? #t
                                         #:app-name? #f
                                         #:accelerator-style 'cua))
               ;; A menu bar is two halves.  The workspace switcher fits here
               ;; and is left out for the same reason the reference leaves it
               ;; out: niri draws its own.
               #:center '()
               ;; A bare list of forms in argument position is an application:
               ;; the first module would be called as a procedure.  Splice the
               ;; rows into a `(list ...)' form so the file evaluates to the
               ;; records whelk expects.
               #:right (list ,@(whelk-rows))
               ;; The chevron at the end of that row, holding what is read once
               ;; in a while.  It starts closed: a shelf that opens itself eats
               ;; the width it was folded away to save.
               #:overflow (list ,@(whelk-overflow-rows))
               #:overflow-expanded? #f))
    ;; The desktop's own cards, one form per card; see whelk-widgets.
    #:widgets (list ,@(whelk-widgets))
    ;; The background.  whelk draws one layer surface per monitor, transitions
    ;; between pictures, rotates through the palette's set and remembers what
    ;; the picker chose; `heks-wallpaper' is the front end a keybinding runs, not
    ;; a second renderer.  The form is spliced as data from (heks-linux
    ;; wallpaper), so the collection, the interval and the fit are written once.
    #:wallpaper ,(wallpaper-whelk-form)
    ;; One idle manager, not a second daemon: logind reports the hint, whelk
    ;; runs the one countdown and asks for the same lock screen the lock key
    ;; opens.  Five minutes is long enough to read a page and short enough that
    ;; walking away from the desk locks it.
    #:idle (idle-settings #:lock-after 300)
    ;; The history is memory-only and bounded: nothing is written to disk, so a
    ;; copy of a password is not sitting in a file after the session ends.
    ;; Unpinned copies expire after an hour and are forgotten when the session
    ;; locks; pinned ones stay until they are unpinned by hand.  A password
    ;; manager's own hint is honoured either way.
    #:clipboard (clipboard-settings
                 #:persist #f
                 #:persist-only-pinned? #f
                 #:clear-on-lock? #t
                 ;; Fifty entries, and the byte caps whelk starts with: a
                 ;; screenshot on the clipboard is megabytes, so the cap is what
                 ;; keeps a history from becoming a memory leak with a picker.
                 #:max-entries 50
                 #:max-entry-bytes (* 32 1024 1024)
                 #:max-total-bytes (* 128 1024 1024)
                 #:ttl-seconds 3600)))

(define* (whelk-config #:key (palette (heks-linux-palette))
                       (sans-font (heks-linux-sans-font)))
  "Render the whelk @file{settings.scm} file as text.

@var{palette} and @var{sans-font} are passed straight to @code{whelk-settings}.

The file is a Guile program, so it is written the way this tree writes Scheme:
an S-expression printed by @code{pretty-print}, preceded by the commentary that
says it is generated and which module is the source of truth.

@example
(display (whelk-config #:palette 'nord))
@end example"
  (call-with-output-string
    (lambda (port)
      (format port
              ";;; whelk -- generated by heks-linux, do not edit
;;;
;;; Rendered from (heks-linux whelk); edit that module, or set a value in
;;; ~a
;;; and run `maak install-whelk' again.  Whelk re-reads this file whenever it
;;; is saved, so a render lands in the running shell without a restart.
;;;
;;; The colours, the fonts and the commands come from the palette in
;;; ~a
;;; and from the settings in (heks-linux user-settings).

"
              (format #f "~a/heks-linux/whelk-settings.scm"
                      (or (getenv "XDG_CONFIG_HOME")
                        (format #f "~a/.config"
                                (or (getenv "HOME") "/tmp"))))
              (format #f "~a/heks-linux/local-settings.scm"
                      (or (getenv "XDG_CONFIG_HOME")
                        (format #f "~a/.config"
                                (or (getenv "HOME") "/tmp")))))
      (pretty-print (whelk-settings #:palette palette #:sans-font sans-font)
                    port)
      (newline port))))

;; whelk follows the XDG spec for its directory, so the file is plainly
;; @file{settings.scm} inside it.
(define whelk-config-filename
  (make-parameter "settings.scm"))

(define whelk-config-dir
  (make-parameter (format #f "~a/.config/whelk"
                          (or (getenv "HOME") "/tmp"))))

(define* (install-whelk-config)
  "Write the whelk settings file to @code{whelk-config-dir}, and the session menu.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/whelk-settings.scm} first.  A running shell
picks the settings up on its own - it watches the directory and rebuilds the bar
a quarter of a second after the write - so nothing here has to signal it, and a
  palette switch repaints the bar without a restart.  The session menu is a
script rather than a configuration, so it is written executable."
  (log-info s "Installing whelk configuration")
  (load-local-overrides '(heks-linux whelk)
                        'whelk-settings)
  (install-config-file! #:name (whelk-config-filename)
                        #:dir (whelk-config-dir)
                        #:contents (whelk-config #:palette (heks-linux-palette)
                                                 #:sans-font (heks-linux-sans-font)))
  (install-config-file! #:name (whelk-power-menu-filename)
                        #:dir (whelk-script-dir)
                        #:contents (make-whelk-power-menu-script)
                        #:perms 493)
  (log-success s "Installed whelk configuration"))
