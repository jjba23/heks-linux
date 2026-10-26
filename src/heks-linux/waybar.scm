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
  #:use-module (heks-linux rofi)
  #:use-module (heks-linux wallpaper)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux prelude)
  #:use-module (json)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (install-waybar-config waybar-css
                                  waybar-bar-bg
                                  waybar-system-menu
                                  waybar-system-menu-button
                                  waybar-system-menu-entries
                                  waybar-about
                                  waybar-spotlight
                                  waybar-spotlight-command
                                  waybar-mako-dnd
                                  waybar-border-radius
                                  waybar-keybindings
                                  waybar-media
                                  waybar-clipboard
                                  waybar-clipboard-command
                                  waybar-wallpaper
                                  waybar-palette
                                  waybar-docs
                                  waybar-audio-icon
                                  waybar-power-profiles
                                  waybar-battery-2
                                  waybar-battery
                                  waybar-clock
                                  waybar-taskbar
                                  waybar-backlight
                                  waybar-language
                                  waybar-language-label
                                  waybar-language-menu
                                  waybar-language-label-filename
                                  waybar-language-menu-filename
                                  waybar-language-script-dir
                                  waybar-conf
                                  waybar-config-dir
                                  waybar-config-filename
                                  waybar-style-filename
                                  waybar-system-menu-filename
                                  waybar-system-menu-dir
                                  waybar-about-filename
                                  waybar-media-menu-filename
                                  waybar-media-menu-dir
                                  waybar-media-menu
                                  waybar-position
                                  waybar-height
                                  waybar-system-menu-label
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

;; The logo at the far left of the bar, where a Mac menu bar carries the apple.
;;
;; It is the lambda of the Guile this desktop is written in; a machine that
;; would rather wear its kernel can point ~/.config/heks-linux/
;; waybar-settings.scm at a penguin instead, or at anything else its fonts can
;; draw:
;;
;;   (waybar-system-menu-label "\uf17c")   ; Font Awesome's Linux brand glyph
;;   (waybar-system-menu-label "🐧")
;;
;; A glyph from the text font (the lambda, the penguin) is always drawn; a
;; private-use glyph needs the brand face the bar asks for by name, which is why
;; the Font Awesome one is spelled out in full here.
(define waybar-system-menu-label
  (make-parameter "λ"))

