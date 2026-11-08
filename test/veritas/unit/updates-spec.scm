;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for the two readers behind `maak check-updates': the one that
;; reads the pins out of a channels file, and the one that reads a commit out of
;; what `git ls-remote' printed.
;;
;; Both are fed text instead of a forge, so the suite stays hermetic and
;; answers the same on a machine with no network: what is asserted is which pin
;; belongs to which channel and which line of an ls-remote listing is the branch
;; itself, not whether codeberg is up.

;;; Code:

(define-module (veritas unit updates-spec)
  #:use-module (veritas veritas)
  #:use-module (maak)
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 textual-ports)
  #:export (spec))

;; The task file exports nothing, on purpose: maak reads a module that declares
;; exports as an opt-in list and would then run only what it names, so a spec
;; reaches the readers by their module instead of widening what the file
;; publishes.
(define channel-pins (@@ (maak) channel-pins))
(define ls-remote-commit (@@ (maak) ls-remote-commit))

(define scratch-dir
  (format #f "/tmp/heks-updates-spec-~a" (getpid)))

;;; A channels file the shape of the one in this repository: two channels, the
;;; first carrying an introduction.  It is never evaluated, so the fingerprint
;;; and the introduction are only there to prove the reader walks past them.
(define pinned-channels-text
  (string-append "(list (channel\n"
                 "       (name 'guix)\n"
                 "       (url \"https://example.org/guix.git\")\n"
                 "       (branch \"master\")\n"
                 "       (commit \"1111111111111111111111111111111111111111\")\n"
                 "       (introduction\n"
                 "        (make-channel-introduction\n"
                 "         \"2222222222222222222222222222222222222222\"\n"
                 "         (openpgp-fingerprint\n"
                 "          \"83BC 6E1C 8726 B8C2 97F8  D16E 24F4 6738 CE11 4AF6\"))))\n"
                 "      (channel\n"
                 "       (name 'jointhefreeworld)\n"
                 "       (url \"https://example.org/jointhefreeworld.git\")\n"
                 "       (branch \"trunk\")\n"
                 "       (commit \"3333333333333333333333333333333333333333\")))\n"))

(define (pinned-channels-file)
  "Write the fixture into the scratch directory and return its path."
  (let ((path (format #f "~a/channels.scm" scratch-dir)))
    (ensure-directory-tree! scratch-dir)
    (call-with-output-file path
                           (lambda (port) (display pinned-channels-text port)))
    path))

;;; The listing `git ls-remote URL refs/heads/master' answered with on the
;;; machine this was written on: the branch itself first, then the refs a forge
;;; keeps copies of it under.  The copies are what makes the reader have to
;;; match the whole ref rather than a prefix of it.
(define ls-remote-listing
  (string-append
   "72442a6baa199f4944df54cfdb45929af98ef99f\trefs/heads/master\n"
   "ed7eb108e5ba38135db99aa3b162f88797c372f9\trefs/origin-ssh/master\n"
   "22c229ff4e0869cdbcb5eabbe482fde7725e75e1\trefs/remotes/mirror/master\n"
   "a1fadeb4bb96422bc0ca1f63e302da5b62575dd7\trefs/heads/trunk\n"))

(define updates-suite
  (suite "Update Check Suite"
    (test "Channel Pins Are Read As Data"
      (assert-equal #:expect '(("guix"
                                "https://example.org/guix.git"
                                "master"
                                "1111111111111111111111111111111111111111")
                               ("jointhefreeworld"
                                "https://example.org/jointhefreeworld.git"
                                "trunk"
                                "3333333333333333333333333333333333333333"))
        #:got (channel-pins (pinned-channels-file))
        #:name
        "Each channel should yield its name, url, branch and commit, in order"))

    (test "Ls Remote Answers With The Branch Itself"
      (assert-equal #:expect "72442a6baa199f4944df54cfdb45929af98ef99f"
        #:got (ls-remote-commit ls-remote-listing "refs/heads/master")
        #:name
        "The exact ref should win over the copies under it")
      (assert-equal #:expect "a1fadeb4bb96422bc0ca1f63e302da5b62575dd7"
        #:got (ls-remote-commit ls-remote-listing "refs/heads/trunk")
        #:name
        "A branch named later in the listing should still be found")
      (assert-equal #:expect #f
        #:got (ls-remote-commit ls-remote-listing "refs/heads/master-old")
        #:name
        "A ref that only starts the same way should not be taken for the branch")
      (assert-equal #:expect #f
        #:got (ls-remote-commit "" "refs/heads/master")
        #:name
        "An empty listing should answer nothing rather than raise"))))

(define (spec)
  (veritas-run updates-suite))
