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
                                            get-cursor-theme
                                            ansi-color-escapes
                                            get-ansi-color
                                            hex-to-decimal
                                            hex-to-rgba
                                            everforest-light
                                            everforest-dark
                                            kaolin-dark
                                            heavy-metal
                                            solarized-light
                                            ef-autumn
                                            ef-cyprus
                                            ef-bio
                                            ef-dream
                                            ef-melissa-light
                                            dracula
                                            gruvbox-dark
                                            gruvbox-light
                                            catppuccin-mocha
                                            catppuccin-latte))

(define (raise-unknown-palette-exception palette)
  (raise-exception (make-exception-with-message (format #f
                                                 "exception ocurred! unknown palette selected: ~a"
                                                 palette))))

(define-syntax-rule (get-color palette sym)
  (match palette
    ('catppuccin-latte (cdr (assoc sym catppuccin-latte)))
    ('catppuccin-mocha (cdr (assoc sym catppuccin-mocha)))
    ('dracula (cdr (assoc sym dracula)))
    ('ef-autumn (cdr (assoc sym ef-autumn)))
    ('ef-bio (cdr (assoc sym ef-bio)))
    ('ef-cyprus (cdr (assoc sym ef-cyprus)))
    ('ef-dream (cdr (assoc sym ef-dream)))
    ('ef-melissa-light (cdr (assoc sym ef-melissa-light)))
    ('everforest-dark (cdr (assoc sym everforest-dark)))
    ('everforest-light (cdr (assoc sym everforest-light)))
    ('gruvbox-dark (cdr (assoc sym gruvbox-dark)))
    ('gruvbox-light (cdr (assoc sym gruvbox-light)))
    ('heavy-metal (cdr (assoc sym heavy-metal)))
    ('kaolin-dark (cdr (assoc sym kaolin-dark)))
    ('modus-vivendi (cdr (assoc sym modus-vivendi)))
    ('solarized-light (cdr (assoc sym solarized-light)))
    (_ (raise-unknown-palette-exception palette))))

(define-syntax-rule (get-gtk-theme palette)
  "Adwaita")

(define-syntax-rule (is-dark-palette palette)
  (match palette
    ('catppuccin-latte #f)
    ('catppuccin-mocha #t)
    ('dracula #t)
    ('ef-autumn #t)
    ('ef-bio #t)
    ('ef-cyprus #f)
    ('ef-dream #t)
    ('ef-melissa-light #f)
    ('everforest-dark #t)
    ('everforest-light #f)
    ('gruvbox-dark #t)
    ('gruvbox-light #f)
    ('heavy-metal #t)
    ('kaolin-dark #t)
    ('modus-vivendi #t)
    ('solarized-light #f)
    (_ (raise-unknown-palette-exception palette))))

(define-syntax-rule (get-icon-theme palette)
  "Adwaita")

(define-syntax-rule (get-emacs-theme palette)
  (match palette
    ('catppuccin-latte "'catppuccin-latte")
    ('catppuccin-mocha "'catppuccin-mocha")
    ('dracula "'dracula")
    ('ef-autumn "'ef-autumn")
    ('ef-bio "'ef-bio")
    ('ef-cyprus "'ef-cyprus")
    ('ef-dream "'ef-dream")
    ('ef-melissa-light "'ef-melissa-light")
    ('everforest-dark "'everforest-hard-dark")
    ('everforest-light "'everforest-hard-light")
    ('gruvbox-dark "'gruvbox-dark-hard")
    ('gruvbox-light "'gruvbox-light-hard")
    ('heavy-metal "'ef-tritanopia-dark")
    ('kaolin-dark "'kaolin-dark")
    ('modus-vivendi "'modus-vivendi")
    ('solarized-light "'solarized-light")
    (_ (raise-unknown-palette-exception palette))))

(define-syntax-rule (get-gtk-accent-color palette)
  (match palette
    ('catppuccin-latte "'yellow'")
    ('catppuccin-mocha "'pink'")
    ('dracula "'pink'")
    ('ef-autumn "'orange'")
    ('ef-bio "'green'")
    ('ef-cyprus "'green'")
    ('ef-dream "'purple'")
    ('ef-melissa-light "'yellow'")
    ('everforest-dark "'green'")
    ('everforest-light "'green'")
    ('gruvbox-dark "'orange'")
    ('gruvbox-light "'orange'")
    ('heavy-metal "'red'")
    ('kaolin-dark "'green'")
    ('modus-vivendi "'purple'")
    ('solarized-light "'pink'")
    (_ (raise-unknown-palette-exception palette))))

(define-syntax-rule (get-cursor-theme palette)
  "Adwaita")

(define-syntax-rule (get-ansi-color palette)
  (match palette
    ('modus-vivendi (assoc ansi-color-escapes
                           'magenta))
    ('ef-melissa-light (assoc-ref ansi-color-escapes
                                  'yellow))
    ('ef-bio (assoc-ref ansi-color-escapes
                        'green))
    ('ef-dream (assoc-ref ansi-color-escapes
                          'magenta))
    ('heavy-metal (assoc-ref ansi-color-escapes
                             'red))
    ('ef-cyprus (assoc-ref ansi-color-escapes
                           'green))
    ('ef-autumn (assoc-ref ansi-color-escapes
                           'yellow))
    ('solarized-light (assoc-ref ansi-color-escapes
                                 'default))
    ('everforest-light (assoc-ref ansi-color-escapes
                                  'default))
    ('everforest-dark (assoc-ref ansi-color-escapes
                                 'green))
    ('gruvbox-light (assoc-ref ansi-color-escapes
                               'default))
    ('gruvbox-dark (assoc-ref ansi-color-escapes
                              'yellow))
    ('dracula (assoc-ref ansi-color-escapes
                         'magenta))
    ('catppuccin-latte (assoc-ref ansi-color-escapes
                                  'magenta))
    ('catppuccin-mocha (assoc-ref ansi-color-escapes
                                  'magenta))
    ('kaolin-dark (assoc-ref ansi-color-escapes
                             'green))
    (_ (raise-unknown-palette-exception palette))))

(define-syntax-rule (hex-to-decimal n)
  (string->number (string-append "#x" n)))

(define* (hex-to-rgba hex
                      #:key (alpha 1))
  (let* ((digits (string-drop hex 1))
         (red (hex-to-decimal (string-take digits 2)))
         (green (hex-to-decimal (string-take (string-drop digits 2) 2)))
         (blue (hex-to-decimal (string-drop digits 4))))
    (format #f
            "rgba(~a, ~a, ~a, ~a)"
            red
            green
            blue
            alpha)))

(define ansi-color-escapes
  `((yellow . "\x1b[0;33m") (magenta . "\x1b[0;35m")
    (green . "\x1b[0;32m")
    (default . "\x1b[0;39m")
    (red . "\x1b[0;31m")
    (blue . "\x1b[0;34m")
    (cyan . "\x1b[0;36m")
    (reset . "\x1b[0m")))

(define ef-melissa-light
  `((primary . "#efbf00") (primary-l . "#ba5205")
    (text . "#484431")
    (text-l . "#585542")
    (background . "#fff6d8")
    (background-l . "#f5e9cb")))

(define ef-dream
  `((primary . "#675072") (primary-l . "#b0a0cf")
    (text . "#efd5c5")
    (text-l . "#dec4b4")
    (background . "#232025")
    (background-l . "#322f34")))

(define ef-bio
  `((primary . "#00552f") (primary-l . "#3fb83f")
    (text . "#dfefe6")
    (text-l . "#cfdfd5")
    (background . "#111111")
    (background-l . "#222522")))

(define ef-cyprus
  `((primary . "#b3d19d") (primary-l . "#c4f2af")
    (text . "#242521")
    (text-l . "#353632")
    (background . "#fcf7ef")
    (background-l . "#f0ece0")))

(define ef-autumn
  `((primary . "#7a3b23") (primary-l . "#c0620e")
    (text . "#dfcdcb")
    (text-l . "#cfbcba")
    (background . "#26211d")
    (background-l . "#36322f")))

(define solarized-light
  `((primary . "#f9a25a") (primary-l . "#e89149")
    (text . "#142a31")
    (text-l . "#253b42")
    (background . "#fdf6e3")
    (background-l . "#eee8d5")))

(define heavy-metal
  `((primary . "#b02930") (primary-l . "#f47360")
    (text . "#ffe6d6")
    (text-l . "#efd5c5")
    (background . "#111111")
    (background-l . "#222522")))

(define everforest-dark
  `((primary . "#a7c080") (primary-l . "#b8d191")
    (text . "#d3c6aa")
    (text-l . "#e4d7bb")
    (background . "#272e33")
    (background-l . "#1e2326")))

(define everforest-light
  `((primary . "#a7c080") (primary-l . "#b8d191")
    (text . "#272e33")
    (text-l . "#383f44")
    (background . "#fffbef")
    (background-l . "#eeeade")))

(define gruvbox-dark
  `((primary . "#fe8019") (primary-l . "#d65d0e")
    (text . "#ebdbb2")
    (text-l . "#fbf1c7")
    (background . "#1d2021")
    (background-l . "#282828")))

(define gruvbox-light
  `((primary . "#d65d0e") (primary-l . "#d75f00")
    (text . "#1d2021")
    (text-l . "#282828")
    (background . "#ebdbb2")
    (background-l . "#fbf1c7")))

(define dracula
  `((primary . "#bd93f9") (primary-l . "#ff79c6")
    (text . "#f8f8f2")
    (text-l . "#e7e8e1")
    (background . "#282a36")
    (background-l . "#44475a")))

(define catppuccin-latte
  `((primary . "#df8e1d") (primary-l . "#dc8a78")
    (text . "#4c4f69")
    (text-l . "#5c5f77")
    (background . "#eff1f5")
    (background-l . "#e6e9ef")))

(define catppuccin-mocha
  `((primary . "#cba6f7") (primary-l . "#f5c2e7")
    (text . "#cdd6f4")
    (text-l . "#bac2de")
    (background . "#1e1e2e")
    (background-l . "#181825")))

(define modus-vivendi
  `((primary . "#feacd0") (primary-l . "#caa6df")
    (text . "#ffffff")
    (text-l . "#989898")
    (background . "#000000")
    (background-l . "#1e1e1e")))

(define kaolin-dark
  `((primary . "#80bcb6") (primary-l . "#4d9391")
    (text . "#e6e6e8")
    (text-l . "#f2f2f2")
    (background . "#18181B")
    (background-l . "#222225")))
