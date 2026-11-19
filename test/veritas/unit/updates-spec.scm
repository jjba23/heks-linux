;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for the update engine, and for the channels reader it leans on.
;;
;; What is worth pinning here is the table: five package managers, each with the
;; program that has to exist, the query that answers what would change and the
;; commands that change it.  A manager with no check command is a manager whose
;; update cannot be previewed, and a manager with no program is one a machine
;; does not have - both are reported rather than guessed.
;;
;; The reader is fed text instead of a forge, so the suite stays hermetic: what
;; is asserted is which pin belongs to which channel, not whether codeberg is up.

;;; Code:

(define-module (veritas unit updates-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux update)
  #:use-module (heks-linux pins)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define scratch-dir
  (format #f "/tmp/heks-updates-spec-~a" (getpid)))

(define pinned-channels-text
  (string-append "(list (channel\n"
                 "        (name 'guix)\n"
                 "        (url \"https://codeberg.org/guix/guix.git\")\n"
                 "        (branch \"master\")\n"
                 "        (commit \"e65da4f38f68390dba0b2799b7d4651b84ec76cc\"))\n"
                 "      (channel\n"
                 "        (name 'jointhefreeworld)\n"
                 "        (url \"https://github.com/jjba23/guix-jointhefreeworld\")\n"
                 "        (branch \"trunk\")\n"
                 "        (commit \"4f92c2d14bdf692aba3d63a616563f6ae7093165\")))\n"))

(define (pinned-channels-file)
  (catch #t (lambda () (mkdir scratch-dir)) (lambda _ #f))
  (let ((path (format #f "~a/channels.scm" scratch-dir)))
    (call-with-output-file path
                           (lambda (port) (display pinned-channels-text port)))
    path))

(define (manager-table-suite)
  (suite "The manager table"
    (test "Five Managers, Each Named Once"
      (let ((names (map manager-name update-managers)))
        (assert-equal #:expect 5
          #:got (length names)
          #:name "The machine is updated from five sources")
        (assert-equal #:expect (length names)
          #:got (length (delete-duplicates names))
          #:name "Two entries for one manager is one entry too many")))
    (test "Every Manager Names A Program And A Label"
      (assert-equal #:expect '()
        #:got (filter (lambda (manager)
                        (or (null? (manager-programs manager))
                          (not (string? (manager-label manager)))))
                      update-managers)
        #:name "A manager without a program cannot be run"))
    (test "The Order Is Stable"
      (assert-equal #:expect '(xbps zypper flatpak nix guix)
        #:got (map manager-name update-managers)
        #:name "The table is read top to bottom, not raced"))))

(define (channel-reader-suite)
  (suite "Channel pins"
    (test "A Channels File Yields One Pin Per Channel"
      (let ((pins (channel-pins (pinned-channels-file))))
        (assert-equal #:expect 2
          #:got (length pins)
          #:name "Two channels, two pins")
        (assert-equal #:expect '("guix" "jointhefreeworld")
          #:got (map pin-name pins)
          #:name "The names come from the file")
        (assert-equal #:expect 'guix-channel
          #:got (pin-kind (car pins))
          #:name "A channel is a channel pin")))
    (test "The Commit Is The Version"
      (assert-equal #:expect "e65da4f38f68390dba0b2799b7d4651b84ec76cc"
        #:got (pin-current (car (channel-pins (pinned-channels-file))))
        #:name "A channel pin is held at a commit"))
    (test "The Remote Is Unknown Until Asked"
      (assert-equal #:expect 'unknown
        #:got (pin-status (car (channel-pins (pinned-channels-file))))
        #:name "Reading a file does not ask the network"))))

(define (spec)
  (veritas-run
    (manager-table-suite)
    (channel-reader-suite)))
