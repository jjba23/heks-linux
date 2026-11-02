;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; What this desktop takes out of an OS X Mavericks installation image: the
;; typefaces it is drawn in, and the pictures it was drawn against.
;;
;; Heks is modelled on Mavericks.  The menu bar is that menu bar, the text is
;; smoothed the way that text was smoothed, and the greys the bar is made of are
;; those greys - but the one thing a comment cannot copy out of a system is what
;; the system was actually made of.  Its interface face, its terminal face, its
;; key glyphs and its wallpapers are files inside an installation image, and a
;; machine that owns that image already owns them.
;;
;; So this module is the way out of the image: it writes one program,
;; @file{~/.local/bin/heks-mavericks}, with a subcommand per thing worth taking.
;; The program reads the image and writes into this machine, and nothing here
;; downloads anything.
;;
;; Nothing here ships a byte of Apple's artwork either, and that is why this is a
;; program rather than a package.  The faces and the pictures are Apple's to
;; distribute; a checkout of heks-linux is a checkout anybody can have, and it
;; carries nothing it would have to take down.  A machine without the image is
;; not broken by this module: the script is written, and running it says which
;; path it looked in.
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
;; The pictures are @file{Library/Desktop Pictures}: the wave Mavericks shipped
;; with, plus the forty-odd others and the ten flat tints.  They land in the
;; wallpaper collection rather than anywhere of their own, so the wall view that
;; already browses that collection browses these too.

;;; Code:

(define-module (heks-linux mavericks)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux wallpaper)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (mavericks-image-dir mavericks-fonts-dir mavericks-typefaces
                                mavericks-pictures-dir mavericks-picture-package
                                mavericks-script-dir mavericks-script-filename
                                mavericks-font-families mavericks-font-files
                                mavericks-script install-mavericks-config))

(define s
  (scriba-auto-logger))

;; Where the image is.  A machine that made a USB installer, or that merged the
;; BaseSystem with the packages beside it - which is what a USB installer is -
;; points this at the root of that volume.  The script looks in both layouts
;; under it, so a mounted Install ESD works with the same path.
(define mavericks-image-dir
  (make-parameter (format #f "~a/Downloads/OS X Mavericks/OS X Base System"
                          (or (getenv "HOME") "/tmp"))))

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
;; parameter, so a machine that also wants the CJK faces - another hundred
;; megabytes, in the same directory of the same image - adds them here instead
;; of forking the module.
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

;; Where the pictures go.  Inside the wallpaper collection rather than in a
;; directory of their own, because that collection is what the wall view reads
;; and what @command{heks-wallpaper all-list} walks: a picture that is in it is a
;; picture that can be chosen, and one that is next to it is not.
;;
;; Two consequences worth writing down.  The directory is untracked in the
;; collection's own repository - these are pictures Apple drew, and the clone is
;; a checkout of somebody else's artwork, not a place to commit them into.  And
;; the collection is replaced wholesale by
;; @command{maak install-wallpaper-files}, which deletes the directory before it
;; clones: the pictures last until that task runs again, and after it
;; @command{maak mavericks-pictures} puts them back.  A machine that wants them
;; to be permanent sets this parameter to a directory of its own and leaves the
;; collection out of the argument.
(define mavericks-pictures-dir
  (make-parameter (format #f "~a/mavericks"
                          (wallpaper-catalog-dir))))

