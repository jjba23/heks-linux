;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; What this desktop takes out of OS X Mavericks: the typefaces it is drawn in.
;;
;; Heks is modelled on Mavericks.  The menu bar is that menu bar, the text is
;; smoothed the way that text was smoothed, and the greys the bar is made of are
;; those greys - but the one thing a comment cannot copy out of a system is what
;; the system was actually made of.  Its interface face, its terminal face and
;; its key glyphs are files inside the system, and a desktop that wants to look
;; like it has to have the files.
;;
;; So the files are in this checkout, under @file{resources/mavericks/fonts}:
;; seven faces, taken out of an OS X 10.9 installation image once, and this
;; module is what puts them where a running desktop reads them - fontconfig's
;; user directory, which is the directory the sandboxed applications see too.
;;
;; Those files are not ours.  They are Apple's: the faces are copyright Apple
;; Inc., they are here because this desktop is modelled on Apple's, and no part
;; of heks-linux's MIT license covers them.  @file{resources/mavericks/NOTICE}
;; says so in full, and the program this module writes says so too - in its help
;; text and in @command{status} - because a copy that is installed without
;; knowing whose it is, is a copy that gets passed on.  Nothing here downloads
;; anything, and a machine that would rather not carry Apple's faces can point
;; @code{mavericks-assets-dir} at a directory of its own.
;;
;; The faces are the ones a Linux desktop cannot get anywhere else:
;;
;;   Lucida Grande     the interface face of OS X 10.0 through 10.9, and the
;;                     face the menu bar was drawn in - the one the bar's own
;;                     metrics were measured against.
;;   Helvetica Neue    the face that replaced it in 10.10, for a machine that
;;                     follows Apple forward rather than back.
;;   Menlo             the Terminal face from 10.6 on; an alternative to the
;;                     configured mono font.
;;   Monaco            the Terminal face before that, and the ancestor of the
;;                     DejaVu Sans Mono this desktop usually draws in.
;;   Geneva            the interface face of the Mac before OS X.
;;   .Keyboard         the modifier glyphs (command, option, shift, control,
;;                     escape, caps lock), the Apple mark at U+F8FF, and the
;;                     media keys - the alphabet heks-toon's key reference and
;;                     the bar's key labels want.
;;   Apple Symbols     the symbol font the menus drew their marks from.
;;
;; The wallpapers Mavericks shipped with are not here.  They are thirty times
;; the size of the faces, they are the part of the system a desktop replaces
;; first, and the wallpaper collection this configuration already clones is
;; where a picture a person actually chose comes from.

;;; Code:

(define-module (heks-linux mavericks)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (mavericks-checkout-dir mavericks-assets-dir
                                mavericks-fonts-dir mavericks-typefaces
                                mavericks-script-dir mavericks-script-filename
                                mavericks-font-families mavericks-font-files
                                mavericks-script install-mavericks-config))

(define s
  (scriba-auto-logger))

;; --- where the artwork is ---

;; The checkout this module came out of.  The modules are loaded from
;; <checkout>/src, so the checkout is the parent of whichever @code{%load-path}
;; entry holds @file{heks-linux/mavericks.scm}.
;;
;; It is resolved instead of assumed because the path is written into the
;; generated program at render time and read back later, from whatever directory
;; the person happens to be in: a relative @code{./resources/mavericks} would be
;; right when it was rendered and wrong when it was used.  When nothing in the
;; load path looks like this checkout - a REPL started somewhere else, a copy
;; loaded out of a cache - the current directory is the only answer left, and
;; the program reports the path it got rather than failing quietly.
(define (mavericks-checkout-dir)
  "Return the root directory of the heks-linux checkout this module came from."
  (let loop ((dirs %load-path))
    (cond
      [(null? dirs)
       (or (getcwd) "/tmp")]
      [(file-exists? (string-append (car dirs) "/heks-linux/mavericks.scm"))
       (canonicalize-path (string-append (car dirs) "/.."))]
      [else
       (loop (cdr dirs))])))

