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

(define-module (heks-linux fastfetch)
  #:declarative? #t
  #:use-module (json)
  #:use-module (ice-9 string-fun)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:export (fastfetch-conf install-fastfetch-config))

;; {
;;          "type": "cpu",
;;          "key": "Temperature",
;;          "temp": true,
;;          "format": "{temperature}"
;;      },

(define* (fastfetch-conf #:key clone-dir)
  (let* ((modules `(title separator
                          ((type . os)
                           (format . "Heks GNU/Linux: {pretty-name}"))
                          host
                          kernel
                          uptime
                          packages
                          shell
                          cpu
                          ((type . cpu) (key . "CPU Temp")
                           (temp . #t)
                           (format . "{temperature}"))
                          gpu
                          memory
                          disk
                          wm
                          wmtheme
                          theme
                          icons
                          terminal
                          display
                          battery
                          locale
                          break
                          colors)))
    `(($schema . "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json")
      (logo (source unquote
                    (string-replace-substring (format #f
                                               "~a/resources/varesa-small-3.png"
                                               (heks-linux-clone-dir)) "~/"
                                              (format #f "~a/"
                                                      (getenv "HOME"))))
            (width . 32)
            (padding (top . 2)
                     (left . 2)
                     (right . 2)))
      (modules unquote
               (list->vector modules)))))

(define* (install-fastfetch-config)
  (with-output-to-file (format #f "~a/.config/fastfetch/config.jsonc"
                               (getenv "HOME"))
    (lambda ()
      (display (scm->json-string (fastfetch-conf #:clone-dir (heks-linux-clone-dir))
                                 #:pretty #t)))))
