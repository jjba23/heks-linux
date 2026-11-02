;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

(define-module (heks-linux waybar)
  #:declarative? #t
  #:use-module (heks-linux toon)
  #:use-module (heks-linux rofi)
  #:use-module (heks-linux wallpaper)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux prelude)
  #:use-module (json)
  ;; The bar's stylesheet carries numbers with three decimals (the sheen's
  ;; alpha stops), which the core formatter cannot print.
  #:use-module (ice-9 format)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (install-waybar-config waybar-css
                                  waybar-style
                                  waybar-bar-bg
                                  waybar-system-menu
                                  waybar-system-menu-button
                                  waybar-system-menu-entries
                                  waybar-about
                                  waybar-search
                                  waybar-search-command
                                  waybar-icon
                                  waybar-icon-face
                                  waybar-mako-dnd
                                  waybar-border-radius
                                  waybar-bar-tint
                                  waybar-bar-opacity
                                  waybar-bar-neutral-light
                                  waybar-bar-neutral-dark
                                  waybar-bar-sheen
                                  waybar-hover-opacity
                                  waybar-hover-radius
                                  waybar-extra-css
                                  waybar-keybindings
                                  waybar-media
                                  waybar-clipboard
                                  waybar-clipboard-command
                                  waybar-password
                                  waybar-password-program
                                  waybar-password-command
                                  waybar-password-icon
                                  waybar-password-label
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
                                  waybar-popover-offset
                                  waybar-system-menu-label
                                  waybar-system-menu-face
                                  waybar-system-menu-mark
                                  waybar-mark-characters
                                  waybar-modules-left
                                  waybar-modules-right
                                  waybar-font-size
                                  waybar-margin-top
                                  waybar-margin-bottom
                                  waybar-margin-left
                                  waybar-margin-right
                                  waybar-battery-warning
                                  waybar-battery-critical
                                  waybar-battery-warning-color
                                  waybar-battery-critical-color
                                  waybar-clock-format
                                  waybar-clock-interval))

(define s
  (scriba-auto-logger))

;; ===========================================
;; Configurable Waybar Parameters
;; ===========================================

