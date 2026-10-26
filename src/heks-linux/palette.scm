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

(define-module (heks-linux palette)
  #:declarative? #t
  #:use-module (ice-9 match)
  #:use-module (ice-9 exceptions)
  #:export (raise-unknown-palette-exception get-color
                                            get-gtk-theme
                                            is-dark-palette
                                            get-gtk-accent-color
                                            skeu-icon-theme
                                            get-icon-theme
                                            get-emacs-theme
                                            get-btop-theme
                                            get-lambdock-theme
                                            get-cursor-theme
                                            get-cursor-size
                                            get-wezterm-opacity
                                            get-rofi-opacity
                                            get-waybar-opacity
                                            get-mako-opacity
                                            ansi-color-escapes
                                            get-ansi-color
                                            hex-to-decimal
                                            mix-colors
                                            hex-to-rgba
                                            everforest-light
                                            everforest-dark
                                            kaolin-dark
                                            heavy-metal
                                            modus-vivendi
                                            modus-operandi
                                            modus-vivendi-tinted
                                            modus-operandi-tinted
                                            modus-vivendi-deuteranopia
                                            modus-operandi-deuteranopia
                                            modus-vivendi-tritanopia
                                            modus-operandi-tritanopia
                                            solarized-light
                                            solarized-dark
                                            nord
                                            tokyo-night
                                            rose-pine-moon
                                            rose-pine-dawn
                                            ef-autumn
                                            ef-cyprus
                                            ef-bio
                                            ef-dream
                                            ef-melissa-light
                                            hex-to-rgb
                                            hex-to-rgba
                                            ef-day
                                            ef-kassio
                                            doom-tomorrow-night
                                            doom-molokai
                                            doom-one
                                            doom-one-light
                                            dracula
                                            gruvbox-dark
                                            gruvbox-light
                                            catppuccin-mocha
                                            catppuccin-latte
                                            ayu-dark
                                            ayu-mirage
                                            ayu-light
                                            kanagawa
                                            golden-gate-light
                                            golden-gate-dark
                                            palette-registry
                                            palette-names))

;; --- Core Utilities & Constants ---

(define (raise-unknown-palette-exception palette)
  "Raise an exception naming an unknown palette.
Called by @code{lookup-palette} so that an unrecognised palette stops the run
with a message saying which name was wrong."
  (raise-exception (make-exception-with-message (format #f
                                                 "exception ocurred! unknown palette selected: ~a"
                                                 palette))))

