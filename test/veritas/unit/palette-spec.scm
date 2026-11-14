;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

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
  #:use-module (heks-linux icons)
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
         '(primary primary-l text text-l background background-l)))

(define (opacity? value)
  "Whether @var{value} is a usable 0-1 opacity fraction."
  (and (number? value) (<= 0 value 1)))

(define (palette-icon-accent name)
  "The accent symbol behind @var{name}'s icon theme.
@code{get-gtk-accent-color} returns the quoted keyword dconf stores, so the
quotes are stripped here before the accent is handed to @code{tela-icon-theme}."
  (let ((quoted (get-gtk-accent-color name)))
    (string->symbol (substring quoted 1 (1- (string-length quoted))))))

;; The palette getters that expose an app's own background opacity.  The bar is
;; whelk's; the terminal is WezTerm's.
(define opacity-getters
  (list get-wezterm-opacity
        get-whelk-opacity))

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
                                            lambdock-theme-names))
                                    (palette-names))))
        #:name
        "Each palette must map to a supported lambdock theme"))

    (test "Surfaces Resolve By Rule, Not By Hand"
      ;; A palette carries colours; the surfaces below want names from
      ;; vocabularies it has no word for.  GTK and the cursors are one installed
      ;; set, the Emacs theme is the palette's own name unless the editor has
      ;; none, and btop and the dock take their brightness default unless a
      ;; palette is close enough to a named theme to be worth the exception.
      (assert-true (every (lambda (name)
                            (let ((entry (assoc-ref palette-registry name)))
                              (not (or (assoc 'gtk-theme entry)
                                     (assoc 'cursor-theme entry)
                                     (assoc 'btop-theme entry)
                                     (assoc 'lambdock-theme entry)
                                     (assoc 'emacs-theme entry)))))
                          (palette-names))
        #:name "No palette should hand-fill a surface name")
      (assert-equal #:expect "Adwaita"
        #:got (get-gtk-theme 'nord)
        #:name "GTK takes the one theme that is installed")
      (assert-equal #:expect "WhiteSur-cursors"
        #:got (get-cursor-theme 'nord)
        #:name "The cursor set is the one the tasks install")
      (assert-equal #:expect "'nord"
        #:got (get-emacs-theme 'nord)
        #:name "A palette with its own Emacs theme names it")
      (assert-equal #:expect "'everforest-hard-dark"
        #:got (get-emacs-theme 'everforest-dark)
        #:name "A palette without one takes the nearest")
      (assert-equal #:expect "\"solarized-light\""
        #:got (get-btop-theme 'modus-operandi)
        #:name "A light palette takes the light default")
      (assert-equal #:expect "\"Default\""
        #:got (get-btop-theme 'modus-vivendi)
        #:name "A dark palette takes the dark default")
      (assert-equal #:expect 'vanilla
        #:got (get-lambdock-theme 'modus-vivendi)
        #:name "The dock takes the dark default")
      (assert-equal #:expect 'vanilla-light
        #:got (get-lambdock-theme 'modus-operandi)
        #:name "And the light one")
      (assert-true (not (not (every (lambda (name)
                                      (member (get-btop-theme name)
                                              btop-theme-names))
                                    (palette-names))))
        #:name "Every btop answer should be a theme btop ships")
      (assert-true (not (not (every (lambda (name)
                                      (memq (get-lambdock-theme name)
                                            lambdock-theme-names))
                                    (palette-names))))
        #:name "Every dock answer should be a theme lambdock ships")
      (assert-true (not (not (every (lambda (name)
                                      (assoc-ref palette-registry name))
                                    (append (map car palette-emacs-themes)
                                            (map car palette-btop-themes)
                                            (map car palette-lambdock-themes)))))
        #:name "An exception should name a registered palette"))

    (test "Every Palette Wears A Tela Icon Theme"
      (assert-true (not (not (every (lambda (name)
                                      (member (get-icon-theme name)
                                              (tela-icon-themes)))
                                    (palette-names))))
        #:name
        "Every icon theme should be a Tela variant the installer carries")
      ;; NOTE: the accent comes back out of `get-gtk-accent-color',
      ;; the same procedure dconf is fed from, so the icons cannot
      ;; follow one accent while GTK is told another.
      (assert-true (not (not (every (lambda (name)
                                      (string=?
                                       (get-icon-theme name)
                                       (tela-icon-theme
                                        (palette-icon-accent name)
                                        #:dark? (is-dark-palette name))))
                                    (palette-names))))
        #:name
        "The icon theme should follow the palette's accent and brightness")
      (assert-equal #:expect "Tela-purple-light"
        #:got (tela-icon-theme 'purple #:dark? #f)
        #:name "GTK's purple accent should map to the light purple artwork")
      (assert-equal #:expect "Tela-purple-dark"
        #:got (tela-icon-theme 'purple #:dark? #t)
        #:name "A dark palette should take the dark purple artwork")
      (assert-equal #:expect "Tela-green-light"
        #:got (tela-icon-theme 'green #:dark? #f)
        #:name "Green should take the green artwork")
      (assert-equal #:expect "Tela-blue-light"
        #:got (tela-icon-theme 'cyan #:dark? #f)
        #:name "Cyan should take the nearest colour Tela ships")
      (assert-error (lambda () (tela-icon-theme 'chartreuse #:dark? #f))
        #:name "An accent no Tela variant carries should raise"))

    (test "Every Palette Exposes App Opacities"
      (assert-true (every (lambda (name)
                            (every (lambda (getter)
                                     (opacity? (getter name)))
                                   opacity-getters))
                          (palette-names))
        #:name
        "Each palette must declare a 0-1 opacity for the terminal and the bar"))

    (test "No Palette Carries A Retired Program's Opacity"
      ;; The bar's alpha is whelk's.  A palette that still spells the old
      ;; surfaces would be a field nothing reads, and the suite would not say so.
      (assert-true (every (lambda (name)
                            (let ((entry (assoc-ref palette-registry name)))
                              (not (or (assoc 'waybar-opacity entry)
                                     (assoc 'rofi-opacity entry)
                                     (assoc 'mako-opacity entry)))))
                          (palette-names))
        #:name "The bar's opacity should be the only shell opacity"))

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
        #:name "hex-to-rgba should fall back on bad input"))

    (test "Colours Can Be Mixed"
      ;; The bar takes a palette's own background and moves it toward
      ;; the neutral material a menu bar is made of, so one
      ;; weight and two colours have to be enough to say how far.
      (assert-equal #:expect "#808080"
        #:got (mix-colors "#000000" "#ffffff" #:weight 0.5)
        #:name "Halfway between black and white should be grey")
      (assert-equal #:expect "#000000"
        #:got (mix-colors "#000000" "#ffffff" #:weight 0)
        #:name "A weight of zero should leave the base alone")
      (assert-equal #:expect "#ffffff"
        #:got (mix-colors "#000000" "#ffffff" #:weight 1)
        #:name "A weight of one should return the other colour")
      (assert-equal #:expect "#ffffff"
        #:got (mix-colors "#000000" "#ffffff" #:weight 1.2)
        #:name "A weight past one should clamp, not overflow")
      ;; The actual pair the bar mixes for a light palette: the bar's
      ;; neutral and gruvbox-light's warm background, at its default.
      (assert-equal #:expect "#eee5cd"
        #:got (mix-colors "#f2f3f5" "#ebdbb2" #:weight 0.6)
        #:name "Each channel should move by its own amount")
      (assert-equal #:expect "#123456"
        #:got (mix-colors "#123456" "not-a-colour" #:weight 0.5)
        #:name "Malformed input should fall back on the base colour"))

    (test "Contrast Is Measured, Not Assumed"
      ;; The anchors WCAG itself states, so a change to the maths shows up here
      ;; rather than as a surface nobody can read.
      (assert-true (< 20.9 (contrast-ratio "#000000" "#ffffff") 21.1)
        #:name "Black on white should be 21:1")
      (assert-true (< 0.99 (contrast-ratio "#123456" "#123456") 1.01)
        #:name "A colour on itself should be 1:1")
      (assert-true (>= (contrast-ratio "#767676" "#ffffff") 4.5)
        #:name "#767676 is the lightest grey that clears AA on white")
      (assert-equal #:expect "#333333"
        #:got (readable-ink "#ffffff" (list "#777777" "#333333"))
        #:name "The first candidate that clears the floor should win")
      (assert-equal #:expect "#000000"
        #:got (readable-ink "#ffffff" (list "#999999"))
        #:name "An ink that cannot be read should give way to plain black")
      (assert-equal #:expect "#ffffff"
        #:got (readable-ink "#002b36" (list "#1d2021"))
        #:name "On a dark surface the fallback is white, not black"))))

(define (spec)
  (veritas-run palette-suite))
