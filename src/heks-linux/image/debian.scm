;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The Debian medium: a Debian live system, built by Debian's own live-build,
;; carrying this desktop's packages and the payload that renders it.
;;
;; It is second class to the Void image on purpose, and the difference is worth
;; writing down where somebody changing it will read it.  The Void build is this
;; project's own: void-mklive for the rootfs and the ISO, a wizard of this tree's
;; that partitions a disk, opens it and unpacks the system, and a payload of runit
;; services that draw the desktop.  None of that is portable, and re-implementing
;; it for Debian would be a second installer to keep correct.  So this module
;; renders a live-build description instead: Debian's own tooling, Debian's own
;; installer, Debian's own init, and one command of this tree's - `heks-setup' -
;; to install the two stores and render the desktop once Debian is on the disk.
;;
;; What it is, then, is a Debian installer that already has everything a Heks
;; session is used with on it, and knows the one command that finishes the job.
;; What it is not is an image that boots into the finished desktop: the stores
;; and the render are a person's, run once, with the download in front of them.
;; `docs/debian-image.org' says the same thing to a reader.
;;
;; The description is data - a list of paths and their contents - for the reason
;; the Void one is: a build that costs an hour is reviewed as files, and a spec
;; can read what the build will read.
;;
;;; Code:

(define-module (heks-linux image debian)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (heks-linux image)
  #:use-module (heks-linux packages)
  #:use-module (heks-linux packages apt)
  #:use-module (heks-linux platform)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux services)
  #:export (debian-suite
            debian-mirror
            debian-archive-areas
            debian-architecture
            debian-description-dir
            debian-config-filename
            debian-build-filename
            debian-package-list-filename
            debian-setup-filename
            debian-share-dir
            debian-image-name
            debian-medium-packages
            debian-quickstart
            debian-issue
            debian-config-script
            debian-build-script
            debian-description
            install-debian-image-config))

;; ===========================================
;; What it builds, and where
;; ===========================================

;; The suite this tree builds for.  Debian 13 is the current stable and the one
;; whose archives carry niri and greetd; a suite that moves (testing, sid) is a
;; medium that changes under the person who built it, so this is a name and not a
;; URL's last segment to be updated whenever something else is.
(define debian-suite
  (make-parameter "trixie"))

(define debian-mirror
  (make-parameter "http://deb.debian.org/debian"))

;; main is Debian; contrib is where a few of the desktop's programs live;
;; non-free-firmware is the firmware a wireless card needs to reach the network
;; the stores arrive over.  Firmware is not an aesthetic choice on a machine
;; whose first task is a download.
(define debian-archive-areas
  (make-parameter "main contrib non-free-firmware"))

;; The build, under `dist/', which git ignores: it is a description and then an
;; artefact, never a source file.
(define debian-description-dir
  (make-parameter "dist/image-debian"))

(define debian-config-filename
  (make-parameter "auto/config"))

(define debian-build-filename
  (make-parameter "build-iso.sh"))

;; live-build reads one package name per line from this file.
(define debian-package-list-filename
  (make-parameter "config/package-lists/heks.list.chroot"))

(define debian-setup-filename
  (make-parameter (image-setup-filename)))

(define (debian-share-dir)
  "Return the directory the medium's documents live in."
  "/usr/local/share/heks-linux")

(define (debian-architecture)
  "Return the Debian architecture name for the platform's target.

Debian spells the two architectures this tree builds for differently from
Void: `amd64' and `arm64', not `x86_64' and `aarch64'."
  (case (target-arch)
    [(x86_64) "amd64"]
    [(aarch64) "arm64"]
    [else
      (error "debian-architecture: no Debian name for the target:"
             (target-arch))]))

(define (debian-image-name)
  "Return the name the ISO is handed over as.

The version is the tag the checkout is at, read the way the Void artefacts are
read, so a file's name says which release it is."
  (format #f "~a-~a-debian-~a.iso"
          image-name (image-version) (debian-architecture)))

;; ===========================================
;; The packages
;; ===========================================

