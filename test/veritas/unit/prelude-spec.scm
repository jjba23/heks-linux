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
;; Unit tests for (heks-linux prelude), the small helper layer every config
;; module is built on: list flattening, key/value rendering and the file
;; installer.

;;; Code:

(define-module (veritas unit prelude-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 textual-ports)
  #:export (spec))

(define scratch-dir
  (format #f "/tmp/heks-prelude-spec-~a" (getpid)))

(define (read-file path)
  (let ((port (open-input-file path)))
    (let ((contents (get-string-all port)))
      (close-port port)
      contents)))

(define prelude-suite
  (suite "Prelude Helper Suite"
         (test "List Flattening"
               (assert-equal #:expect '(1 2 3 4 5)
                             #:got (flatten-list '(1 (2 (3 4)) 5))
                             #:name "Nested lists should be flattened")
               (assert-equal #:expect '()
                             #:got (flatten-list '())
                             #:name "Flattening the empty list should stay empty"))

         (test "Key Value Rendering"
               (assert-equal #:expect "host=localhost\nport=80\n"
                             #:got (mk-kv-conf-lines '((host . "localhost")
                                                       (port . 80)))
                             #:name "Pairs should render with the default template")
               (assert-equal #:expect "host = localhost\n"
                             #:got (mk-kv-conf-lines '((host . "localhost"))
                                                     #:template
                                                     spaced-equal-conf-pair)
                             #:name "The template should be overridable")
               (assert-equal #:expect "  color: black;\n"
                             #:got (mk-kv-conf-lines '((color . "black"))
                                                     #:template
                                                     css-conf-pair)
                             #:name "CSS pairs should render indented"))

         (test "Nested Structures Render As Ini Sections"
               (assert-equal #:expect "\n[settings]\nport=8080\n"
                             #:got (mk-rec-kv-conf-lines '((settings
                                                            (port . 8080)))
                                                         #:template "~a=~a\n")
                             #:name
                             "A nested list should become an INI section header"))

         (test "Directory Trees Are Created Recursively"
               (ensure-directory-tree! (format #f "~a/a/b/c" scratch-dir))
               (assert-true (file-exists? (format #f "~a/a/b/c" scratch-dir))
                            #:name
                            "Missing parents should be created, not just the leaf")
               (assert-true (eqv? 'directory
                                  (stat:type (stat (format #f "~a/a/b/c"
                                                           scratch-dir))))
                            #:name "The created leaf should really be a directory"))

         (let ((target-dir (format #f "~a/installed/nested" scratch-dir)))
           (install-config-file! #:name "deep.conf"
                                 #:dir target-dir
                                 #:contents "hello\n")
           (test "Config Files Install Into Missing Directories"
                 (assert-true (file-exists? (format #f "~a/deep.conf"
                                                    target-dir))
                              #:name
                              "The installer should create its directory tree")
                 (assert-equal #:expect "hello\n"
                               #:got (read-file (format #f "~a/deep.conf"
                                                        target-dir))
                               #:name "The installer should write the contents")
                 (assert-equal #:expect 420
                               #:got (stat:perms (stat (format #f "~a/deep.conf"
                                                               target-dir)))
                               #:name
                               "The default permissions should be #o644")))

         (test "Executable Config Files Get Executable Permissions"
               (let ((target-dir (format #f "~a/bin" scratch-dir)))
                 (install-config-file! #:name "script.sh"
                                       #:dir target-dir
                                       #:contents "#!/usr/bin/env bash\n"
                                       #:perms 493)
                 (assert-equal #:expect 493
                               #:got (stat:perms (stat (format #f "~a/script.sh"
                                                               target-dir)))
                               #:name
                               "Passing #o755 should make the file executable")))))

(define (spec)
  (veritas-run prelude-suite))
