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

(define-module (heks-linux prelude)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 time)
  #:use-module (ice-9 i18n)
  #:use-module (ice-9 format)
  #:use-module (ice-9 iconv)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 textual-ports)
  #:export (log-exprs get-setting
                      log-message
                      log
                      log-info
                      log-error
                      G_
                      setup-i18n
                      log-active-sss-settings
                      pretty-quote
                      string-drop-first-last-n
                      syscall
                      flatten-list
                      mk-lines
                      mk-kv-conf-lines
                      serialize-rec-conf-item
                      mk-rec-kv-conf-lines
                      spaced-equal-conf-pair
                      equal-conf-pair
                      equal-conf-quote-value-pair
                      nix-profile-install
                      mk-css-conf-lines
                      heks-linux-palette
                      heks-linux-mono-font
                      heks-linux-sans-font
                      heks-linux-keyboard-layout))

(define heks-linux-palette 'modus-vivendi)
(define heks-linux-mono-font "Adwaita Mono")
(define heks-linux-sans-font "Adwaita Sans")
(define heks-linux-keyboard-layout "us")

(define (G_ msg)
  (gettext msg))

(define (setup-i18n)
  (catch #t
         (lambda ()
           (setlocale LC_MESSAGES "")
           (bindtextdomain "sss" "./resources/locale")
           (textdomain "sss"))
         (lambda (key . args)
           (display (format #f "error setting i18n up: ~a: ~a" key args)))))

(define preferred-strftime-format
  (make-parameter "%Y-%m-%d %H:%M:%S%z"))

(define (log-message msg)
  (display (format #f "\n\x1b[1m~a\x1b[0m\n" msg)))

(define (log msg . args)
  (log-message (apply format
                      (append (list #f msg) args))))

(define (log-info msg . args)
  (log-message (format #f "~a"
                       (apply format
                              (append (list #f msg) args)))))

(define (log-error msg . args)
  (log-message (format #f "[error] ~a"
                       (apply format
                              (append (list #f msg) args)))))

(define-syntax-rule (log-exprs exp ...)
  "Log a variadic number of expressions, and the result of their evaluation."
  (begin
    (format #t
            "~a~a:~a ~a~S~a\n"
            (assoc-ref ansi-color-escapes
                       'green)
            (pretty-quote (with-output-to-string (lambda ()
                                                   (write 'exp))))
            (assoc-ref ansi-color-escapes
                       'reset)
            (assoc-ref ansi-color-escapes
                       'default)
            exp
            (assoc-ref ansi-color-escapes
                       'reset)) ...))

(define-syntax-rule (string-drop-first-last-n s n)
  (let* ((len (string-length s))
         (start-idx n)
         (end-idx (- len n)))
    (if (>= start-idx end-idx) s
        (substring s start-idx end-idx))))

(define-syntax-rule (pretty-quote str)
  (regexp-substitute/global #f
                            "\\((quote [^)]*)\\)*"
                            str
                            'pre
                            (lambda (m)
                              
                              (let* ((mm (string-drop-first-last-n (match:substring
                                                                    m) 1)))
                                (string-replace-substring mm "quote " "'")))
                            'post))

(define* (syscall cmd
                  #:key (silent? #f))
  "Executes a system command and returns its output as a string.
 Be cautious with input: Passing untrusted or unsanitized strings can lead to
security vulnerabilities (e.g. shell injection attacks)."
  (let* ((process (open-input-pipe cmd))
         (process-output (get-string-all process)))
    (close-pipe process)
    (unless silent?
      (display process-output)) process-output))

(define (mk-lines items)
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (display (format #f "~a\n" x))) items))))

(define* (mk-css-conf-lines pairs)
  "Create a CSS configuration from PAIRS, a selector to values alist."
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (display (format #f "~a {\n"
                                                        (car x)))
                                       (display (mk-kv-conf-lines (cdr x)
                                                                  #:template
                                                                  "  ~a: ~a;\n"))
                                       (display "}\n\n")) pairs))))

(define* (mk-kv-conf-lines pairs
                           #:key (template "~a=~a\n"))
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (display (format #f template
                                                        (car x)
                                                        (cdr x)))) pairs))))

(define (serialize-rec-conf-item template item)
  (cond
    ((list? (cdr item))
     (cond
       ((string? (car item))
        (display (string-append "\n["
                                (car item) "]\n")))
       (else (display (string-append "\n["
                                     (symbol->string (car item)) "]\n"))))
     (display (mk-rec-kv-conf-lines (cdr item)
                                    #:template template)))
    (else (display (format #f template
                           (car item)
                           (cdr item))))))

(define* (mk-rec-kv-conf-lines pairs
                               #:key (template "~a=~a\n"))
  (with-output-to-string (lambda ()
                           (for-each (lambda (item)
                                       (serialize-rec-conf-item template item))
                                     pairs))))

(define spaced-equal-conf-pair
  "~a = ~a\n")

(define equal-conf-pair
  "~a=~a\n")

(define equal-conf-quote-value-pair
  "~a=\"~a\"\n")

(define (nix-profile-install x)
  (syscall (format #f "nix-env -iA ~a" x)))

(define (flatten-list xs)
  (cond
    ((null? xs)
     '())
    ((pair? xs)
     (append (flatten-list (car xs))
             (flatten-list (cdr xs))))
    (else (list xs))))