(define ansi-color-escapes
  `((yellow . "\x1b[0;33m") (magenta . "\x1b[0;35m")
    (green . "\x1b[0;32m")
    (default . "\x1b[0;39m")
    (red . "\x1b[0;31m")
    (blue . "\x1b[0;34m")
    (cyan . "\x1b[0;36m")
    (reset . "\x1b[0m")))

(define (raise-unknown-icon-accent-exception accent)
  "Raise an exception naming an accent that has no icon theme.
Called by @code{skeu-icon-theme} so a palette whose @code{gtk-accent} has no
Skeu Icons enamel stops the run instead of quietly wearing a fallback set."
  (raise-exception (make-exception-with-message (format #f
                                                 "exception ocurred! unknown icon accent selected: ~a"
                                                 accent))))

(define-syntax-rule (hex-to-decimal n)
  (string->number (string-append "#x" n)))

(define* (hex-to-rgba hex
                      #:key (alpha 1))
  "Convert a @code{#rrggbb} colour string to a CSS @code{rgba()} colour.
@var{alpha} is a 0-1 fraction and defaults to 1, so a plain colour becomes fully
opaque.  As with @code{hex-to-rgb}, input that is not a colour string falls back
to opaque black."
  (if (and (string? hex)
           (>= (string-length hex) 7)
           (char=? (string-ref hex 0) #\#))
      (let* ((digits (string-drop hex 1))
             (red (hex-to-decimal (string-take digits 2)))
             (green (hex-to-decimal (string-take (string-drop digits 2) 2)))
             (blue (hex-to-decimal (string-drop digits 4))))
        (format #f
                "rgba(~a, ~a, ~a, ~a)"
                red
                green
                blue
                alpha)) "rgba(0, 0, 0, 1)"))

(define* (hex-to-rgb hex)
  "Convert a @code{#rrggbb} colour string to a CSS @code{rgb()} colour.
@var{hex} is rendered with its components as decimal integers.  Input that is
not a colour string falls back to opaque black, which keeps a malformed palette
from aborting a whole render."
  (if (and (string? hex)
           (>= (string-length hex) 7)
           (char=? (string-ref hex 0) #\#))
      (let* ((digits (string-drop hex 1))
             (red (hex-to-decimal (string-take digits 2)))
             (green (hex-to-decimal (string-take (string-drop digits 2) 2)))
             (blue (hex-to-decimal (string-drop digits 4))))
        (format #f "rgb(~a, ~a, ~a)" red green blue)) "rgb(0, 0, 0)"))

(define (colour-channels hex)
  "Return the red, green and blue channels of a @code{#rrggbb} colour.

@var{hex} that is not a colour string returns @code{#f}, so a caller can fall
back on the colour it already had instead of failing on a malformed palette."
  (if (and (string? hex)
           (>= (string-length hex) 7)
           (char=? #\# (string-ref hex 0)))
      (let ((digits (substring hex 1 7)))
        (list (hex-to-decimal (substring digits 0 2))
              (hex-to-decimal (substring digits 2 4))
              (hex-to-decimal (substring digits 4 6))))
      #f))

(define (colour-to-hex channels)
  "Return three 0-255 @var{channels} as a @code{#rrggbb} colour string.

Each channel is padded to two digits, so a colour with a low channel keeps its
shape - @code{#0a0b0c} and not @code{#abc}."
  (string-append "#"
                 (string-pad (number->string (list-ref channels 0) 16) 2 #\0)
                 (string-pad (number->string (list-ref channels 1) 16) 2 #\0)
                 (string-pad (number->string (list-ref channels 2) 16) 2 #\0)))

(define* (mix-colors base over #:key (weight 0.5))
  "Return @var{base} moved @var{weight} of the way toward @var{over}.

@var{weight} is a 0-1 fraction: 0 leaves @var{base} untouched, 1 returns
@var{over}, and 0.5 is the colour halfway between them.  This is how the bar
takes a palette's own background and moves it toward the neutral grey a Mac's
menu bar is made of, so that a warm or a blue palette still reads as a menu bar
rather than as a coloured strip taped to the screen.

Both arguments are @code{#rrggbb} strings and the result is one too.  Input that
is not a colour string falls back on @var{base}, the same tolerance
@code{hex-to-rgba} has.  The fraction is clamped to 0-1, so a setting written as
1.2 cannot produce a colour that is not a colour."
  (let* ((from (colour-channels base))
         (to (colour-channels over))
         (w (max 0 (min 1 weight))))
    (if (and from to)
        (colour-to-hex (map (lambda (a b)
                              (inexact->exact
                               (round (+ (* a (- 1 w)) (* b w)))))
                            from to))
        base)))

;; --- Icon Themes ---
;;
;; Every palette wears the same artwork - Skeu Icons - so the icon theme is
;; derived rather than stored in a palette: the accent a palette already names
;; for GTK picks the enamel variant, and its `dark?' key picks the light-ink
;; sibling.  Deriving it is what keeps a palette's icons on the accent the rest
;; of the desktop is asked for, and means no palette can name a theme that is
;; not installed.
;;
;; Skeu Icons ships one theme per enamel - red, orange, yellow, lime, green,
;; teal, cyan, blue, indigo, violet, magenta, pink, brown and graphite - plus a
;; -dark sibling of each for light-ink symbolic icons.  The bare accent name is
;; the light theme.  GTK has no violet and no graphite accent - it calls those
;; purple and slate - so those two are translated instead of copied.  The
;; reverse names are listed too, because a palette is free to spell its accent
;; the way the icons do.

(define skeu-icon-accents
  '((red . "red")
    (orange . "orange")
    (yellow . "yellow")
    (lime . "lime")
    (green . "green")
    (teal . "teal")
    (cyan . "cyan")
    (blue . "blue")
    (indigo . "indigo")
    (violet . "violet")
    (purple . "violet")
    (magenta . "magenta")
    (pink . "pink")
    (brown . "brown")
    (graphite . "graphite")
    (slate . "graphite")))

