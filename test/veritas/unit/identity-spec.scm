;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux identity).
;;
;; Two files say what a machine is: /etc/os-release, which programs read, and
;; /etc/issue, which a getty prints above its login prompt.  The tests hold them
;; to two promises - the system presents itself as Heks, and it still says what
;; it is built on, because a distribution that hides its base is a distribution
;; whose tooling fails in ways nobody can read.

;;; Code:

(define-module (veritas unit identity-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux identity)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? text line)
  "Return #t when @var{text} has @var{line} in it."
  (not (eq? #f (string-contains text line))))

(define (lines text)
  "Return the lines of @var{text} that say something."
  (remove string-null? (string-split (string-trim-right text #\newline) #\newline)))

(define (os-release-cases)
  (suite "What The System Says It Is"
    (test "Every Line Is A Variable A Shell Can Read"
      (for-each (lambda (line)
                  (assert-true (and (not (string-prefix? "#" line))
                                 (contains? line "=")
                                 (not (string-prefix? " " line)))
                    #:name (format #f "~a is KEY=value" line)))
                (lines (os-release))))
    (test "The Name A Person Reads Is Heks"
      (let ((text (os-release)))
        (assert-true (contains? text "NAME=\"Heks GNU/Linux\"")
          #:name "NAME is what a program shows in a menu or a summary")
        (assert-true (contains? text "PRETTY_NAME=\"Heks GNU/Linux\"")
          #:name "PRETTY_NAME is what a person is shown")
        (assert-true (contains? text "ID=heks")
          #:name "And the identifier is this system's, not its base's")))
    (test "It Still Says What It Is Built On"
      ;; An identifier no distribution knows sends tooling down its fallback
      ;; path; naming the base is what makes those paths work.
      (assert-true (contains? (os-release) "ID_LIKE=void")
        #:name "ID_LIKE names the distribution the packages come from"))
    (test "It Points At This Project, Not At The Base"
      (let ((text (os-release)))
        (assert-true (contains? text "HOME_URL=\"https://codeberg.org/jjba23/heks-linux\"")
          #:name "The home page is where this tree lives")
        (assert-true (contains? text "BUG_REPORT_URL=\"https://codeberg.org/jjba23/heks-linux/issues\"")
          #:name "And a bug goes to the place that can fix it")))
    (test "A Release Says Which Release"
      (let ((text (os-release "6.0.0")))
        (assert-true (contains? text "VERSION=\"6.0.0\"")
          #:name "The version the image was built from")
        (assert-true (contains? text "VERSION_ID=\"6.0.0\"")
          #:name "As the identifier programs compare")))
    (test "A Tree With No Tag Claims No Version"
      (assert-true (not (contains? (os-release) "VERSION="))
        #:name "A rolling base has no version to claim, and a wrong one is worse than none"))))

(define (issue-cases)
  (suite "What A Console Prints Above Its Login"
    (test "It Says The System's Name"
      (assert-true (contains? (issue) "Heks GNU/Linux")
        #:name "The one line a person sees on Ctrl+Alt+F4"))
    (test "The Escapes Belong To agetty"
      ;; getty expands these itself, so they have to reach it as a backslash and
      ;; a letter - a string that already turned them into control characters is
      ;; a banner with no kernel release in it.
      (assert-true (contains? (issue) "\\r")
        #:name "The kernel release is an escape, not a carriage return")
      (assert-true (contains? (issue) "\\l")
        #:name "So is the console")
      (assert-true (not (contains? (issue) "\r"))
        #:name "And nothing has expanded them on the way out"))
    (test "It Ends In A Newline"
      (assert-true (string-suffix? "\n" (issue))
        #:name "The login prompt starts on its own line"))))

(define (spec)
  (veritas-run (os-release-cases) (issue-cases)))
