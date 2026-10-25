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
;; Unit tests for (heks-linux waybar).

;; IMPORTANT contributor note:
;;
;; `assert-true' and friends are *pure constructors*: they return a closure
;; that the veritas runner later applies to a context.  When such a call sits
;; in a non-final position of a body (typically inside a `let'), its return
;; value is unused and Guile's optimizer deletes the call entirely, so the
;; assertion silently never runs.  Always pass assertions as direct arguments
;; to `test', as this file does.

;;; Code:

(define-module (veritas unit waybar-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux waybar)
  #:use-module (heks-linux palette)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (tree-contains? tree needle)
  "Return @code{#t} when @var{needle} occurs anywhere inside the nested list
structure @var{tree}.  SXML attributes such as the @code{logout} id hold
strings, so the comparison uses @code{equal?}."
  (cond
    ((null? tree) #f)
    ((pair? tree) (or (tree-contains? (car tree) needle)
                      (tree-contains? (cdr tree) needle)))
    ((equal? tree needle) #t)
    (else #f)))

(define (css-rule-for id)
  "Return the declaration list of the CSS rule that selects @var{id}, or @code{#f}.

The bar's stylesheet groups modules that share a role into one rule - the
appearance buttons, the readouts, the quiet states - so the selector a given id
appears in changes whenever the grouping does.  Looking the id up inside the
selectors, rather than restating the whole selector here, keeps these tests
about what the bar does and not about how the rules happen to be spelled."
  (let loop ((rules (waybar-css)))
    (cond ((null? rules) #f)
          ((and (pair? (car rules))
                (string? (car (car rules)))
                (string-contains (car (car rules)) id))
           (cdr (car rules)))
          (else (loop (cdr rules))))))

(define (css-values key)
  "Return every value the stylesheet declares under @var{key}.

A menu bar is read as one row, so what matters about its ink is a property of
the whole row: \"every item is painted in the palette's text colour\" is a claim
about this list, not about any one rule."
  (filter-map (lambda (rule)
                (and (pair? rule)
                     (list? (cdr rule))
                     (let ((entry (assoc key (cdr rule))))
                       (and entry (cdr entry)))))
              (waybar-css)))

(define (bar-ink)
  "Return the ink the bar paints its items in.

It is the colour the stylesheet declares on @code{module}, which every item
inherits: taking it from the stylesheet rather than from the palette keeps the
test about one ink rather than about which palette happens to be in use."
  (assoc-ref (assoc-ref (waybar-css)
                        'module)
             'color))

(define waybar-suite
  (suite "Waybar Configuration Suite"
         (test "Power Menu SXML Structure"
               (assert-equal #:expect '*TOP*
                             #:got (car waybar-power-menu)
                             #:name
                             "Power menu should start with SXML TOP node")
               (assert-true (list? (member 'interface
                                           (caddr waybar-power-menu)))
                #:name "Power menu should contain an interface definition")
               (assert-true (tree-contains? waybar-power-menu "logout")
                #:name "Power menu should contain a logout GtkMenuItem")
               (assert-true (tree-contains? waybar-power-menu "Log Out")
                #:name "The logout entry should carry a readable label"))

         (test "Power Menu Actions"
               (assert-equal #:expect "loginctl terminate-session $XDG_SESSION_ID"
                             #:got
                             (assoc-ref (assoc-ref (waybar-power-button)
                                                   'menu-actions)
                                        'logout)
                             #:name
                             "The logout entry should terminate the login session")
               (assert-equal #:expect "systemctl poweroff"
                             #:got
                             (assoc-ref (assoc-ref (waybar-power-button)
                                                   'menu-actions)
                                        'shutdown)
                             #:name "The shutdown entry should power the machine off"))

         (test "Dynamic Start Button"
               (assert-true (list? (waybar-start-button #:content "λ test"))
                            #:name "Start button should return a list")
               (assert-equal #:expect "λ test"
                             #:got (cdadr (waybar-start-button #:content
                                                               "λ test"))
                             #:name
                             "Start button should respect the content keyword argument"))

         (test "Main Configuration (JSON Source)"
               (assert-true (list? (waybar-conf))
                            #:name
                            "Waybar config should be a list (convertible to JSON)")
               (assert-equal #:expect 'top
                              #:got (assoc-ref (waybar-conf) 'position)
                              #:name "Waybar position should be top by default")
               (assert-true (vector? (assoc-ref (waybar-conf)
                                                'modules-left))
                            #:name
                            "Modules should be represented as vectors for JSON arrays")
               (assert-true (not (eq? #f (member 'custom/mako-dnd
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The do-not-disturb indicator should sit on the bar"))

         (test "Keybinding Reference Button"
               (assert-true (not (eq? #f (member 'custom/heks-keys
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The question-mark button should sit on the bar")
               (assert-true (eq? #f (member 'custom/heks-info
                                            (vector->list
                                             (assoc-ref (waybar-conf)
                                                        'modules-right))))
                            #:name
                            "The bar should carry only the new question mark")
               (assert-equal #:expect "\uf059"
                             #:got (assoc-ref (waybar-keybindings)
                                              'format)
                             #:name
                             "The button should be a circled question mark glyph")
               ;; The bar asks the compositor to spawn the window: a client
               ;; that spawns it itself has no activation token, and an open
               ;; window cannot be raised without one.
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-keybindings)
                                                     'on-click)
                                          "niri msg action spawn")))
                            #:name
                            "Clicking it should ask the compositor to activate it")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-keybindings)
                                                     'on-click)
                                          "heks-toon")))
                            #:name
                            "Clicking it should open the keyboard reference")
               (assert-true (not (eq? #f (css-rule-for "#custom-heks-keys")))
                            #:name
                            "The button should be styled like the rest of the bar")

               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-keybindings)
                                                     'on-click-right)
                                          "codeberg.org/jjba23/heks-linux")))
                            #:name
                            "A right click should still reach the project page"))

         (test "Wallpaper Button"
               (assert-true (not (eq? #f (member 'custom/heks-wallpaper
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The wallpaper button should sit beside the palette")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-wallpaper) 'on-click)
                                          "heks-toon walls")))
                            #:name
                            "Clicking it should open the wall chooser")
               (assert-true (string? (assoc-ref (waybar-wallpaper) 'format))
                            #:name "The button is a glyph, not a label")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-wallpaper) 'format)
                                          "\uf03e")))
                            #:name
                            "The glyph should be the picture icon the bar's first font can draw")
               (assert-true (not (eq? #f (css-rule-for "#custom-heks-palette")))
                            #:name
                            "The appearance buttons should share one rule")
               (assert-equal #:got (css-rule-for "#custom-heks-palette")
                             #:expect (css-rule-for "#custom-heks-wallpaper")
                             #:name
                             "The palette and the wall chooser should wear one style"))

         (test "Documentation Button"
               ;; The docs button is the same question as the palette and the
               ;; wall chooser - what is this desktop - answered from the
               ;; projects' own READMEs instead of a browser tab.
               (assert-true (not (eq? #f (member 'custom/heks-docs
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The documentation button should sit on the bar")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-docs) 'on-click)
                                          "heks-toon docs")))
                            #:name
                            "Clicking it should open the documentation view")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-docs) 'on-click)
                                          "niri msg action spawn")))
                            #:name
                            "It should ask the compositor for the activation a bar click cannot prove")
               (assert-equal #:expect "\uf518"
                             #:got (assoc-ref (waybar-docs) 'format)
                             #:name
                             "The glyph should be the book the bar's font can draw")
               (assert-true (not (eq? #f (assoc-ref (waybar-docs) 'tooltip)))
                            #:name
                            "The tooltip should say what the book opens"))

         (test "The Bar Wears The Mac Menu Bar"
               ;; Snow Leopard's menu bar: a gloss, a lit top edge, a shaded
               ;; foot, and text with a shadow so it survives the wallpaper.
               (assert-true (not (eq? #f (assoc-ref (assoc-ref (waybar-css)
                                                               "window#waybar")
                                                    'background-image)))
                            #:name "The bar should carry a gloss, not a flat fill")
               (assert-true (not (eq? #f (assoc-ref (assoc-ref (waybar-css)
                                                               "window#waybar")
                                                    'border-top)))
                            #:name "The top edge should be lit")
               (assert-true (not (eq? #f (assoc-ref (assoc-ref (waybar-css)
                                                               "window#waybar")
                                                    'border-bottom)))
                            #:name "The foot of the bar should be shaded")
               (assert-true (not (eq? #f (string-contains
                                          (format #f "~a"
                                                  (assoc-ref (assoc-ref (waybar-css)
                                                                        'module)
                                                             'text-shadow))
                                          "rgba")))
                            #:name
                            "The items should carry the menu bar's text shadow")
               (assert-equal #:expect "0px 10px"
                             #:got (assoc-ref (css-rule-for "#cpu") 'padding)
                             #:name
                             "Items should keep the wider spacing, and changing it should be deliberate"))

         (test "Do Not Disturb Indicator"
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-mako-dnd)
                                                     'on-click)
                                          "makoctl mode -t do-not-disturb")))
                            #:name
                            "Clicking the indicator should toggle the mako DND mode"))

         (test "One Ink, No Accent"
               ;; Mavericks' menu bar has no accent colour in it at all: the
               ;; brightest thing there is the frontmost application's name, and
               ;; it is bright because it is bold.  The bar follows that, so the
               ;; palette's accent appears nowhere and every item is painted in
               ;; the same ink - the two battery alarms excepted, which are not
               ;; decoration but the same red OS X turns its battery to.
               (assert-equal #:expect #f
                             #:got (string-contains (format #f "~s"
                                                            (waybar-css))
                                                    "primary")
                             #:name
                             "The palette's accent should appear nowhere in the bar")
               (assert-equal #:expect #f
                             #:got (string-contains (format #f "~s"
                                                            (waybar-css))
                                                    "text-l")
                             #:name
                             "The bar should not keep a second, dimmer ink")
               (assert-equal #:expect '()
                             #:got (remove (lambda (value)
                                             (member value
                                                     (list (bar-ink)
                                                           "#ff9e3b"
                                                           "#e82424")))
                                           (css-values 'color))
                             #:name
                             "Every item should be painted in the palette's one ink")
               (assert-true (not (eq? #f (assoc 'color (css-rule-for "#battery.warning"))))
                            #:name
                            "The low battery should still be the one exception")
               ;; Hovers are a veil of the bar's own ink, never a colour of their
               ;; own: the power button used to flash red at the cursor.
               (assert-equal #:expect '()
                             #:got (remove (lambda (value)
                                             (let ((text (format #f "~a" value)))
                                               (or (string=? text "transparent")
                                                   (string-contains text "rgba("))))
                                           (css-values 'background))
                             #:name
                             "Every background should be the strip or a veil of the ink"))

         (test "Keyboard Layout Item"
               ;; A menu bar names a layout in two letters.  Waybar's own
               ;; niri/language module only knows the full name, which is why
               ;; this is a custom item with a label script and a menu behind it.
               (assert-equal #:expect 'custom/heks-language
                             #:got (car (waybar-language))
                             #:name "The layout should be the bar's own custom item")
               (assert-equal #:expect 8
                             #:got (assoc-ref (waybar-language) 'signal)
                             #:name
                             "The label should repaint on the bar's layout signal")
               (assert-equal #:expect "once"
                             #:got (assoc-ref (waybar-language) 'interval)
                             #:name
                             "The label is not a poll: the menu pokes it")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-label)
                                          "niri msg keyboard-layouts")))
                            #:name "The label reads the layouts from the compositor")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-label)
                                          "CODES=(\"us\")")))
                            #:name
                            "The label bakes in the configured layouts, in the compositor's order")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-menu)
                                          "switch-layout")))
                            #:name
                            "The menu switches the layout through the compositor")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-menu)
                                          "RTMIN+8")))
                            #:name
                            "The menu pokes the bar so the label repaints at once")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-menu)
                                          "lines: $lines")))
                            #:name
                            "The menu is only as tall as the layouts it lists"))

         (test "Rounded Bar Styling"
               (assert-equal #:expect "0px"
                             #:got
                             (assoc-ref (assoc-ref (waybar-css)
                                                   "window#waybar")
                                        'border-radius)
                             #:name
                             "The floating bar should carry the configured corner radius")
               (assert-equal #:expect "0px"
                             #:got
                             (parameterize ((waybar-border-radius "0px"))
                               (assoc-ref (assoc-ref (waybar-css)
                                                     "window#waybar")
                                          'border-radius))
                             #:name
                             "The bar corner radius should be overridable"))

         (test "CSS Rules Generation"
               (assert-true (not (null? (waybar-css)))
                            #:name "CSS list should not be empty")
               (assert-true (not (eq? #f (assoc-ref (waybar-css)
                                                    "window#waybar")))
                            #:name "CSS should contain a rule for the waybar window")
               (assert-equal #:expect 'transparent
                             #:got (assoc-ref (assoc-ref (waybar-css)
                                                         'module)
                                              'background)
                             #:name
                             "Module background should be transparent in CSS"))))

(define (spec)
  (veritas-run waybar-suite))
