;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The icon themes: Tela, every colour and brightness variant upstream ships.
;;
;; The desktop wears one of them per palette: the palette's GTK accent picks
;; the colour, and its dark or light classification picks the brightness.  That
;; is why the whole set is installed rather than only the variant in use - a
;; palette switch re-renders GTK, dconf and the dock, and the theme it asks for
;; has to be on disk before the switch happens.
;;
;; Tela is not packaged by openSUSE or by Guix, so the installation is a
;; checkout at a released tag rather than a distribution package - the same
;; shape the WhiteSur cursors and the wallpaper collection have.  The tag is
;; written here and nowhere else, so `maak install-icon-files' puts the same
;; artwork on every machine and `maak update-guix' cannot move it.
;;
;; Upstream ships an installer that renders each variant from its sources, so
;; the checkout is run rather than copied.  The generated themes land in
;; ~/.local/share/icons, which GTK searches before the profile.  That directory
;; is also what the image build checks, so a task that silently installed
;; nothing fails the build instead of shipping a desktop whose icons fall back
;; to hicolor.
;;
;;; Code:

(define-module (heks-linux icons)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (raise-unknown-icon-accent-exception
            tela-icon-accents
            tela-icon-colors
            tela-icon-brightnesses
            tela-icon-theme
            tela-icon-themes
            tela-icon-repository
            tela-icon-checkout-dir
            tela-icon-dir
            install-tela-icons))

(define s
  (scriba-auto-logger))

;; --- The pinned source ---
;;
;; Each entry is (name url tag).  The tag is a release, not a branch: a branch
;; would make two machines that ran the task a week apart wear different
;; artwork, and the palette asks for a theme by name.  Bumping the tag is one
;; line here, the way a channel pin is one line in channels.scm.

(define tela-icon-repository
  '(tela-icon-theme
    "https://github.com/vinceliuice/Tela-icon-theme.git"
    "2026-07-07"))

