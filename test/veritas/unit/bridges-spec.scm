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
;; Unit tests for (heks-linux bridges), the adapters that publish Heks Linux
;; settings to Emacs (Elisp) and to Bash (environment variables).

;;; Code:

(define-module (veritas unit bridges-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux bridges)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (contains-setopt? elisp variable)
  "Helper to check if a list contains a specific Elisp setopt call."
  (not (eq? #f (member variable
                       (map (lambda (x)
                              (if (list? x)
                                  (cadr x) #f))
                            (cdr elisp))))))

(define (bridge-value elisp variable)
  "Return the value bound to @var{variable} by a @code{(setopt variable value)}
form inside the generated Emacs bridge payload."
  (let ((entry (find (lambda (x)
                       (and (list? x)
                            (eq? 'setopt (car x))
                            (eq? variable (cadr x))))
                     (cdr elisp))))
    (if entry (caddr entry) #f)))

(define bridges-test-suite
  (suite "bridges test suite"
         (test "Emacs Bridge Elisp Generation"
               (assert-true (list? (heks-linux-to-emacs-bridge))
                            #:name
                            "Bridge output should be a list (S-expression)")
               (assert-equal #:expect 'progn
                             #:got (car (heks-linux-to-emacs-bridge))
                             #:name "Bridge output should be wrapped in a 'progn")
               (assert-true (contains-setopt? (heks-linux-to-emacs-bridge)
                                              'heks-emacs-font-mono)
                            #:name "Should configure mono font")
               (assert-true (contains-setopt? (heks-linux-to-emacs-bridge)
                                              'heks-emacs-font-sans)
                            #:name "Should configure the sans font")
               (assert-true (contains-setopt? (heks-linux-to-emacs-bridge)
                                              'heks-emacs-theme)
                            #:name "Should configure the Emacs theme"))

         (test "Emacs Bridge Carries The Settings Values"
               (assert-equal #:expect (heks-linux-mono-font)
                             #:got
                             (bridge-value (heks-linux-to-emacs-bridge)
                                           'heks-emacs-font-mono)
                             #:name
                             "The mono font setting should travel across the bridge")
               (assert-equal #:expect (heks-linux-clone-dir)
                             #:got
                             (bridge-value (heks-linux-to-emacs-bridge)
                                           'heks-emacs-clone-dir)
                             #:name
                             "The clone directory should travel across the bridge"))

         (test "Bash Bridge String Generation"
               (assert-true (string-prefix? "#!/usr/bin/env bash"
                                            (heks-linux-to-bash-bridge))
                            #:name
                            "Bash bridge should start with correct shebang")
               (assert-true (not (eq? #f
                                      (string-contains (heks-linux-to-bash-bridge)
                                                       "HEKS_BASH_HIGHLIGHT_TEXT=")))
                #:name "Bash bridge should export the highlight variable"))))

(define (spec)
  (veritas-run bridges-test-suite))
