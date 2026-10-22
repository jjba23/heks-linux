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
                                            get-icon-theme
                                            get-emacs-theme
                                            get-btop-theme
                                            get-lambdock-theme
                                            get-cursor-theme
                                            get-cursor-size
                                            ansi-color-escapes
                                            get-ansi-color
                                            hex-to-decimal
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

;; --- Palette Definitions ---

(define ef-day
  `((dark? . #f) (emacs-theme . "'ef-day")
    (cursor-theme . "WhiteSur-cursors")
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-orange")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'cyan'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-orange")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . "'yellow'")
    (lambdock-theme . solarized-light)
    (icon-theme . "WhiteSur-orange")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'purple'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-purple-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'green'")
    (lambdock-theme . nature)
    (icon-theme . "WhiteSur-green-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . "'green'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-green")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dusklight\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . unity)
    (icon-theme . "WhiteSur-orange")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . solarized-light)
    (icon-theme . "WhiteSur-orange")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"monokai\"")
    (gtk-accent . "'red'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-red-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-dark-medium\"")
    (gtk-accent . "'green'")
    (lambdock-theme . nature)
    (icon-theme . "WhiteSur-green-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . "'green'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-green")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"gruvbox_dark_v2\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-orange-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"gruvbox_light\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . solarized-light)
    (icon-theme . "WhiteSur-orange")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-purple-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'yellow'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-purple")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-purple-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-pink-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'purple'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-pink")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'purple'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-pink-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'purple'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-pink")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-pink-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-pink")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-pink-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-pink")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"matcha-dark-sea\"")
    (gtk-accent . "'green'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-green-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-purple-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"gruvbox_dark_v2\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-orange-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'purple'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-purple-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"gruvbox_light_v2\"")
    (gtk-accent . "'purple'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-purple")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-dark\"")
    (gtk-accent . "'blue'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"nord\"")
    (gtk-accent . "'blue'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"tokyo-night\"")
    (gtk-accent . "'purple'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-purple-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-pink-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'pink'")
    (lambdock-theme . solarized-light)
    (icon-theme . "WhiteSur-pink")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . "'blue'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-orange-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-orange-dark")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'orange'")
    (lambdock-theme . vanilla-light)
    (icon-theme . "WhiteSur-orange")
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
;; WhiteSur installs its blue variant under the bare names `WhiteSur' (light)
;; and `WhiteSur-dark'; there is no `WhiteSur-blue' theme, so the blue names
;; below must stay unprefixed or the icons silently fall back to the generic set.
(define golden-gate-light
  `((dark? . #f) (emacs-theme . "'modus-operandi")
    (cursor-theme . "WhiteSur-cursors")
    (gtk-theme . "Adwaita")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'blue'")
    (lambdock-theme . snow-leopard)
    (icon-theme . "WhiteSur")
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
    (gtk-theme . "Adwaita")
    (btop-theme . "\"default\"")
    (gtk-accent . "'blue'")
    (lambdock-theme . vanilla)
    (icon-theme . "WhiteSur-dark")
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
The value is a quoted GTK colour keyword, as the dconf accent setting expects."
  (cdr (assoc 'gtk-accent
              (lookup-palette palette-sym))))

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
  "Return the icon theme name a palette declares."
  (cdr (assoc 'icon-theme
              (lookup-palette palette-sym))))

(define (get-cursor-theme palette-sym)
  "Return the cursor theme name a palette declares."
  (cdr (assoc 'cursor-theme
              (lookup-palette palette-sym))))

(define (get-cursor-size palette-sym)
  "Return the cursor size used with a palette.
Every palette uses the same size, so @var{palette-sym} is accepted and ignored;
the argument is kept so that all palette getters can be called alike."
  "32")
