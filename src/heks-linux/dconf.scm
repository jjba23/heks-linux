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

(define-module (heks-linux dconf)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (mk-dconf-writer-commands flatten-dconf-settings
                                     mk-nested-dconf-writer-commands
                                     dconf-config-filename
                                     dconf-config-dir
                                     heks-linux-dconf-settings
                                     install-dconf-config))

(define s
  (scriba-auto-logger))

(define (mk-dconf-writer-commands x)
  (format #f
          "echo \"~a --> ~a\" && dconf write \"~a\" \"~a\""
          (car x)
          (cdr x)
          (car x)
          (cdr x)))

(define (flatten-dconf-settings xs)
  (map (lambda (p)
         (append (map (lambda (pp)
                        (cons (format #f "~a/~a"
                                      (car p)
                                      (car pp))
                              (cdr pp)))
                      (cdr p)))) xs))

(define (mk-nested-dconf-writer-commands xs)
  (map mk-dconf-writer-commands
       (apply append
              (flatten-dconf-settings xs))))

(define* (heks-linux-dconf-settings)
  `(("/heks-linux" (lang unquote
                         (format #f "'~a'"
                                 (heks-linux-language)))
     (timezone unquote
               (format #f "'~a'"
                       (heks-linux-timezone)))
     (caps-to-ctrl . "true")
     (hostname unquote
               (format #f "'~a'"
                       (heks-linux-hostname)))
     (clone-dir unquote
                (format #f "'~a'"
                        (heks-linux-clone-dir)))
     (palette unquote
              (format #f "'~a'"
                      (heks-linux-palette)))
     (sans-font unquote
                (format #f "'~a'"
                        (heks-linux-sans-font)))
     (serif-font unquote
                 (format #f "'~a'"
                         (heks-linux-serif-font)))
     (mono-font unquote
                (format #f "'~a'"
                        (heks-linux-mono-font))))))

(define dconf-config-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define dconf-config-filename
  (make-parameter "write-heks-linux-dconf-settings"))

(define (install-dconf-config)
  (log-info s "Installing DConf configuration")
  (load-local-overrides '(heks-linux dconf)
                        'dconf-settings)
  (install-config-file! #:name (dconf-config-filename)
                        #:dir (dconf-config-dir)
                        #:contents (string-join (append `("#!/usr/bin/env bash"
                                                          ""
                                                          "# ====== HEKS-LINUX settings dconf writer ======"
                                                          "#"
                                                          "# auto-generated file, DO NOT EDIT!"
                                                          "")
                                                        (mk-nested-dconf-writer-commands
                                                         (heks-linux-dconf-settings)))
                                                "\n")
                        #:perms 493)
  (log-success s "Installed DConf configuration"))
