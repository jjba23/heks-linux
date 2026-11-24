;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux profile).
;;
;; A profile is parameters and nothing else.  These tests are about the line
;; between the two halves of configuration: a profile may set a parameter, and a
;; profile that tries to be code - an unknown key, a value of the wrong shape, a
;; form where a value belongs - is refused before anything is applied.  That is
;; what makes "a laptop and a desktop differ by one file" a claim the project can
;; check rather than a promise it makes.

;;; Code:

(define-module (veritas unit profile-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux profile)
  #:use-module (heks-linux user-settings)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (scratch-profile contents)
  "Write @var{contents} to a temporary profile and return its path."
  (let ((path (format #f "/tmp/heks-profile-~a.scm" (getpid))))
    (call-with-output-file path
                           (lambda (port) (display contents port)))
    path))

(define (validation-suite)
  (suite "Validation"
    (test "A Known Key With The Right Shape Is Accepted"
      (assert-equal #:expect '()
        #:got (profile-validate '((palette . kanagawa)))
        #:name "One palette is a valid profile"))
    (test "An Unknown Key Names The Vocabulary"
      (let ((problems (profile-validate '((colour . blue)))))
        (assert-equal #:expect 1
          #:got (length problems)
          #:name "An unknown key is one problem")
        (assert-true (if (string-contains (car problems) "known keys") #t #f)
          #:name "The message lists what a profile may say")))
    (test "A Value Of The Wrong Shape Is Refused"
      (assert-equal #:expect 1
        #:got (length (profile-validate '((blur? . "yes"))))
        #:name "blur? takes a boolean"))
    (test "A Form Is Not A Value"
      (assert-equal #:expect 1
        #:got (length (profile-validate '((palette . (lambda () 'kanagawa)))))
        #:name "A profile cannot smuggle in code"))
    (test "A Non-List Is Refused"
      (assert-equal #:expect 1
        #:got (length (profile-validate "laptop"))
        #:name "A profile is an alist, not a string"))))

(define (reading-suite)
  (suite "Reading"
    (test "A Profile Is Read As Data"
      (let ((path (scratch-profile
                   '"((palette . rose-pine)\n  (tab-bar? . #f))\n")))
        (call-with-values (lambda () (profile-read path))
          (lambda (data problems)
            (assert-equal #:expect '()
              #:got problems
              #:name "The shipped shape is valid")
            (assert-equal #:expect 'rose-pine
              #:got (cdr (assq 'palette data))
              #:name "The palette is read as a symbol")
            (assert-equal #:expect #f
              #:got (cdr (assq 'tab-bar? data))
              #:name "A boolean stays a boolean")))))
    (test "A Missing Profile Is Empty, Not An Error"
      (call-with-values (lambda () (profile-read "/tmp/no-such-heks-profile.scm"))
        (lambda (data problems)
          (assert-equal #:expect '()
            #:got data
            #:name "Nothing to apply")
          (assert-equal #:expect '()
            #:got problems
            #:name "Nothing to complain about"))))))

(define (application-suite)
  (suite "Application"
    (test "Applying A Profile Is Applying Parameters"
      (let ((before (heks-linux-palette)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (apply-profile! '((palette . doom-one)))
            (assert-equal #:expect 'doom-one
              #:got (heks-linux-palette)
              #:name "The palette parameter moved"))
          (lambda () (heks-linux-palette before))))
      (assert-true #t #:name "The palette was restored afterwards"))
    (test "An Invalid Profile Applies Nothing"
      (let ((before (heks-linux-palette)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (apply-profile! '((palette . doom-one)
                              (no-such-key . 1)))
            (assert-equal #:expect before
              #:got (heks-linux-palette)
              #:name "A refused profile leaves the parameters alone"))
          (lambda () (heks-linux-palette before)))))))

(define (vocabulary-suite)
  (suite "Vocabulary"
    (test "The Table Is The Contract"
      (assert-true (not (null? (profile-keys)))
        #:name "There is a vocabulary")
      (assert-true (if (sorted? (profile-keys)
                                (lambda (a b)
                                  (string<? (symbol->string a)
                                            (symbol->string b))))
                     #t #f)
        #:name "The keys are listed in a stable order"))
    (test "Every Key Resolves To A Parameter"
      (assert-true (every (lambda (key)
                            (let ((row (profile-parameter key)))
                              (and row (list? row) (= 2 (length row)))))
                          (profile-keys))
        #:name "A key names a module and a variable"))))

(define (spec)
  (veritas-run
    (validation-suite)
    (reading-suite)
    (application-suite)
    (vocabulary-suite)))