(define waybar-modules-left
  ;; The macOS menu bar: the system menu at the far left, the way the apple
  ;; sits, then the search field's glyph, then what is in front of you.
  ;; Everything else is a status item and lives on the right.
  (make-parameter #(custom/heks-system-menu custom/heks-spotlight niri/window)))

(define waybar-modules-right
  ;; Status items, in the order macOS keeps them: the things you glance at
  ;; (now playing, do-not-disturb, the input language, the palette, help) come
  ;; first, then the hardware readouts, then the tray, and the clock closes the
  ;; row at the right edge.  The session lives in the system menu now, where a
  ;; Mac keeps it, so the old power glyph at the end of the row is gone.
  (make-parameter
   #(custom/media custom/heks-clipboard custom/mako-dnd custom/heks-language
                  custom/heks-palette custom/heks-wallpaper custom/heks-docs
                  custom/heks-keys cpu memory backlight pulseaudio
                  keyboard-state battery power-profiles-daemon tray clock)))

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

;; Retired: the GTK menu the bar's old power glyph opened.  Nothing reads it any
;; more - the session lives in the system menu - but the file is still named here
;; so a machine that has one loses it instead of keeping a menu nobody opens.
(define waybar-power-menu-filename
  (make-parameter "power_menu.xml"))

;; The system menu and the About window behind its first row.  Both are
;; generated scripts, like the media popover and the layout pair, and both live
;; in ~/.local/bin because the bar launches them rather than reading them.
(define waybar-system-menu-filename
  (make-parameter "heks-system-menu"))

(define waybar-about-filename
  (make-parameter "heks-about"))

(define waybar-system-menu-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

;; The media popover lives next to the other generated scripts, not next to the
;; bar's configuration: it is a program the bar launches, and ~/.local/bin is
;; where the rest of them are.
(define waybar-media-menu-filename
  (make-parameter "heks-media-menu"))

(define waybar-media-menu-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

;; The keyboard-layout pair: the label the bar shows and the menu a click opens.
;; Both are generated scripts, like the media popover, and both live in
;; ~/.local/bin.
(define waybar-language-label-filename
  (make-parameter "heks-language-label"))

(define waybar-language-menu-filename
  (make-parameter "heks-language-menu"))

(define waybar-language-script-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

;; The history browser behind the bar's clipboard glyph.  It is a parameter, like
;; the program names in @code{(heks-linux toon)}, so a machine that keeps its
;; clipboard with something else can point the glyph at it without forking.  The
;; default is the same command the compositor binds to Mod+V.
(define waybar-clipboard-command
  (make-parameter "clipman pick --tool=rofi"))

;; The launcher behind the bar's magnifier glyph, and behind the Search row of
;; the system menu.  It is a parameter for the same reason the clipboard picker
;; is: a machine that launches with something other than Rofi should not have to
;; edit the module to say so.  The command is the launcher alone - whichever
;; caller opens it adds the pkill that replaces an open launcher, because a
;; second Rofi would refuse the click rather than take it.
(define waybar-spotlight-command
  (make-parameter "rofi -show drun"))

;; ===========================================
;; Layout & Component Definitions
;; ===========================================

;; One trap is worth writing down before the first module: on a *custom* module
;; `tooltip` is a boolean - it only turns the tooltip on and off - and the text
;; belongs in `tooltip-format`.  A string in `tooltip` is silently ignored, which
;; is how most of this bar came to have no useful hover text at all: the option
;; looks exactly like the one every built-in module takes, and nothing complains.

;; The rule Rofi draws between two groups of rows in the system menu.  It is a
;; row of its own, which is why it is a string and not a (label icon command)
;; list: a rule that could be picked and launched is not a rule.  It is kept
;; short on purpose - Rofi ellipsizes a row wider than its window, and a rule
;; that ends in three dots is a row that looks like it was cut off.
(define waybar-system-menu-rule "────────────────")

(define (waybar-system-menu-relaunch command)
  "Return @var{command} as a menu action that opens a Rofi menu of its own.

A row of a Rofi menu that opens another Rofi has to wait for the first one to be
gone: two Rofi at once race for the keyboard grab, and the one that loses opens
without focus.  The wait is short enough not to be felt, and it happens in the
detached session the row runs in, so the menu closes at once either way."
  (format #f "sleep 0.15; ~a" command))

(define (waybar-system-menu-entries)
  "Return the rows of the bar's system menu, top to bottom.

Each row is @code{(label icon command)}, and @code{waybar-system-menu-rule} is a
rule between two groups.  The shape is the one a Mac's Apple menu has: what this
machine is, the ways into it, and then the ways out of the session.  The last
group is @code{rofi-power-menu-entries} - the very rows Rofi's own power mode
offers - instead of a second copy of the six commands, so the menu under the
logo and the power menu on a right click cannot drift apart."
  (append (list (list "About This Heks" "help-about"
                      (waybar-about-filename))
                waybar-system-menu-rule
                (list "Search" "system-search"
                      (waybar-system-menu-relaunch (waybar-spotlight-command)))
                (list "Desktop Appearance" "preferences-desktop-theme"
                      (toon-spawn-command (toon-palettes-command)))
                (list "Wallpaper" "preferences-desktop-wallpaper"
                      (toon-spawn-command (toon-walls-command)))
                (list "Keyboard Shortcuts" "preferences-desktop-keyboard"
                      (toon-spawn-command (toon-keys-command)))
                (list "Documentation" "help-browser"
                      (toon-spawn-command (toon-docs-command)))
                waybar-system-menu-rule)
          (rofi-power-menu-entries)))

(define (waybar-system-menu-column row index)
  "Return field @var{index} of @var{row}, or the empty string for a rule.

A rule is a plain string, and nothing that reads a row should have to test for
that first: the two places that render a row - the list and the action table -
only differ in what they put in the fields, never in their shape."
  (if (string? row) "" (list-ref row index)))

(define (waybar-system-menu-quote command)
  "Return @var{command} inside the single quotes the generated @code{case} uses.

A single quote in the command is closed, escaped and reopened, because an action
is a shell string and not a symbol: the launcher is a parameter, and a launcher
somebody spelled with a quote in it should not break the menu it is listed in."
  (format #f "'~a'"
          (string-join (string-split command #\') "'\\''")))

(define (waybar-system-menu-rows)
  "Render the generated shell that prints the system menu's rows.

A rule is printed with @code{nonselectable} set, so the keyboard cannot land on
it and a stray Return cannot launch it."
  (string-join (map (lambda (row)
                      (if (string? row)
                          (format #f
                                  "    printf '~a\\0nonselectable\\x1ftrue\\n'\n"
                                  row)
                          (format #f "    printf '~a\\0icon\\x1f~a\\n'\n"
                                  (waybar-system-menu-column row 0)
                                  (waybar-system-menu-column row 1))))
                    (waybar-system-menu-entries))
               ""))

(define (waybar-system-menu-actions)
  "Render the generated shell @code{case} that runs the chosen row."
  (string-join (map (lambda (row)
                      (if (string? row)
                          ""
                          (format #f "      \"~a\") run ~a ;;\n"
                                  (waybar-system-menu-column row 0)
                                  (waybar-system-menu-quote
                                   (waybar-system-menu-column row 2)))))
                    (waybar-system-menu-entries))
               ""))

(define (waybar-system-menu)
  "Render the bar's system menu as a Bash script.

It is a Rofi script-mode menu, like the power menu and the palette picker: it
wears the same glass as the launcher, it can be driven from the keyboard, and it
needs nothing of GTK's menu widgets.  Rofi calls it with @code{ROFI_RETV} unset
to list the rows, and with @code{ROFI_RETV} set to 1 and the chosen row in the
first argument to run that row's action.

Called with no @code{ROFI_RETV} at all it is the bar that is calling, so the
script opens Rofi with itself as a script-mode module - @code{-modi} hands Rofi
the file.  One generated file is therefore both the rows and the way to reach
them, and @file{config.rasi} needs no entry per menu the bar owns.  The window
is pinned under the logo at the top left and is exactly as tall as its list,
which is what a menu dropping from a menu bar does.

Every action is detached, and that is not tidiness: Rofi reads this script's
standard output as its list of rows, so a program still writing into that pipe
when the menu closes dies of SIGPIPE instead of opening."
  (format #f "#!/usr/bin/env bash
# ====== Heks-Linux system menu ======
#
# auto-generated file, DO NOT EDIT!
#
# The row behind the logo at the far left of the bar: what a Mac keeps under the
# apple, this desktop keeps under the lambda.

# Every action below is a string the inner shell reads, so a dollar sign in one
# is meant for it and not for this file.
# shellcheck disable=SC2016

set -u

run() {
    setsid bash -c \"$1\" >/dev/null 2>&1 &
}

if [ -z \"${ROFI_RETV:-}\" ]; then
    # Not Rofi calling: open the menu, handing Rofi this very file as a
    # script-mode module.  A relative invocation - the bar names the script
    # rather than its path - is resolved first, because Rofi would look for it
    # on a path of its own rather than the one this shell is holding.
    self=$0
    [ \"${self#/}\" != \"$self\" ] || self=$(command -v -- \"$self\" || printf '%s' \"$self\")
    exec rofi -show Heks -modi \"Heks:$self\" \\
        -theme-str 'window { location: north west; anchor: north west; xoffset: 12px; yoffset: 46px; width: 26%; }' \\
        -theme-str 'listview { lines: ~a; dynamic: false; }'
fi

case \"${ROFI_RETV:-0}\" in
  0)
~a    ;;
  1)
    case \"$1\" in
~a    esac
    ;;
esac
"
          (length (waybar-system-menu-entries))
          (waybar-system-menu-rows)
          (waybar-system-menu-actions)))

(define (waybar-about)
  "Render the About This Heks window as a Bash script.

The system menu's first row answers the question every desktop's first row
answers - what am I running - and it is a small GTK dialog rather than a second
Rofi menu: the row that opens it is itself a row of a Rofi menu, and two menus
at once would race for the keyboard grab.  On a machine with no zenity the same
fields go to the notification daemon, so the row is never a click that does
nothing.

The palette is baked in at render time, the way the palette picker's current
name is, so the window says which palette the desktop is wearing without having
to find and parse the settings file at click time."
  (format #f "#!/usr/bin/env bash
# ====== Heks-Linux About This Heks ======
#
# auto-generated file, DO NOT EDIT!
#
# What the first row of the system menu opens: the machine, in the words the
# machine uses for itself.

set -u

os='GNU/Linux'
if [ -r /etc/os-release ]; then
    # Sourcing is how os-release is meant to be read: every field it defines is
    # a variable afterwards, and the file is written for exactly this.  The
    # directive is for shellcheck, which cannot follow a distribution file.
    # shellcheck source=/dev/null
    . /etc/os-release
    os=\"${PRETTY_NAME:-${NAME:-$os}}\"
fi

host=$(uname -n)
kernel=$(uname -sr)
cpu=$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo 2>/dev/null)
[ -n \"${cpu:-}\" ] || cpu=$(uname -m)
memory=$(awk '/^MemTotal:/ { total = $2 } /^MemAvailable:/ { free = $2 }
              END { if (total > 0)
                        printf \"%.1f GiB of %.1f GiB\", (total - free) / 1048576, total / 1048576 }' \\
        /proc/meminfo 2>/dev/null)
# Not `uptime -p': the procps of some distributions has never learned the flag,
# and a field that reads unknown on the machine it is describing is worse than
# no field at all.  /proc/uptime is a number of seconds everywhere.
uptime=$(awk '{ d = int($1 / 86400); h = int(($1 % 86400) / 3600); m = int(($1 % 3600) / 60)
                if (d > 0) printf \"%d days, \", d
                if (d > 0 || h > 0) printf \"%d hours, \", h
                printf \"%d minutes\", m }' /proc/uptime 2>/dev/null)
compositor=$(niri --version 2>/dev/null | head -n 1)

[ -n \"${memory:-}\" ] || memory='unknown'
[ -n \"${uptime:-}\" ] || uptime='unknown'
[ -n \"${compositor:-}\" ] || compositor='niri'

# One field: its name in bold, its value in the monospace face an About window
# sets a version number in.
row() {
    printf '<b>%s</b>  <tt>%s</tt>\\n' \"$1\" \"$2\"
}

body=$(printf '%s\\n' \\
    \"$(row 'System' \"$os\")\" \\
    \"$(row 'Host' \"${USER:-$(id -un)}@$host\")\" \\
    \"$(row 'Kernel' \"$kernel\")\" \\
    \"$(row 'Compositor' \"$compositor\")\" \\
    \"$(row 'Palette' '~a')\" \\
    \"$(row 'Processor' \"$cpu\")\" \\
    \"$(row 'Memory' \"$memory\")\" \\
    \"$(row 'Uptime' \"$uptime\")\")

text=\"<span size='x-large'><b>Heks GNU/Linux</b></span>
<span size='small'>the desktop as a program, in Guile Scheme</span>

$body\"

if command -v zenity >/dev/null 2>&1; then
    setsid zenity --info --title='About This Heks' --width=420 --no-wrap \\
        --text=\"$text\" >/dev/null 2>&1 &
elif command -v fyi >/dev/null 2>&1; then
    # No GTK dialog on this machine: the fields still have to reach somebody,
    # so the notification daemon gets them with the markup stripped.
    fyi -a 'Heks Linux' 'About This Heks' \\
        \"$(printf '%s' \"$body\" | sed -e 's/<[^>]*>//g')\" >/dev/null 2>&1
else
    printf '%s\\n' \"$body\" | sed -e 's/<[^>]*>//g'
fi
"
          (heks-linux-palette)))

(define (waybar-system-menu-button)
  "Return the system menu button: the logo at the far left of the bar.

It is the bar's Apple menu - the one item that belongs to the machine rather than
to whatever is open - so it carries the desktop's own mark rather than Apple's: a
lambda, since that is the language this desktop is written in, or a penguin on a
machine that would rather wear its kernel.  A left click opens the menu and a
right click goes straight to the session rows; the tooltip says both, because one
glyph is not a sentence."
  `(custom/heks-system-menu (format unquote (waybar-system-menu-label))
                            (tooltip-format . "Heks GNU/Linux — the machine's own menu\nClick: open it · Right-click: the session menu")
                            (on-click unquote
                                      (format #f "pkill rofi || ~a"
                                              (waybar-system-menu-filename)))
                            (on-click-right . "pkill rofi || rofi -show power")))

(define (waybar-spotlight)
  "Return the spotlight button: one glyph, next to the logo.

Rofi is this desktop's Spotlight, and it used to hide behind the bar's own
label - the leftmost item was a launcher.  Now that the leftmost item is the
system menu, the thing a menu bar keeps there, the launcher gets a glyph of its
own so it is not one click further away than it was.  A left click opens the
launcher and a right click the window switcher, which is the other half of what
Spotlight does.

The glyph is the app grid, Font Awesome's grip, and not the magnifier a Mac
Spotlight wears.  That is not a Preference: U+F002 is claimed by Arial's symbol
table, so on a machine with the Microsoft core fonts Pango draws the ligature
\"fl\" there instead of a magnifier, and a broken glyph on the far left of the
menu bar is the first thing anyone sees.  U+F58D is claimed by Font Awesome and
nothing else, so it draws every time - and it is the mark an app launcher wears
on every other desktop anyway."
  `(custom/heks-spotlight (format . "\uf58d")
                          (tooltip-format . "Search applications\nClick: the launcher · Right-click: switch windows")
                          (on-click unquote
                                    (format #f "pkill rofi || ~a"
                                            (waybar-spotlight-command)))
                          (on-click-right . "pkill rofi || rofi -show window")))

(define (waybar-keybindings)
  "Return the question-mark button that opens the keyboard reference.
The reference is one view of heks-toon, which the bar only has to launch.  A
right click keeps the project page reachable now that this is the bar's only
question mark.  The glyph is Font Awesome's circled question mark rather than a
typed \"?\" - the bar is a row of glyphs, and a character from the text font was
the one item in it that was not one."
  `(custom/heks-keys (format . "\uf059")
                     (tooltip-format . "Every keyboard shortcut\nClick: the reference · Right-click: the Heks Linux project page")
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
Awesome's palette rather than a text label.

A right click is the short way round: the Rofi swatch picker on its own, for the
switch that does not need the window."
  `(custom/heks-palette (format . "\uf53f")
                        (tooltip-format unquote
                                 (format #f
                                         "Palette: ~a\nClick: browse the palettes · Right-click: the quick picker"
                                         (heks-linux-palette)))
                        ;; Through a shell, like the reference and the wall
                        ;; chooser: Waybar spawns the command line as written,
                        ;; and `toon-spawn-command' is what asks the compositor
                        ;; for the activation a bar click cannot prove.
                        (on-click unquote
                                  (toon-spawn-command (toon-palettes-command)))
                        (on-click-right unquote
                                        (format #f "pkill rofi || ~a"
                                                (rofi-theme-menu-filename)))))

(define (waybar-wallpaper)
  "Return the wallpaper button: one picture glyph, next to the palette.

Clicking it opens the wall chooser view of heks-toon, the collection with a
large preview of whatever is selected - the same window ~Mod+Shift+W~ opens.  It
sits beside the palette glyph because the two are the same kind of thing - the
two halves of how the desktop looks - so a menu bar answers the question of how
it looks from one place.

A right click shuffles instead, which is what ~Mod+Shift+B~ does: the wall is
the one thing on this desktop that can be changed without being chosen."
  `(custom/heks-wallpaper (format . "\uf03e")
                          (tooltip-format . "Wallpaper: browse the collection\nClick: browse · Right-click: shuffle")
                          (on-click unquote
                                    (toon-spawn-command (toon-walls-command)))
                          (on-click-right unquote
                                          (format #f "~a random"
                                                  (wallpaper-script-command)))))

(define (waybar-docs)
  "Return the documentation button: one book glyph, beside the wall chooser.

Clicking it opens the documentation view of heks-toon, which reads this
machine's own READMEs rather than a second copy written for the window, so the
page cannot say something the checkouts do not.  It sits with the palette and
wall glyphs because all three are the same question - what is this desktop - and
the book is how the bar answers it without a browser tab.

A right click is for the reader who wants the reference rather than the prose:
the published API documentation, which is generated from these modules' own
docstrings."
  `(custom/heks-docs (format . "\uf518")
                     (tooltip-format . "Heks documentation: the desktop, the editor, the shell\nClick: read · Right-click: the API reference")
                     (on-click unquote
                               (toon-spawn-command (toon-docs-command)))
                     (on-click-right . "xdg-open 'https://jointhefreeworld.org/api-docs/heks-linux/API.html'")))

(define (waybar-mako-dnd)
  "Do-not-disturb indicator.  Shows a slashed bell while mako's
@code{do-not-disturb} mode is active, and toggles it on click.  The word it used
to show - @code{DND} - was the only sentence among the bar's glyphs.

The tooltip is written out rather than taken from the script, because the script
prints one glyph and nothing else.  It can be: the item is only on the bar while
the mode is on, so the tooltip has only one thing to say."
  `(custom/mako-dnd (format . "{}")
                    (tooltip . #t)
                    (tooltip-format . "Do not disturb is on — click to let notifications through")
                    (interval . 3)
                    ;; A slashed bell, in the bar's own alphabet: "DND" was the
                    ;; one text label among the status glyphs.
                    (exec . "makoctl mode 2>/dev/null | grep -q do-not-disturb && printf '\\uf1f6'")
                    (on-click . "makoctl mode -t do-not-disturb")))

(define (waybar-media)
  "Return the now-playing button: one glyph, with the track in its tooltip.

Clicking it opens the media popover - a small Rofi menu of transport controls
that appears under the bar, the way Control Center's Now Playing does.  The bar
itself stays a row of glyphs, which is the whole point of moving the title out
of it: a menu bar names the app you are in, not the song you are playing.

The three mouse buttons are the transport, so the common case needs no menu at
all: a right click plays or pauses and a middle click skips, and the tooltip
names the track and both."
  `(custom/media (format . "\uf025")
                 (interval . 2)
                 (exec . "playerctl metadata --format '{{title}} — {{artist}}' 2>/dev/null || echo 'Nothing playing'")
                 (max-length . 40)
                 (tooltip . #t)
                 (tooltip-format . "{text}\nClick: transport controls · Right: play or pause · Middle: next track")
                 (on-click . "pkill rofi || heks-media-menu")
                 (on-click-right . "playerctl play-pause")
                 (on-click-middle . "playerctl next")))

(define (waybar-clipboard)
  "Return the clipboard button: one clipboard glyph, the history behind it.

Clicking it opens the history picker the compositor binds to Mod+V - clipman's
own pick mode, which puts the chosen entry back on the clipboard.  A bar click
is not the compositor, so the picker is spawned the way every other bar menu is:
after a @code{pkill rofi}, because a second rofi while one is open would refuse
to start rather than take the click.  The glyph is the solid clipboard from the
bar's first font, which is the same alphabet as its neighbours."
  `(custom/heks-clipboard (format . "\uf328")
                          (tooltip-format . "Clipboard history\nClick: browse the history")
                          (on-click unquote
                                    (format #f "pkill rofi || ~a"
                                            (waybar-clipboard-command)))))

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
# Plain text, not pango markup: whether mesg markup renders depends on the theme,
# and a sentence reads the same either way.  The angle brackets are stripped in
# case the theme in use does parse it.
headline=$(printf '%s · %s' \"$status\" \"$track\" | sed -e 's/[<>&]//g')

choice=$(printf '%s\\n' 'Play / Pause' 'Next track' 'Previous track' 'Stop' 'Open RMPC' \\
    | rofi -dmenu -i -no-custom -p 'Media' \\
        -mesg \"$headline\" \\
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

(define (waybar-language-label)
  "Render the script that prints the bar's keyboard-layout label.

It prints the XKB code of the layout in use, in capitals - \"US\", \"NL\" - which
is what a menu bar does with a locale: two letters, not a sentence.  The codes
are baked in from @code{heks-linux-keyboard-layout}, in the same order niri
numbers its layouts, because the display name niri reports (\"English (US)\") is
not something the bar has room for."
  (format #f "#!/usr/bin/env bash
# ====== Heks-Linux keyboard-layout label ======
#
# auto-generated file, DO NOT EDIT!
#
# The bar's language item: the XKB code of the layout in use.

set -u

# The layouts this desktop is configured with, in niri's order.
CODES=(~a)

idx=$(niri msg keyboard-layouts 2>/dev/null | awk '/^ \\*/ {print $2+0}')
[ -n \"${idx:-}\" ] || exit 0

code=\"${CODES[$idx]:-}\"
if [ -n \"$code\" ]; then
    printf '%s' \"${code^^}\"
    exit 0
fi

# A layout this list does not know about - somebody edited niri by hand:
# show its name rather than nothing at all.
niri msg keyboard-layouts 2>/dev/null | sed -n 's/^ *\\* *[0-9][0-9]* //p'
"
          (string-join (map (lambda (code)
                              (format #f "\"~a\"" code))
                            (string-split (heks-linux-keyboard-layout) #\,))
                       " ")))

(define (waybar-language-menu)
  "Render the keyboard-layout menu behind the bar's language item.

A Rofi list of the layouts niri knows, the one in use marked, and a choice that
cycles to it: niri can only step a layout at a time, so a menu entry is \"press
next until it is the one I picked\".  The clever half is choosing the shorter
direction, so picking the last layout does not walk through the whole list.  The
window is only as tall as the list, because a desktop usually has two layouts
and a four row dialog around one of them is three empty rows.

After switching it pokes waybar with @code{SIGRTMIN+8}, which is the signal the
bar's language item watches, so the label changes at once instead of waiting for
the next refresh."
  (format #f "#!/usr/bin/env bash
# ====== Heks-Linux keyboard-layout menu ======
#
# auto-generated file, DO NOT EDIT!
#
# The menu behind the bar's language item: pick a layout, and the desktop
# switches to it.

set -u

listing=$(niri msg keyboard-layouts 2>/dev/null) || exit 0
[ -n \"$listing\" ] || exit 0

current=$(printf '%s\\n' \"$listing\" | awk '/^ \\*/ {print $2+0}')
[ -n \"${current:-}\" ] || current=0

# \" * 0 English (US)\" and \"   1 Dutch\" both become \"0<TAB>English (US)\".
rows=$(printf '%s\\n' \"$listing\" | sed -e '1d' -e 's/^ *\\** *\\([0-9][0-9]*\\) */\\1\\t/')

count=$(printf '%s\\n' \"$rows\" | grep -c .)
[ \"$count\" -gt 0 ] || exit 0

# A window exactly as tall as its list.  Four rows of theme around one layout is
# a dialog with three empty rows in it, and most desktops have two layouts, not
# four.
lines=$(( count < 4 ? count : 4 ))

menu=$(printf '%s\\n' \"$rows\" | while IFS=$(printf '\\t') read -r index name; do
           if [ \"$index\" = \"$current\" ]; then
               printf '✓ %s\\n' \"$name\"
           else
               printf '  %s\\n' \"$name\"
           fi
       done)

choice=$(printf '%s\\n' \"$menu\" | rofi -dmenu -i -no-custom -p 'Keyboard layout' \\
    -mesg \"Right-clicking the bar's language item steps back one layout.\" \\
    -theme-str 'window { width: 22%; location: north; yoffset: 46px; }' \\
    -theme-str \"listview { lines: $lines; dynamic: false; }\" \\
    -theme-str 'inputbar { children: [ button-light-close, prompt, entry ]; }')

[ -n \"${choice:-}\" ] || exit 0

# Put the mark back: what is left is the layout's name, which is how the row is
# found again.
name=${choice#✓ }
name=${name#  }

target=$(printf '%s\\n' \"$rows\" | awk -F\"$(printf '\\t')\" -v want=\"$name\" \\
    '$2 == want { print $1 + 0; exit }')
[ -n \"${target:-}\" ] || exit 0

delta=$(( (target - current + count) % count ))
step=next
if [ \"$delta\" -gt $(( count / 2 )) ]; then
    delta=$(( count - delta ))
    step=prev
fi

i=0
while [ \"$i\" -lt \"$delta\" ]; do
    niri msg action switch-layout \"$step\" >/dev/null 2>&1
    i=$((i + 1))
done

# The label is not a poll: it re-runs when waybar is poked.
pkill -RTMIN+8 waybar 2>/dev/null || true
"))

(define (waybar-language)
  "Return the keyboard-layout item: the layout in capitals, a menu behind it.

Niri reports its layouts by their display name - \"English (US)\" - and its own
module has no short form, which left the bar with one full sentence among a row
of glyphs and numbers.  This is a custom item instead: @code{heks-language-label}
prints the two-letter code, @code{heks-language-menu} is the picker behind a
click, and the right button steps back one layout without opening anything.

The label is not refreshed on a timer.  It is read once, and again when the menu
switches a layout and pokes waybar with @code{SIGRTMIN+8} - the signal this item
declares.  Two letters are not a sentence either, so the tooltip is where the
long name and the two buttons are written down."
  `(custom/heks-language (format . "{}")
                         (tooltip . #t)
                         (tooltip-format . "Keyboard layout: {text}\nClick: choose a layout · Right-click: previous layout")
                         (interval . "once")
                         (signal . 8)
                         (exec unquote
                               (format #f
                                       "~a/~a"
                                       (waybar-language-script-dir)
                                       (waybar-language-label-filename)))
                         (on-click . "pkill rofi || heks-language-menu")
                         (on-click-right . "niri msg action switch-layout prev; pkill -RTMIN+8 waybar")))

(define (waybar-audio-icon)
  "Return the PulseAudio volume indicator.
Shows the volume as one glyph and one number, with a Bluetooth badge when a
headset is connected."
  `(pulseaudio ;; Glyph first, then the number: the same order as every other
    ;; readout on the bar, so the row reads as one thing rather than two.
    ;; A loudspeaker, not the f026..f028 volume ramp: the ramp could not be drawn
    ;; at the bar's weight, so the item was drawing a bare notdef dot.  The mute
    ;; glyph does render, and says what matters anyway.
    ;;
    ;; The source - the microphone - is not in these formats.  `{format_source}'
    ;; is what expanded to it, and it expanded always, so a quiet bar read
    ;; "40% 100% <mic>" wherever the volume was: two numbers for one speaker and
    ;; a glyph for something nobody was recording.  The microphone's own state is
    ;; still declared below, because waybar uses it when the default device *is*
    ;; an input, and because `pavucontrol' on click is where the rest belongs.
    (format . "{icon} {volume}%")
               (format-bluetooth . "{icon} {volume}% \uf294")
               (format-bluetooth-muted . "\uf6a9 \uf294")
               (format-muted . "\uf6a9")
               (format-source . "\uf130 {volume}%")
               (format-source-muted . "\uf131")
               ;; The glyph still follows the device - headphones, a headset, a
               ;; car - and falls back to the loudspeaker.  Only the volume ramp
               ;; is gone: f026..f028 could not be drawn at all.
               (format-icons (headphone . "\uf025")
                             (hands-free . "\uf590")
                             (headset . "\uf590")
                             (phone . "\uf095")
                             (portable . "\uf095")
                             (car . "\uf1b9")
                             (default . "\uf0a1"))
               ;; The tooltip is the one place on this bar with room for a
               ;; sentence, so it names the device and says what the buttons do:
               ;; a menu bar hides its verbs, it does not keep them secret.
               (tooltip-format . "Output: {desc}\nVolume: {volume}%\nClick: mixer · Right: mute · Middle: mute the microphone · Scroll: volume")
               (on-click . "pavucontrol")
               (on-click-right . "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
               (on-click-middle . "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
               ;; The wheel is why a volume glyph is on a bar at all: reach up,
               ;; turn it, and the number follows without opening anything.
               (on-scroll-up . "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")
               (on-scroll-down . "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")))

(define (waybar-power-profiles)
  "Return the power-profiles-daemon indicator.
Shows the active profile with a per-profile glyph and names the driver in its
tooltip.

The item only exists where power-profiles-daemon does: waybar hides the module
when nothing answers on the bus.  So do its buttons - a machine that has the
daemon has the CLI that cycles it, and a machine without both never sees the
glyph to click."
  `(power-profiles-daemon ;; One glyph, and the profile's name in the tooltip:
    ;; the bar is a row of glyphs, and "perf"/"bal"/"eco" were the only words
    ;; that were not a number.
    (format . "{icon}")
                          (tooltip-format . "Power profile: {profile}\nDriver: {driver}\nClick: next profile")
                          (tooltip . #t)
                          (on-click . "powerprofilesctl cycle")
                          (format-icons (default . "\uf0e7")
                                        (performance . "\uf135")
                                        (balanced . "\uf24e")
                                        (power-saver . "\uf06c"))))

(define waybar-battery-2
  `(#{battery#bat2}# (bat . "BAT2")))

(define (waybar-battery)
  "Return the battery indicator.
The warning and critical thresholds come from the module parameters, and the
glyph changes while the machine is charging.

The tooltip is where the numbers that do not fit on a menu bar go: how long is
left, how much power is being drawn, and how worn the pack is - the three things
a battery readout is asked when it is not being glanced at.  A click opens the
session menu, which is the only thing anybody does about a battery that is
nearly flat."
  `(battery (states (warning unquote
                             (waybar-battery-warning))
                    (critical unquote
                              (waybar-battery-critical)))
            (format . "{icon} {capacity}%")
            (format-full . "{icon} {capacity}%")
            ;; Charging and plugged share the bolt, in the icon's place: the
            ;; glyph says what is happening, the number never moves.
            (format-charging . "\uf0e7 {capacity}%")
            (format-plugged . "\uf0e7 {capacity}%")
            (format-alt . "{time} {icon}")
            (format-icons . #("\uf244" "\uf243" "\uf242" "\uf241" "\uf240"))
            (tooltip-format . "{capacity}% — {timeTo}\nPower: {power} W · Health: {health}% · Cycles: {cycles}\nClick: session menu")
            (on-click . "pkill rofi || rofi -show power")))

(define (waybar-clock)
  "Return the clock.
Its format string and refresh interval are parameters, so the bar can show
seconds or a longer date without touching the renderer.

Its tooltip is the month, laid out as a calendar, which is the one thing a date
on a menu bar is asked to explain.  A right click copies the exact time instead,
because the other reason to look at a clock is to write the time down."
  `(clock (on-click . "gnome-calendar")
          (on-click-right . "wl-copy \"$(date '+%Y-%m-%d %H:%M:%S')\"")
          (format unquote
                  (waybar-clock-format))
          (tooltip-format . "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>\nClick: calendar · Right-click: copy the time")
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
Shows the brightness percentage with a glyph that brightens as the value rises.

Three ways to move it, because brightness is the readout people adjust most:
the wheel for a nudge, a click for a nudge the other way, and a right click to
go straight back to full.  The tooltip says all three - a menu bar item that
needs to be discovered by trying it is a puzzle, not a control."
  `(backlight (format . "{icon} {percent}%")
              (format-icons . #("\uf186" "\uf6c4" "\uf185"))
              (tooltip-format . "Brightness: {percent}%\nClick: brighter · Right: full · Scroll: adjust")
              (on-click . "brightnessctl set 5%+")
              (on-click-right . "brightnessctl set 100%")
              (on-scroll-up . "brightnessctl set 5%+")
              (on-scroll-down . "brightnessctl set 5%-")
              (interval . 2)))

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
    ;; The far left of the bar: the machine's own menu, then the launcher's
    ;; glyph.  Everything after this is a status item on the right, except the
    ;; one module below that names what is in front of you.
    ,(waybar-system-menu-button)
    ,(waybar-spotlight)
    ,(waybar-palette)
    ,(waybar-wallpaper)
    ,(waybar-docs)
    ,(waybar-keybindings)
    ;; What is in front of you, the way a menu bar names the focused app.  The
    ;; tooltip is the whole title, which is what the truncation on the bar is
    ;; for; waybar's niri module takes no click handlers, so this one item is a
    ;; label and not a control.
    (niri/window (format . "{title}")
                 (max-length . 40)
                 (tooltip . #t))
    ,(waybar-mako-dnd)
    ,(waybar-language)
    ,(waybar-media)
    ,(waybar-clipboard)
    (keyboard-state ;; One glyph, and only while it means something: caps lock
                    ;; is the key whose state a person cannot see.  The `{name}'
                    ;; the module defaults to spelled "Caps" and "Num" out in a
                    ;; row of glyphs, and an unlocked padlock spends the same
                    ;; width saying nothing - so the unlocked format is empty,
                    ;; which collapses the item to nothing at all.
                    ;;
                    ;; The glyph is the keyboard's own caps-lock symbol and not a
                    ;; padlock: Font Awesome's padlock came out as empty space in
                    ;; this bar, and a state nobody can see, drawn as nothing, is
                    ;; worse than the word it replaced.
                    ;;
                    ;; No tooltip and no click: waybar's keyboard-state module
                    ;; takes neither, and there is nothing an honest click on a
                    ;; locked key could do.  The glyph is the whole message.
                    (numlock . #f)
                    (capslock . #t)
                    (format . "{icon}")
                    (format-icons (locked . "⇪")
                                  (unlocked . "")))
    (niri/mode (format . "<span style=\"italic\">{}</span>"))
    (tray (spacing . 6))
    ,(waybar-clock)
    ;; The two readouts that are someone's whole answer to "why is this machine
    ;; slow".  Waybar's cpu tooltip is the per-core load and its memory tooltip
    ;; is a single number, so the memory one is spelled out here: used, free and
    ;; swap are three facts, and a tooltip is the only place on the bar with room
    ;; for all three.
    (cpu (format . "\uf2db {usage}%")
         (on-click . "gnome-system-monitor")
         (on-click-right . "wezterm start -- btop"))
    (memory (format . "\uf0c9 {percentage}%")
            (interval . 5)
            (tooltip-format unquote
                            (format #f "RAM: {used} GiB of {total} GiB ({percentage}%)\nAvailable: {avail} GiB\nSwap: {swapState} — {swapUsed} GiB of {swapTotal} GiB ({swapPercentage}%)\nClick: system monitor · Right: btop"))
            (on-click . "gnome-system-monitor")
            (on-click-right . "wezterm start -- btop"))
    ,(waybar-backlight)
    ,(waybar-battery)
    ,waybar-battery-2
    ,(waybar-power-profiles)
    ,(waybar-taskbar)
    ,(waybar-audio-icon)))

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
            (color unquote
                   (get-color (heks-linux-palette)
                              'text)))
    ;; The bar's one family, and it has to be declared here rather than on
    ;; `module'.  Waybar builds each item as a label that carries the `*` rule
    ;; itself, so a family declared on the module above never reaches the text:
    ;; the bar has been drawing the system default instead of the configured
    ;; sans font all along, which is only visible as a font nobody asked for.
    ;;
    ;; One family, and not the Font Awesome list this used to be.  GTK's parser
    ;; takes a quoted comma list as a single family *name* - quotes and commas
    ;; included - which matches nothing, and the bar then silently fell back to
    ;; the system default for everything.  So the icons are not named here at
    ;; all: they come from Pango's per-character fallback, which finds the
    ;; Font Awesome face for a private-use codepoint and the sans font for
    ;; anything else, in the same label.
    ;;
    ;; That fallback is also why the items' glyphs are chosen from codepoints
    ;; no text font claims.  U+F002, the magnifier, is claimed by Arial (its
    ;; symbol table maps the range to ligatures), so on a machine carrying the
    ;; Microsoft core fonts the bar drew "fl" where the spotlight should have
    ;; been.  The grip at U+F58D is claimed by Font Awesome alone.
    ("*" (font-family unquote
                      (format #f "'~a'"
                              (heks-linux-sans-font)))
     (padding . "0px")
     (font-weight . 600)
     (transition . "all 0.25s cubic-bezier(0.4, 0, 0.2, 1)"))

    ;; Global window structure
    ("window" (background . transparent))
    ("window#waybar" unquote
     (waybar-bar-bg))

    ;; Individual stylized module layout (Capsule Architecture)
    ;; The macOS menu bar is a row of glyphs on a translucent strip: no chips,
    ;; no frames, no dividers, and one ink.  Mavericks had no accent in its menu
    ;; bar at all - the brightest thing in it is the frontmost application's
    ;; name, and that is bright because it is bold, not because it is coloured -
    ;; so the palette's accent is spent nowhere here.  What the palette still
    ;; decides is the ink and the strip: a light theme gets a white bar with
    ;; dark text, a dark one a smoked strip with light text.
    ("#custom-heks-system-menu" unquote
     `((margin . "0px") (padding . "0px 14px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text))
       ;; GTK's CSS only accepts 100-900 in hundreds, so no 650 here.  The logo
       ;; is bold for the same reason the frontmost window's name is not: it is
       ;; the one item that stands for the machine, not for what it is doing.
       (font-weight . 700)))

    ("#custom-heks-system-menu:hover" unquote
     `((background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'text)
                                #:alpha 0.12))
       (border-radius . "6px")))

    ("#window" unquote
     `((margin . "0px")
       (padding . "0px 12px")
       ;; The frontmost window is the one piece of text on the bar that is not a
       ;; control or a number, so it is told apart by weight, not by ink: the
       ;; system menu is the bold name and this is the light one beside it.
       (font-weight . 400)
       (color unquote
              (get-color (heks-linux-palette)
                         'text))))

    ;; ---------------------------------------------------------------
    ;; Three roles, one ink.
    ;;
    ;; A menu bar is read as one row, so the bar has three kinds of item and
    ;; nothing in between: things you click, things you read at a glance, and
    ;; the states that are usually not there at all.  Before this every module
    ;; carried its own padding, its own weight and its own hover, which is what
    ;; made a bar that was nearly right look assembled rather than drawn.
    ;;
    ;; They are separated by size and by hover, never by colour: the palette
    ;; dresses the strip and the ink, and a bar that tints its own buttons is
    ;; advertising the palette instead of wearing it.
    ;; ---------------------------------------------------------------

    ;; 1. Actions: the spotlight, the reference, the docs, the palette, the wall
    ;;    chooser, the media popover, the clipboard history, the layout menu,
    ;;    do-not-disturb.
    ("#custom-heks-spotlight, #custom-heks-keys, #custom-heks-palette, #custom-heks-wallpaper, #custom-heks-docs, #custom-media, #custom-heks-clipboard, #custom-heks-language, #custom-mako-dnd"
     unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'text))
       (padding . "0px 10px")
       (margin . "0px")
       (font-size . "12pt")
       (font-weight . 600)
       (font-style . "normal")))

    ("#custom-heks-spotlight:hover, #custom-heks-keys:hover, #custom-heks-palette:hover, #custom-heks-wallpaper:hover, #custom-heks-docs:hover, #custom-media:hover, #custom-heks-clipboard:hover, #custom-heks-language:hover, #custom-mako-dnd:hover"
     unquote
     `((background unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'text)
                                #:alpha 0.12))
       (border-radius . "6px")))

    ;; 2. Readouts: one glyph, then the number, in the same order everywhere.
    ("#cpu, #memory, #backlight, #pulseaudio, #battery" unquote
     `((padding . "0px 10px")
       (margin . "0px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text))))

    ;; 3. Quiet state: a profile and a locked key are not actions and not
    ;;    numbers.  They are one glyph that is usually not there at all, so they
    ;;    sit at the readouts' size - their absence is the quiet, not their ink.
    ("#keyboard-state, #power-profiles-daemon" unquote
     `((padding . "0px 8px")
       (margin . "0px")
       (font-size . "12pt")
       (color unquote
              (get-color (heks-linux-palette)
                         'text))))

    ("#clock" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'text))
       (padding . "0px 14px 0px 6px")
       (margin . "0px")))

    ;; Battery states styling: the only colours on the bar that are not the
    ;; palette's, because "nearly flat" and "nearly empty" are not a theme.
    ("#battery.warning" unquote
     `((color . "#ff9e3b")))
    ("#battery.critical" unquote
     `((color . "#e82424") (animation . "blink 1s linear infinite")))

    ;; The tray: the status items other programs bring to the bar.  There is no
    ;; session block below it any more - the ways out of a session live in the
    ;; system menu at the far left, where a Mac keeps them.
    ("#tray" (padding . "0px 6px"))))

;; ===========================================
;; Installation
;; ===========================================

(define* (install-waybar-config)
  "Write @file{config.jsonc} and @file{style.css}, plus the scripts the bar
launches - the system menu, the About window, the media popover and the
keyboard-layout pair - under @file{~/.local/bin}.

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
  ;; The system menu and the About window behind its first row.  They used to
  ;; be a GTK menu in a generated XML file, which only a GTK menu widget could
  ;; wear; as scripts they wear the same glass as the launcher.
  (install-config-file! #:name (waybar-system-menu-filename)
                        #:dir (waybar-system-menu-dir)
                        #:contents (waybar-system-menu)
                        #:perms 493)
  (install-config-file! #:name (waybar-about-filename)
                        #:dir (waybar-system-menu-dir)
                        #:contents (waybar-about)
                        #:perms 493)
  (install-config-file! #:name (waybar-media-menu-filename)
                        #:dir (waybar-media-menu-dir)
                        #:contents (waybar-media-menu)
                        #:perms 493)
  ;; The language item and the menu behind it: one generated pair, like the
  ;; media popover, because both are programs the bar launches.
  (install-config-file! #:name (waybar-language-label-filename)
                        #:dir (waybar-language-script-dir)
                        #:contents (waybar-language-label)
                        #:perms 493)
  (install-config-file! #:name (waybar-language-menu-filename)
                        #:dir (waybar-language-script-dir)
                        #:contents (waybar-language-menu)
                        #:perms 493)
  ;; A machine that ran an older bar still has the XML menu its power glyph
  ;; opened.  It is removed here, when it is there, so the retirement costs
  ;; nothing on a machine that never had one.
  (let ((retired (format #f "~a/~a"
                         (waybar-config-dir)
                         (waybar-power-menu-filename))))
    (when (file-exists? retired)
      (delete-file retired)
      (log-info s "Removed the retired power menu: ~a" retired)))
  (log-success s "Installed Waybar configuration"))
