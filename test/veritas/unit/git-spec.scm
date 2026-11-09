;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux git).  The module renders four files from two
;; tables of settings, and the tests read the rendered @file{~/.gitconfig} the
;; way git does: a section header in the first column, one @code{key = value}
;; line under it, and the @code{includeIf} rules still switching identity by
;; the path a repository lives in.

;;; Code:

(define-module (veritas unit git-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux git)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (rendered-gitconfig)
  "Return @file{~/.gitconfig} as @code{install-git-config} writes it.

The renderer is called here rather than the file read, so the tests need no
home directory: the template and the table are the same two arguments the
installer passes."
  (mk-rec-kv-conf-lines gitconfig
                        #:template spaced-equal-conf-pair))

(define (section name)
  "Return the body of the @code{[NAME]} section, without its header.

The body ends at the next section header, so a key written under the wrong
section is a key this does not find."
  (let* ((header (string-append "[" name "]\n"))
         (start (string-contains (rendered-gitconfig) header)))
    (and start
      (let ((rest (substring (rendered-gitconfig)
                             (+ start (string-length header)))))
        (let ((end (string-contains rest "\n[")))
          (if end
            (substring rest 0 end)
            rest))))))

(define (section-contains? name fragment)
  "Return whether the @code{[NAME]} section of @file{~/.gitconfig} has @var{fragment}.

A section the file does not carry contains nothing, so this answers @code{#f}
rather than raising: a missing setting should read as a failed assertion, not as
a test that died."
  (let ((body (section name)))
    (and body
      (not (eq? #f (string-contains body fragment))))))

(define git-suite
  (suite "Git Suite"

    (test "Diffs Are Read Through Delta"
      ;; The pager and the interactive filter are two settings, not one: git
      ;; hands `git add -p' its own patch text, which delta needs to be told
      ;; to colour rather than to page.
      (assert-true (section-contains? "core" "pager = delta\n")
        #:name "Git should page every diff through delta")
      (assert-true (section-contains? "interactive"
                                      "diffFilter = delta --color-only\n")
        #:name
        "And colour the hunks it shows under `git add -p' itself"))

    (test "Delta Moves Between Sections Of A Diff"
      (assert-true (section-contains? "delta" "navigate = true\n")
        #:name
        "n and N should move between the sections of a diff"))

    (test "Conflicts Are Shown Against The Common Ancestor"
      (assert-true (section-contains? "merge" "conflictStyle = zdiff3\n")
        #:name "A conflict should keep the common ancestor in view"))

    (test "The Identity Rules Survive The Delta Settings"
      ;; The includeIf rules are why the file has a shape at all; a setting
      ;; added beside them must not swallow them.
      (assert-true (section-contains? "core" "editor = emacsclient\n")
        #:name "Core should keep the editor the commits are written in")
      (assert-true (section-contains? "core"
                                      "excludesfile = ~/.gitignore-global\n")
        #:name "And the machine-wide ignore list")
      (assert-equal #:expect 4
        #:got
        (length (filter (lambda (line)
                          (string-prefix? "[includeIf " line))
                        (string-split (rendered-gitconfig) #\newline)))
        #:name "One rule for each directory the identity switches on")
      (assert-true (section-contains? "includeIf \"gitdir:~/Work/\""
                                      "  path = ~/.gitconfig-work.ini")
        #:name "The work identity should still be named by its rule"))))

(define (spec)
  (veritas-run git-suite))
