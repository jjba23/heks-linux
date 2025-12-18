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
  #:export (mk-dconf-writer-commands flatten-dconf-settings
                                     mk-nested-dconf-writer-commands
                                     heks-linux-dconf-settings
                                     install-dconf-config))

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

(define* (heks-linux-dconf-settings #:key lang
                                    timezone
                                    keyboard-layout
                                    caps-to-ctrl?
                                    hostname
                                    clone-dir
                                    palette
                                    sans-font
                                    serif-font
                                    mono-font)
  `(("/heks-linux" (lang unquote
                         (format #f "'~a'" lang))
     (timezone unquote
               (format #f "'~a'" timezone))
     (caps-to-ctrl unquote
                   (if caps-to-ctrl? "true" "false"))
     (hostname unquote
               (format #f "'~a'" hostname))
     (clone-dir unquote
                (format #f "'~a'" clone-dir))
     (palette unquote
              (format #f "'~a'" palette))
     (sans-font unquote
                (format #f "'~a'" sans-font))
     (serif-font unquote
                 (format #f "'~a'" serif-font))
     (mono-font unquote
                (format #f "'~a'" mono-font)))))

(define (install-dconf-config)
  (with-output-to-file (format #f
                        "~a/.local/bin/write-heks-linux-dconf-settings"
                        (getenv "HOME"))
    (lambda ()
      (display (string-join (append `("#!/usr/bin/env bash" ""
                                      "# ====== HEKS-LINUX settings dconf writer ======"
                                      "#"
                                      "# auto-generated file, DO NOT EDIT!" "")
                                    (mk-nested-dconf-writer-commands (heks-linux-dconf-settings
                                                                      #:lang (heks-linux-language)
                                                                      #:timezone
                                                                      (heks-linux-timezone)
                                                                      #:keyboard-layout
                                                                      (heks-linux-keyboard-layout)
                                                                      #:caps-to-ctrl?
                                                                      #t
                                                                      #:hostname
                                                                      (heks-linux-hostname)
                                                                      #:clone-dir
                                                                      (heks-linux-clone-dir)
                                                                      #:palette
                                                                      (heks-linux-palette)
                                                                      #:sans-font
                                                                      (heks-linux-sans-font)
                                                                      #:serif-font
                                                                      (heks-linux-serif-font)
                                                                      #:mono-font
                                                                      (heks-linux-mono-font))))
                            "\n")))))
