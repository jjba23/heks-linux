;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux pins).
;;
;; The readers are the interesting half: a channels file, a flake lock, a pom and
;; a manifest are four formats that all say one thing - a name and the version it
;; is held at - and each is read as text or data, never evaluated.  What the
;; tests pin is that the four answers agree in shape, that a file that cannot be
;; read answers nothing rather than failing a report, and that a pin whose value
;; the source has not answered is "unknown" rather than "current".

;;; Code:

(define-module (veritas unit pins-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux pins)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 format)
  #:export (spec))

(define (scratch name contents)
  "Write @var{contents} to @var{name} below a temporary directory."
  (let* ((directory (format #f "/tmp/heks-pins-~a" (getpid)))
         (path (format #f "~a/~a" directory name)))
    (catch #t (lambda () (mkdir directory)) (lambda _ #f))
    (call-with-output-file path
                           (lambda (port) (display contents port)))
    path))

(define channels-text
  ";; the pins\n(list (channel\n        (name 'guix)\n        (url \"https://git.savannah.gnu.org/git/guix.git\")\n        (branch \"master\")\n        (commit \"0123456789abcdef0123456789abcdef01234567\"))\n      (channel\n        (name 'nonguix)\n        (url \"https://gitlab.com/nonguix/nonguix\")\n        (branch \"master\")\n        (commit \"fedcba9876543210fedcba9876543210fedcba98\")))\n")

(define pom-text
  "<project>\n  <properties>\n    <guile-veritas.version>0.11.0</guile-veritas.version>\n  </properties>\n  <dependencies>\n    <dependency>\n      <groupId>org.example</groupId>\n      <artifactId>widget</artifactId>\n      <version>1.4.2</version>\n    </dependency>\n  </dependencies>\n</project>\n")

(define manifest-text
  "(specifications->manifest\n (list \"guile-veritas@0.11.0\"\n       \"guile@3.0.9\"))\n")

(define flake-lock-text
  "{\"nodes\": {\"nixpkgs\": {\"locked\": {\"rev\": \"aaaabbbbccccddddeeeeffff0000111122223333\", \"type\": \"github\"}}, \"root\": {\"inputs\": {\"nixpkgs\": \"nixpkgs\"}}}, \"root\": \"root\", \"version\": 7}\n")

(define (names-and-versions pins)
  "Return @var{pins} as (NAME VERSION) pairs, for comparing readers."
  (map (lambda (pin) (list (pin-name pin) (pin-current pin))) pins))

(define (reader-suite)
  (suite "Readers"
    (test "A Channels File Yields One Pin Per Channel"
      (let ((pins (channel-pins (scratch "channels.scm" channels-text))))
        (assert-equal #:expect 2
          #:got (length pins)
          #:name "Two channels, two pins")
        (assert-equal #:expect '("guix" "nonguix")
          #:got (map pin-name pins)
          #:name "The names come from the file")
        (assert-equal #:expect 'guix-channel
          #:got (pin-kind (car pins))
          #:name "A channel is a channel pin")
        (assert-equal #:expect "master"
          #:got (second (pin-locator (car pins)))
          #:name "The branch is kept for the remote check")))
    (test "A Pom Yields Dependencies And Properties"
      (let ((pins (maven-pins (scratch "pom.xml" pom-text))))
        (assert-equal #:expect 2
          #:got (length pins)
          #:name "One dependency and one property")
        (assert-true (not (eq? #f (find (lambda (pin)
                                          (string=? (pin-name pin)
                                                    "org.example:widget"))
                                        pins)))
          #:name "The dependency is named group:artifact")
        (assert-true (any (lambda (pin) (string=? (pin-name pin)
                                                  "guile-veritas.version"))
                          pins)
          #:name "The property is a pin of its own")))
    (test "A Manifest Yields The Versions It Writes Down"
      (let ((pins (manifest-pins (scratch "manifest.scm" manifest-text))))
        (assert-equal #:expect '(("guile-veritas" "0.11.0")
                                 ("guile" "3.0.9"))
          #:got (names-and-versions pins)
          #:name "A name@version string is a pin")))
    (test "A Flake Lock Yields Its Locked Inputs"
      (let ((pins (flake-pins (scratch "flake.lock" flake-lock-text))))
        (assert-equal #:expect '("nixpkgs")
          #:got (map pin-name pins)
          #:name "Only nodes with a locked revision count")
        (assert-equal #:expect 'nix-input
          #:got (pin-kind (car pins))
          #:name "A flake input is Nix's to move")))
    (test "A Missing File Is Not A Failure"
      (assert-equal #:expect '()
        #:got (channel-pins "/tmp/heks-pins-none/channels.scm")
        #:name "A file that is not there says nothing"))))

(define (status-suite)
  (suite "Status"
    (test "A Pin Without An Answer Is Unknown"
      (assert-equal #:expect 'unknown
        #:got (pin-status (pin 'guix-channel "/tmp/c.scm" "guix"
                               "0123456789abcdef0123456789abcdef01234567"))
        #:name "No latest value means unknown, not current"))
    (test "A Pin Whose Branch Moved Is Outdated"
      (assert-equal #:expect 'behind
        #:got (pin-status (pin 'guix-channel "/tmp/c.scm" "guix" "aaaa"
                               #:latest "bbbb"))
        #:name "Two commits are two answers"))
    (test "A Pin At The Tip Is Current"
      (assert-equal #:expect 'current
        #:got (pin-status (pin 'guix-channel "/tmp/c.scm" "guix" "aaaa"
                               #:latest "aaaa"))
        #:name "The same commit twice is current"))))

(define (report-suite)
  (suite "Report"
    (test "The Table Names Every Pin"
      (let* ((pin (pin 'maven "/tmp/pom.xml" "org.example:widget" "1.4.2"
                       #:latest "1.5.0"))
             (text (with-output-to-string
                    (lambda ()
                      (pins-report (list pin)
                                   #:port (current-output-port))))))
        (assert-true (not (eq? #f (string-contains text "org.example:widget")))
          #:name "The name is in the table")
        (assert-true (not (eq? #f (string-contains text "1.5.0")))
          #:name "The answer is in the table")
        ;; The row's format string asked for five values and was given six, and
        ;; Guile's `format' to a port drops the extra rather than refusing it: the
        ;; table printed without its STATUS column, so every report said what was
        ;; pinned and never which of them was behind.
        (assert-true (not (eq? #f (string-contains text "STATUS")))
          #:name "The table names its status column")))
    (test "The JSON Names One Object Per Pin"
      (let* ((pin (pin 'maven "/tmp/pom.xml" "org.example:widget" "1.4.2"
                       #:latest "1.5.0"))
             (text (pins-json (list pin))))
        (assert-true (not (eq? #f (string-contains text "org.example:widget")))
          #:name "The pin is in the document")
        (assert-true (not (eq? #f (string-contains text "current")))
          #:name "The current value is reported")))))

(define (discovery-suite)
  (suite "Discovery"
    (test "A POM One Level Down Is Found"
      ;; `discover-pins' reads a pom at the root and one level down, because
      ;; that is the shape of a Maven reactor.  A discovery that cannot list the
      ;; directory answers nothing, and a report saying the project holds no
      ;; Maven pins reads exactly like a project that holds none.
      (let* ((directory (format #f "/tmp/heks-pins-scan-~a" (getpid)))
             (module (format #f "~a/module" directory)))
        (system* "rm" "-rf" directory)
        (mkdir directory)
        (mkdir module)
        (call-with-output-file (format #f "~a/pom.xml" module)
                               (lambda (port) (display pom-text port)))
        (assert-true (pair? (discover-pins directory))
          #:name "The module's pom is read from the directory it is in")))))

(define (spec)
  (veritas-run
    (reader-suite)
    (status-suite)
    (report-suite)
    (discovery-suite)))
