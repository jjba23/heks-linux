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

(define-module (veritas unit waybar-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux waybar)
  #:use-module (heks-linux palette)
  #:use-module (ice-9 match)
  #:export (spec))

(define waybar-suite
  (suite "Waybar Configuration Suite"
         (test "Power Menu SXML Structure"
               (assert-equal #:expect '*TOP*
                             #:got (car waybar-power-menu)
                             #:name
                             "Power menu should start with SXML TOP node")
               (assert-true (list? (member 'interface
                                           (caddr waybar-power-menu)))
                #:name "Power menu should contain an interface definition"))

         (test "Dynamic Start Button"
               (let ((custom-btn (waybar-start-button #:content "λ test")))
                 (assert-true (list? custom-btn)
                              #:name "Start button should return a list")
                 (assert-equal #:expect "λ test"
                  #:got (cdadr custom-btn)
                  #:name
                  "Start button should respect the content keyword argument")))

         (test "Main Configuration (JSON Source)"
               (let ((conf (waybar-conf)))
                 (assert-true (list? conf)
                  #:name
                  "Waybar config should be a list (convertible to JSON)")
                 (assert-equal #:expect 'bottom
                               #:got (assoc-ref conf
                                                'position)
                               #:name
                               "Waybar position should be bottom by default")
                 (assert-true (vector? (assoc-ref conf
                                                  'modules-left))
                  #:name
                  "Modules should be represented as vectors for JSON arrays")))

         (test "CSS Rules Generation"
               (let ((css (waybar-css)))
                 (assert-true (not (null? css))
                              #:name "CSS list should not be empty")
                 (assert-true (assoc-ref css "window#waybar")
                  #:name "CSS should contain a rule for the waybar window")
                 (assert-equal #:expect 'transparent
                  #:got (assoc-ref (assoc-ref css
                                              'module)
                                   'background)
                  #:name "Module background should be transparent in CSS")))))

(define (spec)
  (veritas-run waybar-suite))
