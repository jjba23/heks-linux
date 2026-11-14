;;; heks-linux
;;;
;;; SPDX-License-Identifier: MIT
;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;;
;;; The Nix side of the package lists: what openSUSE does not carry.
;;;
;;; A package belongs here only when the distribution's own repositories do not
;;; have it.  Zypper upgrades what it installed along with the rest of the system,
;;; while every Nix package is another profile generation to keep current, so the
;;; two lists stay apart instead of naming the same tool twice.
;;;
;;; What lands here is the tooling around the code this configuration is written
;;; in and the legacy image formats it has to read:
;;;
;;; - the language servers no openSUSE package provides: @code{nil} for Nix
;;; (the flake at the root), @code{yaml-language-server} for the CI workflows
;;; and the desktop's YAML, @code{marksman} for the Markdown half of the
;;; documentation, and @code{vscode-langservers-extracted}, which is the JSON,
;;; CSS and HTML servers in one package.  Bash, Lua and TOML servers are
;;; packaged by openSUSE and live in @code{(heks-linux packages zypper)}
;;; instead;
;;; - the readers for .dmg disk images that only Nix packages:
;;; @code{undmg} unpacks a @file{.dmg} into the HFS+ volume inside it, and
;;; @code{hfsprogs} provides the @command{fsck.hfsplus} and
;;; @command{mkfs.hfsplus} that check and rebuild that volume;
;;; - the capture tooling openSUSE does not carry: @code{satty} and
;;; @code{swappy} to annotate a screenshot, and @code{gifski} for the GIF
;;; encoder the capture program prefers.
;;;
;;; The declaration is a list of attributes rather than installables, so the
;;; @code{.#} prefix the installer needs is built in exactly one place
;;; (@code{nix-installable}) and an attribute that is not an attribute cannot
;;; reach a command line.  Installing from the flake at the root of the checkout -
;;; rather than from @code{nixpkgs#} - is what makes @file{flake.lock} the pin the
;;; machine gets: the registry entry answers with whatever nixpkgs it currently
;;; points at, which is a different set of builds on the next machine and on the
;;; next day.
;;;
;;; @code{install-nix-packages} reads the profile first: a package it already
;;; holds is skipped, because @command{nix profile install} refuses a package
;;; twice and the profile is not emptied between runs, and one that came from the
;;; registry is removed and installed again, because a machine that installed
;;; from the registry would otherwise keep following it and never see the pin.
;;;
;;; The categories are parameters, so a machine adds to them from
;;; @file{$XDG_CONFIG_HOME/heks-linux/nix-settings.scm} without forking the
;;; module.

;;; Code:

(define-module (heks-linux packages nix)
  #:declarative? #t
  #:use-module (heks-linux packages)
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:export (nix-package nix-package?
                        nix-package-attribute
                        nix-attribute?
                        nix-installable
                        heks-linux-language-server-nix
                        heks-linux-disk-image-nix
                        heks-linux-capture-nix
                        heks-linux-shell-nix
                        heks-linux-nix
                        nix-profile
                        nix-profile-elements
                        nix-profile-packages
                        nix-profile-name
                        nix-profile-elements-of
                        nix-backend
                        install-nix-packages))

;;; --- Declaring a package ---

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
  (let* ((attribute (if (symbol? attribute)
                      (symbol->string attribute) attribute)))
    (unless (nix-attribute? attribute)
      (error "nix-package: not a nixpkgs attribute:" attribute))
    (%make-nix-package attribute)))

(define (nix-installable package)
  "Return the installable for @var{package}: its attribute of this flake.

@code{.#} is the flake at the root of the checkout the task runs in, and its
@file{flake.lock} pins nixpkgs and nix-jointhefreeworld.  That pin is the point:
@code{nixpkgs#} comes from whatever the registry entry points at, so two
machines that ran the old installer could hold different builds of the same
attribute, and neither of them held the one a checkout of this repository says.

@example
(nix-installable (nix-package \"nil\"))
@result{} \".#nil\"
@end example"
  (string-append ".#" (nix-package-attribute package)))

;;; --- The lists ---

;;; The editor's language servers that no openSUSE repository packages.  nil is
;;; the Nix one - the flake at the root of this repository is the first file it
;;; opens here - and marksman covers the Markdown that docs/ and the generated
;;; API reference are written in.
(define heks-linux-language-server-nix
  (make-parameter (list (nix-package "yaml-language-server")
                        (nix-package "nil")
                        (nix-package "marksman")
                        ;; The JSON, CSS and HTML servers in one package: the
                        ;; three of them are one release of the VS Code
                        ;; extensions, so they are installed together or not at
                        ;; all.
                        (nix-package "vscode-langservers-extracted"))))

;;; The .dmg disk-image readers.  dmg2img (in the Zypper list) only converts a
;;; compressed .dmg, so unpacking it into files is undmg's job; hfsprogs then
;;; checks and rebuilds the HFS+ volume that came out - on Linux its two programs
;;; are fsck.hfsplus and mkfs.hfsplus.  Neither is packaged by openSUSE.
(define heks-linux-disk-image-nix
  (make-parameter (list (nix-package "undmg")
                        (nix-package "hfsprogs"))))

;;; The capture and annotation tooling that no openSUSE repository packages:
;;; satty is the annotation editor heks-capture opens first, swappy is the one it
;;; falls back to when satty is absent, and gifski encodes better GIFs than the
;;; ffmpeg palette fallback.  gifsicle, ffmpeg, ImageMagick, grim, slurp and the
;;; recorders are all in the Zypper list, so only these three live here.
(define heks-linux-capture-nix
  (make-parameter (list (nix-package "satty")
                        (nix-package "swappy")
                        (nix-package "gifski"))))

;;; The desktop shell.  It is here rather than in the Zypper list because no
;;; openSUSE repository carries it, and here rather than in a task of its own
;;; because it is not a special case: the flake at the root exports it, the same
;;; way it exports heks-toon, so `maak install-nix-packages' puts it on the
;;; machine and `maak update-nix' moves it with everything else.
;;;
;;; One package for four programs: whelk is the bar, the launcher, the
;;; notification daemon and the lock screen this configuration used to render a
;;; file for each.
(define heks-linux-shell-nix
  (make-parameter (list (nix-package "whelk"))))

(define (heks-linux-nix)
  "Return every Nix package, deduplicated and sorted by attribute.
The result is the union of the category parameters, read at call time so a
local override is observed, and sorted by attribute so the installation order is
stable and a duplicate declaration in two categories cannot install twice.

@example
(map nix-package-attribute (heks-linux-nix))
@end example"
  (package-sorted-set (append (heks-linux-language-server-nix)
                              (heks-linux-disk-image-nix)
                              (heks-linux-capture-nix)
                              (heks-linux-shell-nix))
                      nix-package-attribute))

;;; --- Installing ---

(define (nix-installed?)
  "Return @code{#t} when a @command{nix} program is on @env{PATH}."
  (let ((path (syscall "command -v nix" #:silent? #t)))
    (and path (not (string-null? path)))))

;;; The origin @command{nix profile list} prints for an element installed from
;;; @code{nixpkgs#}: the registry entry, which pins nothing.  An element installed
;;; from the flake at the root prints the store path that flake was copied to
;;; instead, and that is how the installer tells the two apart.
(define nix-registry-origin
  "flake:nixpkgs")

(define (split-profile-elements lines)
  "Split @var{lines} of @command{nix profile list} at every @code{Name:} line.
Each element is a list of the lines that describe it, so a field added to the
listing lands inside one element's lines rather than between two."
  (let loop
    ((lines lines)
     (current '())
     (elements '()))
    (cond
      [(null? lines)
       (reverse (if (null? current)
                  elements
                  (cons (reverse current) elements)))]
      [(string-prefix? "Name:" (car lines))
       (loop (cdr lines)
             (list (car lines))
             (if (null? current)
               elements
               (cons (reverse current) elements)))]
      [else (loop (cdr lines)
                  (cons (car lines) current)
                  elements)])))

(define display-escape
  (make-regexp "\x1b\\[[0-9;]*m"))

(define (strip-display-escapes text)
  "Return @var{text} without the ANSI sequences a coloured listing carries.

@command{nix profile list} prints each element's name in bold, and it does so
whether or not its output is a terminal - `NO_COLOR' and `TERM=dumb' do not turn
it off, and it has no `--color' flag.  A name read with the escapes still on it
is not the attribute it names, so every lookup against that name misses: the
installer decided the profile was empty and tried to install everything again,
which is the one thing `nix profile add' refuses.

@example
(strip-display-escapes \"\\x1b[1mnil\\x1b[0m\")
@result{} \"nil\"
@end example"
  (regexp-substitute/global #f display-escape text 'pre 'post))

(define (nix-profile-elements listing)
  "Return a @command{nix profile list} @var{listing} as @code{(NAME . ORIGIN)} pairs.

@var{origin} is the flake the element was originally installed from:
@code{flake:nixpkgs} for the registry, a store path for one installed from a
checkout.  An element whose listing has no origin field is reported with the
empty string, so a version of Nix that stops printing it leaves the profile
recognisable rather than everything in it looking absent.  The bold a coloured
listing puts around each name is removed; see @code{strip-display-escapes}.

@example
(nix-profile-elements \"Name:  nil\\nOriginal flake URL: flake:nixpkgs\\n\")
@result{} ((\"nil\" . \"flake:nixpkgs\"))
@end example"
  (define (field element prefix)
    (let ((line (find (lambda (line)
                        (string-prefix? prefix line))
                      element)))
      (and line
        (strip-display-escapes
         (string-trim-both (substring line (string-length prefix)))))))
  (filter-map (lambda (element)
                (let ((name (field element "Name:")))
                  (and name
                    (cons name (or (field element "Original flake URL:") "")))))
              (split-profile-elements (string-split listing #\newline))))

(define (nix-profile)
  "Return the current @command{nix profile} as `nix-profile-elements' reads it.
A profile that cannot be listed answers with no elements, which makes the
installer try every package: the failure that follows names the package instead
of leaving the profile silently short."
  (nix-profile-elements (or (syscall "nix profile list" #:silent? #t) "")))

(define (nix-profile-packages)
  "Return the package names the current @command{nix profile} holds."
  (map car (nix-profile)))

(define (nix-profile-name element-name)
  "Return the attribute a profile element's @var{element-name} belongs to.

@command{nix profile add} names an element after the package, and appends
@code{-1}, @code{-2} and so on when that name is taken.  A profile that has been
through the registry-to-flake migration therefore holds @code{gifski} and
@code{gifski-1} at once, and both of them provide @code{gifski} - which matters,
because the registry pins nothing and the flake pins everything, so the two are
the same attribute and not two packages.

@example
(nix-profile-name \"gifski-1\")
@result{} \"gifski\"
@end example"
  (let ((suffix (string-contains element-name "-"
                                 (max 0 (- (string-length element-name) 6)))))
    (if (and suffix
          (let ((rest (substring element-name (1+ suffix))))
            (and (positive? (string-length rest))
              (string->number rest))))
      (substring element-name 0 suffix)
      element-name)))

(define (nix-profile-elements-of present attribute)
  "Return every element of @var{present} that provides @var{attribute}.

@var{present} is a profile as @code{nix-profile} reads it, and an element
provides @var{attribute} when its name is that attribute or that attribute with
a @code{-N} suffix - see @code{nix-profile-name}."
  (filter (lambda (element)
            (string=? (nix-profile-name (car element)) attribute))
          present))

(define (run-nix args)
  "Run @var{args} with @command{nix} and report whether it succeeded."
  (run-package-command (car args) (cdr args)))

(define (install-nix-package-list packages)
  "Install @var{packages} into the current Nix profile.

A package the profile already holds is skipped, because
@command{nix profile add} refuses one that is there and the task has to be
safe to re-run - unless every copy of it came from @code{flake:nixpkgs}, the
registry entry that pins nothing.  Those are removed and installed again: a
machine that has been installing from the registry would otherwise keep
following it, and the lock would never reach it.  Copies are matched by
attribute rather than by element name, so a profile that holds @code{gifski}
and @code{gifski-1} - which is what the migration leaves behind, because
@command{nix profile add} appends @code{-1} to a name that is taken - counts as
holding one package and hands both copies to the removal.

A failure is reported at the end with every attribute that did not install,
rather than stopping at the first one: the network is usually what went wrong,
and the rest of the list is still wanted."
  (if (not (nix-installed?))
    (error "install-nix-package-list: nix is not on PATH")
    (let ((present (nix-profile))
          (failed '()))
      (define (install package)
        (let ((attribute (nix-package-attribute package)))
          (unless (run-nix (list "nix" "profile" "add"
                                 (nix-installable package)))
            (set! failed (cons attribute failed)))))
      (for-each (lambda (package)
                  (let* ((attribute (nix-package-attribute package))
                         (elements (nix-profile-elements-of present attribute)))
                    (cond
                      [(null? elements) (install package)]
                      [(every (lambda (element)
                                (string=? (cdr element) nix-registry-origin))
                              elements)
                       ;; Every copy came from the registry, which pins nothing:
                       ;; the pinned build takes their place.  All of them go,
                       ;; because `nix profile add' refuses a second element with
                       ;; the same store path as one it already holds.
                       (format #t "~a came from ~a; replacing it from this flake\n"
                               attribute (cdr (car elements)))
                       (for-each (lambda (element)
                                   (run-nix (list "nix" "profile" "remove"
                                                  (car element))))
                                 elements)
                       (install package)]
                      [else
                        (format #t "~a is already in the nix profile\n"
                                attribute)])))
                packages)
      (unless (null? failed)
        (error "install-nix-package-list: could not install:"
               (reverse failed)))
      (format #t "\nThe nix profile carries every package in (heks-linux-nix).\n"))))

(define nix-backend
  (package-backend 'nix
                   #:packages heks-linux-nix
                   #:name-of nix-package-attribute
                   #:name-valid? nix-attribute?
                   #:install install-nix-package-list))

(define (install-nix-packages)
  "Install every package in @code{(heks-linux-nix)} into the current Nix profile.

Each package is installed with @code{nix profile add .#<attribute>}: the flake at
the root of this checkout, whose @file{flake.lock} pins nixpkgs and
nix-jointhefreeworld, so it is the same build on every machine that runs the
task.  @code{maak update-nix} upgrades them with the rest of the profile.

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
  (package-backend-install nix-backend (heks-linux-nix)))