;; --- The variants ---
;;
;; Upstream's installer takes a colour and a brightness and writes one theme
;; directory per pair.  The colour list is what `install.sh -a' renders; the
;; last four are the distribution and editor colours upstream also ships, kept
;; so the installed set is the complete one even though no palette names them.
;;
;; The standard colour is the bare @code{Tela} directory, which is the blue
;; artwork; every other colour appends its own name.

(define tela-icon-colors
  '("standard" "black" "blue" "brown" "green" "grey" "orange" "pink"
    "purple" "red" "yellow" "manjaro" "ubuntu" "dracula" "nord"))

;; A brightness of "" is the plain theme.  The other two adjust the glyphs for
;; a light or a dark interface, which is what lets the icons follow a palette's
;; own classification rather than only its accent.

(define tela-icon-brightnesses
  '("" "-light" "-dark"))

(define (tela-color-name color)
  "Return the Tela theme directory name for @var{color}.
The standard colour is the bare @code{Tela} directory; every other colour
appends its name to it."
  (if (string=? color "standard")
    "Tela"
    (string-append "Tela-" color)))

(define (tela-icon-themes)
  "Return every theme name @code{install-tela-icons} puts in place.
The result is every colour variant at each brightness, because a palette picks
one and the next palette switch may ask for another."
  (append-map (lambda (color)
                (map (lambda (brightness)
                       (string-append (tela-color-name color) brightness))
                     tela-icon-brightnesses))
              tela-icon-colors))

;; --- Palette accents to colour variants ---
;;
;; A palette names a symbolic GTK accent, and this is where that accent becomes
;; the artwork of the same colour.  Tela ships no aqua, teal, cyan, lime,
;; indigo, navy or sand, so those take the nearest colour it does ship: the
;; cool ones take blue, lime takes green and sand takes yellow.  GTK's
;; `purple', `slate' and `graphite' have no Tela spelling of their own, so they
;; are translated the way GTK itself translates them.
;;
;; The reverse spellings are listed too, because a palette is free to name its
;; accent the way the icons do.

(define tela-icon-accents
  '((red . "red")
    (orange . "orange")
    (yellow . "yellow")
    (lime . "green")
    (green . "green")
    (aqua . "blue")
    (teal . "blue")
    (cyan . "blue")
    (blue . "blue")
    (indigo . "blue")
    (navy . "blue")
    (violet . "purple")
    (purple . "purple")
    (magenta . "pink")
    (pink . "pink")
    (brown . "brown")
    (sand . "yellow")
    (grey . "grey")
    (gray . "grey")
    (graphite . "grey")
    (slate . "grey")
    (black . "black")))

(define (raise-unknown-icon-accent-exception accent)
  "Raise an exception naming an accent that has no Tela icon theme.
Called by @code{tela-icon-theme} so a palette whose @code{gtk-accent} has no
colour variant stops the run instead of quietly wearing a fallback set."
  (raise-exception
   (make-exception-with-message
    (format #f "exception ocurred! unknown icon accent selected: ~a" accent))))

(define* (tela-icon-theme accent #:key dark?)
  "Return the Tela icon theme that matches @var{accent} and @var{dark?}.
@var{accent} is a palette's symbolic GTK accent, which picks the colour
variant.  A dark palette takes the @code{-dark} brightness and a light one
takes @code{-light}, so the icons follow the same accent and contrast as the
rest of the desktop.  An accent Tela has no colour for raises rather than
returning a name nothing installs."
  (string-append (tela-color-name
                  (or (assoc-ref tela-icon-accents accent)
                    (raise-unknown-icon-accent-exception accent)))
                 (if dark? "-dark" "-light")))

;; --- Installing ---
;;
;; `git clone' at the pinned tag, then upstream's installer.  The installer
;; renders each variant from the checkout's sources, so there is nothing to
;; copy: it is run with `-a' for every colour and writes every brightness
;; itself.

(define (tela-icon-checkout-dir)
  "Return the directory the pinned Tela icon checkout lives in."
  (format #f "~a/.config/tela-icons" (or (getenv "HOME") "/tmp")))

(define (tela-icon-dir)
  "Return the user icon directory the Tela themes are installed into.
GTK searches this before the profile, which is what makes the themes here win
over a copy a previous install left behind."
  (format #f "~a/.local/share/icons" (or (getenv "HOME") "/tmp")))

(define (path-exists? path)
  "Return @code{#t} when @var{path} exists, without following a dangling link."
  (catch 'system-error
         (lambda () (lstat path) #t)
         (lambda _ #f)))

(define (delete-tree path)
  "Remove @var{path} and everything below it; a missing path is not an error."
  (when (path-exists? path)
    (let ((info (lstat path)))
      (if (eq? 'directory (stat:type info))
        (begin
          (for-each (lambda (name)
                      (unless (member name '("." ".."))
                        (delete-tree (format #f "~a/~a" path name))))
                    (scandir path))
          (rmdir path))
        (delete-file path)))))

(define (run-command args)
  "Run @var{args} as one program and raise when it exits non-zero."
  (format #t "~%Executing command: ~a~%" (string-join args " "))
  (let ((status (apply system* args)))
    (unless (and status (zero? status))
      (error "install-tela-icons: command failed:" args))))

(define (install-tela-repository! repository)
  "Check @var{repository} out at its pinned tag and run its installer.
@var{repository} is @code{tela-icon-repository}."
  (let* ((name (symbol->string (car repository)))
         (url (cadr repository))
         (tag (caddr repository))
         (checkout (format #f "~a/~a" (tela-icon-checkout-dir) name)))
    (delete-tree checkout)
    (run-command (list "git" "clone" "--quiet" "--depth" "1"
                       "--branch" tag url checkout))
    (run-command (list "bash" (format #f "~a/install.sh" checkout)
                       "-a" "-d" (tela-icon-dir)))))

(define (retired-icon-theme? name)
  "Whether @var{name} belongs to an icon set this module replaced."
  (or (string-prefix? "Mint-X" name)
    (string-prefix? "Mint-Y" name)
    (string-prefix? "skeu-icons" name)))

(define (install-tela-icons)
  "Install every Tela theme at the tag this module pins.

Both the colour and the brightness variants are installed whole: the palettes
derive a theme from their accent and their light or dark classification, so the
variant the next palette switch asks for has to be there before the switch
happens.  The checkout is shallow and pinned, and upstream's installer renders
the themes into @file{~/.local/share/icons} - the directory GTK searches before
the profile - so the installed artwork cannot drift from the tag written here.

Mint-X, Mint-Y and Skeu Icons copies left in that directory are removed.  The
desktop wears Tela now, and a stale copy that shadows the profile is exactly
what keeps a switch from happening."
  (log-info s "Installing Tela icon themes")
  (ensure-directory-tree! (tela-icon-checkout-dir))
  (ensure-directory-tree! (tela-icon-dir))
  ;; Remove the themes this module owns before installing, so a variant a later
  ;; tag drops does not linger and answer a name upstream no longer ships.
  (for-each (lambda (theme)
              (delete-tree (format #f "~a/~a" (tela-icon-dir) theme)))
            (tela-icon-themes))
  (install-tela-repository! tela-icon-repository)
  ;; Retire the artwork the previous icon tasks installed.
  (for-each (lambda (name)
              (when (retired-icon-theme? name)
                (delete-tree (format #f "~a/~a" (tela-icon-dir) name))))
            (scandir (tela-icon-dir)
                     (lambda (name)
                       (not (member name '("." ".."))))))
  (log-success s "Installed Tela icon themes"))