(define (skeu-icon-theme accent dark?)
  "Return the Skeu Icons theme name for @var{accent} and @var{dark?}.
@var{accent} is a palette's symbolic GTK accent and is translated to the enamel
of the same name, except for the two GTK-only names (@code{purple} and
@code{slate}).  @var{dark?} picks the theme's light-ink sibling, which is the
same artwork with @code{-dark} appended.  An accent Skeu Icons has no enamel for
raises rather than returning a name nothing installs."
  (let ((enamel (assoc-ref skeu-icon-accents accent)))
    (if enamel
        (format #f "skeu-icons-~a~a" enamel (if dark? "-dark" ""))
        (raise-unknown-icon-accent-exception accent))))

;; --- Palette Definitions ---

(define ef-day
  `((dark? . #f) (emacs-theme . "'ef-day")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . orange)
    (lambdock-theme . vanilla-light)
    (ansi-color . default)
    (primary . "#c06000")
    (primary-l . "#da7800")
    (text . "#3b3b3b")
    (text-l . "#4c4c4c")
    (background . "#fefcf4")
    (background-l . "#f4f0e0")))

(define ef-kassio
  `((dark? . #f) (emacs-theme . "'ef-kassio")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . cyan)
    (lambdock-theme . vanilla-light)
    (ansi-color . cyan)
    (primary . "#007a9a")
    (primary-l . "#0096bc")
    (text . "#203235")
    (text-l . "#32484c")
    (background . "#f4f9fa")
    (background-l . "#e5eff1")))

(define ef-melissa-light
  `((dark? . #f) (emacs-theme . "'ef-melissa-light")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . yellow)
    (lambdock-theme . solarized-light)
    (ansi-color . yellow)
    (primary . "#efbf00")
    (primary-l . "#ba5205")
    (text . "#484431")
    (text-l . "#585542")
    (background . "#fff6d8")
    (background-l . "#f5e9cb")))

(define ef-dream
  `((dark? . #t) (emacs-theme . "'ef-dream")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . purple)
    (lambdock-theme . vanilla)
    (ansi-color . magenta)
    (primary . "#675072")
    (primary-l . "#b0a0cf")
    (text . "#efd5c5")
    (text-l . "#dec4b4")
    (background . "#232025")
    (background-l . "#322f34")))

(define ef-bio
  `((dark? . #t) (emacs-theme . "'ef-bio")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . green)
    (lambdock-theme . nature)
    (ansi-color . green)
    (primary . "#00552f")
    (primary-l . "#3fb83f")
    (text . "#dfefe6")
    (text-l . "#cfdfd5")
    (background . "#111111")
    (background-l . "#222522")))

(define ef-cyprus
  `((dark? . #f) (emacs-theme . "'ef-cyprus")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . green)
    (lambdock-theme . vanilla-light)
    (ansi-color . green)
    (primary . "#b3d19d")
    (primary-l . "#4fc94f")
    (text . "#242521")
    (text-l . "#353632")
    (background . "#fcf7ef")
    (background-l . "#f0ece0")))

(define ef-autumn
  `((dark? . #t) (emacs-theme . "'ef-autumn")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dusklight\"")
    (gtk-accent . orange)
    (lambdock-theme . unity)
    (ansi-color . yellow)
    (primary . "#7a3b23")
    (primary-l . "#c0620e")
    (text . "#dfcdcb")
    (text-l . "#cfbcba")
    (background . "#26211d")
    (background-l . "#36322f")))

(define solarized-light
  `((dark? . #f) (emacs-theme . "'solarized-light")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . pink)
    (lambdock-theme . solarized-light)
    (ansi-color . default)
    (primary . "#f9a25a")
    (primary-l . "#e89149")
    (text . "#142a31")
    (text-l . "#253b42")
    (background . "#fdf6e3")
    (background-l . "#eee8d5")))

(define heavy-metal
  `((dark? . #t) (emacs-theme . "'ef-tritanopia-dark")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"monokai\"")
    (gtk-accent . red)
    (lambdock-theme . vanilla)
    (ansi-color . red)
    (primary . "#b02930")
    (primary-l . "#f47360")
    (text . "#ffe6d6")
    (text-l . "#efd5c5")
    (background . "#111111")
    (background-l . "#222522")))

(define everforest-dark
  `((dark? . #t) (emacs-theme . "'everforest-hard-dark")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-dark-medium\"")
    (gtk-accent . green)
    (lambdock-theme . nature)
    (ansi-color . green)
    (primary . "#a7c080")
    (primary-l . "#b8d191")
    (text . "#d3c6aa")
    (text-l . "#e4d7bb")
    (background . "#272e33")
    (background-l . "#1e2326")))

(define everforest-light
  `((dark? . #f) (emacs-theme . "'everforest-hard-light")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . green)
    (lambdock-theme . vanilla-light)
    (ansi-color . default)
    (primary . "#a7c080")
    (primary-l . "#b8d191")
    (text . "#272e33")
    (text-l . "#383f44")
    (background . "#fffbef")
    (background-l . "#eeeade")))

(define gruvbox-dark
  `((dark? . #t) (emacs-theme . "'gruvbox-dark-hard")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"gruvbox_dark_v2\"")
    (gtk-accent . orange)
    (lambdock-theme . vanilla)
    (ansi-color . yellow)
    (primary . "#fe8019")
    (primary-l . "#d65d0e")
    (text . "#ebdbb2")
    (text-l . "#fbf1c7")
    (background . "#1d2021")
    (background-l . "#282828")))

(define gruvbox-light
  `((dark? . #f) (emacs-theme . "'gruvbox-light-hard")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"gruvbox_light\"")
    (gtk-accent . orange)
    (lambdock-theme . solarized-light)
    (ansi-color . default)
    (primary . "#d65d0e")
    (primary-l . "#d75f00")
    (text . "#1d2021")
    (text-l . "#282828")
    (background . "#ebdbb2")
    (background-l . "#fbf1c7")))

(define dracula
  `((dark? . #t) (emacs-theme . "'dracula")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . pink)
    (lambdock-theme . vanilla)
    (ansi-color . magenta)
    (primary . "#bd93f9")
    (primary-l . "#ff79c6")
    (text . "#f8f8f2")
    (text-l . "#e7e8e1")
    (background . "#282a36")
    (background-l . "#44475a")))

(define catppuccin-latte
  `((dark? . #f) (emacs-theme . "'catppuccin-latte")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . yellow)
    (lambdock-theme . vanilla-light)
    (ansi-color . magenta)
    (primary . "#8839ef")
    (primary-l . "#ea76cb")
    (text . "#4c4f69")
    (text-l . "#5c5f77")
    (background . "#eff1f5")
    (background-l . "#e6e9ef")))

(define catppuccin-mocha
  `((dark? . #t) (emacs-theme . "'catppuccin-mocha")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . pink)
    (lambdock-theme . vanilla)
    (ansi-color . magenta)
    (primary . "#cba6f7")
    (primary-l . "#f5c2e7")
    (text . "#cdd6f4")
    (text-l . "#bac2de")
    (background . "#1e1e2e")
    (background-l . "#181825")))

(define modus-vivendi
  `((dark? . #t) (emacs-theme . "'modus-vivendi")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . pink)
    (lambdock-theme . vanilla)
    (ansi-color . magenta)
    (primary . "#feacd0")
    (primary-l . "#caa6df")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#000000")
    (background-l . "#1e1e1e")))

(define modus-operandi
  `((dark? . #f) (emacs-theme . "'modus-operandi")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . purple)
    (lambdock-theme . vanilla-light)
    (ansi-color . magenta)
    (primary . "#feacd0")
    (primary-l . "#caa6df")
    (text . "#000000")
    (text-l . "#1e1e1e")
    (background . "#ffffff")
    (background-l . "#cbcbcb")))

(define modus-vivendi-tinted
  `((dark? . #t) (emacs-theme . "'modus-vivendi-tinted")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . purple)
    (lambdock-theme . vanilla)
    (ansi-color . magenta)
    (primary . "#feacd0")
    (primary-l . "#caa6df")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#1d2021")
    (background-l . "#282a2b")))

(define modus-operandi-tinted
  `((dark? . #f) (emacs-theme . "'modus-operandi-tinted")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . purple)
    (lambdock-theme . vanilla-light)
    (ansi-color . magenta)
    (primary . "#feacd0")
    (primary-l . "#caa6df")
    (text . "#000000")
    (text-l . "#1e1e1e")
    (background . "#fbf7ee")
    (background-l . "#f3ede2")))

(define modus-vivendi-deuteranopia
  `((dark? . #t) (emacs-theme . "'modus-vivendi-deuteranopia")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . pink)
    (lambdock-theme . vanilla)
    (ansi-color . blue)
    (primary . "#6495ed")
    (primary-l . "#79a8ff")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#000000")
    (background-l . "#1e1e1e")))

(define modus-operandi-deuteranopia
  `((dark? . #f) (emacs-theme . "'modus-operandi-deuteranopia")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . pink)
    (lambdock-theme . vanilla-light)
    (ansi-color . blue)
    (primary . "#0031a9")
    (primary-l . "#2544bb")
    (text . "#000000")
    (text-l . "#1e1e1e")
    (background . "#ffffff")
    (background-l . "#cbcbcb")))

(define modus-vivendi-tritanopia
  `((dark? . #t) (emacs-theme . "'modus-vivendi-tritanopia")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . pink)
    (lambdock-theme . vanilla)
    (ansi-color . cyan)
    (primary . "#00bcff")
    (primary-l . "#54d5ff")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#000000")
    (background-l . "#1e1e1e")))

(define modus-operandi-tritanopia
  `((dark? . #f) (emacs-theme . "'modus-operandi-tritanopia")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . pink)
    (lambdock-theme . vanilla-light)
    (ansi-color . cyan)
    (primary . "#005f88")
    (primary-l . "#007ea7")
    (text . "#000000")
    (text-l . "#1e1e1e")
    (background . "#ffffff")
    (background-l . "#cbcbcb")))

(define kaolin-dark
  `((dark? . #t) (emacs-theme . "'kaolin-dark")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"matcha-dark-sea\"")
    (gtk-accent . green)
    (lambdock-theme . vanilla)
    (ansi-color . green)
    (primary . "#80bcb6")
    (primary-l . "#4d9391")
    (text . "#e6e6e8")
    (text-l . "#f2f2f2")
    (background . "#18181B")
    (background-l . "#222225")))

(define doom-tomorrow-night
  `((dark? . #t) (emacs-theme . "'doom-tomorrow-night")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . orange)
    (lambdock-theme . vanilla)
    (ansi-color . magenta)
    (primary . "#de935f")
    (primary-l . "#dd9955")
    (text . "#c5c8c6")
    (text-l . "#c5c5c5")
    (background . "#1d1f21")
    (background-l . "#161719")))

(define doom-molokai
  `((dark? . #t) (emacs-theme . "'doom-molokai")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"gruvbox_dark_v2\"")
    (gtk-accent . orange)
    (lambdock-theme . vanilla)
    (ansi-color . yellow)
    (primary . "#fd971f")
    (primary-l . "#dd9955")
    (text . "#dfdfdf")
    (text-l . "#d6d6d4")
    (background . "#1c1e1f")
    (background-l . "#222323")))

(define doom-one
  `((dark? . #t) (emacs-theme . "'doom-one")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . purple)
    (lambdock-theme . vanilla)
    (ansi-color . magenta)
    (primary . "#c678dd")
    (primary-l . "#a9a1e1")
    (text . "#dfdfdf")
    (text-l . "#bfbfbf")
    (background . "#282c34")
    (background-l . "#21242b")))

(define doom-one-light
  `((dark? . #f) (emacs-theme . "'doom-one-light")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"gruvbox_light_v2\"")
    (gtk-accent . purple)
    (lambdock-theme . vanilla-light)
    (ansi-color . magenta)
    (primary . "#b751b6")
    (primary-l . "#a626a4")
    (text . "#383a42")
    (text-l . "#424242")
    (background . "#fafafa")
    (background-l . "#f0f0f0")))

(define solarized-dark
  `((dark? . #t) (emacs-theme . "'solarized-dark")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-dark\"")
    (gtk-accent . blue)
    (lambdock-theme . vanilla)
    (ansi-color . blue)
    (primary . "#268bd2")
    (primary-l . "#2aa198")
    (text . "#839496")
    (text-l . "#93a1a1")
    (background . "#002b36")
    (background-l . "#073642")))

(define nord
  `((dark? . #t) (emacs-theme . "'nord")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"nord\"")
    (gtk-accent . blue)
    (lambdock-theme . vanilla)
    (ansi-color . cyan)
    (primary . "#88c0d0")
    (primary-l . "#81a1c1")
    (text . "#eceff4")
    (text-l . "#d8dee9")
    (background . "#2e3440")
    (background-l . "#3b4252")))

(define tokyo-night
  `((dark? . #t) (emacs-theme . "'tokyo-night")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"tokyo-night\"")
    (gtk-accent . purple)
    (lambdock-theme . vanilla)
    (ansi-color . blue)
    (primary . "#7aa2f7")
    (primary-l . "#bb9af7")
    (text . "#c0caf5")
    (text-l . "#a9b1d6")
    (background . "#1a1b26")
    (background-l . "#24283b")))

(define rose-pine-moon
  `((dark? . #t) (emacs-theme . "'rose-pine-moon")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . pink)
    (lambdock-theme . vanilla)
    (ansi-color . magenta)
    (primary . "#ea9a97")
    (primary-l . "#c4a7e7")
    (text . "#e0def4")
    (text-l . "#908caa")
    (background . "#232136")
    (background-l . "#2a283e")))

(define rose-pine-dawn
  `((dark? . #f) (emacs-theme . "'rose-pine-dawn")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . pink)
    (lambdock-theme . solarized-light)
    (ansi-color . magenta)
    (primary . "#d7827e")
    (primary-l . "#907aa9")
    (text . "#575279")
    (text-l . "#797593")
    (background . "#faf4ed")
    (background-l . "#fffaf3")))

(define kanagawa
  `((dark? . #t) (emacs-theme . "'kanagawa")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . blue)
    (lambdock-theme . vanilla)
    (ansi-color . blue)
    (primary . "#7e9cd8")
    (primary-l . "#a3b8ef")
    (text . "#dcd7ba")
    (text-l . "#c8c093")
    (background . "#1f1f28")
    (background-l . "#2a2a37")))

(define ayu-dark
  `((dark? . #t) (emacs-theme . "'ayu-dark")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . orange)
    (lambdock-theme . vanilla)
    (ansi-color . yellow)
    (primary . "#ff9940")
    (primary-l . "#ffb454")
    (text . "#e6e1cf")
    (text-l . "#b3b1ad")
    (background . "#0f1419")
    (background-l . "#131721")))

(define ayu-mirage
  `((dark? . #t) (emacs-theme . "'ayu-grey")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . orange)
    (lambdock-theme . vanilla)
    (ansi-color . yellow)
    (primary . "#ffae57")
    (primary-l . "#ffcc66")
    (text . "#cbccc6")
    (text-l . "#707a8c")
    (background . "#212733")
    (background-l . "#242936")))

(define ayu-light
  `((dark? . #f) (emacs-theme . "'ayu-light")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.82)
    (rofi-opacity . 0.80)
    (waybar-opacity . 0.68)
    (mako-opacity . 0.66)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . orange)
    (lambdock-theme . vanilla-light)
    (ansi-color . default)
    (primary . "#ff9940")
    (primary-l . "#f29718")
    (text . "#5a6c75")
    (text-l . "#6d7277")
    (background . "#fafafa")
    (background-l . "#f3f3f3")))

;; The Golden Gate pair follows Apple's own system palette rather than a
;; third-party theme: the window backgrounds, the ink and the secondary label
;; greys are the values macOS uses, and so is the system blue.  The two variants
;; differ only in where the light comes from, which is what keeps them a pair.
;;
;; macOS translucency is the other half of the look: the Golden Gate pair asks
;; every app for a lower opacity than the rest of the registry, so its windows
;; and panels let more of the wallpaper through.
(define golden-gate-light
  `((dark? . #f) (emacs-theme . "'modus-operandi")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.68)
    (rofi-opacity . 0.70)
    (waybar-opacity . 0.48)
    (mako-opacity . 0.50)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . blue)
    (lambdock-theme . snow-leopard)
    (ansi-color . blue)
    (primary . "#007aff")
    (primary-l . "#0a84ff")
    (text . "#1d1d1f")
    (text-l . "#6e6e73")
    (background . "#f5f5f7")
    (background-l . "#e5e5ea")))

(define golden-gate-dark
  `((dark? . #t) (emacs-theme . "'modus-vivendi")
    (cursor-theme . "WhiteSur-cursors")
    (wezterm-opacity . 0.68)
    (rofi-opacity . 0.70)
    (waybar-opacity . 0.48)
    (mako-opacity . 0.50)
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . blue)
    (lambdock-theme . vanilla)
    (ansi-color . blue)
    (primary . "#0a84ff")
    (primary-l . "#409cff")
    (text . "#f5f5f7")
    (text-l . "#a1a1a6")
    (background . "#1e1e1e")
    (background-l . "#2c2c2e")))

;; --- Master Unified Registry ---

(define palette-registry
  `((ef-melissa-light unquote ef-melissa-light)
    (ef-dream unquote ef-dream)
    (ef-bio unquote ef-bio)
    (ef-cyprus unquote ef-cyprus)
    (ef-autumn unquote ef-autumn)
    (ef-day unquote ef-day)
    (ef-kassio unquote ef-kassio)
    (solarized-light unquote solarized-light)
    (heavy-metal unquote heavy-metal)
    (everforest-dark unquote everforest-dark)
    (everforest-light unquote everforest-light)
    (gruvbox-dark unquote gruvbox-dark)
    (gruvbox-light unquote gruvbox-light)
    (dracula unquote dracula)
    (catppuccin-latte unquote catppuccin-latte)
    (catppuccin-mocha unquote catppuccin-mocha)
    (modus-vivendi unquote modus-vivendi)
    (modus-operandi unquote modus-operandi)
    (modus-vivendi-tinted unquote modus-vivendi-tinted)
    (modus-operandi-tinted unquote modus-operandi-tinted)
    (modus-vivendi-deuteranopia unquote modus-vivendi-deuteranopia)
    (modus-operandi-deuteranopia unquote modus-operandi-deuteranopia)
    (modus-vivendi-tritanopia unquote modus-vivendi-tritanopia)
    (modus-operandi-tritanopia unquote modus-operandi-tritanopia)
    (kaolin-dark unquote kaolin-dark)
    (doom-tomorrow-night unquote doom-tomorrow-night)
    (doom-molokai unquote doom-molokai)
    (doom-one unquote doom-one)
    (doom-one-light unquote doom-one-light)
    (solarized-dark unquote solarized-dark)
    (nord unquote nord)
    (tokyo-night unquote tokyo-night)
    (rose-pine-moon unquote rose-pine-moon)
    (rose-pine-dawn unquote rose-pine-dawn)
    (kanagawa unquote kanagawa)
    (ayu-dark unquote ayu-dark)
    (ayu-mirage unquote ayu-mirage)
    (ayu-light unquote ayu-light)
    (golden-gate-light unquote golden-gate-light)
    (golden-gate-dark unquote golden-gate-dark)))

(define (palette-names)
  "Return the list of every palette name supported by Heks Linux, in
registry order.

This is what powers the Rofi theme picker and any other UI that needs to
enumerate the available palettes without hardcoding them.

@example
(palette-names)
@result{} (ef-melissa-light ef-dream ... kanagawa)
@end example"
  (map car palette-registry))

(define (lookup-palette palette-sym)
  "Return the association list for @var{palette-sym}.
This is the single entry point into the palette registry and every other getter
is a thin wrapper over it.  An unknown palette raises rather than returning
@code{#f}, so a typo fails loudly at render time instead of producing a
half-configured system."
  (let ((res (assoc-ref palette-registry palette-sym)))
    (if res res
        (raise-unknown-palette-exception palette-sym))))

;; --- Functional Engine / Getters ---

(define (get-color palette-sym sym)
  "Look up one semantic colour in a palette.
@var{palette-sym} names a registered palette and @var{sym} one of its keys, such
as @code{text}, @code{primary} or @code{background}.  Every renderer goes
through this procedure, which is why all of them follow the selected palette."
  (cdr (assoc sym
              (lookup-palette palette-sym))))

(define (is-dark-palette palette-sym)
  "Return @code{#t} when @var{palette-sym} is a dark palette.
Reads the @code{dark?} key that every palette declares; consumers use it to pick
between the light and dark variant of a theme."
  (cdr (assoc 'dark?
              (lookup-palette palette-sym))))

(define (get-emacs-theme palette-sym)
  "Return the Emacs theme a palette wants loaded.
The value is the Lisp form the palette declares for @code{load-theme}, such as
@code{'ef-day}."
  (cdr (assoc 'emacs-theme
              (lookup-palette palette-sym))))

(define (get-btop-theme palette-sym)
  "Return the btop colour theme a palette declares.
The value is the quoted theme name btop expects in its configuration file."
  (cdr (assoc 'btop-theme
              (lookup-palette palette-sym))))

(define (get-lambdock-theme palette-sym)
  "Return the lambdock theme a palette declares."
  (cdr (assoc 'lambdock-theme
              (lookup-palette palette-sym))))

(define (get-gtk-accent-color palette-sym)
  "Return the GTK accent colour a palette declares.
A palette names its accent as a bare symbol, while dconf stores a quoted
keyword, so this is where the quotes are added.  The same symbol picks the
palette's icon theme, via @code{get-icon-theme}."
  (format #f "'~a'"
          (cdr (assoc 'gtk-accent
                      (lookup-palette palette-sym)))))

(define (get-ansi-color palette-sym)
  "Return the terminal escape sequence for a palette's ANSI colour.
The palette names one colour from the small ANSI set; this maps that name to
the escape sequence used when colouring terminal output."
  (let* ((palette (lookup-palette palette-sym))
         (color-sym (cdr (assoc 'ansi-color palette))))
    (assoc-ref ansi-color-escapes color-sym)))

(define (get-gtk-theme palette-sym)
  "Return the GTK theme name a palette declares."
  (cdr (assoc 'gtk-theme
              (lookup-palette palette-sym))))

(define (get-icon-theme palette-sym)
  "Return the icon theme a palette wears.
Derived from the palette instead of declared by it: @code{gtk-accent} picks the
Skeu Icons enamel and @code{dark?} picks its light-ink sibling, so the icons
always match the accent the rest of the desktop is asked for."
  (skeu-icon-theme (cdr (assoc 'gtk-accent
                               (lookup-palette palette-sym)))
                   (is-dark-palette palette-sym)))

(define (get-cursor-theme palette-sym)
  "Return the cursor theme name a palette declares."
  (cdr (assoc 'cursor-theme
              (lookup-palette palette-sym))))

(define (get-cursor-size palette-sym)
  "Return the cursor size used with a palette.
Every palette uses the same size, so @var{palette-sym} is accepted and ignored;
the argument is kept so that all palette getters can be called alike."
  "32")

;; --- App Opacities ---
;;
;; Opacity is a palette property, not an application default: a theme that wants
;; more of the wallpaper to show through lowers these fractions, and every app
;; follows.  Each value is the alpha of that app's main background, so 1 means
;; fully opaque and 0 fully transparent.

(define (get-wezterm-opacity palette-sym)
  "Return the WezTerm window background opacity a palette declares.
The value is a 0-1 fraction used for @code{window_background_opacity}; the
Golden Gate pair asks for a lower value so the compositor blur shows through."
  (cdr (assoc 'wezterm-opacity
              (lookup-palette palette-sym))))

(define (get-rofi-opacity palette-sym)
  "Return the Rofi window background opacity a palette declares.
The value is a 0-1 fraction applied to the launcher panel behind the spotlight
results."
  (cdr (assoc 'rofi-opacity
              (lookup-palette palette-sym))))

(define (get-waybar-opacity palette-sym)
  "Return the Waybar bar background opacity a palette declares.
The value is a 0-1 fraction applied to the floating bar's own background."
  (cdr (assoc 'waybar-opacity
              (lookup-palette palette-sym))))

(define (get-mako-opacity palette-sym)
  "Return the Mako notification background opacity a palette declares.
The value is a 0-1 fraction rendered as the alpha half of the banner's
@code{#RRGGBBAA} background."
  (cdr (assoc 'mako-opacity
              (lookup-palette palette-sym))))
