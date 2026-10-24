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
;; Unit tests for (heks-linux mako).  The configuration is an association list
;; that is later flattened into @code{key=value} lines, so the tests inspect
;; the flattened text exactly like mako will read it.

;;; Code:

(define-module (veritas unit mako-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux mako)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:export (spec))

(define (render-mako-config-for palette)
  "Render the mako configuration for @var{palette} the way it is written to disk."
  (mk-kv-conf-lines (mako-config #:palette palette
                                 #:sans-font "Lucida Sans")))

(define (render-mako-config)
  "Render the mako configuration the way it is written to disk."
  (render-mako-config-for 'modus-operandi))

(define (mako-conf-occurs? fragment)
  (not (eq? #f (string-contains (render-mako-config) fragment))))

(define mako-suite
  (suite "Mako Notification Suite"
         (test "Notification behaviour is configured"
               (assert-true (mako-conf-occurs? "max-history=7")
                            #:name "Notification history should be kept")
               (assert-true (mako-conf-occurs? "default-timeout=10000")
                            #:name "A default timeout should be set")
               (assert-true (mako-conf-occurs? "on-button-left=dismiss")
                            #:name "Left click should dismiss a notification"))

         (test "Do Not Disturb Mode Is Declared"
               (assert-true (mako-conf-occurs? "[mode=do-not-disturb]")
                            #:name
                            "A do-not-disturb mode section should exist so makoctl can toggle it")
               (assert-true (mako-conf-occurs? "invisible=1")
                            #:name
                            "While in do-not-disturb, notifications must not be drawn"))

         (test "Banner Background Follows Palette Opacity"
               ;; The expected alpha is derived from the palette, not baked in:
               ;; the whole point of these keys is that they are tunable, so a
               ;; test that hardcodes one turns a taste change into a failure.
               (assert-true (mako-conf-occurs?
                             (format #f "background-color=~a~a"
                                     (string-upcase (get-color 'modus-operandi
                                                               'background))
                                     (string-upcase
                                      (opacity->hex-alpha (get-mako-opacity
                                                           'modus-operandi)))))
                            #:name
                            "The default banner should use its palette mako-opacity")
               (assert-true (not (eq? #f
                                      (string-contains
                                       (render-mako-config-for 'golden-gate-dark)
                                       (format #f "background-color=~a~a"
                                               (string-upcase
                                                (get-color 'golden-gate-dark
                                                           'background))
                                               (string-upcase
                                                (opacity->hex-alpha
                                                 (get-mako-opacity
                                                  'golden-gate-dark)))))))
                            #:name
                            "Golden Gate should render its own, more transparent banner"))

         (test "Banners Match The macOS Look"
               (assert-true (mako-conf-occurs? "border-radius=16")
                            #:name "Notification banners should be rounded")
               (assert-true (mako-conf-occurs? "border-size=1")
                            #:name
                            "Notification banners should carry a one-pixel hairline edge")
               (assert-true (mako-conf-occurs?
                             (format #f "border-color=~a26"
                                     (get-color 'modus-operandi 'text-l)))
                            #:name
                            "The edge should be the secondary text colour at 15% opacity"))))

(define (spec)
  (veritas-run mako-suite))
