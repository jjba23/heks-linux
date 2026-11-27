;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The collection's programs, as the two distributions package them.
;;
;; whelk, Lambdock, heks-toon and Maak are programs of their own, and none of
;; them belongs on a Nix list: a desktop that needs a store to draw its bar is a
;; desktop that stops when the store does.  Each one is therefore a package the
;; machine's own manager installs - an xbps package on Void, a .deb on Debian -
;; and this repository is where those packagings live, under `packaging/':
;;
;; - `packaging/void/<name>/template' is the xbps-src recipe, copied from the
;;   program's own tree where it has one, and written here where it does not
;;   (heks-toon ships no packaging).  `maak xbps-build' builds them in a
;;   void-packages checkout;
;; - `packaging/debian/<name>/debian/' is the Debian packaging, in the same
;;   spirit.  `maak deb-build' fetches the release it names, drops this
;;   directory into it and runs `dpkg-buildpackage'.
;;
;; The two packagings must not disagree about which release a machine gets, and
;; the way they are kept in step is that they are not two declarations: the Void
;; template is the source of truth - `version', `homepage', `distfiles' and
;; `checksum' - and `deb-build' reads those same four fields to fetch the same
;; archive and check its digest before it builds anything.  The Debian changelog
;; names the version as well, and `collection-disagreements' is what tells you
;; when the two have drifted apart.
;;
;; What is *not* here: the machines' own packages.  The session, the terminal,
;; the capture stack and the fonts come from the distribution's repositories -
;; see `(heks-linux packages xbps)' and `(heks-linux packages apt)' - and the
;; Nix list keeps the development tooling, which is what Nix is good at and what
;; nothing on the desktop depends on.
;;
;;; Code:

(define-module (heks-linux packages collection)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:use-module (heks-linux packages)
  #:use-module (heks-linux validation)
  #:export (collection-void-directory
            collection-debian-directory
            collection-package?
            collection-package-name
            collection-package-version
            collection-package-archive
            collection-package-checksum
            collection-packages
            collection-package-names
            collection-desktop-names
            collection-template-path
            collection-debian-path
            collection-debian-package?
            debian-changelog-version
            debian-upstream-version
            collection-disagreements
            collection-manager
            collection-install-argv
            collection-built-files
            collection-files-for-desktop
            install-collection
            build-debs))

;; ===========================================
;; Where the packagings live
;; ===========================================

(define collection-void-directory
  "packaging/void")

(define collection-debian-directory
  "packaging/debian")

