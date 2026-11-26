;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for the documentation itself.
;;
;; The manual is a directory of Org pages, and a page rots in ways nobody reads a
;; diff for: a link to a file that was renamed, a page that no table ever grows an
;; entry for, a title that was a heading and left the page starting at two stars.
;; Each of those is mechanical, so each is a test rather than a habit.
;;
;; The last suite is the one that keeps the instructions honest: Void is the
;; distribution this tree is written for, and a paragraph that tells a reader to
;; enable a unit or refresh a package manager this machine does not run is a
;; paragraph that sends them somewhere the tree has never been.

;;; Code:

(define-module (veritas unit docs-spec)
  #:use-module (veritas veritas)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

;; The pages that sit beside the manual, not in it.
(define manual-pages
  '("README.org" "HACKING.org"))

;; The words that describe a machine this tree does not run on: another init
;; system, another package manager, and the policy modules that go with them.
;; They are foreign in a page about Void, which is the path, and native in a page
;; about Debian, which is the second target.  `debian-pages' is every page that
;; may legitimately name them - the two Debian pages, and the three that map both
;; targets - and the list is written out rather than derived, so adding a page is
;; a decision somebody makes here.
(define foreign-words
  '("systemd" "systemctl" "openSUSE" "zypper" "SELinux" "Fedora"))

(define debian-pages
  '("README.org"
    "docs/index.org"
    "docs/installation.org"
    "docs/install-debian.org"
    "docs/debian-image.org"))

;; What the page that installs Heks on Void may not tell a reader to run: the
;; other target's package manager and init tool.  A Void instruction that names
;; either is an instruction that stops at "command not found".
(define wrong-on-void-words
  '("apt-get" "apt install" "systemctl"))

(define (slurp path)
  "Return the whole of @var{path} as a string."
  (call-with-input-file path get-string-all))

(define (contains? haystack needle)
  "Return @code{#t} when @var{needle} occurs in @var{haystack}, case folded."
  (not (eq? #f (string-contains-ci haystack needle))))

(define (pages)
  "Return every Org page under @file{docs/}, sorted."
  (map (lambda (name) (string-append "docs/" name))
       (scandir "docs/"
                (lambda (name) (string-suffix? ".org" name)))))

(define (file-links text)
  "Return the @code{file:} targets in @var{text}, without anchors or brackets.

A link is written @code{[[file:docs/x.org::#anchor][what a reader sees]]}, and
the part before @code{::} is the file.  A target ending in a slash is the
directory @code{[[file:docs/]]} means."
  (let ((pattern (make-regexp "\\[\\[file:([^]]+)\\]")))
    (let loop ((start 0) (found '()))
      (let ((match (regexp-exec pattern text start)))
        (if (not match)
          (reverse found)
          (loop (match:end match)
                (cons (car (string-split (match:substring match 1) #\:))
                      found)))))))

(define (dangling-links page)
  "Return the links in @var{page} that point at nothing, as PAGE LINK pairs.

Org resolves a link against the directory of the page that holds it, which is
what lets a page under @file{docs/} say @code{file:void-image.org}."
  (let ((directory (dirname page)))
    (filter-map (lambda (path)
                  (let ((resolved (if (string-prefix? "/" path)
                                    path
                                    (string-append directory "/" path))))
                    (and (not (file-exists? resolved))
                      (cons page path))))
                (file-links (slurp page)))))

(define (unlinked-pages)
  "Return the pages under @file{docs/} that the README never points at.

The README's table is how a page is found; a page nothing links to is a page only
its author knows about."
  (let ((readme (slurp "README.org")))
    (remove (lambda (page) (contains? readme (basename page))) (pages))))

(define (first-heading text)
  "Return the first line of @var{text} that starts a heading, or @code{#f}."
  (find (lambda (line) (string-prefix? "*" line))
        (string-split text #\newline)))

;; The tasks the instructions name that are not this repository's: heks-emacs
;; carries its own maak.scm, and the medium's wizard runs that task in that
;; checkout rather than this one.
(define foreign-tasks
  '("emacs-update"))

(define (task-names)
  "Return every task @file{maak.scm} defines, as a list of names.

Helpers are in the list too: the question these cases ask is whether a name the
manual hands a reader exists at all, not whether it is exported."
  (let ((pattern (make-regexp "^\\(define\\*? \\(([^ )]+)")))
    (filter-map (lambda (line)
                  (let ((match (regexp-exec pattern line)))
                    (and match (match:substring match 1))))
                (string-split (slurp "maak.scm") #\newline))))

(define (named-tasks text)
  "Return the @code{maak COMMAND} names in @var{text}, in its own markup.

Only the names a page writes as a command count: @code{~maak x~} and
@code{=maak x=}.  The same words in prose - @code{guix install maak guile} - are
not a task and are not asked about."
  (let ((pattern (make-regexp "[~=]maak ([a-z][a-z0-9-]*)")))
    (let loop ((start 0) (found '()))
      (let ((match (regexp-exec pattern text start)))
        (if (not match)
          (reverse found)
          (loop (match:end match) (cons (match:substring match 1) found)))))))

(define (shape-cases)
  "Return the cases for the shape every page shares.

@code{#+title:} is what Org exports as the document title, @code{toc:nil} is
what keeps a long page from repeating its own headings at the top, and the back
link is what makes the manual a graph rather than eighteen dead ends."
  (list (assert-equal #:expect '()
          #:got (remove (lambda (page) (contains? (slurp page) "#+title:"))
                        (pages))
          #:name "Every page names itself with #+title")
        (assert-equal #:expect '()
          #:got (remove (lambda (page)
                          (string-prefix? "#+title:" (slurp page)))
                        (pages))
          #:name "And the title is the first thing in the file")
        (assert-equal #:expect '()
          #:got (remove (lambda (page) (contains? (slurp page) "#+options: toc:nil"))
                        (pages))
          #:name "Every page leaves the table of contents out")
        (assert-equal #:expect '()
          #:got (remove (lambda (page) (contains? (slurp page) "file:../README.org"))
                        (pages))
          #:name "Every page leads back to the README")
        (assert-equal #:expect '()
          #:got (filter (lambda (page)
                          (let ((heading (first-heading (slurp page))))
                            (and heading (string-prefix? "**" heading))))
                        (pages))
          #:name "No page starts its headings at two stars")))

(define (link-cases)
  "Return the cases for the links between the pages.

A moved page is a link that lies, and the lie is invisible until a reader follows
it.  The check runs over the README, the contributor's guide and every page under
@file{docs/}, and reports the page and the target, so the fix is one edit."
  (list (assert-equal #:expect '()
          #:got (append-map dangling-links (append manual-pages (pages)))
          #:name "Every file: link points at a file that is there")
        (assert-equal #:expect '()
          #:got (unlinked-pages)
          #:name "Every page is reachable from the README")))

(define (void-cases)
  "Return the cases for the distribution the instructions are written for.

Void is the path: runit for services, xbps for packages.  Three rules, and each
one is about a reader following an instruction rather than about a word:

- no page but the mapping ones names another distribution's init system or
  policy modules;
- the page that installs Heks on Void names neither apt nor systemctl, because
  either one is a command that stops at \"command not found\" on the machine that
  page is for;
- and both targets are named where a reader chooses between them."
  (list (assert-equal #:expect '()
          #:got (filter-map (lambda (page)
                              (let ((text (slurp page)))
                                (and (not (member page debian-pages))
                                  (any (lambda (word) (contains? text word))
                                       foreign-words)
                                  page)))
                            (append manual-pages (pages)))
          #:name "No page about Void names an init system or package manager Void does not use")
        (assert-equal #:expect '()
          #:got (filter (lambda (word)
                          (contains? (slurp "docs/install-void.org") word))
                        wrong-on-void-words)
          #:name "The Void install page tells a reader to run what Void runs")
        (assert-true (contains? (slurp "docs/install-void.org") "xbps-install")
          #:name "Its package manager is Void's own")
        (assert-true (contains? (slurp "README.org") "Void")
          #:name "And the README says which distribution that is")
        (assert-true (contains? (slurp "README.org") "Debian")
          #:name "And which one it runs on second")))

(define (command-cases)
  "Return the cases for the commands the manual hands a reader.

A page that says @code{maak something} and a task that no longer exists is the
worst kind of instruction: it reads as an answer and ends in \"Unknown task\".
The names are compared against the definitions in @file{maak.scm}, and the two
that belong to another checkout are named above rather than guessed at."
  (let ((known (append (task-names) foreign-tasks)))
    (list (assert-equal #:expect '()
            #:got (remove (lambda (name) (member name known))
                          (delete-duplicates
                           (append-map (lambda (page) (named-tasks (slurp page)))
                                       (append manual-pages (pages)))))
            #:name "Every maak command a page names is a task this tree defines"))))

(define docs-suite
  (suite "Documentation Suite"
    (test "Every Page Has The Shape Of A Page" (shape-cases))
    (test "The Pages Link To Things That Exist" (link-cases))
    (test "The Instructions Are Void's" (void-cases))
    (test "The Commands The Manual Names Exist" (command-cases))))

(define (spec)
  (veritas-run docs-suite))