;; The artwork itself, in the checkout rather than in an installation image: the
;; typefaces in @file{fonts}.  They are Apple's, they are covered by
;; @file{NOTICE} in this directory, and nothing in the checkout changes that -
;; the files are here because this desktop is modelled on Apple's, not because
;; heks-linux has any claim on them.
(define mavericks-assets-dir
  (make-parameter (format #f "~a/resources/mavericks"
                          (mavericks-checkout-dir))))

;; Where the faces go.  @file{~/.local/share/fonts} is the directory fontconfig
;; reads for the user, and unlike the older @file{~/.fonts} it is also the one
;; the sandboxed applications see, so a Flatpak that asks for a font finds it.
;;
;; A directory of its own, and not a scattering: these faces came from one place
;; and a machine that wants them gone deletes one directory.
(define mavericks-fonts-dir
  (make-parameter (format #f "~a/.local/share/fonts/Mavericks"
                          (or (getenv "HOME") "/tmp"))))

;; The faces to take, as @code{(file family note)} rows.
;;
;; @var{note} is what the program prints when it installs one, because a copy
;; that says "installed: Lucida Grande" is a copy somebody can check, while a
;; silent one is a copy somebody has to go and look for.  The list is a
;; parameter, so a machine that carries more of the image's faces in its own
;; resources directory - the CJK ones are another hundred megabytes - adds them
;; here instead of forking the module.
(define mavericks-typefaces
  (make-parameter '(("LucidaGrande.ttc" "Lucida Grande"
                     "the interface face, and the menu bar's")
                    ("HelveticaNeue.ttc" "Helvetica Neue"
                     "the face that replaced it in 10.10")
                    ("Menlo.ttc" "Menlo" "the Terminal face, for a mono alternative")
                    ("Monaco.ttf" "Monaco" "the Terminal face before it")
                    ("Geneva.ttf" "Geneva" "the interface face before OS X")
                    ("Keyboard.ttf" ".Keyboard"
                     "the modifier keys, the Apple mark, the media keys")
                    ("Apple Symbols.ttf" "Apple Symbols"
                     "the marks the menus are drawn with"))))

(define mavericks-script-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define mavericks-script-filename
  (make-parameter "heks-mavericks"))

(define (mavericks-font-files)
  "Return the file names of the faces @code{mavericks-typefaces} lists."
  (map car (mavericks-typefaces)))

(define (mavericks-font-families)
  "Return the family names of the faces @code{mavericks-typefaces} lists.

The names are the ones fontconfig reports, which is what makes them usable in a
stylesheet: @code{.Keyboard} keeps its leading dot because that is its family."
  (map cadr (mavericks-typefaces)))