;; The programs a desktop needs, which is what `install-collection' installs.  It
;; is not every package this repository builds: Maak is the task runner, and a
;; machine that has it from a Guix profile or a Nix profile is not missing
;; anything by leaving the packaged one alone.
(define collection-desktop-names
  '("whelk" "lambdock" "heks-toon"))

;; ===========================================
;; Reading a Void template
;; ===========================================

(define (template-assignment line)
  "Return the @code{(NAME . VALUE)} a template @var{line} assigns, or @code{#f}.

A template is shell, so a value may be quoted either way or not at all, and it
may name another field: @code{distfiles=\"${homepage}/archive/v${version}.tar.gz\"}.
The name is read as an identifier; a comment, a function or a blank line is not
an assignment and answers @code{#f}."
  (let ((match (regexp-exec (make-regexp "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
                            line)))
    (and match
      (cons (match:substring match 1) (unquote-shell (match:substring match 2))))))

(define (unquote-shell value)
  "Return @var{value} without one layer of matching shell quotes."
  (let ((length (string-length value)))
    (if (and (> length 1)
          (or (and (char=? #\" (string-ref value 0))
                (char=? #\" (string-ref value (- length 1))))
            (and (char=? #\' (string-ref value 0))
              (char=? #\' (string-ref value (- length 1))))))
      (substring value 1 (- length 1))
      value)))

(define (template-fields text)
  "Return the assignments of a Void template @var{text} as an alist."
  (filter-map template-assignment (string-split text #\newline)))

(define (expand-template-vars text fields)
  "Return @var{text} with every @code{${NAME}} replaced by its value in @var{fields}.

Two passes, because a field may name another: @code{wrksrc=\"${pkgname}\"} is one
level deep and @code{distfiles} may name @code{homepage}, which names nothing.
An unknown name is left as it was written, so a template that uses a variable
this reader does not know is visible rather than silently empty."
  (let loop
    ((text text)
     (pass 0))
    (if (= pass 2)
      text
      (loop (fold (lambda (field accumulated)
                    (string-replace-all accumulated
                                        (format #f "${~a}" (car field))
                                        (cdr field)))
                  text
                  fields)
            (+ pass 1)))))

(define (string-replace-all text needle replacement)
  "Return @var{text} with every @var{needle} replaced by @var{replacement}.

It walks the string rather than building a regular expression, because the needle
is a template variable and a template variable is a literal: a name this reader
did not invent has no business being read as a pattern."
  (if (or (string-null? needle) (string-null? text))
    text
    (let loop
      ((start 0)
       (pieces '()))
      (let ((at (string-contains text needle start)))
        (cond
          [(not at)
           (string-concatenate (reverse (cons (substring text start) pieces)))]
          [else
            (loop (+ at (string-length needle))
                  (cons replacement
                        (cons (substring text start at) pieces)))])))))

(define-record-type <collection-package>
  (%make-collection-package name version archive checksum)
  collection-package?
  (name collection-package-name)
  (version collection-package-version)
  (archive collection-package-archive)
  (checksum collection-package-checksum))

(define (collection-template-path name)
  "Return the path of @var{name}'s Void template in this checkout."
  (format #f "~a/~a/template" collection-void-directory name))

(define (template-paths)
  "Return every template under `packaging/void', sorted by package name."
  (if (file-exists? collection-void-directory)
    (sort (filter-map (lambda (name)
                        (let ((path (collection-template-path name)))
                          (and (file-exists? path) path)))
                      (scandir collection-void-directory
                               (lambda (name)
                                 (not (member name '("." ".."))))))
          string<?)
    '()))

(define (slurp path)
  "Return the whole of @var{path} as a string."
  (call-with-input-file path get-string-all))

(define* (collection-package-source template-path)
  "Return the package the Void template at @var{template-path} declares.

The four fields this needs are the template's own: @code{pkgname} names it,
@code{version} is the release, and @code{distfiles} and @code{checksum} are where
that release is fetched from and what its digest is - with the variables the
template uses expanded, so a caller gets a URL it can hand to curl rather than a
line of shell to evaluate."
  (let* ((fields (template-fields (slurp template-path)))
         (field (lambda (name)
                  (let ((entry (assoc name fields)))
                    (and entry
                      (expand-template-vars (cdr entry) fields))))))
    (%make-collection-package (or (field "pkgname")
                                (error "collection-package-source: no pkgname:"
                                       template-path))
                              (or (field "version")
                                (error "collection-package-source: no version:"
                                       template-path))
                              (or (field "distfiles")
                                (error "collection-package-source: no distfiles:"
                                       template-path))
                              (field "checksum"))))

(define (collection-packages)
  "Return every package this repository builds, sorted by name.

Read from `packaging/void' at call time, so a template added there is a package
this tree builds without a second list to update."
  (sort (map collection-package-source (template-paths))
        (lambda (a b)
          (string<? (collection-package-name a)
                    (collection-package-name b)))))

(define (collection-package-names)
  "Return the names of every package this repository builds."
  (map collection-package-name (collection-packages)))

;; ===========================================
;; Reading the Debian packaging
;; ===========================================

(define (collection-debian-path name)
  "Return the path of @var{name}'s Debian packaging in this checkout."
  (format #f "~a/~a/debian" collection-debian-directory name))

(define (collection-debian-package? name)
  "Return @code{#t} when @var{name} has a Debian packaging here."
  (file-exists? (format #f "~a/control" (collection-debian-path name))))

(define (debian-changelog-version name)
  "Return the Debian version @var{name} is packaged at, e.g. @code{0.53.1-1}."
  (let* ((path (format #f "~a/changelog" (collection-debian-path name)))
         (first (if (file-exists? path)
                  (car (string-split (slurp path) #\newline))
                  ""))
         (match (regexp-exec (make-regexp "^[^ ]+ \\(([^)]+)\\)") first)))
    (and match (match:substring match 1))))

(define (debian-upstream-version version)
  "Return @var{version} without the Debian revision: @code{0.53.1-1} is @code{0.53.1}."
  (let ((dash (string-rindex version #\-)))
    (if dash (substring version 0 dash) version)))

(define (collection-disagreements)
  "Return every way the two packagings disagree about a package.

A disagreement is a package this tree builds that Debian has no packaging for, a
Debian changelog with no version, or a changelog version whose upstream half is
not the template's version.  Each one is a machine that would get two different
releases depending on which distribution installed it, which is the one thing
two packagings of one program must not do."
  (append-map (lambda (package)
                (let ((name (collection-package-name package))
                      (version (collection-package-version package)))
                  (cond
                    [(not (collection-debian-package? name))
                     (list (format #f "~a: no Debian packaging" name))]
                    [(not (debian-changelog-version name))
                     (list (format #f "~a: a changelog with no version" name))]
                    [(not (string=? version
                                    (debian-upstream-version
                                     (debian-changelog-version name))))
                     (list (format #f "~a: template says ~a, changelog says ~a"
                                   name
                                   version
                                   (debian-changelog-version name)))]
                    [else '()])))
              (collection-packages)))

;; ===========================================
;; Installing what was built
;; ===========================================

(define (collection-manager)
  "Return the package manager this machine installs local packages with.

@code{'apt} when @command{apt-get} is on @env{PATH}, @code{'xbps} when
@command{xbps-install} is, and @code{#f} when neither is: a machine with neither
is not one of the two distributions this tree packages for."
  (cond
    [(program-on-path? "apt-get") 'apt]
    [(program-on-path? "xbps-install") 'xbps]
    [else #f]))

(define* (collection-built-files manager #:key directory)
  "Return the built package files of this checkout, for @var{manager}, sorted.

@code{dist/deb/*.deb} is what `maak deb-build' leaves and
@code{dist/xbps/*.xbps} is what `maak xbps-build' leaves; the caller asks for the
one its machine installs, and @var{directory} is read only in a test.  An absent
directory is no files rather than an error, so the task that needs them is the
one that says how to make them."
  (let* ((directory (or directory
                      (case manager
                        [(apt) "dist/deb"]
                        [(xbps) "dist/xbps"]
                        [else #f])))
         (suffix (case manager
                   [(apt) ".deb"]
                   [(xbps) ".xbps"]
                   [else #f])))
    (if (and directory suffix (file-exists? directory))
      (sort (filter-map (lambda (name)
                          (and (string-suffix? suffix name)
                            (format #f "~a/~a" directory name)))
                        (scandir directory
                                 (lambda (name)
                                   (not (member name '("." ".."))))))
            string<?)
      '())))

(define (collection-files-for-desktop files)
  "Return the @var{files} that belong to the desktop's own programs.

A build leaves one file per package this repository packages, Maak included; the
desktop needs the other three, and installing the runner a second time - from the
package it is running - is how a machine ends up with two of them."
  (filter (lambda (file)
            (any (lambda (name)
                   (string-prefix? name (basename-of file)))
                 collection-desktop-names))
          files))

(define (basename-of path)
  "Return @var{path} without its directory."
  (let ((slash (string-rindex path #\/)))
    (if slash (substring path (+ slash 1)) path)))

(define (collection-install-argv manager files)
  "Return the argument vector that installs the local packages @var{files}.

@code{sudo} is an argument rather than the beginning of a shell line, and every
file is one argument, the way every installer in this tree is handed a vector.
@command{xbps-install} needs no sync for a file it is given, and
@command{apt-get} is told not to reach for the network by naming the files
themselves rather than package names: a path is what it installs."
  (case manager
    [(apt) (append (list "sudo" "apt-get" "install" "--yes") files)]
    [(xbps) (append (list "sudo" "xbps-install" "--yes") files)]
    [else (error "collection-install-argv: unknown manager:" manager)]))

(define (install-collection)
  "Install the collection's desktop programs from the packages built here.

It refuses when nothing has been built, and names the task that builds it: the
packages are this repository's, not the distribution's, and a machine that has
not run `maak xbps-build' or `maak deb-build' has nothing to install.  What it
installs is whelk, Lambdock and heks-toon - see @code{collection-desktop-names} -
from whichever of the two managers this machine has."
  (let* ((manager (collection-manager))
         (files (and manager
                  (collection-files-for-desktop
                   (collection-built-files manager)))))
    (cond
      [(not manager)
       (error (string-append "no package manager this tree packages for:"
                             " install xbps on Void, or apt on Debian"))]
      [(null? files)
       (error (format #f
                      "nothing built in dist/~a: run ~a first"
                      (if (eq? manager 'apt) "deb" "xbps")
                      (if (eq? manager 'apt) "maak deb-build" "maak xbps-build")))]
      [else
        (format #t "installing ~a with ~a\n"
                (string-join (map basename-of files) " ")
                manager)
        (let ((argv (collection-install-argv manager files)))
          (unless (zero? (apply system* argv))
            (error "installing the collection's packages failed")))])))

;; ===========================================
;; Building the Debian packages
;; ===========================================

(define debian-build-directory
  "dist/deb")

(define (run-step program args)
  "Run @var{program} with @var{args}, and stop when it fails.

The argv is a list and never a shell line: a package name and a path both come
from a template, and neither is handed to a shell to re-parse."
  (format #t "\n$ ~a\n" (string-join (cons program args) " "))
  (unless (zero? (apply system* program args))
    (error (format #f "~a exited non-zero" program))))

(define (in-directory directory thunk)
  "Call @var{thunk} with @var{directory} as the working directory, and come back.

The change is an effect on the process, so it is undone whatever @var{thunk}
does: a build that fails must not leave the next step in the wrong tree."
  (let ((previous (getcwd)))
    (dynamic-wind (lambda () (chdir directory))
      thunk
      (lambda () (chdir previous)))))

(define (write-text! path text)
  "Write @var{text} to @var{path}, and return @var{path}."
  (call-with-output-file path (lambda (port) (display text port)))
  path)

(define* (build-deb package #:key (directory debian-build-directory))
  "Fetch, verify and build @var{package} into @var{directory}.

The archive is the one the package's Void template names, and it is checked
against that template's own checksum before anything is unpacked: one pin, two
packagings.  The tree is unpacked with its top directory stripped - GitHub packs
@file{whelk-0.53.1/} and Codeberg packs @file{heks-toon/} - the vendored
@file{debian/} directory is dropped in, and @command{dpkg-buildpackage} builds a
binary package, which is what a machine installs.  It leaves the .deb beside the
unpacked tree, which is @var{directory} itself."
  (let* ((name (collection-package-name package))
         (version (collection-package-version package))
         (work (format #f "~a/~a-~a" directory name version))
         (archive (format #f "~a/archive.tar.gz" work)))
    (run-step "rm" (list "-rf" work))
    (run-step "mkdir" (list "-p" work))
    (run-step "curl" (list "-fsSL" "-o" archive
                           (collection-package-archive package)))
    (write-text! (format #f "~a/archive.sha256" work)
                 (format #f "~a  ~a\n"
                         (collection-package-checksum package)
                         (basename-of archive)))
    (in-directory work
                  (lambda ()
                    (run-step "sha256sum" (list "-c" "archive.sha256"))))
    (run-step "tar" (list "xzf" archive "-C" work "--strip-components=1"))
    (run-step "cp" (list "-a" (collection-debian-path name)
                         (format #f "~a/debian" work)))
    (in-directory work
                  (lambda ()
                    (run-step "dpkg-buildpackage"
                              (list "-b" "-us" "-uc" "-rfakeroot"))))
    (format #t "~a ~a is built\n" name version)))

(define (build-debs)
  "Build every package in `packaging/debian' into `dist/deb'.

It needs a Debian machine: @command{dpkg-buildpackage}, the toolchain and the
build dependencies each package names.  The result is one .deb per package, which
`maak install-collection' installs and `maak image-debian' puts on the medium."
  (unless (program-on-path? "dpkg-buildpackage")
    (error (string-append "dpkg-buildpackage is not on PATH: this task builds"
                          " Debian packages, so it runs on Debian")))
  (let ((disagreements (collection-disagreements)))
    (unless (null? disagreements)
      (error "the two packagings disagree:" (string-join disagreements "; "))))
  (run-step "mkdir" (list "-p" debian-build-directory))
  (for-each (lambda (package)
              (when (collection-debian-package?
                     (collection-package-name package))
                (build-deb package)))
            (collection-packages))
  (format #t "\nthe packages are in ~a\n" debian-build-directory))
