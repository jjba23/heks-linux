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
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (fastfetch-conf install-fastfetch-config fastfetch-config-filename
                           fastfetch-config-dir))

(define s
  (scriba-auto-logger))

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
      (logo (type . small))
      ;; === Use this for images in fastfetch (works well with Kitty) ===
      ;; (logo (source unquote
      ;; (string-replace-substring (format #f
      ;; "~a/resources/varesa-small-3.png"
      ;; (heks-linux-clone-dir)) "~/"
      ;; (format #f "~a/"
      ;; (getenv "HOME"))))
      ;; (width . 32)
      ;; (padding (top . 2)
      ;; (left . 2)
      ;; (right . 2)))
      (modules unquote
               (list->vector modules)))))

(define fastfetch-config-dir
  (make-parameter (format #f "~a/.config/fastfetch"
                          (or (getenv "HOME") "/tmp"))))

(define fastfetch-config-filename
  (make-parameter "config.jsonc"))

(define (install-fastfetch-config)
  (log-info s "Installing FastFetch configuration")
  (load-local-overrides '(heks-linux fastfetch) 'fastfetch-settings)
  (install-config-file! #:name (fastfetch-config-filename)
                        #:dir (fastfetch-config-dir)
                        #:contents (scm->json-string (fastfetch-conf
                                                                     #:clone-dir
                                                                     (heks-linux-clone-dir))
                                                     #:pretty #t))
  (log-success s "Installed FastFetch configuration"))