(define waybar-position
  (make-parameter 'top))

;; The bar is a menu bar, not a floating capsule: it is flush with the top edge,
;; runs the whole width of the screen, and is as tall as its text plus the air
;; the reference leaves around it.
;;
;; The number is a proportion before it is a number of pixels.  The reference's
;; menu bar was 22 pixels tall and its menus were set in 13 pixel type, so
;; the text filled 59% of the bar and was separated from both edges by about six
;; pixels.  Eleven points of the same face is 14.7 pixels, so that proportion
;; alone would put the bar at 25 or 26 - and at 26 the row reads as cramped: the
;; mark, the icons and the clock are taller than the text they sit beside, and an
;; icon is not satisfied by six pixels of air the way a lowercase letter is.
;; Thirty-two pixels gives the row more air above and below its tallest glyph than
;; a letter needs, which is the same proportion measured against the icons and the
;; mark rather than against the text, and it lets one pixel of the bar's material
;; show above the selection veil when a module is hovered.  Taller than that
;; starts to look like a panel floating under the top edge rather than the top of
;; the screen.
;;
;; A machine that wants the tighter bar sets 26, and everything that hangs off the
;; bar follows it: see @code{waybar-popover-offset}.
(define waybar-height
  (make-parameter 32))

;; How far below the top of the screen the windows the bar opens are pinned.
;;
;; The bar's menus hang off it rather than float under it: the menu's top edge
;; is at the bar's bottom edge, so the pointer's own hop from the bar into the
;; menu is the one step the design is built around.  The bar and the windows it
;; opens are two different programs here - Waybar and Rofi - and the only thing
;; they share is this number, so it is computed from the bar rather than written
;; out in each of them: the bar's height plus the four pixels Rofi's own window
;; shadow needs to land under the hairline.
(define waybar-popover-offset
  (make-parameter (+ 4 (waybar-height))))

;; The mark at the far left of the bar, where the reference menu bar carries its mark.
;;
;; A witch's hat, because the slot is the machine's own - the one item on the bar
;; that belongs to the system rather than to whatever is open - and an empty star,
;; drawn as an outline, is a mark that reads at 16 pixels without competing with
;; the window title beside it.
;;
;; U+F005 is Font Awesome's `star', and it is the outline because the face below is
;; the Regular cut: the Solid file draws the same codepoint as a filled shape, and
;; a filled star at the bar's size is a blob.  A machine that would rather have a
;; wheel draws `gear' (U+F013) from the solid face instead.
;;
;; Anything else a machine would rather wear goes in the same slot.  The face is
;; named for whatever it picks, because several fonts claim the codepoints a mark
;; usually comes from:
;;
;;   (waybar-system-menu-label "\uf005")             ; this mark, Font Awesome's star
;;   (waybar-system-menu-face "Font Awesome 6 Free") ; the Regular cut: an outline
;;   (waybar-system-menu-label "\uf6e8")             ; Font Awesome's hat
;;   (waybar-system-menu-face "Font Awesome 6 Free Solid")
;;   (waybar-system-menu-label "\uf17c")             ; Font Awesome's penguin
;;   (waybar-system-menu-face "Font Awesome 6 Brands")
;;   (waybar-system-menu-label "λ")                  ; the language this desktop is written in
;;   (waybar-system-menu-face "DejaVu Sans")
;;   (waybar-system-menu-label "🐧\ufe0e")           ; the penguin as line art
;;   (waybar-system-menu-face "DejaVu Sans")
;;   (waybar-system-menu-label "Heks")               ; the wordmark, in the text font
;;
;; An emoji codepoint needs the variation selector U+FE0E - the *text*
;; presentation - or the colour font answers it whatever face is named: without
;; the selector the bar drew a cream cartoon in a row of one-ink glyphs.  With it,
;; Pango takes DejaVu Sans' drawing of the same codepoint.
;;
;; A single glyph is the other thing this slot can wear, and a machine carrying a
;; face with U+F8FF in it can put one there - a face it installed itself, since
;; this checkout ships none: `(waybar-system-menu-label "\uf8ff")` with
;; `(waybar-system-menu-face ".Keyboard")`.
(define waybar-system-menu-label
  (make-parameter "\uf005"))

;; The face the mark is drawn from, when the label is a mark rather than a word.
;;
;; The regular cut of the bar's icon face, because the mark is one of the bar's
;; glyphs: a private-use codepoint is claimed by several fonts, and the one Pango
;; picks by fallback is not always the one the bar meant - which is why the icons
;; are drawn from named markup spans in the first place.  The cut matters as much
;; as the family: Font Awesome's star is U+F005 in both files, filled in Solid and
;; an outline in Regular, so naming the Regular family is what draws the empty
;; star.  A machine with a different mark names its face here, and the faces above
;; are the ones the comments name.
(define waybar-system-menu-face
  (make-parameter "Font Awesome 6 Free"))

(define waybar-modules-left
  ;; A menu bar's left half is three things and nothing else: the machine's own
  ;; menu, the name of the frontmost application in bold, and the application's
  ;; own menus beside it.  This is the first two: the machine's own menu where the
  ;; mark sits, then what is in front of you - the frontmost window's application
  ;; in bold, its title in the bar's ordinary weight.
  ;;
  ;; The launcher used to sit here and does not any more.  Search is a status item
  ;; - the magnifier is at the right end of the row, next to the clock - and a
  ;; menu bar whose left side is two glyphs and a window list is a menu bar that
  ;; no longer looks like the reference.  The launcher is where the reference
  ;; keeps it; the system menu's Search row is still one click away.
  (make-parameter #(custom/heks-system-menu niri/window)))

(define waybar-modules-right
  ;; Status items, in the order the reference keeps them: the things you glance at
  ;; (now playing, what you copied last, the passwords behind the key,
  ;; do-not-disturb, the input language, the palette, help) come first, then the
  ;; hardware readouts, then the tray - other programs' status items - and then
  ;; the two at the far right: the search magnifier and the clock.  The session
  ;; lives in the system menu, where the reference keeps it, so the old power
  ;; glyph at the end of the row is gone.
  (make-parameter
   #(custom/media custom/heks-clipboard custom/heks-password custom/mako-dnd
     custom/heks-language custom/heks-palette
     custom/heks-wallpaper custom/heks-docs custom/heks-keys cpu
     memory backlight pulseaudio keyboard-state battery
     power-profiles-daemon tray custom/heks-search clock)))

(define waybar-font-size
  (make-parameter "11pt"))

(define waybar-border-radius
  (make-parameter "0px"))

;; How much of the palette's own background survives in the bar, as a 0-1
;; fraction: 0 leaves the neutral menu-bar grey, 1 leaves the palette's
;; colour untouched, and the default moves halfway between them.
;;
;; A palette names a window background, and a window background is not a menu
;; bar: the reference bar was the same graphite in every theme - the wallpaper's
;; colour came through the translucency, not through the theme.  Mixing the two
;; keeps the bar recognisably the palette's (a warm palette stays warm) while
;; stopping a beige or a blue-paper background from turning the menu bar into a
;; coloured strip.  A machine that wants the palette exactly sets 1; one that
;; wants the reference exactly sets 0.
(define waybar-bar-tint
  (make-parameter 0.5))

;; The alpha the bar's background is painted at, or @code{#f} to take the
;; palette's own @code{waybar-opacity}.
;;
;; The palette's fraction is a good default and stays the default; this is the
;; knob for the machine that wants a more (or a less) transparent menu bar than
;; its palette asks for - the difference between a bar you read through and a
;; bar that is part of the wallpaper.
(define waybar-bar-opacity
  (make-parameter #f))

;; The two neutral greys the bar is made of, one per kind of palette.  The
;; reference menu bar was graphite in every theme - the colour in it came through
;; the translucent material, not from the theme - so the bar has a colour of its
;; own and the palette only tints it (see @code{waybar-bar-tint}).  These are the
;; two ends that colour can have: a machine that wants a cooler, a warmer or a
;; slightly darker menu bar than the reference's own changes them here.
(define waybar-bar-neutral-light
  (make-parameter "#f2f3f5"))

(define waybar-bar-neutral-dark
  (make-parameter "#1b1b1d"))

;; How strong the sheen on the bar is, as a multiplier on its three stops: 1 is
;; the full highlight, 0 is a flat strip.  Above 1 the bar starts to look milky,
;; which is what the highlight is not for - the whole look of the bar is that you
;; can see through it - but the knob is there for a machine that
;; wants it brighter.
(define waybar-bar-sheen
  (make-parameter 1))

;; The veil an item wears under the pointer, as the alpha of the bar's own ink,
;; and the corner radius of that veil.  The menu bar does not tint what it is
;; about to open; it darkens the material under the pointer, which is what
;; these two describe.
(define waybar-hover-opacity
  (make-parameter 0.12))

(define waybar-hover-radius
  (make-parameter "6px"))

;; Free-form CSS appended to the generated stylesheet, the one hook for the
;; things this module has no parameter for.  The dock has the same hook
;; (@code{lambdock-styles}) for the same reason: a bar with forty parameters
;; still meets a machine that wants forty-one, and a machine should not have to
;; fork the renderer to ask for letter-spacing.
;;
;; @example
;; (waybar-extra-css "#clock { letter-spacing: 0.5px; }")
;; @end example
(define waybar-extra-css
  (make-parameter ""))

;; A menu bar touches the edges it is a bar against: no floating gap above it and
;; none beside it, because a rounded strip with air around it is a widget pinned
;; to the top of the screen, not the top of the screen.  A machine that wants the
;; floating look back sets these to the old values - 6px above, 12px beside.
(define waybar-margin-top
  (make-parameter "0px"))

(define waybar-margin-bottom
  (make-parameter "0px"))

(define waybar-margin-left
  (make-parameter "0px"))

(define waybar-margin-right
  (make-parameter "0px"))

(define waybar-battery-warning
  (make-parameter 30))

(define waybar-battery-critical
  (make-parameter 15))

;; The colour a battery wears when it is nearly flat, and when it is nearly
;; empty, one per kind of palette.
;;
;; These are the only colours in the bar that are not the palette's: "nearly
;; flat" is not a theme, and a bar that painted it in the palette's own accent
;; would say "look at the palette" at the moment it should say "plug me in".  But
;; a warning is a contrast problem before it is a colour, and the amber that
;; shouts on a smoked bar disappears into a pale one, so each state has a shade
;; for each kind of palette and @code{waybar-alert-color} picks.
(define waybar-battery-warning-color
  (make-parameter '((dark . "#ffb340") (light . "#9a5b00"))))

(define waybar-battery-critical-color
  (make-parameter '((dark . "#ff5f56") (light . "#b3261e"))))

(define waybar-clock-format
  ;; The menu bar's clock: the day, the date, then the time, with the two spaces
  ;; the reference leaves between them ("Sun 26 Oct  13:02").
  ;;
  ;; %d is zero-padded, and the reference's clock is not: the 2nd is "2", not "02".  The
  ;; two spellings that would drop the zero are both worse here - %-d is not a
  ;; chrono specifier, and waybar answers it with `clock: chrono format error:
  ;; invalid specifier' and no clock at all; %e pads with a space instead, which
  ;; gives "Sun  2 Oct" and a gap where the zero was.  So the zero stays, and the
  ;; example above is what the format says rather than what it prints.
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

;; The program behind the bar's key glyph, or @code{#f} for the machine's own
;; password manager (@code{heks-linux-password-command} in
;; @code{(heks-linux user-settings)}, which is also what the session starts at
;; login).  The bar follows the machine unless a machine has a reason for the
;; bar alone to run something else - the web vault, a second manager - which is
;; what this override is for.
;;
;; The default is @code{#f} rather than a copy of the command, so the two cannot
;; drift: change the settings file and both the bar and the session follow.
(define waybar-password-command
  (make-parameter #f))

;; The glyph on that button, as one private-use codepoint from the solid face.
;; Font Awesome's key, because a padlock says "this is locked" - which is the
;; caps-lock indicator's job - while a key says "the passwords are behind here".
;; A machine whose vault has its own mark in a font it installs can say so.
(define waybar-password-icon
  (make-parameter "\uf084"))

;; What the bar's hover text calls the password manager.  The program behind the
;; glyph is @code{heks-linux-password-command} (or the override above); this is
;; the name the tooltip gives it, so a machine that points the glyph at another
;; program points the words at it too instead of leaving 1Password's name on
;; somebody else's vault.
(define waybar-password-label
  (make-parameter "1Password"))

;; The launcher behind the bar's app-grid glyph, and behind the Search row of
;; the system menu.  It is a parameter for the same reason the clipboard picker
;; is: a machine that launches with something other than Rofi should not have to
;; edit the module to say so.  The command is the launcher alone - whichever
;; caller opens it adds the pkill that replaces an open launcher, because a
;; second Rofi would refuse the click rather than take it.
(define waybar-search-command
  (make-parameter "rofi -show drun"))

;; ===========================================
;; Layout & Component Definitions
;; ===========================================

;; One trap is worth writing down before the first module: on a *custom* module
;; `tooltip` is a boolean - it only turns the tooltip on and off - and the text
;; belongs in `tooltip-format`.  A string in `tooltip` is silently ignored, which
;; is how most of this bar came to have no useful hover text at all: the option
;; looks exactly like the one every built-in module takes, and nothing complains.

;; The face the bar's icons are drawn from: not the fontconfig family, which has
;; two faces in it, but the solid file, which is the one with every glyph.
(define waybar-icon-face
  "Font Awesome 6 Free Solid")

(define (waybar-icon glyph)
  "Return @var{glyph} marked up so that the icon face draws it.

The stylesheet can name only one family for the whole bar - GTK reads a quoted
comma list as a single family *name* - so the family there is the text font, and
the icons would otherwise arrive through Pango's per-character fallback.  That
fallback asks fontconfig for a face *at the bar's weight*, and at a regular
weight it is Font Awesome's Regular face, whose glyph for a codepoint is not
always the one the bar meant: U+F518 came out as a slashed circle where the book
belongs.  A markup span is the one place in a label where a font can be named
for a single run of text, so every icon is named here, once, and the text is
left to the stylesheet.

@var{glyph} is a private-use codepoint from Font Awesome 6 Free Solid."
  (format #f "<span font_family=\"~a\">~a</span>" waybar-icon-face glyph))

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
rule between two groups.  The shape is the one a system menu has: what this
machine is, the ways into it, and then the ways out of the session.  The last
group is @code{rofi-power-menu-entries} - the very rows Rofi's own power mode
offers - instead of a second copy of the six commands, so the menu under the
logo and the power menu on a right click cannot drift apart."
  (append (list (list "About This Heks" "help-about"
                      (waybar-about-filename))
                waybar-system-menu-rule
                (list "Search" "system-search"
                      (waybar-system-menu-relaunch (waybar-search-command)))
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
# The row behind the logo at the far left of the bar: what the reference keeps
# under its mark, this desktop keeps under the lambda.

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
    # The window is pinned under the mark, exactly as tall as its rows; the
    # rows themselves are a menu's rows, not the launcher's - the launcher's
    # 40px logos would make a fourteen-row menu taller than most screens, and a
    # menu that drops from a menu bar is read, not browsed.  Its top edge is the
    # bar's bottom edge plus the four pixels a menu's shadow needs, which is
    # `waybar-popover-offset' and not a number written out here.
    exec rofi -show Heks -modi \"Heks:$self\" \\
        -theme-str 'window { location: north west; anchor: north west; xoffset: 12px; yoffset: ~apx; width: 26%; }' \\
        -theme-str 'listview { lines: ~a; dynamic: false; }' \\
        -theme-str 'element { padding: 4px 10px; }' \\
        -theme-str 'element-icon { size: 22px; }'
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
          (waybar-popover-offset)
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

The layout is the reference's About dialog: the machine's name and the system it
runs at the top, then one line per fact with the label bold and the value beside
it - including a startup disk, which the reference names as a disk and this
machine reports as the space left on the root filesystem.

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
# The About window's Startup Disk: the reference names a disk, and this machine
# reports the space left on the root filesystem.
startup=$(df -h / 2>/dev/null | awk 'NR == 2 { printf \"%s free of %s\", $4, $2 }')

[ -n \"${memory:-}\" ] || memory='unknown'
[ -n \"${uptime:-}\" ] || uptime='unknown'
[ -n \"${compositor:-}\" ] || compositor='niri'
[ -n \"${startup:-}\" ] || startup='unknown'

# The reference's About dialog puts the label and the value on one line - the
# label bold, the value in the same face and size as everything else - and that
# is the whole difference between a dialog that reads and a table of fields.
row() {
    printf '<b>%s</b>  %s\\n' \"$1\" \"$2\"
}

body=$(printf '%s\\n' \\
    \"$(row 'Processor' \"$cpu\")\" \\
    \"$(row 'Memory' \"$memory\")\" \\
    \"$(row 'Startup Disk' \"$startup\")\" \\
    \"$(row 'Kernel' \"$kernel\")\" \\
    \"$(row 'Compositor' \"$compositor\")\" \\
    \"$(row 'Palette' '~a')\" \\
    \"$(row 'Uptime' \"$uptime\")\")

text=\"<span size='x-large'><b>Heks GNU/Linux</b></span>
<span size='small'>$os — ${USER:-$(id -un)}@$host</span>

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

(define (waybar-mark-characters text)
  "Return the visible characters of @var{text}, without its variation selectors.

U+FE0E and U+FE0F decide how the character before them is drawn - as text or as
an emoji - and are not characters of their own.  A mark that carries one is still
a mark, and counting it as a second character would send the wordmark down the
\"draw it in the mark's face\" path."
  (let loop ((chars (string->list text)) (kept '()))
    (cond [(null? chars) (reverse kept)]
          [(memv (car chars)
                 (list #\xfe0e #\xff0f #\xfe0f))
           (loop (cdr chars) kept)]
          [else (loop (cdr chars)
                      (cons (car chars) kept))])))

(define (waybar-system-menu-mark)
  "Return the system menu's label, drawn from the face that carries it.

A label of one character is a mark and is wrapped in a span that names
@code{waybar-system-menu-face}; anything longer is a word and is left to the
bar's own font.  The rule is what keeps both halves honest:

  the mark needs its face named, because several fonts claim the codepoints a mark
  is usually drawn from - the cow face is in DejaVu Sans as line art and in Noto
  Color Emoji as a cartoon, and the same glyph is in .Keyboard and in
  Font Awesome.  The one Pango picks by fallback is not always the one the bar
  meant.

  a word must not be wrapped, because the span would draw the wordmark in the
  mark's face instead of the bar's - \"Heks\" in DejaVu Sans beside a title in
  the bar's own face is two different typefaces in one row.

One character is the whole test: @code{🐮\\ufe0e}, @code{λ} and @code{\\uf8ff}
are marks; @code{Heks} is a word.  A machine that wants a multi-glyph mark puts it
in @code{waybar-extra-css} instead, where the row's own rules are."
  (let ((label (waybar-system-menu-label)))
    (if (<= (length (waybar-mark-characters label)) 1)
      (format #f "<span font_family=\"~a\">~a</span>"
              (waybar-system-menu-face)
              label)
      label)))

(define (waybar-system-menu-button)
  "Return the system menu button: the mark at the far left of the bar.

It is the bar's system menu - the one item that belongs to the machine rather than
to whatever is open - so it wears this machine's own mark: an empty star drawn as
an outline, from the regular cut of the bar's icon face in the bar's own ink.  A
left click opens the menu and a right click goes straight to the session rows;
the tooltip says both."
  `(custom/heks-system-menu (format unquote (waybar-system-menu-mark))
                            (tooltip-format . "Heks GNU/Linux — the machine's own menu\nClick: open it · Right-click: the session menu")
                            (on-click unquote
                                      (format #f "pkill rofi || ~a"
                                              (waybar-system-menu-filename)))
                            (on-click-right . "pkill rofi || rofi -show power")))

(define (waybar-search)
  "Return the search button: one magnifier, at the right end of the row.

Rofi is this desktop's launcher, and the reference keeps its search where the
status items are - the magnifier is the last thing on the right before the clock
- so this is a status item and not part of the left-hand menus.  The left of the
bar is then the machine's own menu and the name of whatever is in front of you.
A left click opens the launcher and a right click the window switcher, which is
the other half of what search does.

The glyph is the magnifier, U+F002.  It
used to be the app grid, and the reason is worth keeping: U+F002 is claimed by
Arial's symbol table, so a label that relies on Pango's *fallback* draws the
ligature \"fl\" there on a machine with the Microsoft core fonts.  Inside
`waybar-icon`'s span the family is named, and a named family turns the fallback
off - verified on this machine, which has Arial installed."
  `(custom/heks-search (format unquote (waybar-icon "\uf002"))
                       (tooltip-format . "Search applications\nClick: the launcher · Right-click: switch windows")
                       (on-click unquote
                                 (format #f "pkill rofi || ~a"
                                         (waybar-search-command)))
                       (on-click-right . "pkill rofi || rofi -show window")))

(define (waybar-keybindings)
  "Return the question-mark button that opens the keyboard reference.
The reference is one view of heks-toon, which the bar only has to launch.  A
right click keeps the project page reachable now that this is the bar's only
question mark.  The glyph is Font Awesome's circled question mark rather than a
typed \"?\" - the bar is a row of glyphs, and a character from the text font was
the one item in it that was not one."
  `(custom/heks-keys (format unquote (waybar-icon "\uf059"))
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
  `(custom/heks-palette (format unquote (waybar-icon "\uf53f"))
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
  `(custom/heks-wallpaper (format unquote (waybar-icon "\uf03e"))
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
  `(custom/heks-docs (format unquote (waybar-icon "\uf518"))
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
  `(custom/mako-dnd (format unquote (format #f "<span font_family=\"~a\">{}</span>" waybar-icon-face))
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
  `(custom/media (format unquote (waybar-icon "\uf025"))
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
  `(custom/heks-clipboard (format unquote (waybar-icon "\uf328"))
                          (tooltip-format . "Clipboard history\nClick: browse the history")
                          (on-click unquote
                                    (format #f "pkill rofi || ~a"
                                            (waybar-clipboard-command)))))

(define (waybar-password-program)
  "Return the command the key glyph runs.

Either the bar's own override (@code{waybar-password-command}) or, when that is
@code{#f}, the machine's password manager from
@code{(heks-linux user-settings)} - the same command the session starts at
login, so the app the bar opens is the app that is already running."
  (or (waybar-password-command)
    (heks-linux-password-command)))

(define (waybar-password)
  "Return the password-manager button: one key glyph, the vault behind it.

The glyph is Font Awesome's key, and not a padlock: a padlock says \"this is
locked\", which is what the caps-lock indicator already says, while a key says
\"the passwords are behind here\" - which is the one thing a password manager's
menu-bar item has to say.  Font Awesome's keyhole is a Pro glyph, and its free
lookalike at U+F13E turned out to be the *open* padlock, which reads as the
opposite of a vault.  The glyph itself is @code{waybar-password-icon}.

The program is the machine's @code{heks-linux-password-command} unless the bar
overrides it, so a machine that installed 1Password from its distribution and
one that installed the Flatpak both work without editing this module; the name
in the tooltip is @code{waybar-password-label}, so pointing the glyph elsewhere
does not leave 1Password's name on somebody else's vault.  The click is spawned
through the compositor like the other windows the bar opens: a 1Password that is
already running - it starts at login with @code{--silent} - has to be raised,
and a client cannot raise a window without an activation token.  The
@code{pkill rofi} in front is the same courtesy every bar menu pays: an open
launcher would otherwise swallow the click."
  `(custom/heks-password (format unquote (waybar-icon (waybar-password-icon)))
                         (tooltip-format unquote
                                         (format #f
                                                 "~a: passwords, passkeys and one-time codes\nClick: open it"
                                                 (waybar-password-label)))
                         (on-click unquote
                                   (format #f "pkill rofi || ~a"
                                           (toon-spawn-command
                                            (waybar-password-program))))))

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
        -theme-str 'window { width: 24%; location: north; yoffset: ~apx; }' \\
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
"
          (waybar-popover-offset)))

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
    -theme-str 'window { width: 22%; location: north; yoffset: ~apx; }' \\
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
"
          (waybar-popover-offset)))

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
    (format unquote
            (format #f "~a {volume}%"
                    (waybar-icon "{icon}")))
    (format-bluetooth unquote
                      (format #f "~a {volume}% ~a"
                              (waybar-icon "{icon}")
                              (waybar-icon "\uf294")))
    (format-bluetooth-muted unquote
                            (format #f "~a ~a"
                                    (waybar-icon "\uf6a9")
                                    (waybar-icon "\uf294")))
    (format-muted unquote (waybar-icon "\uf6a9"))
    (format-source unquote
                   (format #f "~a {volume}%"
                           (waybar-icon "\uf130")))
    (format-source-muted unquote (waybar-icon "\uf131"))
    ;; The glyph still follows the device - headphones, a headset, a
    ;; car - and falls back to the loudspeaker.  Only the volume ramp
    ;; is gone: f026..f028 could not be drawn at all.
    (format-icons (headphone unquote (waybar-icon "\uf025"))
                  (hands-free unquote (waybar-icon "\uf590"))
                  (headset unquote (waybar-icon "\uf590"))
                  (phone unquote (waybar-icon "\uf095"))
                  (portable unquote (waybar-icon "\uf095"))
                  (car unquote (waybar-icon "\uf1b9"))
                  (default unquote (waybar-icon "\uf0a1")))
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
    (format-icons (default unquote (waybar-icon "\uf0e7"))
                  (performance unquote (waybar-icon "\uf135"))
                  (balanced unquote (waybar-icon "\uf24e"))
                  (power-saver unquote (waybar-icon "\uf06c")))))

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
            (format unquote
                    (format #f "~a {capacity}%"
                            (waybar-icon "{icon}")))
            (format-full unquote
                         (format #f "~a {capacity}%"
                                 (waybar-icon "{icon}")))
            ;; Charging and plugged share the bolt, in the icon's place: the
            ;; glyph says what is happening, the number never moves.
            (format-charging unquote
                             (format #f "~a {capacity}%"
                                     (waybar-icon "\uf0e7")))
            (format-plugged unquote
                            (format #f "~a {capacity}%"
                                    (waybar-icon "\uf0e7")))
            (format-alt unquote
                        (format #f "{time} ~a"
                                (waybar-icon "{icon}")))
            (format-icons unquote
                          (vector (waybar-icon "\uf244")
                                  (waybar-icon "\uf243")
                                  (waybar-icon "\uf242")
                                  (waybar-icon "\uf241")
                                  (waybar-icon "\uf240")))
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
  `(backlight (format unquote
                      (format #f "~a {percent}%"
                              (waybar-icon "{icon}")))
              (format-icons unquote
                            (vector (waybar-icon "\uf186")
                                    (waybar-icon "\uf6c4")
                                    (waybar-icon "\uf185")))
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
    ;; The custom modules, defined once each: where they sit on the bar is
    ;; `modules-left' and `modules-right' above, and a module defined here but
    ;; named in neither simply does not appear.  Order in this list means
    ;; nothing.
    ,(waybar-system-menu-button)
    ,(waybar-search)
    ,(waybar-palette)
    ,(waybar-wallpaper)
    ,(waybar-docs)
    ,(waybar-keybindings)
    ;; What is in front of you, the way a menu bar names the frontmost
    ;; application.  The tooltip is the whole title, with the application's id
    ;; above it, which is what the truncation on the bar is for; waybar's niri
    ;; module takes no click handlers, so this one item is a label and not a
    ;; control.
    ;;
    ;; Three things were measured here and none of them worked, which is why the
    ;; title is plain text and the mark at the far left is the row's only heavy
    ;; item:
    ;;
    ;;   `{app_id}` exists - the hyphenated `{app-id}` does not, and answers with
    ;;   `niri/window: argument not found` and an empty module - but a Wayland app
    ;;   id is a reverse-DNS string more often than a name.  A WezTerm window on
    ;;   this machine reports `org.wezfurlong.wezterm`, which is not the word a
    ;;   menu bar would set beside its mark.
    ;;
    ;;   `<b>{title}</b>` bolds it, and breaks on the first title with an angle
    ;;   bracket in it: the module puts the title into its label unescaped, so
    ;;   this machine's editor frame - whose title is literally `<eca-chat[...]>` -
    ;;   becomes an unterminated tag and Pango falls back to drawing the whole row
    ;;   unformatted.  A browser title with an ampersand in it does the same.
    ;;
    ;;   `#window { font-weight: 700 }` never reaches the label at all: the module
    ;;   sets its text as markup, and the attribute list Pango builds for it wins
    ;;   over the stylesheet's weight.  Font size from the same rule does apply,
    ;;   which is what makes the weight's silence look like a bug rather than a
    ;;   rule that was ignored.
    (niri/window (format . "{title}")
                 (tooltip-format . "{app_id}\n{title}")
                 (max-length . 50)
                 (tooltip . #t))
    ,(waybar-mako-dnd)
    ,(waybar-language)
    ,(waybar-media)
    ,(waybar-clipboard)
    ,(waybar-password)
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
    (cpu (format unquote
                 (format #f "~a {usage}%"
                         (waybar-icon "\uf2db")))
         (on-click . "gnome-system-monitor")
         (on-click-right . "wezterm start -- btop"))
    (memory (format unquote
                    (format #f "~a {percentage}%"
                            (waybar-icon "\uf0c9")))
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

;; ===========================================
;; The Bar's Material
;; ===========================================
;;
;; A menu bar is not a widget, it is a material: the bar is the wallpaper,
;; blurred and saturated, under a thin veil, with a lit top edge and a hairline
;; at its foot - and it is the same in every theme.  The procedures below are
;; that material.  The compositor does the other half of it: the waybar
;; layer-rule in @code{(heks-linux niri)} blurs what is behind the bar and boosts
;; its saturation, so lowering the veil here is what makes the wallpaper's
;; colour come back through.

(define (waybar-alert-color shades)
  "Return the shade in @var{shades} that belongs to the palette in use.

@var{shades} is an alist of @code{(dark . colour)} and @code{(light . colour)},
so a warning colour can be one idea with two answers and the palette picks
without the caller asking twice whether the theme is dark."
  (let ((key (if (is-dark-palette (heks-linux-palette))
               'dark
               'light)))
    (cdr (assq key shades))))

(define (waybar-bar-neutral)
  "Return the neutral grey the menu bar is made of.

Not a palette colour, because the reference menu bar was graphite in every theme -
the colour in it came through the translucency, not from the theme.  What the
palette decides is which graphite: light themes get
@code{waybar-bar-neutral-light}, dark themes @code{waybar-bar-neutral-dark}."
  (if (is-dark-palette (heks-linux-palette))
    (waybar-bar-neutral-dark)
    (waybar-bar-neutral-light)))

(define (waybar-bar-base)
  "Return the bar's base colour: the neutral material, tinted by the palette.

@code{waybar-bar-tint} says how much of the palette's own background the result
carries, so the bar belongs to the theme it is wearing without becoming a
coloured strip: a beige palette gives a warm-white menu bar, a blue one gives a
cool-white one."
  (mix-colors (waybar-bar-neutral)
              (get-color (heks-linux-palette)
                         'background)
              #:weight (waybar-bar-tint)))

(define (waybar-bar-alpha)
  "Return the alpha the bar's base colour is painted at.

The palette's own @code{waybar-opacity} unless @code{waybar-bar-opacity} says
otherwise, so a palette that asks for more wallpaper to show through gets it,
and a machine that wants a more or less transparent bar than its palette asks
for gets that too."
  (or (waybar-bar-opacity)
    (get-waybar-opacity (heks-linux-palette))))

(define (waybar-bar-gloss)
  "Return the sheen on the bar, the way the reference's menu bar had it.

A sheen, not a fill: the bar itself is the blurred wallpaper under a thin veil,
and this is only the light that falls on it - brightest along the top edge,
almost gone by the foot.  It is deliberately too weak to read as white on its
own: a stronger gloss draws a milky strip with a grey band under it instead of a
menu bar, and the whole look of the bar is that you can see through it.  How
strong it is is @code{waybar-bar-sheen}, which multiplies all three stops."
  (let ((sheen (max 0 (waybar-bar-sheen))))
    (if (is-dark-palette (heks-linux-palette))
      (format #f
              "linear-gradient(180deg, rgba(255, 255, 255, ~,3f) 0%, rgba(255, 255, 255, ~,3f) 50%, rgba(0, 0, 0, ~,3f) 100%)"
              (* 0.16 sheen)
              (* 0.04 sheen)
              (* 0.14 sheen))
      (format #f
              "linear-gradient(180deg, rgba(255, 255, 255, ~,3f) 0%, rgba(255, 255, 255, ~,3f) 50%, rgba(255, 255, 255, ~,3f) 100%)"
              (* 0.34 sheen)
              (* 0.12 sheen)
              (* 0.02 sheen)))))

(define (waybar-bar-text-shadow)
  "Return the shadow under the bar's text.

This is the whole trick of the menu bar: white text on a translucent strip is
unreadable over a bright wallpaper without a dark shadow, and black text on the
light variant needs the opposite one.  The light one is faint on purpose - dark
text sits on a material that is already light enough to carry it, and
a strong white halo around black text reads as a cut-out, not as a menu bar."
  (if (is-dark-palette (heks-linux-palette))
    "0 1px 1px rgba(0, 0, 0, 0.7)"
    "0 1px 0 rgba(255, 255, 255, 0.55)"))

(define* (waybar-bar-bg)
  "Return the bar's own styling attributes.

The bar is the material above - the wallpaper seen through a tinted veil, with a
lit top edge and a hairline at its foot - and its text carries a shadow so it
survives a wallpaper of any tone.  @code{waybar-bar-tint} decides how much of the
palette the veil carries and @code{waybar-bar-opacity} how opaque it is - or, by
default, the palette's own @code{waybar-opacity} - so the bar belongs to the
theme it is wearing.

The drop shadow under the bar is the compositor's, not this stylesheet's: a
Wayland layer surface cannot draw outside its own rectangle, so a CSS box-shadow
here would be clipped away.  @code{(heks-linux niri)} asks niri for the layer's
shadow instead.  The box-shadow below is kept for the compositors that read the
bar's own CSS and clip it anyway, and it is subtle for that reason."
  (let ((dark? (is-dark-palette (heks-linux-palette))))
    `((background unquote
                  (hex-to-rgba (waybar-bar-base)
                               #:alpha
                               (waybar-bar-alpha)))
      (background-image unquote (waybar-bar-gloss))
      (border-top unquote
                  (format #f "1px solid ~a"
                          (if dark?
                            "rgba(255, 255, 255, 0.14)"
                            "rgba(255, 255, 255, 0.9)")))
      (border-bottom unquote
                     (format #f "1px solid ~a"
                             (if dark?
                               "rgba(0, 0, 0, 0.62)"
                               "rgba(0, 0, 0, 0.22)")))
      (border-radius unquote
                     (waybar-border-radius))
      (box-shadow unquote
                  (if dark?
                    "0 1px 2px rgba(0, 0, 0, 0.35)"
                    "0 1px 2px rgba(0, 0, 0, 0.10)"))
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

(define (waybar-hover-veil)
  "Return the declarations a menu-bar item wears under the pointer.

The menu bar does not tint the item it is about to open, it darkens the
material under the pointer - a faint dark veil on the light bar, a faint light
one on the smoked bar.  So the veil is the bar's own ink at
@code{waybar-hover-opacity}, rounded by @code{waybar-hover-radius}: one value
each, and they follow the palette's light or dark choice on their own."
  `((background unquote
                (hex-to-rgba (get-color (heks-linux-palette)
                                        'text)
                             #:alpha
                             (waybar-hover-opacity)))
    (border-radius unquote
                   (waybar-hover-radius))))

(define* (waybar-css)
  "Defines a CSS configuration for Heks-Linux Waybar using Scheme."
  `((module (background . transparent)
            ;; inherited by every item: the bar's text shadow
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
    ;; Microsoft core fonts the bar drew "fl" where the search glyph should have
    ;; been.  The grip at U+F58D is claimed by Font Awesome alone.
    ("*" (font-family unquote
                      (format #f "'~a'"
                              (heks-linux-sans-font)))
     (padding . "0px")
     ;; Regular weight, and that is the reference's decision: the menu bar's face
     ;; was regular, not bold, and the only bold thing in the row was
     ;; the name of the frontmost application.  Asking for 600 made GTK
     ;; synthesise a semibold out of a face that has no semibold in it, which
     ;; reads as a slightly smeared text rather than as a heavier one - and the
     ;; bar's one bold item is worth more when nothing else pretends to be.
     (font-weight . 400)
     (transition . "all 0.25s cubic-bezier(0.4, 0, 0.2, 1)"))

    ;; Global window structure
    ("window" (background . transparent))
    ("window#waybar" unquote
     (waybar-bar-bg))

    ;; Individual stylized module layout (Capsule Architecture)
    ;; A menu bar is a row of glyphs on a translucent strip: no chips, no
    ;; frames, no dividers, and one ink.  The reference had no accent in its menu
    ;; bar at all - the brightest thing in it is the frontmost application's
    ;; name, and that is bright because it is bold, not because it is coloured -
    ;; so the palette's accent is spent nowhere here.  What the palette still
    ;; decides is the ink and the strip: a light theme gets the pale material
    ;; with dark text, a dark one the smoked material with light text, and the
    ;; palette's own background tints either one by `waybar-bar-tint'.
    ("#custom-heks-system-menu" unquote
     `((margin . "0px") (padding . "0px 10px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text))
       ;; A mark, not a word: the first item is a picture, and a picture is
       ;; heavy because it is drawn - so the weight here is the ordinary one, and
       ;; the size is the row's icon size, which is what makes the mark sit level
       ;; with the glyphs beside it instead of a point smaller than them.  A
       ;; machine that puts its wordmark back gets a word at the icon size in the
       ;; ordinary weight, which is a fair description of a logo made of letters.
       (font-size . "12pt")
       (font-weight . 400)))

    ("#custom-heks-system-menu:hover" unquote
     (waybar-hover-veil))

    ("#window" unquote
     `((margin . "0px")
       (padding . "0px 10px")
       ;; Regular, and the row's one heavy item is the mark at the far left - the
       ;; item that stands where the reference keeps its mark.  It sets the
       ;; frontmost application's name bold instead, and that is the one thing of its
       ;; typography this bar cannot copy: the window module's comment records the
       ;; three ways it was tried and what each of them broke on.
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

    ;; 1. Actions: the search, the reference, the docs, the palette, the wall
    ;;    chooser, the media popover, the clipboard history, the passwords, the
    ;;    layout menu, do-not-disturb.
    ("#custom-heks-search, #custom-heks-keys, #custom-heks-palette, #custom-heks-wallpaper, #custom-heks-docs, #custom-media, #custom-heks-clipboard, #custom-heks-password, #custom-heks-language, #custom-mako-dnd"
     unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'text))
       (padding . "0px 8px")
       (margin . "0px")
       (font-size . "12pt")
       (font-style . "normal")))

    ("#custom-heks-search:hover, #custom-heks-keys:hover, #custom-heks-palette:hover, #custom-heks-wallpaper:hover, #custom-heks-docs:hover, #custom-media:hover, #custom-heks-clipboard:hover, #custom-heks-password:hover, #custom-heks-language:hover, #custom-mako-dnd:hover"
     unquote
     (waybar-hover-veil))

    ;; 2. Readouts: one glyph, then the number, in the same order everywhere.
    ("#cpu, #memory, #backlight, #pulseaudio, #battery" unquote
     `((padding . "0px 8px")
       (margin . "0px")
       (color unquote
              (get-color (heks-linux-palette)
                         'text))))

    ;; A status item is a menu too - the network, the sound and the battery all
    ;; open one too - so the readouts light up under the pointer as well.
    ;; Everything that answers a click lights up, and nothing that does not, is
    ;; the rule; the wheel-only items keep their veil because the wheel is the
    ;; click they answer.
    ("#cpu:hover, #memory:hover, #backlight:hover, #pulseaudio:hover, #battery:hover, #clock:hover"
     unquote
     (waybar-hover-veil))

    ;; 3. Quiet state: a profile and a locked key are not actions and not
    ;;    numbers.  They are one glyph that is usually not there at all, so they
    ;;    sit at the readouts' size - their absence is the quiet, not their ink.
    ("#keyboard-state, #power-profiles-daemon" unquote
     `((padding . "0px 6px")
       (margin . "0px")
       (font-size . "12pt")
       (color unquote
              (get-color (heks-linux-palette)
                         'text))))

    ("#clock" unquote
     `((color unquote
              (get-color (heks-linux-palette)
                         'text))
       (padding . "0px 10px 0px 4px")
       (margin . "0px")))

    ;; Battery states styling: the only colours on the bar that are not the
    ;; palette's, because "nearly flat" and "nearly empty" are not a theme.
    ;;
    ;; Two shades of each, because a warning that is legible on a smoked bar is
    ;; not legible on a pale one: the dark palette gets the bright amber and the
    ;; alarm red that read as a warning against near-black, and the light palette
    ;; gets the deeper pair that reads against near-white without turning into a
    ;; smudge.  Contrast against the bar's own background is around 4.5:1 either
    ;; way, which is what the rest of the bar's text is held to.
    ("#battery.warning" unquote
     `((color unquote
              (waybar-alert-color (waybar-battery-warning-color)))))
    ("#battery.critical" unquote
     `((color unquote
              (waybar-alert-color (waybar-battery-critical-color)))
       (animation . "blink 1s linear infinite")))

    ;; The tray: the status items other programs bring to the bar.  There is no
    ;; session block below it any more - the ways out of a session live in the
    ;; system menu at the far left, where the reference keeps them.
    ("#tray" (padding . "0px 4px"))))

;; ===========================================
;; Installation
;; ===========================================

(define* (waybar-style)
  "Return the whole stylesheet: the generated rules, then the machine's own CSS.

The two are one string because they are one file: @code{waybar-extra-css} is
appended rather than merged, so the last word belongs to the machine and it can
override any rule above it - including the material's, which is why no parameter
has to exist for every property a stylesheet can carry."
  (string-append (mk-css-conf-lines (waybar-css))
                 (waybar-extra-css)))

(define* (install-waybar-config)
  "Write @file{config.jsonc} and @file{style.css}, plus the scripts the bar
launches - the system menu, the About window, the media popover and the
keyboard-layout pair - under @file{~/.local/bin}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/waybar-settings.scm} first, and the stylesheet
ends with @code{waybar-extra-css}, so a machine can override any rule the
generator writes.  Waybar has no hot reload, so restart it after a change."
  (log-info s "Installing Waybar configuration")
  (load-local-overrides '(heks-linux waybar)
                        'waybar-settings)
  (install-config-file! #:name (waybar-config-filename)
                        #:dir (waybar-config-dir)
                        #:contents (scm->json-string (waybar-conf #:palette (heks-linux-palette))
                                                     #:pretty #t))
  (install-config-file! #:name (waybar-style-filename)
                        #:dir (waybar-config-dir)
                        #:contents (waybar-style))
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