(define (mavericks-face-rows)
  "Return the face table as the @code{file|family|note} lines the script reads.

One row per face, separated by newlines, and one separator that cannot occur in
a family name, because the shell reads the table with @code{IFS='|' read}: three
parallel lists would have to stay in step by hand, and a face whose note held a
space would split into two."
  (string-join (map (lambda (face)
                      (apply format #f "~a|~a|~a" face))
                    (mavericks-typefaces)) "\n"))

(define (single-quote text)
  "Return @var{text} as one shell word.

The paths in the script are written into it at render time, and a home
directory that carries a single quote in its name is not a reason for the
program to fail at its first `ASSETS='...'` line.  The quote is closed, escaped
and reopened, the way @code{waybar-system-menu-quote} does it for the bar's menu
actions."
  (format #f "'~a'"
          (string-join (string-split text #\') "'\\''")))

(define (mavericks-script)
  "Render @command{heks-mavericks}, the program that installs the faces.

It is a POSIX shell script with three subcommands - @code{fonts},
@code{status} and @code{help} - and its default is the help text, because the
alternative default is a program that copies Apple's faces onto a machine the
first time it is typed by accident.

The source is the checkout's own @file{resources/mavericks/fonts}, not an
installation image.  Nothing in it downloads anything, and the copy of a face
skips what is already there, so running it twice costs one directory listing and
nothing else.

The script also says, twice - in the help text and in @code{status} - that the
artwork it installs is Apple's.  A file that is copied into place without that
sentence is a file somebody later mistakes for part of an MIT-licensed desktop."
  (format #f "#!/usr/bin/env sh
# ====== Heks-Linux Mavericks artwork ======
#
# auto-generated file, DO NOT EDIT!
#
# The typefaces of OS X Mavericks, copied out of this checkout's
# resources/mavericks/fonts into the place a running desktop reads them.
#
#   heks-mavericks fonts      install the faces into the fonts directory
#   heks-mavericks status     what is installed, and where it came from
#   heks-mavericks help       this text
#
# The artwork is Apple's, not heks-linux's: the typefaces are copyright Apple
# Inc., and the MIT license this project ships under does not cover them.
# NOTICE in the resources directory says so, and so does `status'.  Nothing is
# downloaded; the files are in the checkout.

set -u

ASSETS=~a
FONTS=~a

say() { printf '%s\\n' \"$*\"; }
warn() { printf '%s\\n' \"$*\" >&2; }
die() {
	warn \"$*\"
	exit 1
}

usage() {
	cat <<'EOF'
heks-mavericks — the typefaces of the system this desktop is modelled on

  heks-mavericks fonts      install the typefaces the checkout carries
  heks-mavericks status     say what is installed, and where it came from
  heks-mavericks help       this text

The files come from this checkout - resources/mavericks/fonts, beside the
modules - and from nowhere else.  Nothing is downloaded, and an image of OS X
is not needed: the faces were taken out of one once, and they have been here
since.

They land in the fonts directory, where fontconfig and the applications that
ask it read them.  The wallpapers of that system are not here: a picture is
chosen from the wallpaper collection, which this configuration already clones.

The artwork is copyright Apple Inc.  It was taken from an OS X 10.9
installation image and is kept here because this desktop is modelled on that
one; heks-linux's MIT license does not cover it.  See NOTICE in the resources
directory for the whole of it.
EOF
}

# --- the faces ---

# Fontconfig learns about a directory by rebuilding its cache, and a cache
# another version of fontconfig wrote is not rebuilt but ignored - with a
# warning on every command that reads fonts, which is how a machine ends up with
# a face on disk that no program can see.  The faces are therefore checked
# afterwards instead of assumed, and the check is what says what to do about it.
refresh_cache() {
	if ! command -v fc-cache >/dev/null 2>&1; then
		warn \"fc-cache is not installed: fontconfig will find $FONTS on its own\"
		return 0
	fi
	fc-cache -f \"$FONTS\" >/dev/null 2>&1 || warn \"fc-cache did not finish\"
}

# The table the font subcommands share: one face per line, as file|family|why.
# A face whose family has a space in it survives because the separator is a
# character no family name carries.
faces() {
	cat <<'EOF'
~a
EOF
}

check_visible() {
	if ! command -v fc-list >/dev/null 2>&1; then
		warn \"fc-list is not installed: cannot confirm the faces are visible\"
		return 0
	fi
	# The indexed path, not just the family: a face is visible when fontconfig
	# lists *this* file, and asking whether the family exists anywhere answers a
	# different question - it says yes when the same face was already installed
	# somewhere else, which is exactly the case a broken cache hides.
	real=$(cd \"$FONTS\" 2>/dev/null && pwd -P) || real=$FONTS
	index=$(fc-list --format '%{family}|%{file}\\n' 2>/dev/null)
	missing=0
	list=$(mktemp) || return 1
	faces >\"$list\"
	while IFS='|' read -r file family why; do
		[ -f \"$FONTS/$file\" ] || continue
		if ! printf '%s\\n' \"$index\" | grep -qF -- \"|$real/$file\"; then
			warn \"on disk, but not in fontconfig's index: $file\"
			missing=$((missing + 1))
		elif printf '%s\\n' \"$index\" | grep -qxF -- \"$family|$real/$file\"; then
			say \"visible to fontconfig: $family\"
		else
			# The file is indexed, under another name: a face whose family this
			# is not would be installed and still not found by the stylesheets that
			# ask for the family, which is worse than not being installed at all.
			warn \"$file is indexed, but not as \\\"$family\\\"\"
			missing=$((missing + 1))
		fi
	done <\"$list\"
	rm -f \"$list\"
	[ \"$missing\" -eq 0 ] && return 0
	warn ''
	warn 'Two things make a copied face invisible, and both are fixed the same way.'
	warn 'A fonts directory fontconfig does not read has to be one it does, and a'
	warn 'cache another version of fontconfig wrote is not rebuilt but ignored.  When'
	warn 'fc-cache complained about a newer fontconfig above, drop the cache:'
	warn ''
	# shellcheck disable=SC2016
	warn '    rm -rf \"${XDG_CACHE_HOME:-$HOME/.cache}/fontconfig\" && heks-mavericks fonts'
	return 1
}

cmd_fonts() {
	src=\"$ASSETS/fonts\"
	[ -d \"$src\" ] \\
		|| die \"no typefaces in $src: this checkout carries no resources/mavericks/fonts\"
	mkdir -p \"$FONTS\" || die \"could not create $FONTS\"
	list=$(mktemp) || die 'could not create a temporary file'
	faces >\"$list\"
	installed=0
	while IFS='|' read -r file family why; do
		if [ ! -f \"$src/$file\" ]; then
			warn \"not in this checkout: $file ($family)\"
			continue
		fi
		if [ -f \"$FONTS/$file\" ]; then
			say \"already installed: $family\"
			continue
		fi
		if cp \"$src/$file\" \"$FONTS/$file\"; then
			say \"installed: $family — $why\"
			installed=$((installed + 1))
		else
			warn \"could not copy $file\"
		fi
	done <\"$list\"
	rm -f \"$list\"
	[ \"$installed\" -gt 0 ] && refresh_cache
	check_visible
}

# --- what is there ---

cmd_status() {
	say \"assets:   $ASSETS\"
	if [ -d \"$ASSETS/fonts\" ]; then
		say \"faces:    $ASSETS/fonts\"
	else
		warn \"faces:    not in this checkout under $ASSETS\"
	fi
	list=$(mktemp) || return 1
	faces >\"$list\"
	while IFS='|' read -r file family why; do
		if [ -f \"$FONTS/$file\" ]; then
			say \"installed face: $family\"
		fi
	done <\"$list\"
	rm -f \"$list\"
	say ''
	say 'The typefaces are copyright Apple Inc.  They are here because this'
	say \"desktop is modelled on OS X, and heks-linux's MIT license does not\"
	say \"cover them: $ASSETS/NOTICE has the terms.\"
}

main() {
	case \"${1:-help}\" in
		fonts) cmd_fonts ;;
		status) cmd_status ;;
		help|-h|--help) usage ;;
		*)
			usage >&2
			return 2
			;;
	esac
}

main \"$@\"
"
          (single-quote (mavericks-assets-dir))
          (single-quote (mavericks-fonts-dir))
          (mavericks-face-rows)))

(define (install-mavericks-config)
  "Write @command{heks-mavericks} to @code{mavericks-script-dir}, mode #o755.

Nothing is copied here, and it would be wrong to: a reconfigure runs on every
palette switch, and a palette switch that installs seven faces is not a palette
switch.  Rendering the program is cheap and safe; running it is a decision, and
the decision is @command{maak mavericks-fonts}.

A checkout whose @file{resources/mavericks/fonts} is missing - someone cloned
without the artwork, or pointed @code{mavericks-assets-dir} somewhere empty -
still gets the program: it is written, and running it says which directory it
looked in.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/mavericks-settings.scm} first, so a machine
that has its own copy of the artwork - or that wants a different set of faces -
says so in its own file instead of forking this module."
  (log-info s "Installing the Mavericks artwork program")
  (load-local-overrides '(heks-linux mavericks)
                        'mavericks-settings)
  (unless (file-exists? (mavericks-assets-dir))
    (log-warning s "~a does not exist: heks-mavericks will have nothing to copy"
                 (mavericks-assets-dir)))
  (install-config-file! #:name (mavericks-script-filename)
                        #:dir (mavericks-script-dir)
                        #:contents (mavericks-script)
                        #:perms 493)
  (log-success s "Installed the Mavericks artwork program"))
