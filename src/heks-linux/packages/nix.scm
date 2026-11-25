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
;;; encoder the capture program prefers;
;;; - the dev tooling the distribution does not package: the Rust components a
;;; @command{rustup} toolchain only grows on request, Kotlin, Gradle and the
;;; two JVM language servers, the database shells and clients, and the Guile
;;; modules openSUSE has no package for.  Each category says in its own
;;; comment why that package lives here rather than in the Zypper list.
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
                        nix-package-priority
                        nix-attribute?
                        nix-installable
                        nix-add-args
                        heks-linux-language-server-nix
                        heks-linux-disk-image-nix
                        heks-linux-capture-nix
                        heks-linux-shell-nix
                        heks-linux-desktop-nix
                        heks-linux-rust-nix
                        heks-linux-jvm-nix
                        heks-linux-database-nix
                        heks-linux-scheme-nix
                        heks-linux-lsp-nix
                        heks-linux-python-nix
                        heks-linux-utility-nix
                        heks-linux-nix
                        nix-profile
                        nix-profile-elements
                        nix-profile-packages
                        nix-profile-name
                        nix-profile-elements-of
                        nix-backend
                        nix-argv
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
  (%make-nix-package attribute priority) nix-package?
  (attribute nix-package-attribute)
  (priority nix-package-priority))

(define (nix-priority? priority)
  "Return whether @var{priority} can be handed to @command{nix profile add}.
A priority is a positive integer, and a lower number wins: 5 is what Nix gives
an element it is not told about."
  (and (exact-integer? priority) (positive? priority)))

