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

(define-module (veritas unit rofi-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux rofi)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux palette)
  #:export (spec))

(define rofi-suite
  (suite "Rofi Configuration and Theming"
         (test "Rofi Config String Template"
               (let ((config-output (rofi-configuration)))
                 (assert-true (string-contains config-output
                                               "font: \"Iosevka 14\"")
                              #:name
                              "Configuration should inject the provided font")
                 (assert-true (string-contains config-output
                                               "show-icons: true")
                              #:name "Icons should be enabled by default")
                 (assert-true (not (eq? #f
                                        (string-contains config-output
                                         "@theme \"./sss-theme.rasi\"")))
                  #:name "Config must reference the generated theme file")))

         (test "Rofi Theme (AList Structure)"
               (let* ((palette (heks-linux-palette))
                      (theme (rofi-theme)))
                 (assert-true (list? theme)
                              #:name "Theme should be a list (AList)")

                 (let ((wildcard (assoc-ref theme "*")))
                   (assert-true (not (eq? #f wildcard))
                    #:name "Should contain a global wildcard '*' section")
                   (assert-equal #:expect "transparent"
                    #:got (assoc-ref wildcard
                                     'background-color)
                    #:name "Global background-color should be transparent"))

                 ;; Verify font quoting in the message section
                 (let ((message-section (assoc-ref theme "message")))
                   (assert-equal #:expect "\"IBM Plex Sans 14\""
                    #:got (assoc-ref message-section
                                     'font)
                    #:name
                    "Theme sections should correctly quote and inject the font"))))

         ))

(define (spec)
  (veritas-run rofi-suite))

