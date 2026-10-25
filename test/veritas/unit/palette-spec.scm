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

;;; Commentary:
;;
;; Unit tests for (heks-linux palette): the registry that every other module
;; reads colours, GTK themes, icon themes and dock themes from.
;;
;; The suite walks every registered palette, so adding a palette automatically
;; extends the coverage instead of silently shipping an untested colourset.

;;; Code:

(define-module (veritas unit palette-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux palette)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (hex-colour? value)
  "Whether @var{value} looks like a @code{#rrggbb} colour string."
  (and (string? value)
       (>= (string-length value) 7)
       (char=? #\# (string-ref value 0))))

(define (palette-is-complete? name)
  "Whether every colour and theme key resolves for palette @var{name}."
  (every (lambda (key)
           (let ((value (get-color name key)))
             (or (hex-colour? value) (string? value))))
         '(primary primary-l text text-l background background-l)
         ))

(define (opacity? value)
  "Whether @var{value} is a usable 0-1 opacity fraction."
  (and (number? value) (<= 0 value 1)))

(define (palette-icon-accent name)
  "The accent symbol behind @var{name}'s icon theme.
@code{get-gtk-accent-color} returns the quoted keyword dconf stores, so the
quotes are stripped here before the accent is handed to @code{skeu-icon-theme}."
  (let ((quoted (get-gtk-accent-color name)))
    (string->symbol (substring quoted 1 (1- (string-length quoted))))))

;; The palette getters that expose a per-app background opacity.
(define opacity-getters
  (list get-wezterm-opacity
        get-rofi-opacity
        get-waybar-opacity
        get-mako-opacity))

(define (non-golden-gate-palettes)
  "Every registered palette except the Golden Gate pair."
  (remove (lambda (name)
            (memq name '(golden-gate-light golden-gate-dark)))
          (palette-names)))

(define palette-suite
  (suite "Palette Registry Suite"
         (test "Registry Is Non Empty And Symbolic"
               (assert-true (> (length (palette-names)) 0)
                            #:name "At least one palette should be registered")
               (assert-true (every symbol? (palette-names))
                            #:name "Every palette name should be a symbol")
               (assert-true (every string? (map symbol->string
                                                (palette-names)))
                            #:name "Every palette name should be convertible to a string"))

         (test "Every Palette Exposes A Full Colour Set"
               (assert-true (every palette-is-complete? (palette-names))
                            #:name
                            "Each palette must define primary/text/background colours"))

         (test "Every Palette Exposes Its Downstream Themes"
               (assert-true (every (lambda (name)
                                     (and (string? (get-gtk-theme name))
                                          (string? (get-icon-theme name))
                                          (string? (get-cursor-theme name))
                                          (string? (get-gtk-accent-color name))))
                                   (palette-names))
                            #:name
                            "Each palette must map to a GTK, icon, cursor and accent theme")
               ;; NOTE: `every' returns the predicate's last value, which for
               ;; `memq' is a list - and `assert-true' compares with `eq?'
               ;; against #t, so the result has to be normalised first.
               (assert-true (not (not (every (lambda (name)
                                               (memq (get-lambdock-theme name)
                                                     '(vanilla vanilla-light
                                                              snow-leopard
                                                              solarized-light
                                                              nature unity none)))
                                             (palette-names))))
                #:name
                "Each palette must map to a supported lambdock theme"))

         (test "Every Palette Wears A Skeu Icons Theme"
               (assert-true (not (not (every (lambda (name)
                                               (string-prefix? "skeu-icons-"
                                                               (get-icon-theme
                                                                name)))
                                             (palette-names))))
                            #:name
                            "Every icon theme should come from the Skeu Icons pack")
               (assert-true (not (not (every (lambda (name)
                                               (string-suffix?
                                                (if (is-dark-palette name)
                                                    "-dark" "")
                                                (get-icon-theme name)))
                                             (palette-names))))
                            #:name
                            "A dark palette should ask for the light-ink variant and a light one for the plain variant")
               ;; NOTE: the accent comes back out of `get-gtk-accent-color',
               ;; the same procedure dconf is fed from, so the icons cannot
               ;; follow one accent while GTK is told another.
               (assert-true (not (not (every (lambda (name)
                                               (string=?
                                                (get-icon-theme name)
                                                (skeu-icon-theme
                                                 (palette-icon-accent name)
                                                 (is-dark-palette name))))
                                             (palette-names))))
                            #:name
                            "The icon theme should follow the palette's own accent")
               (assert-equal #:expect "skeu-icons-green"
                             #:got (skeu-icon-theme 'green #f)
                             #:name "A light palette should take the bare accent theme")
               (assert-equal #:expect "skeu-icons-violet-dark"
                             #:got (skeu-icon-theme 'purple #t)
                             #:name
                             "GTK's purple accent should map to the violet enamel"))

         (test "Every Palette Exposes App Opacities"
               (assert-true (every (lambda (name)
                                     (every (lambda (getter)
                                              (opacity? (getter name)))
                                            opacity-getters))
                                   (palette-names))
                            #:name
                            "Each palette must declare a 0-1 opacity for every app"))

         (test "Golden Gate Is More Transparent"
               (assert-true (every (lambda (getter)
                                     (and (< (getter 'golden-gate-light)
                                             (apply min
                                                    (map getter
                                                         (non-golden-gate-palettes))))
                                          (< (getter 'golden-gate-dark)
                                             (apply min
                                                    (map getter
                                                         (non-golden-gate-palettes))))))
                                   opacity-getters)
                            #:name
                            "Both Golden Gate variants must be more transparent than every other palette"))

         (test "Dark And Light Classification"
               (assert-true (is-dark-palette 'catppuccin-mocha)
                            #:name "catppuccin-mocha should be a dark palette")
               (assert-true (not (is-dark-palette 'catppuccin-latte))
                            #:name "catppuccin-latte should be a light palette"))

         (test "Unknown Palettes Are Rejected"
               (assert-error (lambda () (get-color 'definitely-not-a-palette
                                                   'primary))
                             #:name
                             "Looking up an unregistered palette should raise"))

         (test "Colour Converters"
               (assert-equal #:expect "rgba(255, 0, 0, 1)"
                             #:got (hex-to-rgba "#ff0000")
                             #:name "hex-to-rgba should convert a hex colour")
               (assert-equal #:expect "rgba(0, 0, 255, 0.5)"
                             #:got (hex-to-rgba "#0000ff" #:alpha 0.5)
                             #:name "hex-to-rgba should honour the alpha argument")
               (assert-equal #:expect "rgb(0, 255, 0)"
                             #:got (hex-to-rgb "#00ff00")
                             #:name "hex-to-rgb should convert a hex colour")
               (assert-equal #:expect "rgba(0, 0, 0, 1)"
                             #:got (hex-to-rgba "not-a-colour")
                             #:name "hex-to-rgba should fall back on bad input"))))

(define (spec)
  (veritas-run palette-suite))
