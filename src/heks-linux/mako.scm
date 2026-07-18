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
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux prelude)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (mako-config install-mako-config mako-config-filename
                        mako-config-dir))

(define s
  (scriba-auto-logger))

(define* (mako-config #:key palette sans-font)
  (let* ((format-color (lambda (key)
                         (string-upcase (format #f "~abb"
                                                (get-color palette key)))))
         (bg-color (format-color 'background))
         (primary-color (format-color 'primary))
         (text-color (format-color 'text)))
    `((sort . "-time") (max-history . 7)
      (max-visible . 5)

      ;; Geometry & Layout
      (anchor . "top-right")
      (width . 380)
      (margin . "20")
      (padding . "14")
      (layer . "top")

      ;; Visual Styling
      (background-color unquote bg-color)
      (border-color unquote primary-color)
      (border-size . 2)
      (border-radius . 10)
      (progress-color unquote primary-color)

      ;; Typography & Content Formatting
      (text-color unquote text-color)
      (font unquote
            (format #f "~a 11" sans-font))
      (text-alignment . "left")
      (markup . 1)
      (format . "<b>%s</b>\\n%b")

      ;; Icons
      (icons . 1)
      (max-icon-size . 48)

      ;; Actions & Timeouts
      (on-button-left . dismiss)
      (on-button-right . invoke-default-action)
      (default-timeout . 10000)
      (ignore-timeout . 1))))

(define mako-config-filename
  (make-parameter "config"))

(define mako-config-dir
  (make-parameter (format #f "~a/.config/mako"
                          (or (getenv "HOME") "/tmp"))))

(define* (install-mako-config)
  (log-info s "Installing Mako configuration")
  (load-local-overrides '(heks-linux mako)
                        'mako-settings)
  (install-config-file! #:name (mako-config-filename)
                        #:dir (mako-config-dir)
                        #:contents (mk-kv-conf-lines (mako-config #:palette (heks-linux-palette)
                                                                  #:sans-font (heks-linux-sans-font))))
  (log-success s "Installed Mako configuration"))
