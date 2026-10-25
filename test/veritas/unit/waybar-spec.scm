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
               (assert-equal #:expect "?"
                             #:got (assoc-ref (waybar-keybindings)
                                              'format)
                             #:name "The button should read as a question mark")
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
               (assert-true (not (eq? #f (assoc-ref (waybar-css)
                                                    "#custom-heks-keys")))
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
               (assert-true (not (eq? #f (assoc-ref (waybar-css)
                                                    "#custom-heks-palette, #custom-heks-wallpaper")))
                            #:name
                            "The two appearance buttons should share one rule"))

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
                             #:got (assoc-ref (assoc-ref (waybar-css)
                                                         "#cpu, #memory")
                                              'padding)
                             #:name
                             "Items should keep the wider spacing, and changing it should be deliberate"))

         (test "Do Not Disturb Indicator"
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-mako-dnd)
                                                     'on-click)
                                          "makoctl mode -t do-not-disturb")))
                            #:name
                            "Clicking the indicator should toggle the mako DND mode"))

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
