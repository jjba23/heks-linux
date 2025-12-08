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

(define-module (heks-linux mako)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:export (mako-config install-mako))

(define* (mako-config #:key palette sans-font)
  `((sort . "-time") (max-history . 7)
    (on-button-left . dismiss)
    (on-button-right . invoke-default-action)
    (background-color unquote
                      (string-upcase (format #f "~abb"
                                             (get-color palette
                                                        'background))))
    (border-color unquote
                  (string-upcase (format #f "~abb"
                                         (get-color palette
                                                    'primary))))
    (text-color unquote
                (string-upcase (format #f "~abb"
                                       (get-color palette
                                                  'text))))
    (font unquote
          (format #f "~a 11" sans-font))
    (width . 420)
    (icons . 1)
    (default-timeout . 10000)
    (ignore-timeout . 1)
    (border-radius . 10)))

(define (install-mako)
  (with-output-to-file (format #f "~a/.config/mako/config"
                               (getenv "HOME"))
    (lambda ()
      (display (mk-kv-conf-lines (mako-config #:palette heks-linux-palette
                                              #:sans-font heks-linux-sans-font))))))

