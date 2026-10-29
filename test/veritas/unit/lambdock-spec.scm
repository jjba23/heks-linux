;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux lambdock).  The dock's configuration format is
;; itself Scheme, so these tests read the generated text the way lambdock does
;; when it loads @file{settings.scm}: a sequence of top-level @code{define}
;; forms.

;;; Code:

(define-module (veritas unit lambdock-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux lambdock)
  #:use-module (heks-linux niri)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:export (spec))

(define (dock-settings-occurs? fragment)
  "Whether the generated dock settings contain @var{fragment}."
  (not (eq? #f (string-contains (lambdock-config) fragment))))

(define (niri-launchpad-rule)
  "Return the slice of the generated niri config holding the launchpad's rule.

Read as a slice rather than as a whole-file search: @code{blur true} appears in
every layer rule, and what these tests are about is the launchpad's own."
  (let* ((conf (string-join (serialize-kdl (niri-config)) "\n"))
         (start (string-contains conf
                                 "match namespace=\"^lambdock-launchpad$\"")))
    (if (not start)
        ""
        (substring conf start (min (string-length conf) (+ start 300))))))

(define (dock-frosts-launchpad?)
  "The value the generated dock settings give @code{dock-launchpad-blur?}."
  (not (eq? #f
            (string-contains (lambdock-config)
                             (format #f "dock-launchpad-blur? ~a"
                                     (heks-linux-blur?))))))

(define (niri-frosts-launchpad?)
  "The blur the generated niri config gives the launchpad's layer rule.

Spelled the way KDL writes a boolean (@code{true}/@code{false}), not the way
Scheme prints one: these are the bytes niri parses."
  (not (eq? #f
            (string-contains (niri-launchpad-rule)
                             (if (heks-linux-blur?)
                                 "blur true"
                                 "blur false")))))

(define lambdock-suite
  (suite "Lambdock Configuration Suite"
         (test "The Dock Is Configured In The File It Loads"
               (assert-true (string=? "settings.scm"
                                      (lambdock-settings-filename))
                #:name
                "The settings file should be the name lambdock reads from its config directory")
               ;; A sequence of defines is the whole contract: the dock's
               ;; parser reads top-level forms, so text that stopped being one
               ;; would load as nothing at all.
               (assert-true (dock-settings-occurs? "(define dock-auto-hide?")
                #:name "The settings should be emitted as top-level defines")
               (assert-true (dock-settings-occurs? "(define dock-items")
                #:name "The dock item list should be emitted"))

         (test "The Launchpad's Frost Is One Setting In Two Places"
               ;; The dock leaves its full screen backdrop translucent, and the
               ;; compositor is the one that blurs what is behind a layer
               ;; surface: two halves of one look, written by two modules from
               ;; one switch.  Both are read back here, because a value baked
               ;; into either side would leave the launchpad frosted in the dock
               ;; and flat on screen, or the other way round.
               (assert-true (dock-settings-occurs? "dock-launchpad-blur?")
                #:name
                "The dock should be told whether its launchpad backdrop is frosted")
               (assert-true (dock-frosts-launchpad?)
                #:name "The dock's launchpad frost should follow the blur switch")
               (assert-true (niri-frosts-launchpad?)
                #:name
                "The launchpad's layer rule should follow the same blur switch")
               (assert-true
                (eq? (dock-frosts-launchpad?) (niri-frosts-launchpad?))
                #:name
                "The dock and the compositor should agree about the launchpad's frost"))))

(define (spec)
  (veritas-run lambdock-suite))