;; The Debian backend's whole list, plus what only a medium needs.  `sudo` is
;; not on the desktop list because a desktop is logged into and sudo arrives with
;; a Debian user's groups; a live medium has a user with no password and no
;; account to have been created with, and `sudo heks-setup' is the one command
;; this medium is for.
(define (debian-medium-packages)
  "Return the packages the medium carries, sorted and deduplicated, as names.

The list is names and not package values because it is written to a file: a
symbol is a way of spelling a name in Scheme, and live-build reads text."
  (map apt-package-name
       (package-sorted-set (append (heks-linux-apt) '("sudo"))
                           apt-package-name)))

;; ===========================================
;; What the medium says about itself
;; ===========================================

(define (debian-issue)
  "Return @file{/etc/issue}, the line a console prints before a login."
  (format #f "
~a ~a (Debian ~a, live)
Type 'heks-help' for what this medium is and what to do with it.

"
          image-name (image-version) (debian-suite)))

(define (debian-quickstart)
  "Return the quickstart the medium prints, as text.

It is written for the console a person lands on with no desktop: what the medium
is, the three commands that put Heks on a machine, and where the long version is.
"
  (format #f "~a ~a - a Debian live medium carrying the Heks desktop
=====================================================================

What this is
------------

A Debian ~a live system with the packages a Heks session is used with - the
two compositors, the login prompt, the terminal, the capture stack, the
command line - and a command of Heks' own that installs the two package
stores and renders the desktop on the machine that will keep it.

It is the second-class medium.  The Void ISO in the same project is built by
this tree's own tooling and installs itself with its own wizard; this one is
Debian's tooling, Debian's installer and Debian's init system, and the wizard
is Debian's.

Install Debian
--------------

Start the installer from this medium's boot menu and install Debian as you
would any Debian.  When it finishes and the machine boots, log in and:

  sudo apt-get update
  sudo apt-get install git curl gnupg    # already on the desktop list
  sudo heks-setup <your-account>

heks-setup clones this project's pinned checkout into the account, installs
GNU Guix and Nix, and renders every file the desktop reads.  It is minutes of
download and one long render, and it says which phase it is in as it goes.
It is safe to run again.

If you would rather do it by hand, or you are installing onto a Debian you
already run, the steps are the same ones in the project's own pages:

  https://codeberg.org/jjba23/heks-linux/src/branch/trunk/docs/install-debian.org

Before you install
------------------

  heks-help      this text, in a pager
  ip a           the network, which the stores arrive over
  lsblk          the disks, so the installer's question is an easy one

"
          image-name (image-version) (debian-suite)))

;; ===========================================
;; The build
;; ===========================================

(define (debian-config-script)
  "Return @file{auto/config}, the live-build configuration.

live-build runs this file itself before it assembles anything, which is why the
arguments live here rather than in a script of ours: `lb config noauto' is how a
project states its own configuration, and every key below is one Debian's
live-manual documents.

@option{--debian-installer live} carries Debian's installer on the medium;
@option{--apt-recommends false} keeps the package list this tree wrote the
package list the medium gets; @option{--firmware-chroot true} puts the firmware
in the image, so a machine can reach the network it needs before it has a
desktop; and @option{--bootappend-live} turns plymouth off, for the reason the
Void medium does: a splash that cannot draw on a machine's graphics is a black
screen where the console would have said something."
  (format #f "#!/bin/sh
# ====== Heks-Linux: the Debian medium ======
#
# auto-generated file, DO NOT EDIT!
#
# live-build runs this before it assembles the image.  Re-run it by hand with
# `lb config' in this directory after a change, or let `lb build' do it.

set -eu

lb config noauto \\
    --mode debian \\
    --distribution ~a \\
    --architectures ~a \\
    --parent-mirror-bootstrap ~a \\
    --mirror-bootstrap ~a \\
    --archive-areas \"~a\" \\
    --binary-images iso-hybrid \\
    --bootappend-live \"boot=live components quiet plymouth.enable=0\" \\
    --debian-installer live \\
    --debian-installer-gui false \\
    --firmware-chroot true \\
    --memtest none \\
    --apt-recommends false \\
    --initsystem systemd \\
    --iso-application \"~a\" \\
    --iso-volume \"HEKS_LINUX\"
"
          (debian-suite)
          (debian-architecture)
          (debian-mirror)
          (debian-mirror)
          (debian-archive-areas)
          image-name))

