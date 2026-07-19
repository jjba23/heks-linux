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
                                            get-cursor-theme
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
                                            kanagawa))

;; --- Core Utilities & Constants ---

(define (raise-unknown-palette-exception palette)
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

;; --- Palette Definitions ---

(define ef-day
  `((dark? . #f) (emacs-theme . "'ef-day")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . "'orange'")
    (ansi-color . default)
    (primary . "#c06000")
    (primary-l . "#da7800")
    (text . "#3b3b3b")
    (text-l . "#4c4c4c")
    (background . "#fefcf4")
    (background-l . "#f4f0e0")))

(define ef-kassio
  `((dark? . #f) (emacs-theme . "'ef-kassio")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'cyan'")
    (ansi-color . cyan)
    (primary . "#007a9a")
    (primary-l . "#0096bc")
    (text . "#203235")
    (text-l . "#32484c")
    (background . "#f4f9fa")
    (background-l . "#e5eff1")))

(define ef-melissa-light
  `((dark? . #f) (emacs-theme . "'ef-melissa-light")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . "'yellow'")
    (ansi-color . yellow)
    (primary . "#efbf00")
    (primary-l . "#ba5205")
    (text . "#484431")
    (text-l . "#585542")
    (background . "#fff6d8")
    (background-l . "#f5e9cb")))

(define ef-dream
  `((dark? . #t) (emacs-theme . "'ef-dream")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'purple'")
    (ansi-color . magenta)
    (primary . "#675072")
    (primary-l . "#b0a0cf")
    (text . "#efd5c5")
    (text-l . "#dec4b4")
    (background . "#232025")
    (background-l . "#322f34")))

(define ef-bio
  `((dark? . #t) (emacs-theme . "'ef-bio")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'green'")
    (ansi-color . green)
    (primary . "#00552f")
    (primary-l . "#3fb83f")
    (text . "#dfefe6")
    (text-l . "#cfdfd5")
    (background . "#111111")
    (background-l . "#222522")))

(define ef-cyprus
  `((dark? . #f) (emacs-theme . "'ef-cyprus")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . "'green'")
    (ansi-color . green)
    (primary . "#b3d19d")
    (primary-l . "#c4f2af")
    (text . "#242521")
    (text-l . "#353632")
    (background . "#fcf7ef")
    (background-l . "#f0ece0")))

(define ef-autumn
  `((dark? . #t) (emacs-theme . "'ef-autumn")
    (btop-theme . "\"dusklight\"")
    (gtk-accent . "'orange'")
    (ansi-color . yellow)
    (primary . "#7a3b23")
    (primary-l . "#c0620e")
    (text . "#dfcdcb")
    (text-l . "#cfbcba")
    (background . "#26211d")
    (background-l . "#36322f")))

(define solarized-light
  `((dark? . #f) (emacs-theme . "'solarized-light")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'pink'")
    (ansi-color . default)
    (primary . "#f9a25a")
    (primary-l . "#e89149")
    (text . "#142a31")
    (text-l . "#253b42")
    (background . "#fdf6e3")
    (background-l . "#eee8d5")))

(define heavy-metal
  `((dark? . #t) (emacs-theme . "'ef-tritanopia-dark")
    (btop-theme . "\"monokai\"")
    (gtk-accent . "'red'")
    (ansi-color . red)
    (primary . "#b02930")
    (primary-l . "#f47360")
    (text . "#ffe6d6")
    (text-l . "#efd5c5")
    (background . "#111111")
    (background-l . "#222522")))

(define everforest-dark
  `((dark? . #t) (emacs-theme . "'everforest-hard-dark")
    (btop-theme . "\"everforest-dark-medium\"")
    (gtk-accent . "'green'")
    (ansi-color . green)
    (primary . "#a7c080")
    (primary-l . "#b8d191")
    (text . "#d3c6aa")
    (text-l . "#e4d7bb")
    (background . "#272e33")
    (background-l . "#1e2326")))

(define everforest-light
  `((dark? . #f) (emacs-theme . "'everforest-hard-light")
    (btop-theme . "\"everforest-light-medium\"")
    (gtk-accent . "'green'")
    (ansi-color . default)
    (primary . "#a7c080")
    (primary-l . "#b8d191")
    (text . "#272e33")
    (text-l . "#383f44")
    (background . "#fffbef")
    (background-l . "#eeeade")))

(define gruvbox-dark
  `((dark? . #t) (emacs-theme . "'gruvbox-dark-hard")
    (btop-theme . "\"gruvbox_dark_v2\"")
    (gtk-accent . "'orange'")
    (ansi-color . yellow)
    (primary . "#fe8019")
    (primary-l . "#d65d0e")
    (text . "#ebdbb2")
    (text-l . "#fbf1c7")
    (background . "#1d2021")
    (background-l . "#282828")))

(define gruvbox-light
  `((dark? . #f) (emacs-theme . "'gruvbox-light-hard")
    (btop-theme . "\"gruvbox_light\"")
    (gtk-accent . "'orange'")
    (ansi-color . default)
    (primary . "#d65d0e")
    (primary-l . "#d75f00")
    (text . "#1d2021")
    (text-l . "#282828")
    (background . "#ebdbb2")
    (background-l . "#fbf1c7")))

(define dracula
  `((dark? . #t) (emacs-theme . "'dracula")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'pink'")
    (ansi-color . magenta)
    (primary . "#bd93f9")
    (primary-l . "#ff79c6")
    (text . "#f8f8f2")
    (text-l . "#e7e8e1")
    (background . "#282a36")
    (background-l . "#44475a")))

(define catppuccin-latte
  `((dark? . #f) (emacs-theme . "'catppuccin-latte")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'yellow'")
    (ansi-color . magenta)
    (primary . "#8839ef")
    (primary-l . "#ea76cb")
    (text . "#4c4f69")
    (text-l . "#5c5f77")
    (background . "#eff1f5")
    (background-l . "#e6e9ef")))

(define catppuccin-mocha
  `((dark? . #t) (emacs-theme . "'catppuccin-mocha")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'pink'")
    (ansi-color . magenta)
    (primary . "#cba6f7")
    (primary-l . "#f5c2e7")
    (text . "#cdd6f4")
    (text-l . "#bac2de")
    (background . "#1e1e2e")
    (background-l . "#181825")))

(define modus-vivendi
  `((dark? . #t) (emacs-theme . "'modus-vivendi")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'purple'")
    (ansi-color . magenta)
    (primary . "#feacd0")
    (primary-l . "#caa6df")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#000000")
    (background-l . "#1e1e1e")))

(define modus-operandi
  `((dark? . #f) (emacs-theme . "'modus-operandi")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'purple'")
    (ansi-color . magenta)
    (primary . "#feacd0")
    (primary-l . "#caa6df")
    (text . "#000000")
    (text-l . "#1e1e1e")
    (background . "#ffffff")
    (background-l . "#cbcbcb")))

(define modus-vivendi-tinted
  `((dark? . #t) (emacs-theme . "'modus-vivendi-tinted")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'purple'")
    (ansi-color . magenta)
    (primary . "#feacd0")
    (primary-l . "#caa6df")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#1d2021")
    (background-l . "#282a2b")))

(define modus-operandi-tinted
  `((dark? . #f) (emacs-theme . "'modus-operandi-tinted")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'purple'")
    (ansi-color . magenta)
    (primary . "#feacd0")
    (primary-l . "#caa6df")
    (text . "#000000")
    (text-l . "#1e1e1e")
    (background . "#fbf7ee")
    (background-l . "#f3ede2")))

(define modus-vivendi-deuteranopia
  `((dark? . #t) (emacs-theme . "'modus-vivendi-deuteranopia")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'blue'")
    (ansi-color . blue)
    (primary . "#6495ed")
    (primary-l . "#79a8ff")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#000000")
    (background-l . "#1e1e1e")))

(define modus-operandi-deuteranopia
  `((dark? . #f) (emacs-theme . "'modus-operandi-deuteranopia")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'blue'")
    (ansi-color . blue)
    (primary . "#0031a9")
    (primary-l . "#2544bb")
    (text . "#000000")
    (text-l . "#1e1e1e")
    (background . "#ffffff")
    (background-l . "#cbcbcb")))

(define modus-vivendi-tritanopia
  `((dark? . #t) (emacs-theme . "'modus-vivendi-tritanopia")
    (btop-theme . "\"Default\"")
    (gtk-accent . "'cyan'")
    (ansi-color . cyan)
    (primary . "#00bcff")
    (primary-l . "#54d5ff")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#000000")
    (background-l . "#1e1e1e")))

(define modus-operandi-tritanopia
  `((dark? . #f) (emacs-theme . "'modus-operandi-tritanopia")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'cyan'")
    (ansi-color . cyan)
    (primary . "#005f88")
    (primary-l . "#007ea7")
    (text . "#000000")
    (text-l . "#1e1e1e")
    (background . "#ffffff")
    (background-l . "#cbcbcb")))

(define kaolin-dark
  `((dark? . #t) (emacs-theme . "'kaolin-dark")
    (btop-theme . "\"matcha-dark-sea\"")
    (gtk-accent . "'green'")
    (ansi-color . green)
    (primary . "#80bcb6")
    (primary-l . "#4d9391")
    (text . "#e6e6e8")
    (text-l . "#f2f2f2")
    (background . "#18181B")
    (background-l . "#222225")))

(define doom-tomorrow-night
  `((dark? . #t) (emacs-theme . "'doom-tomorrow-night")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'orange'")
    (ansi-color . magenta)
    (primary . "#de935f")
    (primary-l . "#dd9955")
    (text . "#c5c8c6")
    (text-l . "#c5c5c5")
    (background . "#1d1f21")
    (background-l . "#161719")))

(define doom-molokai
  `((dark? . #t) (emacs-theme . "'doom-molokai")
    (btop-theme . "\"gruvbox_dark_v2\"")
    (gtk-accent . "'orange'")
    (ansi-color . yellow)
    (primary . "#fd971f")
    (primary-l . "#dd9955")
    (text . "#dfdfdf")
    (text-l . "#d6d6d4")
    (background . "#1c1e1f")
    (background-l . "#222323")))

(define doom-one
  `((dark? . #t) (emacs-theme . "'doom-one")
    (btop-theme . "\"dracula\"")
    (gtk-accent . "'purple'")
    (ansi-color . magenta)
    (primary . "#c678dd")
    (primary-l . "#a9a1e1")
    (text . "#dfdfdf")
    (text-l . "#bfbfbf")
    (background . "#282c34")
    (background-l . "#21242b")))

(define doom-one-light
  `((dark? . #f) (emacs-theme . "'doom-one-light")
    (btop-theme . "\"gruvbox_light_v2\"")
    (gtk-accent . "'purple'")
    (ansi-color . magenta)
    (primary . "#b751b6")
    (primary-l . "#a626a4")
    (text . "#383a42")
    (text-l . "#424242")
    (background . "#fafafa")
    (background-l . "#f0f0f0")))

(define solarized-dark
  `((dark? . #t) (emacs-theme . "'solarized-dark")
    (btop-theme . "\"solarized-dark\"")
    (gtk-accent . "'blue'")
    (ansi-color . blue)
    (primary . "#268bd2")
    (primary-l . "#2aa198")
    (text . "#839496")
    (text-l . "#93a1a1")
    (background . "#002b36")
    (background-l . "#073642")))

(define nord
  `((dark? . #t) (emacs-theme . "'nord")
    (btop-theme . "\"nord\"")
    (gtk-accent . "'blue'")
    (ansi-color . cyan)
    (primary . "#88c0d0")
    (primary-l . "#81a1c1")
    (text . "#eceff4")
    (text-l . "#d8dee9")
    (background . "#2e3440")
    (background-l . "#3b4252")))

(define tokyo-night
  `((dark? . #t) (emacs-theme . "'tokyo-night")
    (btop-theme . "\"tokyo-night\"")
    (gtk-accent . "'blue'")
    (ansi-color . blue)
    (primary . "#7aa2f7")
    (primary-l . "#bb9af7")
    (text . "#c0caf5")
    (text-l . "#a9b1d6")
    (background . "#1a1b26")
    (background-l . "#24283b")))

(define rose-pine-moon
  `((dark? . #t) (emacs-theme . "'rose-pine-moon")
    (btop-theme . "\"default\"")
    (gtk-accent . "'pink'")
    (ansi-color . magenta)
    (primary . "#ea9a97")
    (primary-l . "#c4a7e7")
    (text . "#e0def4")
    (text-l . "#908caa")
    (background . "#232136")
    (background-l . "#2a283e")))

(define rose-pine-dawn
  `((dark? . #f) (emacs-theme . "'rose-pine-dawn")
    (btop-theme . "\"solarized-light\"")
    (gtk-accent . "'pink'")
    (ansi-color . magenta)
    (primary . "#d7827e")
    (primary-l . "#907aa9")
    (text . "#575279")
    (text-l . "#797593")
    (background . "#faf4ed")
    (background-l . "#fffaf3")))

(define kanagawa
  `((dark? . #t) (emacs-theme . "'kanagawa")
    (btop-theme . "\"default\"")
    (gtk-accent . "'blue'")
    (ansi-color . blue)
    (primary . "#7e9cd8")
    (primary-l . "#a3b8ef")
    (text . "#dcd7ba")
    (text-l . "#c8c093")
    (background . "#1f1f28")
    (background-l . "#2a2a37")))

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
    (kanagawa unquote kanagawa)))

(define (lookup-palette palette-sym)
  (let ((res (assoc-ref palette-registry palette-sym)))
    (if res res
        (raise-unknown-palette-exception palette-sym))))

;; --- Functional Engine / Getters ---

(define (get-color palette-sym sym)
  (cdr (assoc sym
              (lookup-palette palette-sym))))

(define (is-dark-palette palette-sym)
  (cdr (assoc 'dark?
              (lookup-palette palette-sym))))

(define (get-emacs-theme palette-sym)
  (cdr (assoc 'emacs-theme
              (lookup-palette palette-sym))))

(define (get-btop-theme palette-sym)
  (cdr (assoc 'btop-theme
              (lookup-palette palette-sym))))

(define (get-gtk-accent-color palette-sym)
  (cdr (assoc 'gtk-accent
              (lookup-palette palette-sym))))

(define (get-ansi-color palette-sym)
  (let* ((palette (lookup-palette palette-sym))
         (color-sym (cdr (assoc 'ansi-color palette))))
    (assoc-ref ansi-color-escapes color-sym)))

;; Statically resolved system-wide defaults
(define (get-gtk-theme palette-sym)
  "Adwaita")

(define (get-icon-theme palette-sym)
  "Adwaita")

(define (get-cursor-theme palette-sym)
  "Adwaita")
