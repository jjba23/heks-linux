;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux validation).
;;
;; The contract is small and worth pinning: a file has a validator when the
;; program that reads it can check it, the validator is chosen by name and not by
;; guessing, and a machine without that program skips the check instead of
;; failing the render.  Refusing to write a config its own parser rejects is the
;; cheap half of a desktop whose failure mode is a black screen.

;;; Code:

(define-module (veritas unit validation-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux validation)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (validator-suite)
  (suite "Choosing a validator"
    (test "A KDL File Is Niri's To Check"
      (assert-equal #:expect '(program "niri" "validate" "--config")
        #:got (validator-for "config.kdl" "/tmp")
        #:name "KDL is validated by niri"))
    (test "A Whelk Settings File Is Whelk's To Check"
      (assert-equal #:expect '(program "whelk" "--config")
        #:got (validator-for "settings.scm" "/tmp/whelk")
        #:name "The shell checks its own settings"))
    (test "Another Settings File Is Not Whelk's"
      (assert-equal #:expect '(scheme)
        #:got (validator-for "settings.scm" "/tmp/gtk")
        #:name "The directory is part of the question"))
    (test "A Maven File Is XML"
      (assert-equal #:expect '(program "xmllint" "--noout")
        #:got (validator-for "pom.xml" "/tmp")
        #:name "A pom is checked as XML"))
    (test "A JSON File Is JSON"
      (assert-equal #:expect '(json)
        #:got (validator-for "settings.json" "/tmp")
        #:name "JSON is checked by a JSON parser"))
    (test "An Unknown File Has No Validator"
      (assert-equal #:expect #f
        #:got (validator-for "notes.txt" "/tmp")
        #:name "No validator is invented"))))

(define (contents-suite)
  (suite "Checking contents"
    (test "A Guile File That Does Not Read Is Refused"
      (assert-true (string? (validate-config-contents "broken.scm" "/tmp" "(define x"))
        #:name "An unbalanced form is a reason"))
    (test "A Guile File That Reads Is Accepted"
      (assert-equal #:expect #f
        #:got (validate-config-contents "fine.scm" "/tmp" "(define x 1)\n")
        #:name "A well-formed form passes"))
    (test "A File With No Validator Is Accepted"
      (assert-equal #:expect #f
        #:got (validate-config-contents "notes.txt" "/tmp" "anything at all\n")
        #:name "Nothing is checked when nothing can check it"))
    (test "JSON That Does Not Parse Is Refused"
      (assert-true (string? (validate-config-contents "bad.json" "/tmp" "{"))
        #:name "An unclosed object is a reason"))))

(define (path-suite)
  (suite "Programs on the path"
    (test "Guile Is On The Path"
      (assert-true (program-on-path? "guile")
        #:name "The test runner's own program is found"))
    (test "A Missing Program Is Not"
      (assert-true (not (program-on-path? "heks-no-such-program"))
        #:name "A program that is not installed is reported absent"))))

(define (spec)
  (veritas-run
    (validator-suite)
    (contents-suite)
    (path-suite)))