(define (debian-build-script)
  "Return @file{build-iso.sh}: one build, one artefact, one checksum.

live-build works in the directory it is run in and leaves its stages there, so
the script builds beside the description and copies the artefact out under this
tree's own name - a file called @file{live-image-amd64.hybrid.iso} says nothing
about which release it is.  The checksum is written beside it, the way the Void
artefacts are, so what is handed over is what can be checked."
  (format #f "#!/bin/sh
# ====== Heks-Linux: build the Debian medium ======
#
# auto-generated file, DO NOT EDIT!
#
# live-build writes its stages into this directory (chroot/, binary/, cache/),
# which is why the whole of `dist/' is ignored by git.  The build needs root:
# it debootstraps a chroot and mounts filesystems inside it.

set -eu

here=$(CDPATH= cd -- \"$(dirname -- \"$0\")\" && pwd -P)
cd \"$here\"

command -v lb >/dev/null 2>&1 || {
    echo 'live-build is not installed: sudo apt-get install live-build' >&2
    exit 1
}

lb build 2>&1 | tee \"$here/build.log\"

built=$(ls \"$here\"/live-image-*.hybrid.iso 2>/dev/null | head -1)
[ -n \"$built\" ] || {
    echo \"the build finished without an ISO: the log is $here/build.log\" >&2
    exit 1
}

artefact=\"$here/~a\"
mv \"$built\" \"$artefact\"
( cd \"$here\" && sha256sum \"$(basename \"$artefact\")\" > \"$(basename \"$artefact\").sha256\" )
echo \"the medium is $artefact\"
echo \"its checksum is beside it: sha256sum -c $(basename \"$artefact\").sha256\"
"
          (debian-image-name)))

;; ===========================================
;; The payload the medium carries
;; ===========================================

(define (debian-payload-setup)
  "Return @file{heks-setup} as this medium carries it.

It is the script the Void medium carries, rendered for the init system this one
runs: what differs is how the two stores are made to start at boot, and it is
one function of `(heks-linux image)'s where that difference lives.  The desktop
half - the channels, the pull, the render and the check at the end - is the same
file on both, which is the point of rendering it from one place.
"
  (parameterize ((init-system 'systemd))
    (image-setup-script)))

(define (debian-payload-render)
  "Return @file{heks-render}, the command that renders this account's home.

It is the Void payload's: it re-renders every surface for a user who is already
set up, which is the command a person reaches for after changing a setting.
"
  (image-payload-script))

(define (debian-help-wrapper)
  "Return @file{heks-help}, the one command a lost person can remember."
  (format #f "#!/bin/sh
# ====== Heks-Linux: the quickstart ======
#
# auto-generated file, DO NOT EDIT!
#
exec less ~a/quickstart.txt
"
          (debian-share-dir)))

(define (debian-setup-wrapper)
  "Return @file{/usr/local/bin/heks-setup}, the name a person types.

`heks-setup' installs the stores and renders a home, so it takes root: the
wrapper is what makes the documented command the short one.
"
  (format #f "#!/bin/sh
# ====== Heks-Linux: the setup command ======
#
# auto-generated file, DO NOT EDIT!
#
exec /usr/local/lib/heks-linux/~a \"$@\"
"
          (debian-setup-filename)))

(define (debian-render-wrapper)
  "Return @file{/usr/local/bin/heks-render}, the name a person types."
  (format #f "#!/bin/sh
# ====== Heks-Linux: the render command ======
#
# auto-generated file, DO NOT EDIT!
#
exec /usr/local/lib/heks-linux/~a \"$@\"
"
          (image-payload-script-filename)))

;; ===========================================
;; The description
;; ===========================================

(define (debian-description)
  "Return the build as @code{(filename . contents)} pairs.

A description is a directory: live-build's configuration, its package list, the
payload under @file{config/includes.chroot} - which live-build copies onto the
live root - and the script that builds it.
"
  (list (cons (debian-config-filename) (debian-config-script))
        (cons (debian-package-list-filename)
              (format #f "~a\n" (string-join (debian-medium-packages) "\n")))
        (cons (format #f "config/includes.chroot/usr/local/lib/heks-linux/~a"
                      (debian-setup-filename))
              (debian-payload-setup))
        (cons (format #f "config/includes.chroot/usr/local/lib/heks-linux/~a"
                      (image-payload-script-filename))
              (debian-payload-render))
        (cons "config/includes.chroot/usr/local/bin/heks-setup"
              (debian-setup-wrapper))
        (cons "config/includes.chroot/usr/local/bin/heks-render"
              (debian-render-wrapper))
        (cons "config/includes.chroot/usr/local/bin/heks-help"
              (debian-help-wrapper))
        (cons (format #f "config/includes.chroot~a/quickstart.txt"
                      (debian-share-dir))
              (debian-quickstart))
        (cons "config/includes.chroot/etc/issue" (debian-issue))
        (cons (debian-build-filename) (debian-build-script))))

(define* (install-debian-image-config #:key (dir (debian-description-dir)))
  "Write the description into @var{dir} and return the directory.

The two scripts are written executable: live-build runs @file{auto/config} by
itself, and a mode that is not executable stops the build before its first
package.  A path in the description is relative to @var{dir}, so a file under
@file{config/includes.chroot} is written into that tree - live-build copies it
onto the live root as it is."
  (ensure-directory-tree! dir)
  (for-each (lambda (entry)
              (let ((path (car entry)))
                (install-config-file!
                 #:name (basename path)
                 #:dir (format #f "~a/~a" dir (dirname path))
                 #:contents (cdr entry)
                 #:perms
                 (if (or (string=? path (debian-config-filename))
                       (string=? path (debian-build-filename)))
                   493
                   420))))
            (debian-description))
  dir)