(define* (nix-package attribute #:key priority)
  "Declare one nixpkgs package by its @var{attribute} path.
Symbols are accepted for the convenience of a REPL, but the declarations use
strings.  The attribute is checked with @code{nix-attribute?} and a malformed one
is an error, rather than a package that silently fails to install.

@var{priority} is for a package that ships a file another declared package also
ships: @command{nix profile add} refuses the second of the pair unless it is
told which copy wins.  It is a positive integer, lower wins, and it is left out
when the package collides with nothing.

@example
(nix-package \"yaml-language-server\")
@end example"
  (let* ((attribute (if (symbol? attribute)
                      (symbol->string attribute) attribute)))
    (unless (nix-attribute? attribute)
      (error "nix-package: not a nixpkgs attribute:" attribute))
    (unless (or (not priority) (nix-priority? priority))
      (error "nix-package: not a priority:" priority))
    (%make-nix-package attribute priority)))

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

(define (nix-add-args package)
  "Return the @command{nix profile add} arguments for @var{package}.

The installable is the flake at the root, and the priority - when the package
declares one - is the flag @command{nix profile add} takes to settle a file two
packages ship.  Building the vector here is what keeps a priority out of the
installer's hands: the declaration says it, this turns it into arguments.

@example
(nix-add-args (nix-package \"kotlin-language-server\" #:priority 6))
@result{} (\"profile\" \"add\" \".#kotlin-language-server\" \"--priority\" \"6\")
@end example"
  (append (list "profile" "add" (nix-installable package))
          (if (nix-package-priority package)
            (list "--priority"
                  (number->string (nix-package-priority package)))
            '())))

(define* (nix-argv #:rest args)
  "Return a @command{nix} argument vector for @var{args}, the features on.

@command{nix profile} and the flake at the root are Nix's experimental
commands: a machine whose @file{/etc/nix/nix.conf} does not name them answers
every task in this tree with a sentence about a feature rather than about a
package.  The image carries that line, and a person's own machine has whatever
it has, so the flags travel with the vector and the tasks depend on neither.
They come before the subcommand, which is where @command{nix} reads them.

@example
(nix-argv \"profile\" \"list\")
@result{} (\"nix\" \"--extra-experimental-features\" \"nix-command flakes\"
    \"profile\" \"list\")
@end example"
  (append (list "nix" "--extra-experimental-features" "nix-command flakes")
          args))

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

;;; The rest of the desktop the collection carries.  The dock and heks-toon are
;;; programs rather than dotfiles - the dock's own configuration is rendered by
;;; `maak home-reconfigure' like every other surface - so they belong on this
;;; list, and a machine that runs `maak install-nix-packages' gets a desktop with
;;; a dock and a keyboard reference instead of a bare session.  They come from
;;; the same flake as the shell, so `maak update-nix' moves all three together.
(define heks-linux-desktop-nix
  (make-parameter (list (nix-package "lambdock")
                        (nix-package "heks-toon"))))

;;; The Rust tooling that no openSUSE repository packages.  rustup, cargo,
;;; cargo-audit, sccache, mold and lld are in the Zypper list; these are the
;;; pieces a rustup toolchain only grows after `rustup component add', pinned
;;; here so a fresh machine has them without that step, plus the two cargo
;;; subcommands openSUSE does not carry.  The nix copies do not replace the
;;; toolchain: they work on any crate because rustfmt and clippy read source.
(define heks-linux-rust-nix
  (make-parameter (list (nix-package "rust-analyzer")
                        (nix-package "clippy")
                        (nix-package "rustfmt")
                        (nix-package "cargo-nextest")
                        (nix-package "cargo-watch"))))

;;; The JVM tooling the distribution does not carry.  Kotlin's compiler and
;;; language server and the Eclipse JDT server are here, because a Kotlin or
;;; Java buffer in the editor is worth nothing without its server.  Gradle was
;;; here for the JDK it drives and is a Void package now, so it moved to the
;;; xbps list.
;;;
;;; kotlin and kotlin-language-server both ship lib/annotations-13.0.jar, so
;;; `nix profile add' refuses the second of the pair unless one of them is told
;;; how to settle it: priority 6 puts the server's copy behind the compiler's.
;;; They are the same jar, so whichever wins, both programs work.
(define heks-linux-jvm-nix
  (make-parameter (list (nix-package "kotlin")
                        (nix-package "kotlin-language-server" #:priority 6)
                        (nix-package "jdt-language-server")
                        (nix-package "clojure-lsp"))))

;;; The database clients no openSUSE repository packages.  postgresql, mariadb
;;; and valkey are in the Zypper list; these read the same servers from a shell
;;; (pgcli, mycli, usql), from a window (dbeaver) or not at all (duckdb,
;;; sqlite-utils).  No server is installed from here: a database is a service
;;; the machine runs, not a dotfile this configuration renders.
(define heks-linux-database-nix
  (make-parameter (list (nix-package "pgcli")
                        (nix-package "mycli")
                        (nix-package "usql")
                        (nix-package "dbeaver-bin")
                        (nix-package "duckdb")
                        (nix-package "sqlite-utils"))))

;;; The Scheme and Lisp tooling openSUSE lacks: the two Guile modules it has no
;;; package for, and a second implementation to read the standard against.
;;; guile, guile-devel, emacs, sbcl, racket, clisp and ecl are in the Zypper
;;; lists.
(define heks-linux-scheme-nix
  (make-parameter (list (nix-package "guile-lib")
                        (nix-package "guile-ssh")
                        (nix-package "chicken"))))

;;; The language servers no openSUSE repository packages.  eglot starts one per
;;; buffer, and a server that is not on PATH is a buffer with no completion,
;;; hover or rename: TypeScript's server needs the compiler beside it, Pyright
;;; is the Python one, and the C in this tree - heks-toon through Meson, a Guix
;;; checkout through CMake - is read through Meson's and CMake's.  Clangd is
;;; not here: openSUSE's clang package carries it, and clang-tidy and
;;; clang-format beside it.
(define heks-linux-lsp-nix
  (make-parameter (list (nix-package "typescript")
                        (nix-package "typescript-language-server")
                        (nix-package "pyright")
                        ;; openSUSE dropped nodejs-bash-language-server, so the
                        ;; flake is where the Bash server comes from now.
                        (nix-package "bash-language-server")
                        (nix-package "mesonlsp")
                        (nix-package "cmake-language-server"))))

;;; The Python tooling the distribution does not carry.  ruff is the formatter
;;; and the linter at once, and heks-emacs' doctor names it; openSUSE has no
;;; package for it.
(define heks-linux-python-nix
  (make-parameter (list (nix-package "ruff"))))

;;; Utilities the distribution does not carry, and heks-emacs' doctor names:
;;; OpenTofu for the dev-project commands and mongosh for the database menu.
;;; pandoc was here for the document formats a note is exported to and is a Void
;;; package now, so it moved to the xbps list.
;;;
;;; OpenTofu rather than Terraform: Terraform has been under the BUSL since 1.6,
;;; and this flake does not turn on unfree packages for one program.  OpenTofu
;;; is the MPL fork with the same command line, and the Emacs module runs
;;; whatever `terraform-command' names, so pointing that at `tofu' is one line
;;; in the machine's own configuration.
(define heks-linux-utility-nix
  (make-parameter (list (nix-package "opentofu")
                        (nix-package "mongosh"))))

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
                              (heks-linux-shell-nix)
                              (heks-linux-desktop-nix)
                              (heks-linux-rust-nix)
                              (heks-linux-jvm-nix)
                              (heks-linux-database-nix)
                              (heks-linux-scheme-nix)
                              (heks-linux-lsp-nix)
                              (heks-linux-python-nix)
                              (heks-linux-utility-nix))
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
  (nix-profile-elements
   (or (syscall (string-join (nix-argv "profile" "list") " ") #:silent? #t) "")))

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
  "Run @var{args} with @command{nix}, the experimental features on.

@var{args} is a @command{nix} vector as @code{nix-argv} builds it - the program
first - so the flags the tasks depend on travel with every command."
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
          (unless (run-nix (apply nix-argv (nix-add-args package)))
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
                                   (run-nix (append (nix-argv "profile" "remove")
                                                    (list (car element)))))
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