;; The package the pictures live in.  It is the one package of the installer
;; that holds the desktop pictures; everything else in the image - the system,
;; the applications - is not something a desktop can be made of.
(define mavericks-picture-package
  (make-parameter "MediaFiles.pkg"))

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
program to fail at its first `IMAGE='...'` line.  The quote is closed, escaped
and reopened, the way @code{waybar-system-menu-quote} does it for the bar's menu
actions."
  (format #f "'~a'"
          (string-join (string-split text #\') "'\\''")))

(define (mavericks-script)
  "Render @command{heks-mavericks}, the program that opens the image.

It is a POSIX shell script with four subcommands - @code{fonts},
@code{pictures}, @code{status} and @code{help} - and its default is the help
text, because the alternative default is a program that copies three hundred
megabytes of somebody's wallpaper the first time it is typed by accident.

Nothing in it downloads anything, and that is the whole design: the image is on
the machine or the program says where it looked for it.  Both the copy of a face
and the copy of a picture skip what is already there, so running it twice costs
one directory listing and nothing else."
  (format #f "#!/usr/bin/env sh
# ====== Heks-Linux Mavericks artwork ======
#
# auto-generated file, DO NOT EDIT!
#
# The typefaces and the desktop pictures of OS X Mavericks, out of an
# installation image this machine already has.
#
#   heks-mavericks fonts      install the faces into the fonts directory
#   heks-mavericks pictures   copy the desktop pictures into the collection
#   heks-mavericks status     what is installed, and where the image was found
#   heks-mavericks help       this text
#
# Nothing is downloaded: the image is the only source, and what comes out of it
# stays on the machine that owns it.

set -u

IMAGE=~a
FONTS=~a
PICTURES=~a
PACKAGE=~a

say() { printf '%s\\n' \"$*\"; }
warn() { printf '%s\\n' \"$*\" >&2; }
die() {
	warn \"$*\"
	exit 1
}

usage() {
	cat <<'EOF'
heks-mavericks — the artwork of the system this desktop is modelled on

  heks-mavericks fonts      install the typefaces the image carries
  heks-mavericks pictures   copy its desktop pictures into the collection
  heks-mavericks status     say what is installed, and where it looked
  heks-mavericks help       this text

Nothing is downloaded.  The image is looked for in two layouts, so either a USB
installer's volume or a mounted Install ESD works:

  <image>/System/Installation/Packages  a BaseSystem volume with the packages
  <image>/Packages                      an Install ESD image, which keeps them
                                        at its root

The faces land in the fonts directory, the pictures in the wallpaper
collection: the collection's own wall view picks them up with nothing else to
install.
EOF
}

# --- where the image keeps things ---

# The two shapes an Apple installer has on disk.  A volume made by a USB
# installer keeps the packages under System/Installation; the Install ESD image
# keeps them at its root.  Both are tried, so one configured path works for
# either.
font_dir() {
	for dir in \"$IMAGE/System/Library/Fonts/Base\" \"$IMAGE/System/Library/Fonts\"; do
		if [ -d \"$dir\" ]; then
			say \"$dir\"
			return 0
		fi
	done
	return 1
}

package_path() {
	for pkg in \"$IMAGE/System/Installation/Packages/$PACKAGE\" \"$IMAGE/Packages/$PACKAGE\"; do
		if [ -f \"$pkg\" ]; then
			say \"$pkg\"
			return 0
		fi
	done
	return 1
}

# The table the two font subcommands share: one face per line, as
# file|family|why.  A face whose family has a space in it survives because the
# separator is a character no family name carries.
faces() {
	cat <<'EOF'
~a
EOF
}

# --- the payload of a .pkg ---

# A package's payload is one cpio archive behind a compressor, and which
# compressor depends on the release: Mavericks writes bzip2, later systems xz,
# and a few images ship the archive raw.  The first bytes say which, and reading
# them is cheap because `head' closes the pipe and kills bsdtar rather than
# letting it decompress three gigabytes to learn one thing.
payload_stream() {
	pkg=$1
	magic=$(bsdtar -xOf \"$pkg\" Payload 2>/dev/null | head -c 6 | od -An -tx1 | tr -d ' \\n')
	case \"$magic\" in
		425a68*) bsdtar -xOf \"$pkg\" Payload | bzip2 -dc ;;
		fd377a585a00*) bsdtar -xOf \"$pkg\" Payload | xz -dc ;;
		1f8b*) bsdtar -xOf \"$pkg\" Payload | gzip -dc ;;
		7062787a*)
			warn \"$pkg is pbzx-compressed, which this program does not read\"
			return 1
			;;
		*) bsdtar -xOf \"$pkg\" Payload ;;
	esac
}

# --- fonts ---

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
	src=$(font_dir) || die \"no fonts in $IMAGE: that path is not an OS X image\"
	mkdir -p \"$FONTS\" || die \"could not create $FONTS\"
	list=$(mktemp) || die \"could not create a temporary file\"
	faces >\"$list\"
	installed=0
	while IFS='|' read -r file family why; do
		if [ ! -f \"$src/$file\" ]; then
			warn \"not in this image: $file ($family)\"
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

# --- pictures ---

cmd_pictures() {
	command -v bsdtar >/dev/null 2>&1 \\
		|| die 'bsdtar (libarchive) is needed to open an Apple package'
	pkg=$(package_path) \\
		|| die \"no $PACKAGE in $IMAGE: looked under System/Installation/Packages and Packages\"
	work=$(mktemp -d) || die 'could not create a temporary directory'
	trap 'rm -rf \"$work\"' EXIT HUP INT TERM
	say \"reading $pkg — a few hundred megabytes of payload, once\"
	payload_stream \"$pkg\" \\
		| bsdtar -xf - -C \"$work\" './Library/Desktop Pictures/*' \\
		|| die \"could not read the payload of $pkg\"
	pictures=\"$work/Library/Desktop Pictures\"
	[ -d \"$pictures\" ] || die \"$pkg carries no Library/Desktop Pictures\"
	mkdir -p \"$PICTURES\" || die \"could not create $PICTURES\"
	copied=0
	# The photographs, then the flat tints the Mac shipped for a person who
	# wanted no photograph at all.  Both are already at five thousand pixels
	# across, so nothing is resized on the way in.
	for file in \"$pictures\"/*.jpg \"$pictures/Solid Colors\"/*.png; do
		[ -f \"$file\" ] || continue
		name=${file##*/}
		[ -e \"$PICTURES/$name\" ] && continue
		cp \"$file\" \"$PICTURES/$name\" && copied=$((copied + 1))
	done
	say \"installed $copied pictures in $PICTURES\"
}

# --- what is there ---

cmd_status() {
	say \"image:    $IMAGE\"
	if src=$(font_dir); then
		say \"fonts:    $src\"
	else
		warn \"fonts:    not found under $IMAGE\"
	fi
	if pkg=$(package_path); then
		say \"pictures: $pkg\"
	else
		warn \"pictures: $PACKAGE not found under $IMAGE\"
	fi
	list=$(mktemp) || return 1
	faces >\"$list\"
	while IFS='|' read -r file family why; do
		if [ -f \"$FONTS/$file\" ]; then
			say \"installed face: $family\"
		fi
	done <\"$list\"
	rm -f \"$list\"
	count=0
	if [ -d \"$PICTURES\" ]; then
		for file in \"$PICTURES\"/*.jpg \"$PICTURES\"/*.png; do
			[ -f \"$file\" ] && count=$((count + 1))
		done
	fi
	say \"installed pictures: $count\"
}

main() {
	case \"${1:-help}\" in
		fonts) cmd_fonts ;;
		pictures) cmd_pictures ;;
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
          (single-quote (mavericks-image-dir))
          (single-quote (mavericks-fonts-dir))
          (single-quote (mavericks-pictures-dir))
          (single-quote (mavericks-picture-package))
          (mavericks-face-rows)))

(define (install-mavericks-config)
  "Write @command{heks-mavericks} to @code{mavericks-script-dir}, mode #o755.

Nothing is read out of the image here, and it would be wrong to: a reconfigure
runs on every palette switch, and a palette switch that copies a few hundred
megabytes of wallpaper is not a palette switch.  Rendering the program is cheap
and safe; running it is a decision, and the decision is
@command{maak mavericks-fonts} or @command{maak mavericks-pictures}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/mavericks-settings.scm} first, so a machine
that keeps the image elsewhere - or that wants a different set of faces - says so
in its own file instead of forking this module."
  (log-info s "Installing the Mavericks artwork program")
  (load-local-overrides '(heks-linux mavericks)
                        'mavericks-settings)
  (install-config-file! #:name (mavericks-script-filename)
                        #:dir (mavericks-script-dir)
                        #:contents (mavericks-script)
                        #:perms 493)
  (log-success s "Installed the Mavericks artwork program"))
