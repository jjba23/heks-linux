;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The Nix side of the package lists: what openSUSE does not carry.
;;
;; A package belongs here only when the distribution's own repositories do not
;; have it.  Zypper upgrades what it installed along with the rest of the system,
;; while every Nix package is another profile generation to keep current, so the
;; two lists stay apart instead of naming the same tool twice.
;;
;; What lands here is the tooling around the code this configuration is written
;; in and the legacy image formats it has to read:
;;
;;   - the language servers no openSUSE package provides: @code{nil} for Nix
;;     (the flake at the root), @code{yaml-language-server} for the CI workflows
;;     and the desktop's YAML, @code{marksman} for the Markdown half of the
;;     documentation, and @code{vscode-langservers-extracted}, which is the JSON,
;;     CSS and HTML servers in one package.  Bash, Lua and TOML servers are
;;     packaged by openSUSE and live in @code{(heks-linux packages zypper)}
;;     instead;
;;   - the readers for .dmg disk images that only Nix packages:
;;     @code{undmg} unpacks a @file{.dmg} into the HFS+ volume inside it, and
;;     @code{hfsprogs} provides the @command{fsck.hfsplus} and
;;     @command{mkfs.hfsplus} that check and rebuild that volume.
;;
;; The declaration is a list of attributes rather than installables, so the
;; @code{nixpkgs#} prefix the installer needs is built in exactly one place
;; (@code{nix-installable}) and an attribute that is not an attribute cannot
;; reach a command line.  @code{install-nix-packages} reads the profile first and
;; skips what it already holds, because @command{nix profile install} refuses a
;; package twice and the profile is not emptied between runs.
;;
;; The categories are parameters, so a machine adds to them from
;; @file{$XDG_CONFIG_HOME/heks-linux/nix-settings.scm} without forking the
;; module.

;;; Code:

(define-module (heks-linux packages nix)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:export (nix-package nix-package?
                        nix-package-attribute
                        nix-attribute?
                        nix-installable
                        heks-linux-language-server-nix
                        heks-linux-disk-image-nix
                        heks-linux-nix
                        nix-profile-packages
                        install-nix-packages))

;; --- Declaring a package ---

(define (nix-attribute-character? character)
  "Return whether @var{character} may appear in a nixpkgs attribute path.
The allowed set is what attribute names in nixpkgs use: letters, digits, and the
dot, hyphen, underscore and plus that separate or join segments such as
@code{python3Packages.requests} or @code{libfoo-unstable}."
  (or (char-alphabetic? character)
    (char-numeric? character)
    (memv character '(#\. #\- #\_ #\+))))

(define (nix-attribute? attribute)
  "Return @code{#t} when @var{attribute} can name a nixpkgs attribute.
The check is deliberately shallow: a non-empty string that starts with a letter
and holds only attribute characters.  That catches the mistakes that actually
happen - a whole installable pasted in with its @code{nixpkgs#} prefix, a shell
metacharacter, a half-copied entry with a space in it - and it also means an
attribute can never be read as a command-line option, because it cannot start
with a hyphen."
  (and (string? attribute)
    (> (string-length attribute) 0)
    (char-alphabetic? (string-ref attribute 0))
    (every nix-attribute-character? (string->list attribute))))

(define-record-type <nix-package>
  (%make-nix-package attribute) nix-package?
  (attribute nix-package-attribute))

(define* (nix-package attribute)
  "Declare one nixpkgs package by its @var{attribute} path.
Symbols are accepted for the convenience of a REPL, but the declarations use
strings.  The attribute is checked with @code{nix-attribute?} and a malformed one
is an error, rather than a package that silently fails to install.

@example
(nix-package \"yaml-language-server\")
@end example"
  (let ((attribute (if (symbol? attribute)
                     (symbol->string attribute) attribute)))
    (unless (nix-attribute? attribute)
      (error "nix-package: not a nixpkgs attribute:" attribute))
    (%make-nix-package attribute)))

(define (nix-installable package)
  "Return the flake installable for @var{package}.
The @code{nixpkgs#} prefix is written here and nowhere else, so a declaration
cannot carry one and end up installing from a second registry entry.

@example
(nix-installable (nix-package \"nil\"))
@result{} \"nixpkgs#nil\"
@end example"
  (string-append "nixpkgs#" (nix-package-attribute package)))

;; --- The lists ---

;; The editor's language servers that no openSUSE repository packages.  nil is
;; the Nix one - the flake at the root of this repository is the first file it
;; opens here - and marksman covers the Markdown that docs/ and the generated
;; API reference are written in.
(define heks-linux-language-server-nix
  (make-parameter (list (nix-package "yaml-language-server")
                        (nix-package "nil")
                        (nix-package "marksman")
                        ;; The JSON, CSS and HTML servers in one package: the
                        ;; three of them are one release of the VS Code
                        ;; extensions, so they are installed together or not at
                        ;; all.
                        (nix-package "vscode-langservers-extracted"))))

;; The .dmg disk-image readers.  dmg2img (in the Zypper list) only converts a
;; compressed .dmg, so unpacking it into files is undmg's job; hfsprogs then
;; checks and rebuilds the HFS+ volume that came out - on Linux its two programs
;; are fsck.hfsplus and mkfs.hfsplus.  Neither is packaged by openSUSE.
(define heks-linux-disk-image-nix
  (make-parameter (list (nix-package "undmg")
                        (nix-package "hfsprogs"))))

(define (heks-linux-nix)
  "Return every Nix package, deduplicated and sorted by attribute.
The result is the union of the category parameters, read at call time so a
local override is observed, and sorted by attribute so the installation order is
stable and a duplicate declaration in two categories cannot install twice.

@example
(map nix-package-attribute (heks-linux-nix))
@end example"
  (sort (delete-duplicates (append (heks-linux-language-server-nix)
                                   (heks-linux-disk-image-nix))
                           (lambda (a b)
                             (string=? (nix-package-attribute a)
                                       (nix-package-attribute b))))
        (lambda (a b)
          (string<? (nix-package-attribute a) (nix-package-attribute b)))))

;; --- Installing ---

(define (nix-installed?)
  "Return @code{#t} when a @command{nix} program is on @env{PATH}."
  (let ((path (syscall "command -v nix" #:silent? #t)))
    (and path (not (string-null? path)))))

(define (nix-profile-packages)
  "Return the package names the current @command{nix profile} holds.
@command{nix profile list} prints one @code{Name:} line per package (plus two
lines per package for its flake attributes and store paths), so the field is
read rather than the output parsed as a whole.  A profile that cannot be listed
answers with no names, which makes the installer try every package: the failure
that follows names the package instead of leaving the profile silently short."
  (let ((listing (syscall "nix profile list" #:silent? #t)))
    (if listing
      (let loop ((lines (string-split listing #\newline)) (names '()))
        (cond
          [(null? lines)
           (reverse names)]
          [(string-prefix? "Name:" (car lines))
           (let ((words (remove string-null? (string-split (substring (car lines) 5)
                                                           #\space))))
             (loop (cdr lines)
                   (if (pair? words)
                     (cons (car words) names) names)))]
          [else (loop (cdr lines) names)]))
      '())))

(define (run-nix args)
  "Run @var{args} with @command{nix} and report whether it succeeded."
  (format #t "\nExecuting command: ~a\n"
          (string-join args " "))
  (let ((status (apply system* args)))
    (cond
      [(eq? status #f)
       (format (current-error-port) "could not execute ~a\n"
               (string-join args " ")) #f]
      [(zero? status)
       #t]
      [else (format (current-error-port) "nix exited with status ~a: ~a\n"
                    status
                    (string-join args " ")) #f])))

(define (install-nix-packages)
  "Install every package in @code{(heks-linux-nix)} into the current Nix profile.

Each package is installed with @code{nix profile install nixpkgs#<attribute>}, so
it comes from the nixpkgs the flake registry points at rather than from a copy
pinned here; @code{maak update-nix} upgrades them with the rest of the profile.
A package the profile already holds is skipped, because
@command{nix profile install} refuses one that is there and the task has to be
safe to re-run.  A failure is reported at the end with every attribute that did
not install, rather than stopping at the first one: the network is usually what
went wrong, and the rest of the list is still wanted.

Per-machine additions live in
@file{$XDG_CONFIG_HOME/heks-linux/nix-settings.scm}, which is evaluated in this
module's scope before the list is read:

@example
(heks-linux-language-server-nix
 (append (heks-linux-language-server-nix)
         (list (nix-package \\\"zls\\\"))))
@end example"
  (load-local-overrides '(heks-linux packages nix)
                        'nix-settings)
  (if (not (nix-installed?))
    (error "install-nix-packages: nix is not on PATH")
    (let ((present (nix-profile-packages))
          (failed '()))
      (for-each (lambda (package)
                  (let ((attribute (nix-package-attribute package)))
                    (if (member attribute present)
                      (format #t "~a is already in the nix profile\n"
                              attribute)
                      (unless (run-nix (list "nix" "profile" "install"
                                             (nix-installable package)))
                        (set! failed (cons attribute failed))))))
                (heks-linux-nix))
      (unless (null? failed)
        (error "install-nix-packages: could not install:"
               (reverse failed)))
      (format #t "\nThe nix profile carries every package in (heks-linux-nix).\n"))))
