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

(define-module (veritas unit bridges-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux bridges)
  #:export (spec))

(define (contains-setopt? elisp variable)
  "Helper to check if a list contains a specific Elisp setopt call."
  (not (eq? #f
            (member variable
                    (map (lambda (x)
                           (if (list? x)
                               (cadr x) #f))
                         (cdr elisp))))))

(define bridges-test-suite
  (suite "bridges test suite"
         (test "Emacs Bridge Elisp Generation"
               (let ((bridge-code (heks-linux-to-emacs-bridge)))
                 (assert-true (list? bridge-code)
                              #:name
                              "Bridge output should be a list (S-expression)")

                 (assert-equal #:expect 'progn
                               #:got (car bridge-code)
                               #:name
                               "Bridge output should be wrapped in a 'progn")

                 (assert-true (contains-setopt? bridge-code
                                                'heks-emacs-font-mono)
                              #:name "Should configure mono font")

                 (assert-true (contains-setopt? bridge-code
                                                'heks-emacs-theme)
                              #:name "Should configure the Emacs theme")))

         (test "Bash Bridge String Generation"
               (let ((bash-script (heks-linux-to-bash-bridge)))
                 (assert-true (string-prefix? "#!/usr/bin/env bash"
                                              bash-script)
                              #:name
                              "Bash bridge should start with correct shebang")

                 (assert-true (not (eq? #f
                                        (string-contains bash-script
                                         "HEKS_BASH_HIGHLIGHT_TEXT=")))
                  #:name "Bash bridge should export the highlight variable")))))

(define (spec)
  (veritas-run bridges-test-suite))

