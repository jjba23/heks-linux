;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The desktop as two artefacts, both built by Void's own tools.
;;
;; void-mklive is a set of shell scripts: mkrootfs.sh builds a rootfs tarball
;; from packages, mklive.sh builds a live ISO.  Neither runs a configuration
;; phase, and that is the shape this module uses.
;;
;;   - The installed system is a rootfs.  mkrootfs.sh produces the base, the
;;     build unpacks it, installs the desktop's packages with xbps, runs
;;     config.sh in the chroot, and packs the result.  What comes out installs
;;     by being unpacked into a mounted filesystem - the docs use a LUKS2
;;     volume with BTRFS inside it - which is why the disk tools are in the
;;     base package list rather than left to the medium.
;;   - The live medium is mklive.sh with the same package list and the same
;;     payload, so the desktop can be booted and looked at, and the installer
;;     on the medium is what puts it on a disk.
;;
;; Nothing here is a distribution's idea of a desktop: no pattern, no GNOME, no
;; display manager.  The session is Niri, the prompt is the one
;; (heks-linux greeter) names - greetd with gtkgreet under cage - and every
;; package in packages.txt is there because a surface in this tree runs it.
;; The kernel is a parameter because Void's kernel packages carry their
;; version, and a name that ages out should be one line to change.
;;
;; config.sh is the only part that runs as root inside the target, and it is
;; written to be read: one log, one way to fail, one phase per question.
;; Anything that differs between runit and systemd comes from
;; (heks-linux services), so the script is not a second place where the init
;; system is decided.
;;
;;; Code:

(define-module (heks-linux image)
  #:declarative? #t
  #:use-module (heks-linux greeter)
  #:use-module (heks-linux packages)
  #:use-module (heks-linux packages xbps)
  #:use-module (heks-linux platform)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux services)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (image-name
            image-version
            image-user
            image-user-home
            image-checkouts
            image-upstream
            image-kernel
            image-description-dir
            image-packages-filename
            image-config-script-filename
            image-rootfs-script-filename
            image-iso-script-filename
            image-payload-dir
            image-payload-script-filename
            image-installer-filename
            image-setup-filename
            image-setup-script
            image-snapshot-filename
            image-snapshot-dir
            image-snapshot-keep
            image-snapshot-script
            image-snapshot-service
            image-rendered-paths
            image-rendered-commands
            image-rendered-verify-lines
            image-live-payload-dir
            image-help-filename
            image-share-dir
            image-dialog-theme-filename
            image-dialog-theme
            image-services
            image-live-excluded-services
            image-live-services
            image-live-consoles
            image-live-installer-service
            image-live-gui-filename
            image-live-gui-service
            image-live-gui-menu
            image-quickstart
            image-build-log
            image-base-packages
            image-toolchain-packages
            image-network-packages
            image-packages
            image-description
            image-config-script
            image-rootfs-script
            image-iso-script
            image-payload-script
            image-required-paths
            image-required-commands
            install-image-config))

;; ===========================================
;; What the image is called, and who it belongs to
;; ===========================================

(define image-name
  "heks-linux")

(define image-version
  (make-parameter "0.1.0"))

;; The live user: the account the greeter logs in on the live medium, and the
;; account the build installs the desktop into.
(define image-user
  (make-parameter "heks"))

(define (image-user-home)
  "Return the live user's home inside the image.

It is spelled out rather than computed from @code{(getenv \"HOME\")} because it
is a path *inside another filesystem*: the one the build is not running in."
  (format #f "/home/~a" (image-user)))

(define image-upstream
  (make-parameter "https://codeberg.org/jjba23"))

(define image-checkouts
  (make-parameter
   '(("heks-linux" . "trunk")
     ("heks-emacs" . "trunk")
     ("heks-bash" . "trunk"))))

;; Void's kernel packages carry their version, so this is a parameter rather
;; than a constant: when 6.18 leaves the repositories, the image moves with one
;; line instead of a build that fails at the package step.
(define image-kernel
  (make-parameter "linux6.18"))

;; ===========================================
;; Where the build is written
;; ===========================================

(define image-description-dir
  (make-parameter "dist/image"))

(define image-packages-filename
  (make-parameter "packages.txt"))

(define image-config-script-filename
  (make-parameter "config.sh"))

(define image-rootfs-script-filename
  (make-parameter "build-rootfs.sh"))

(define image-iso-script-filename
  (make-parameter "build-iso.sh"))

;; The overlay: everything under here is copied onto the image's root.
(define image-payload-dir
  (make-parameter "root/usr/local/lib/heks-linux"))

(define image-payload-script-filename
  (make-parameter "heks-render"))

;; The installer, written into the payload beside heks-render: the live medium
;; runs it to put this system on a disk, and the installed system keeps a copy so
;; one disk can make another.
(define image-installer-filename
  (make-parameter "heks-install"))

;; The half of the payload that belongs to the medium alone.  build-rootfs.sh
;; copies `root/' into the installed system and never this, so a service or a
;; document that only makes sense on a live medium cannot leak onto a disk.
(define image-live-payload-dir
  (make-parameter "live"))

;; The one command a person who is lost can remember.
(define image-help-filename
  (make-parameter "heks-help"))

;; The files both systems keep in one place: the quickstart a lost person opens,
;; and the theme the wizard's screens are drawn with.
(define (image-share-dir)
  "Return the directory the medium and the installed system share their files in."
  "/usr/local/share/heks-linux")

;; dialog reads its palette from a file, and its own is somebody else's: cyan on
;; blue with white bars.  This one is green ink on a dark screen with a warm
;; title, which is the first thing a person sees of this system - the welcome
;; screen, before anything has been written anywhere.
(define image-dialog-theme-filename
  (make-parameter "dialogrc"))

;; The greeter's file is rendered twice because it is read from two places:
;; mklive.sh copies the payload's /etc/greetd for the live medium, which boots
;; without config.sh, and config.sh installs it from beside itself, the only
;; path that exists before the desktop does.
(define image-greeter-config-filename
  (make-parameter "greetd.toml"))

;; The build's own record, left in the image on purpose: when a booted system is
;; wrong, the first useful file is the one that says how it was made.
(define image-build-log
  "/var/log/heks-image.log")

;; ===========================================
;; What "finished" looks like
;; ===========================================

;; What the packed image must contain, as absolute paths and why.  These are the
;; files the *build* writes: the desktop's own files are not here, because the
;; stores that render them are not in the image.  See `image-rendered-paths'.
(define image-required-paths
  '(("/usr/local/bin/heks-install" . "the installer")
    ("/usr/local/bin/heks-setup" . "the first setup")
    ("/usr/local/bin/heks-render" . "the renderer")
    ("/usr/local/bin/heks-snapshot" . "the snapshots")
    ("/usr/local/bin/heks-help" . "the quickstart")
    ("/usr/local/lib/heks-linux/heks-install" . "the installer the medium runs")
    ("/usr/local/share/heks-linux/quickstart.txt" . "the quickstart page")
    ("/etc/greetd/config.toml" . "the login prompt")))

;; The commands the packed image must answer with.  `guix' and `maak' are absent
;; on purpose: the image carries the Void packages and the tools that install the
;; stores, and the stores themselves are built after the disk is written.
(define image-required-commands
  '("nix" "niri" "kitty" "emacs"
    "cryptsetup" "mkfs.btrfs" "mkfs.ext4" "grub-install"
    "parted" "dialog" "heks-install" "heks-setup" "heks-render"
    "heks-snapshot"))

;; What `heks-setup' must have produced in the account's home.  It is the old
;; build check, moved to the machine that renders the files: a setup that stops
;; before this is a desktop that boots to a bar-less session.
(define image-rendered-paths
  '((".config/niri/config.kdl" . "the compositor's configuration")
    (".config/whelk/settings.scm" . "the shell's configuration")
    (".bashrc" . "the shell")
    (".emacs.d/init.el" . "the editor")
    (".local/share/icons/Tela" . "the icon themes")
    (".local/bin/heks-wallpaper" . "the wallpaper engine")))

;; What a finished setup must have on the account's PATH.  The three heks
;; programs are here because they arrive from the same flake and are what the
;; session is used with: a render that installed the shell and not the dock
;; leaves a desktop one edge emptier than the one this tree describes.
(define image-rendered-commands
  '("guix" "maak" "whelk" "lambdock" "heks-toon"))

;; ===========================================
;; The packages
;; ===========================================

;; base-system is Void's own "a machine that boots" package, dracut is the
;; initramfs generator Void uses, and the kernel is the parameter above.  The
;; disk tools are here because the install path this image documents is a
;; LUKS2 volume with BTRFS inside it, booted by GRUB: a rootfs that cannot
;; format, open or boot its own disk is only half an installed system.  What
;; is *not* here: a desktop metapackage, a display manager, a browser.
(define (image-base-packages)
  "Return the packages: a system, an initramfs, a kernel, and its disk tools."
  (list "base-system" "dracut" (image-kernel)
        ;; The clock is one of the few things a machine cannot be wrong about
        ;; quietly: a certificate is valid over a window, so a first boot in
        ;; 1970 fails every fetch - the Guix installer included - with an error
        ;; about TLS rather than about the time.  chrony keeps it right from the
        ;; first minutes on the network.
        "chrony"
        ;; The disk tools are here because the medium installs itself: it
        ;; partitions with parted, formats the boot partitions, opens a LUKS2
        ;; container, makes BTRFS inside it, and installs a boot loader for
        ;; whichever firmware the machine has.  grub is the BIOS half of that -
        ;; the MBR path - and grub-x86_64-efi the UEFI one, the mode the
        ;; installer offers first.
        "cryptsetup" "btrfs-progs" "e2fsprogs" "parted" "dialog"
        "grub" "grub-x86_64-efi" "dosfstools" "efibootmgr"))

;; What the build needs to finish itself: git clones the checkouts, curl
;; fetches, guile renders and nix installs the shell the distribution does not
;; carry.  A machine does not need these to run the desktop, which is why they
;; are the toolchain and not the session - and why a workstation's own list
;; carries the compilers this one leaves out.
;;
;; wget and gnupg are here for the Guix installer `heks-setup' runs: wget
;; downloads the signing key and the tarball, and gpg verifies them.  Without
;; the pair the installer stops before it installs anything.
(define image-toolchain-packages
  '("curl" "git" "gnupg" "guile" "nix" "wget"))

;; What a machine needs to reach a network, and to be reachable from one.
;;
;; The kernel's own drivers ship with the kernel; what a card loads afterwards
;; is firmware, and a card without it is a device that never appears.  The
;; `linux-firmware' meta package is the whole bundle Void splits - amd, the
;; network blobs (Intel, MediaTek, Atheros, Realtek) and broadcom - because the
;; firmware must be there before the interface exists: nothing on a live medium
;; can know which card this machine has, and a wireless device that is missing
;; its firmware is not a device a person can then install one for.
;;
;; The cost is real and worth naming: half a gigabyte, in the medium and in the
;; installed system, where it is what makes the machine's own network work on
;; the first boot rather than after a trip to another machine for a download.
;; What is *not* here: `linux-firmware-intel', `-nvidia' and `-qualcomm' (GPU
;; and SoC microcode, no network in them), and `broadcom-wl-dkms', the non-free
;; driver for the oldest Broadcom cards - it compiles against a running kernel,
;; which a live medium has no toolchain for, and `brcmfmac' covers the rest.
(define image-network-packages
  '("linux-firmware"
    ;; The supplicant NetworkManager drives.  It comes in with NetworkManager as
    ;; a dependency; naming it here is what keeps wireless working if that ever
    ;; stops being true.
    "wpa_supplicant"))

(define (image-packages)
  "Return every package the image carries, deduplicated and sorted.

The session, the desktop, the command line and the fonts come from
@code{(heks-linux packages xbps)}'s own lists, so an image and a hand-installed
machine cannot disagree about what the desktop is.  The greeter is read here
rather than taken from that module's union because mklive.sh is handed names,
not a backend - switch the greeter and the image follows.  The repositories come
from the same module for the same reason: the non-free tree is enabled by a
package, and the image installs it, so the system the medium unpacks has it."
  (map xbps-package-name
       (package-sorted-set
        (append (image-base-packages)
                image-toolchain-packages
                image-network-packages
                (heks-linux-repository-xbps)
                (map xbps-package-name (greeter-packages))
                (heks-linux-session-xbps)
                (heks-linux-desktop-xbps)
                (heks-linux-cli-xbps)
                (heks-linux-font-xbps))
        xbps-package-name)))

;; ===========================================
;; What the build runs inside the image
;; ===========================================

(define (image-script-prelude)
  "Return the shell every phase is written in: one log, one way to fail."
  (format #f "#!/bin/bash
# ====== Heks-Linux image build ======
#
# auto-generated file, DO NOT EDIT!
#
# Runs inside the target's chroot while the image is being built: as root, with
# the network up and with no init system running - so it may write files and
# enable the services the installed machine will start at boot.  Nothing here
# starts a daemon: the stores are not built in this image, and `heks-setup' is
# what brings them up on the machine that ends up with them.

set -euo pipefail

LOG=~a
install -d -m 755 \"$(dirname \"$LOG\")\"
touch \"$LOG\"

log() { printf '[heks-image] %s\\n' \"$*\" | tee -a \"$LOG\"; }
phase() { log ''; log \"========== $* ==========\"; }

# One way to fail, and it names the command that stopped it.
die() { log \"FAILED: $*\"; log \"the whole record is $LOG\"; exit 1; }
trap 'die \"line $LINENO: $BASH_COMMAND\"' ERR
"
          image-build-log))

;; The services the session needs at boot.  The command per service comes from
;; (heks-linux services), so this is one list and not two: runit links a service
;; into the supervisor's directory, systemd enables its unit.
;;
;; chronyd is the clock.  It is not a session service, and it is here because
;; boot is when it is needed: everything that verifies a certificate - the store
;; the setup installs, the first package the machine fetches - fails on a clock
;; that started from the firmware's idea of the time.
;;
;; heks-snapshot is the daily snapshot of the root subvolume and the cleanup that
;; keeps them from filling the disk.  It is here rather than among the extras
;; because an install that carries a BTRFS layout and takes no snapshots is a
;; layout nobody can roll back; the name is the program's and the service's both.
(define image-services
  '("dbus" "elogind" "polkitd" "rtkit" "NetworkManager" "chronyd"
    "heks-snapshot" "greetd"))

;; What the medium does not start of those.  The medium exists to install, so it
;; boots into the installer on tty1 and leaves greetd out: a graphical prompt
;; over a desktop that has not been rendered yet is a black screen with a login
;; box on it, and it would want the console the installer draws on.  Its root is
;; a squashfs, so it has no BTRFS subvolume to snapshot and nothing to roll back
;; to either, and a snapshot service there would log a failure at every boot.
(define image-live-excluded-services
  '("greetd" "heks-snapshot"))

(define (image-live-services)
  "Return the services the live medium enables at boot."
  (remove (lambda (service)
            (member service image-live-excluded-services))
          image-services))

(define (image-service-lines)
  "Return one line per service that enables it at boot."
  (string-join
   (map (lambda (service)
          (string-join (service-enable-command service) " "))
        image-services)
   "\n"))

(define (image-checkout-lines)
  "Return the lines that clone the three projects into the live user's home."
  (let ((home (image-user-home)))
    (string-join
     (map (lambda (checkout)
            (format #f "git -C ~a/Hacking clone --quiet --depth 1 --branch ~a ~a/~a.git ~a"
                    home (cdr checkout) (image-upstream)
                    (car checkout) (car checkout)))
          (image-checkouts))
     "\n")))

(define* (image-check-lines #:key paths commands user)
  "Return the shell that checks @var{paths} and @var{commands} and counts what is missing.

@var{paths} is a list of @code{(ABSOLUTE-PATH . WHAT-IT-IS)} pairs and
@var{commands} a list of program names asked for on @var{user}'s @code{PATH}.
The message is a person's words, so it is rendered as a double-quoted string:
\"the compositor's configuration\" inside single quotes ends the quote early and
swallows the checks after it, which is a readiness check that quietly checks
less."
  (string-join
   (append
    (map (lambda (required)
           (format #f "check_path ~s ~s" (car required) (cdr required)))
         paths)
    (map (lambda (command)
           (format #f "check_command ~a" command))
         commands))
   "\n"))

(define (image-verify-lines)
  "Return the checks that decide whether the packed image is finished.

The image carries Void, the session, the disk tools and the three commands that
finish the job on the installed machine.  The desktop's own files are not part of
this: they are rendered by `heks-setup', after the stores are built there."
  (image-check-lines #:paths image-required-paths
                     #:commands image-required-commands
                     #:user (image-user)))

(define (image-rendered-verify-lines)
  "Return the checks that decide whether `heks-setup' finished.

The home is spelled @code{\"$home\"} and not the image's own account: the script
is given the account to set up, and it is usually not the one the image was built
with."
  (image-check-lines
   #:paths
   (map (lambda (required)
          (cons (format #f "$home/~a" (car required)) (cdr required)))
        image-rendered-paths)
   #:commands image-rendered-commands
   #:user "$user"))

(define (image-config-script)
  "Return config.sh: the whole build inside the image, in order.

What it does *not* do is build the two stores.  Guix and Nix are not in this
image; `heks-setup' installs them on the installed machine, where they are that
machine's and where the person installing it can see the download begin.  That is
what keeps the medium small and the build a matter of minutes rather than hours:
nothing here reaches the network but the three git clones."
  (let ((user (image-user))
        (home (image-user-home)))
    (string-append
     (image-script-prelude)
     "\n"
     (format #f "phase \"the machine\"
echo ~a > /etc/hostname
printf 'LANG=~a.UTF-8\\n' > /etc/locale.conf
ln -sfn /usr/share/zoneinfo/~a /etc/localtime || log \"no timezone database\"

phase \"the login\"
# The greeter's own file, rendered by (heks-linux greeter) and carried in the
# payload: greetd reads exactly this path.
install -d -m 755 /etc/greetd
install -m 644 /usr/local/lib/heks-linux/~a /etc/greetd/config.toml

~a

phase \"the account\"
# The desktop is rendered into one account's home on the installed machine, so
# the account has to exist here first.  Its password is locked: the installer
# renames it and sets the one the person typed, and the live medium has an
# account of its own - nothing logs in as this one until that happens.
if ! id -u ~a >/dev/null 2>&1; then
    useradd -m -G wheel,video,audio,input,kvm,plugdev -s /bin/bash ~a
fi
passwd -l ~a >/dev/null 2>&1 || log \"no passwd tool: the account keeps no password\"
# A login shell reads .bash_profile, not .bashrc - and it is the login shell
# that puts the account's Guix profile on the PATH.  Without this line `bash -lc'
# finds no maak, and every phase of `heks-setup' after the stores is a command
# that does not exist.
if [ ! -e ~a/.bash_profile ]; then
    printf '%s\\n' '[ -f \"$HOME/.bashrc\" ] && . \"$HOME/.bashrc\"' > ~a/.bash_profile
    chown ~a:users ~a/.bash_profile
fi

phase \"the checkouts\"
install -d -o ~a -g users ~a/Hacking
~a
chown -R ~a:users ~a/Hacking
"
             (heks-linux-hostname)
             (heks-linux-language)
             (heks-linux-timezone)
             (image-greeter-config-filename)
             (string-append (image-service-lines)
                            "\nln -sfn /etc/sv/nix-daemon /etc/runit/runsvdir/default/ 2>/dev/null"
                            " || log \"nix-daemon service missing\"")
             user user user home home user home
             user home (image-checkout-lines) user home)
     "\n"
     (format #f "phase \"the tools that finish the job\"
# Four commands, and they are the whole of what the medium promises: render the
# desktop, set the machine up from nothing, install this system on a disk, and
# snapshot it before and after.  They travel with the installed system as well as
# with the medium, so a disk made from this rootfs can make another one.
for tool in ~a ~a ~a ~a; do
    install -m 755 \"/usr/local/lib/heks-linux/$tool\" \"/usr/local/bin/$tool\"
done

phase \"is it ready?\"
missing=0
check_path() {
    if [ -e \"$1\" ]; then log \"ok      $1 ($2)\"; else log \"MISSING $1 ($2)\"; missing=$((missing + 1)); fi
}
check_command() {
    if runuser -u ~a -- bash -lc \"command -v $1 >/dev/null 2>&1\"; then
        log \"ok      $1 on the user's PATH\"
    else
        log \"MISSING $1 on the user's PATH\"; missing=$((missing + 1))
    fi
}
~a
[ \"$missing\" -eq 0 ] || die \"$missing thing(s) missing from the image\"
log \"ready: the session, the disk tools and the commands that set the desktop up are here\"
"
             (image-payload-script-filename)
             (image-installer-filename)
             (image-setup-filename)
             (image-snapshot-filename)
             user
             (image-verify-lines)))))

;; ===========================================
;; The two artefacts
;; ===========================================

(define (image-host-prelude)
  "Return the shell both build scripts open with: one directory, one namespace.

The build is the one task in this tree that runs as root and mounts things - the
host's /proc, /sys and /dev inside the target, and whatever void-mklive mounts
for itself - so it opens by taking a mount namespace of its own: a build that
dies takes its mounts with it, instead of leaving a bind mount of the host's /dev
where the next `rm -rf' walks into it.  It also moves every temporary file it
makes out of /tmp, which is a tmpfs on most machines and therefore RAM."
  "set -euo pipefail

here=\"$(CDPATH= cd -- \"$(dirname \"$0\")\" && pwd)\"
self=\"$here/$(basename \"$0\")\"

# ---- the machine this runs on ----
# Every mount below this line lives in a namespace of this build's own, private
# and gone when the process is.  Without it a build that is killed - a full
# disk, an out-of-memory kill, a terminal closed at the wrong moment - leaves a
# bind mount of the host's /dev, /proc and /sys behind in the work directory,
# and the next run's rm -rf walks into them: deleting the host's device nodes,
# with every command that writes to /dev/null failing afterwards.  A machine is
# not worth a build that cannot be interrupted.
if [ \"${HEKS_IMAGE_ISOLATED:-0}\" = 0 ]; then
    if command -v unshare >/dev/null 2>&1 && unshare --mount --propagation private true 2>/dev/null; then
        echo \"==> isolated: this build's mounts go when it does\"
        HEKS_IMAGE_ISOLATED=1 exec unshare --mount --propagation private -- \"$self\" \"$@\"
    fi
    echo \"==> no mount namespace on this host: a build that dies leaves its mounts behind\" >&2
fi

# /tmp is a tmpfs on most machines, and a tmpfs is RAM: a base rootfs, an
# unpacked copy of it and a squashfs image beside them are several gigabytes
# held in memory before they are written, which is a machine that swaps itself
# to a standstill rather than a build that fills a disk.  Temporary files go
# beside the build, on the filesystem the build is on.
tmp=\"$here/tmp\"
install -d \"$tmp\"
export TMPDIR=\"$tmp\"

mklive=\"${MKLIVE_DIR:-$here/void-mklive}\"

# void-mklive installs and queries packages with xbps, which a host that is not
# Void does not carry.  A static build beside this script is what the build uses
# when it is there - the whole point of building from another distribution - and
# a host that has xbps of its own is not disturbed.
if [ -d \"$here/xbps-static/usr/bin\" ]; then
    PATH=\"$here/xbps-static/usr/bin:$PATH\"
    export PATH
fi

# void-mklive configures packages by chrooting into the target, and builds the
# medium's EFI loader by handing GRUB's grub-mkstandalone to xbps-uchroot.  Both
# xbps - which writes a package's INSTALL script - and grub-mkstandalone make
# their temporary files in $TMPDIR.  The TMPDIR exported above is a path on this
# machine, so inside the target it does not exist: a package's post-install step
# dies with \"INSTALL script failed to execute the post ACTION: No such file or
# directory\" and the EFI loader with \"cannot make temporary directory\", which
# is the last step of a medium that took an hour.  A wrapper that clears TMPDIR
# gives the target its own /tmp and leaves the disk-backed directory to the
# host, which is what the export above is for.
if [ -z \"${HEKS_IMAGE_TMPDIR_SHIM:-}\" ]; then
    for tool in chroot xbps-uchroot xbps-uunshare; do
        real=\"$(command -v \"$tool\")\" || continue
        printf '#!/bin/sh\\nexec env -u TMPDIR %s \"$@\"\\n' \"$real\" > \"$tmp/$tool\"
        chmod 755 \"$tmp/$tool\"
    done
    PATH=\"$tmp:$PATH\"
    HEKS_IMAGE_TMPDIR_SHIM=1
    export PATH HEKS_IMAGE_TMPDIR_SHIM
fi
")

(define (image-rootfs-script)
  "Return build-rootfs.sh: the installed system, as a tarball.

This is the half void-mklive does not do: mkrootfs.sh builds a base from
packages and stops, so the build unpacks it, installs the desktop with xbps,
runs config.sh in the chroot and packs the result."
  (format #f "#!/bin/bash
# ====== Heks-Linux: the installed system ======
#
# auto-generated file, DO NOT EDIT!

~a
arch=\"~a\"
out=\"$here/~a-~a-rootfs.$arch.tar.xz\"
work=\"$here/work-rootfs\"
rootfs=\"$here/work-base.tar.xz\"

# The three filesystems the configuration phase cannot run without, mounted into
# the target and unmounted on the way out.  Recursive and slave, the way a
# chroot is mounted: a plain bind of /dev leaves out /dev/pts and /dev/shm, and
# without --make-rslave the target could unmount the host's own mounts from
# inside.  The trap is what makes an aborted build clean up after itself.
pseudofs=\"proc sys dev\"

mount_pseudofs() {
    for tree in $pseudofs; do
        install -d \"$work/$tree\"
        mount --rbind \"/$tree\" \"$work/$tree\"
        mount --make-rslave \"$work/$tree\"
    done
}

umount_pseudofs() {
    for tree in $pseudofs; do
        umount -R -f \"$work/$tree\" 2>/dev/null || true
    done
}
trap umount_pseudofs EXIT
trap 'exit 130' INT TERM

[ -x \"$mklive/mkrootfs.sh\" ] || {
    echo \"void-mklive is not here. Clone it first:\" >&2
    echo \"  git clone https://github.com/void-linux/void-mklive $mklive\" >&2
    exit 1
}

echo \"==> the base: mkrootfs.sh ($arch)\"
# void-mklive's scripts open with `. ./lib.sh', so they run from their own
# directory and not from wherever the caller stands.  Every path they are handed
# is absolute for that reason.
cd \"$mklive\"
# void-mklive caches the packages it downloads under the current directory - by
# default that is its own checkout, where a retry after a failure would fetch a
# gigabyte again into a directory a re-clone would throw away.  Keep the cache
# beside the build instead.
export XBPS_CACHEDIR=\"--cachedir=$here/xbps-cache/$arch\"
install -d \"$here/xbps-cache/$arch\"

# Low priority: this build runs for an hour beside a desktop somebody is using.
nice -n 19 ./mkrootfs.sh -b base-system -r \"~a\" -o \"$rootfs\" \"$arch\"

echo \"==> unpacking it\"
# A mount from a build that died here is not deleted: rm would descend into it
# and delete the host's own filesystem instead of the work directory.  It stops
# the build with the one command that cleans it up.
for tree in $pseudofs; do
    if [ -e \"$work/$tree\" ] && mountpoint -q \"$work/$tree\"; then
        echo \"FAILED: $work/$tree is still a mount from a build that did not finish\" >&2
        echo \"  clean it up first: maak image-clean\" >&2
        exit 1
    fi
done
rm -rf --one-file-system \"$work\"
install -d \"$work\"
tar -xpf \"$rootfs\" -C \"$work\"
cp /etc/resolv.conf \"$work/etc/resolv.conf\"

# mkrootfs.sh reconfigures the base itself and does not stop when a package
# fails there, so the tarball it hands back can hold a package that was never
# configured: the error scrolls past among a hundred lines of downloads, and the
# image packed from it boots into a system whose post-install steps never ran.
# 'uu' is xbps's word for unpacked and not configured.
unconfigured=\"$(chroot \"$work\" xbps-query -l | awk '$1 == \"uu\" { print $2 }')\"
[ -z \"$unconfigured\" ] || {
    echo \"FAILED: the base rootfs never configured: $unconfigured\" >&2
    exit 1
}

echo \"==> the packages xbps does not put in a base\"
chroot \"$work\" xbps-install -Suy --yes $(tr '\\n' ' ' < \"$here/~a\")

echo \"==> the payload\"
# The whole overlay, the way mklive.sh is handed it: whatever config.sh reads has
# been delivered here first, so the two cannot drift apart.
cp -a \"$here/root/.\" \"$work/\"
install -D -m 644 \"$here/~a\" \"$work/usr/local/lib/heks-linux/~a\"

echo \"==> config.sh, inside the target\"
mount_pseudofs
chroot \"$work\" /bin/bash /usr/local/lib/heks-linux/config.sh
umount_pseudofs

echo \"==> packing $out\"
# One filesystem, so that nothing mounted inside the target can be packed into
# the tarball: a rootfs that carries the build machine's /proc is a rootfs that
# boots into a copy of somebody else's running system.
tar -C \"$work\" --one-file-system --xattrs -cJpf \"$out\" .
rm -rf --one-file-system \"$work\" \"$rootfs\" \"$tmp\"
echo \"Heks GNU/Linux: $out\"
"
          (image-host-prelude)
          (xbps-arch)
          image-name (image-version)
          (xbps-repository)
          (image-packages-filename)
          (image-config-script-filename) (image-config-script-filename)))

(define (image-iso-script)
  "Return build-iso.sh: the live medium, built by mklive.sh.

mklive.sh takes the package list as one argument, the payload as a directory to
copy into the rootfs, and the services to enable at boot.  It runs no
configuration phase, so the medium boots to a session that has been rendered by
heks-render and not before: the medium is how the desktop is looked at, and the
installer on it is what puts it on a disk."
  (format #f "#!/bin/bash
# ====== Heks-Linux: the live medium ======
#
# auto-generated file, DO NOT EDIT!

~a
# void-mklive makes its build directory in the current directory unless it is
# told where, and the current directory is its own checkout: gigabytes that a
# re-clone throws away.  Beside the build, like everything else.
export ROOTDIR=\"$here\"
arch=\"~a\"
out=\"$here/~a-~a-live.$arch.iso\"

[ -x \"$mklive/mklive.sh\" ] || {
    echo \"void-mklive is not here. Clone it first:\" >&2
    echo \"  git clone https://github.com/void-linux/void-mklive $mklive\" >&2
    exit 1
}

# The medium is only worth booting if it can install: heks-install unpacks this
# exact tarball, so a medium built without it is a look, not an installer.
rootfs=\"$here/~a-~a-rootfs.$arch.tar.xz\"
payload=\"$here/payload-iso\"
if [ ! -r \"$rootfs\" ]; then
    echo \"the medium cannot install without the rootfs\" >&2
    echo \"  build it first: $here/~a\" >&2
    exit 1
fi
rm -rf --one-file-system \"$payload\"
cp -a \"$here/root/.\" \"$payload/\"
# The medium's own half: the service that makes tty1 the installer, and the
# quickstart.  build-rootfs.sh copies `root/' and never this, so nothing here
# reaches an installed disk.
cp -a \"$here/~a/.\" \"$payload/\"
install -D -m 644 \"$rootfs\" \"$payload/usr/local/lib/heks-linux/$(basename \"$rootfs\")\"\n

# mklive.sh writes a hybrid medium: GRUB's BIOS stage in the ISO's own boot
# sector, and an EFI System Partition image beside it, which is what the
# firmware of a modern machine boots.  Nothing here chooses between the two.
# `. ./lib.sh', as above: mklive.sh runs from its own directory.
cd \"$mklive\"
# void-mklive caches the packages it downloads under the current directory - by
# default that is its own checkout, where a retry after a failure would fetch a
# gigabyte again into a directory a re-clone would throw away.  Keep the cache
# beside the build instead.
export XBPS_CACHEDIR=\"--cachedir=$here/xbps-cache/$arch\"
install -d \"$here/xbps-cache/$arch\"

# Low priority: the squashfs takes minutes of every core, and the machine this
# runs on is somebody's desktop.
nice -n 19 ./mklive.sh \\
    -a \"$arch\" \\
    -r \"~a\" \\
    -b base-system \\
    -p \"$(tr '\\n' ' ' < \"$here/~a\")\" \\
    -I \"$payload\" \\
    -S \"~a\" \\
    -k ~a \\
    -l ~a.UTF-8 \\
    -T \"Heks GNU/Linux ~a\" \\
    -o \"$out\"

rm -rf --one-file-system \"$payload\" \"$tmp\"
echo \"Heks GNU/Linux: $out\"
"
          (image-host-prelude)
          (xbps-arch)
          image-name (image-version)
          image-name (image-version)
          (image-rootfs-script-filename) (image-live-payload-dir)
          (xbps-repository)
          (image-packages-filename)
          (string-join (image-live-services) " ")
          (heks-linux-keyboard-layout)
          (heks-linux-language)
          (image-version)))

(define (image-payload-script)
  "Return heks-render: the desktop's files, rendered on demand.

The live medium has no rendered desktop until this runs; an installed system
whose channel pin moved, whose home was lost or whose palette switch went wrong
uses the same command."
  (let ((user (image-user)))
    (format #f "#!/bin/bash
# ====== Heks-Linux re-render ======
#
# auto-generated file, DO NOT EDIT!

set -euo pipefail

if [ \"$(id -un)\" != root ]; then
    echo \"heks-render renders another user's home: run it as root\" >&2
    exit 1
fi

# The account is an argument because it is not always the one the image was
# built for: heks-install renames that account to the name its person chose, and
# the files in the home name the account that rendered them.  The image's own
# account is the default, so the live medium needs no argument.
user=\"${1:-~a}\"

if ! id -u \"$user\" >/dev/null 2>&1; then
    echo \"no such account: $user\" >&2
    exit 1
fi

runuser -u \"$user\" -- bash -lc 'cd $HOME/Hacking/heks-linux && maak home-reconfigure'
runuser -u \"$user\" -- bash -lc 'cd $HOME/Hacking/heks-bash && maak install-bash'
runuser -u \"$user\" -- bash -lc 'cd $HOME/Hacking/heks-linux && maak install-icon-files'
runuser -u \"$user\" -- bash -lc 'cd $HOME/Hacking/heks-linux && maak install-wallpaper-files'
runuser -u \"$user\" -- bash -lc 'cd $HOME/Hacking/heks-emacs && maak install-emacs-config'
runuser -u \"$user\" -- bash -lc 'cd $HOME/Hacking/heks-linux && maak install-nix-packages'

echo \"Heks GNU/Linux is rendered: log out and back in to see it.\"
" user)))

;; ===========================================
;; Writing it
;; ===========================================

(define (image-live-installer-service)
  "Return the service that owns the medium's console.

runsv starts a service with a PATH and nothing else, and the installer draws
with dialog, which exits on an unknown terminal before it draws the first
screen: TERM is the difference between a wizard and a login prompt.

The service is the medium's own rather than Void's agetty-tty1 rewritten.  That
service is a symlink into the getty every console shares, and mklive copies the
payload with @command{cp -rfpP}, which follows a symlink at the *destination*:
shipping @file{agetty-tty1/run} overwrote the script of all six consoles, so each
of them ran an installer redirected at tty1 and then logged the live account in -
six logins in the first second of stage 2, which is what started logind through
dbus before the supervised one had the name and left elogind restarting every
second on the kernel console.  Void's getty is parked with a @file{down} file
instead, and this service runs the installer and gives the console back - when it
finishes, is cancelled or is refused - to a getty for the live account, which has
passwordless sudo."
  "#!/bin/sh
TERM=linux
export TERM
exec >/dev/tty1 2>&1 </dev/tty1
if [ -x /usr/local/bin/heks-install ]; then
    /usr/local/bin/heks-install
fi
exec agetty --autologin anon 38400 tty1
")

(define (image-live-consoles)
  "Return the consoles the medium draws on, as @code{(TTY . SERVICE)} pairs.

A console has one owner.  The installer is what tty1 is for, and a machine with
graphics gets the medium's menu on tty2; Void's getty on those two is parked with
a @file{down} file and never replaced, because mklive copies the payload with
@command{cp -rfpP}, which follows a symlink at the destination and would write
over the getty every console shares.  The remaining consoles keep their getty."
  (list (cons "tty1" "heks-installer")
        (cons "tty2" (image-live-gui-filename))))

(define (image-live-gui-filename)
  "Return the name of the medium's menu: a service, and the script it starts."
  "heks-live-gui")

(define (image-live-gui-service)
  "Return the service that owns the medium's second console.

cage is the compositor, kitty is its one window, and the window draws
@file{heks-live-gui} - the menu.  Nothing here is the desktop this medium
installs: that is rendered on the machine that keeps it, after the disk is
written, so a session on the medium would be a black screen with a login box on
it.  A window with the few things a person came here to do is what the medium can
honestly show.

Three details decide whether this is a screen or a respawn loop:

- cage needs a DRM device to start at all, so a machine whose graphics the kernel
  does not drive - a VM with none - gets the console's getty back instead of a
  compositor that restarts every second.
- runsv starts a service with a PATH and nothing else, and a Wayland compositor
  needs somewhere to put its socket: @var{XDG_RUNTIME_DIR} is set here and made
  private, because libwayland refuses to start without it.
- @option{-s} is what keeps Alt+F1 working, and Alt+F1 is the installer on tty1."
  "#!/bin/sh
TERM=linux
HOME=/root
XDG_RUNTIME_DIR=/run/heks-live-gui
export TERM HOME XDG_RUNTIME_DIR
exec >/dev/tty2 2>&1 </dev/tty2
install -d -m 700 \"$XDG_RUNTIME_DIR\"
if ls /dev/dri/card* >/dev/null 2>&1; then
    cage -s -- kitty -e /usr/local/lib/heks-linux/heks-live-gui
fi
exec agetty --autologin anon -- tty2 38400
")

(define (image-live-gui-menu)
  "Return @file{heks-live-gui}: the medium's one window, as a menu.

It is a terminal menu and not a desktop for the reason above: there is no
rendered session on the medium to show.  Every choice that ends returns to the
menu, because Cancel is how a person says \"not that one\" and a closed window
would take the rest of the menu with it."
  (format #f "#!/bin/sh
# ====== Heks-Linux live menu ======
#
# auto-generated file, DO NOT EDIT!

set -eu

# The wizard's palette: green ink on a dark screen, warm title.  A medium that
# somehow lacks the file draws dialog's own colours and opens all the same.
if [ -r ~a/~a ]; then
    DIALOGRC=~a/~a
    export DIALOGRC
fi

while :; do
    choice=$(dialog --stdout --title 'Heks GNU/Linux ~a' \\
        --menu 'This medium installs the desktop. It does not carry it.

Everything is here to put it on a disk - take your time.' \\
        20 68 6 \\
        install    'Erase a disk and install Heks GNU/Linux' \\
        terminal   'A shell in the live system' \\
        quickstart 'What this medium is, and what it asks' \\
        poweroff   'Power the machine off' \\
        exit       'Close this window') || exit 0
    case \"$choice\" in
        # A failed install must not look like a menu that redrew: the wizard
        # says so on the console, and this window - which draws over it - says
        # so too, and points at the record.
        install) heks-install || \\
            dialog --title 'Heks GNU/Linux' --msgbox 'The install stopped before it finished.

The whole record is /var/log/heks-install.log: read it with less, then run the
install again.' 0 0 ;;
        terminal) runuser -u anon -- bash -l || true ;;
        quickstart) heks-help || true ;;
        poweroff) poweroff ;;
        *) exit 0 ;;
    esac
done
"
          (image-share-dir) (image-dialog-theme-filename)
          (image-share-dir) (image-dialog-theme-filename)
          (image-version)))

(define (image-quickstart)
  "Return the quickstart the medium carries for whoever drops to a shell.

It is plain text on purpose: the one document that has to be readable before
anything is configured, on a console with no pager flags, no fonts and no
colours worth trusting."
  (format #f "Heks GNU/Linux ~a - quickstart

This medium installs the desktop on a disk.  It changes nothing until you say
so, and it carries everything the install itself needs - the disk tools, the
system it unpacks, and the wizard.

The desktop's own stores are the one thing it does not carry: guix and nix are a
few gigabytes, and they are installed on the machine that will keep them, after
the disk is written.  That is the phase that needs the network - and no network
is not a failure: the install finishes, the machine boots, and heks-setup
finishes the desktop once there is one.

Void's non-free repository is enabled before the machine boots: the microcode,
the firmware a wireless card needs and the drivers main does not carry are one
xbps-install away.

  install        sudo heks-install

The wizard asks seven things - the disk, the firmware, the network, the disk
passphrase, the host name and the user with its password - and then shows you the
plan.  The network is only asked about when the machine is not already on one:
pick the wired or the wireless interface, and a wireless network asks for its
name and its password.  That connection is copied to the new system, so the
machine is online the first time it boots.

Your wired and wireless cards work from the medium: it carries the firmware they
load (including the non-free blobs) and the supplicant NetworkManager joins a
WPA network with.

  At boot, the passphrase is typed with a US keyboard.  Use letters and digits
  you can find blind, and write the passphrase down somewhere else.

  Your disk is erased.  Every disk attached is offered; the one this medium is
  running from is refused.

What it builds: UEFI gets a GPT disk with an EFI System Partition and a boot
partition; legacy firmware gets an MBR disk.  The rest is a LUKS2 container with
BTRFS inside it, and the root, the homes and the snapshots as three subvolumes.
The passphrase is asked once, at boot, by the initramfs.

The system snapshots itself once a day: a read-only copy of the root subvolume in
/.snapshots, with the oldest deleted once there are more than 14.  heks-snapshot
list shows them, heks-snapshot create before-update takes one by hand, and
heks-snapshot cleanup throws the old ones away.  The homes are not part of a
snapshot, so rolling back does not cost you today's work.

Once the stores are there, the render assembles the desktop itself - the shell,
the dock, the keyboard reference and every configuration file.  The medium can
then also leave the new system ready with the rest of the projects, the
workstation package sets, the Flatpak applications and Emacs built from master.
Those pull from the network; the first one is on by default.

  live user      anon, with passwordless sudo
  the window     Alt+F2, a menu of the same choices, on a machine with graphics
  the setup      heks-setup, if the install could not finish it
  the logs       /var/log/heks-install.log, /var/log/heks-setup.log
  this text      heks-help, or /usr/local/share/heks-linux/quickstart.txt
  the guide      the installation page of the heks-linux repository

If something goes wrong, the installer stops and names the command that failed
on the screen: the whole record is /var/log/heks-install.log.  Read it, then run
the installer again.  Nothing it does before the confirmation is permanent.
"
          (image-version)))

(define (image-dialog-theme)
  "Return the dialog theme the medium's screens are drawn with.

Every line here is a key @command{dialog --create-rc} writes: the parser refuses
a whole file over one unknown name, so this is that file with its colours
changed rather than a shorthand of it.  What changed is the point - the default
palette is cyan on blue with white bars, and a console that boots into a wizard
should look like the system it is about to install.

@code{GREEN} on @code{BLACK} for everything that is text, the border in green
too, and the title, the position indicator and the active button in @code{YELLOW}
- warm against the green - so the eye lands on the question rather than the
frame.  The buttons invert rather than change hue: dark ink on a green field."
  "# Heks GNU/Linux: green ink on a dark screen, warm where it helps.
#
# Read by dialog when DIALOGRC names it - heks-install and the medium's window
# both do - and ignored by a console that has no file to read.
use_shadow = OFF
use_colors = ON
screen_color = (GREEN,BLACK,OFF)
shadow_color = (BLACK,BLACK,OFF)
dialog_color = (GREEN,BLACK,OFF)
title_color = (YELLOW,BLACK,ON)
border_color = (GREEN,BLACK,ON)
button_active_color = (BLACK,GREEN,ON)
button_inactive_color = (GREEN,BLACK,OFF)
button_key_active_color = (BLACK,GREEN,ON)
button_key_inactive_color = (YELLOW,BLACK,OFF)
button_label_active_color = (BLACK,GREEN,ON)
button_label_inactive_color = (GREEN,BLACK,OFF)
inputbox_color = (GREEN,BLACK,OFF)
inputbox_border_color = (GREEN,BLACK,ON)
inputbox_border2_color = (GREEN,BLACK,OFF)
searchbox_color = (GREEN,BLACK,OFF)
searchbox_title_color = (YELLOW,BLACK,ON)
searchbox_border_color = (GREEN,BLACK,ON)
searchbox_border2_color = (GREEN,BLACK,OFF)
position_indicator_color = (YELLOW,BLACK,ON)
menubox_color = (GREEN,BLACK,OFF)
menubox_border_color = (GREEN,BLACK,ON)
menubox_border2_color = (GREEN,BLACK,OFF)
item_color = (GREEN,BLACK,OFF)
item_selected_color = (BLACK,GREEN,ON)
tag_color = (YELLOW,BLACK,OFF)
tag_selected_color = (BLACK,GREEN,ON)
tag_key_color = (YELLOW,BLACK,OFF)
tag_key_selected_color = (YELLOW,GREEN,ON)
check_color = (GREEN,BLACK,OFF)
check_selected_color = (BLACK,GREEN,ON)
uarrow_color = (GREEN,BLACK,ON)
darrow_color = (GREEN,BLACK,ON)
itemhelp_color = (WHITE,BLACK,OFF)
form_active_text_color = (BLACK,GREEN,ON)
form_text_color = (GREEN,BLACK,OFF)
form_item_readonly_color = (YELLOW,BLACK,OFF)
gauge_color = (YELLOW,BLACK,ON)
border2_color = (GREEN,BLACK,OFF)
")

(define image-setup-filename
  (make-parameter "heks-setup"))

;; The snapshots the installed system takes of itself.
;;
;; The layout heks-install builds is one BTRFS filesystem with `@` mounted at
;; `/`, `@home` at `/home` and `@snapshots` at `/.snapshots`, which is what makes
;; a snapshot of `/` the system without anybody's home directory in it, stored
;; outside the subvolume it was taken from.  Nothing took one until this
;; program did: three subvolumes and a mountpoint, and no snapshot to roll back
;; to.
(define image-snapshot-filename
  (make-parameter "heks-snapshot"))

(define image-snapshot-dir
  (make-parameter "/.snapshots"))

;; How many daily snapshots are kept.  A fortnight is long enough to notice that
;; something broke a week ago and short enough that an idle machine's snapshots
;; do not grow without end; a snapshot is cheap, but a thousand of them are a
;; disk somebody has to clear by hand.
(define image-snapshot-keep
  (make-parameter 14))

(define (image-snapshot-script)
  "Return @code{heks-snapshot}: the snapshots, and the cleanup that keeps them.

Three commands and no daemon: @code{create} takes a read-only snapshot of the
root subvolume, @code{list} shows what is there, @code{cleanup} deletes the
oldest and keeps the newest few.  The service beside it is what calls the first
and the last once a day, and a machine whose service is off - or a person who
wants a snapshot before an upgrade - runs the same two by hand."
  (format #f "#!/bin/bash
# ====== Heks-Linux snapshots ======
#
# auto-generated file, DO NOT EDIT!
#
# A snapshot of the root subvolume, and the cleanup that keeps them from filling
# the disk.  The root is `@`, so a snapshot of it is the system as it was, without
# anybody's home directory: `@home` is a subvolume of its own and is not part of
# it.  The snapshots live in `@snapshots`, mounted at `~a`, which is outside the
# subvolume being snapshotted - a snapshot stored inside the thing it copies is
# a snapshot a rollback takes with it.

set -euo pipefail

snapshots=~a
keep=~a

log() { printf '[heks-snapshot] %s\\n' \"$*\"; }
die() {
    log \"FAILED: $*\" >&2
    exit 1
}

usage() {
    cat >&2 <<'HEKS_USAGE'
usage: heks-snapshot create [DESCRIPTION]
       heks-snapshot list
       heks-snapshot cleanup [KEEP]

create     a read-only snapshot of / in ~a
list       the snapshots there, oldest first
cleanup    delete the oldest, keeping the newest KEEP (~a by default)
HEKS_USAGE
    exit 2
}

# Every command writes inside the subvolume the installer mounted at ~a.  A
# directory that is not a mount is part of @ - the fstab line is missing, or the
# mount failed - and a snapshot in there would be inside the thing it copies.
require_snapshots() {
    [ -d \"$snapshots\" ] \\
        || die \"no $snapshots: this root is not the BTRFS layout heks-install builds\"
    mountpoint -q \"$snapshots\" \\
        || die \"$snapshots is not a mounted subvolume: check /etc/fstab, mount it, then run this again\"
}

# create [DESCRIPTION]: one read-only snapshot, named by the time it was taken.
create() {
    local description=\"${1:-manual}\" stamp name
    require_snapshots
    stamp=\"$(date +%Y-%m-%dT%H%M%S)\"
    # The description becomes part of a name that is sorted and deleted by, so
    # it is reduced to what a directory name can hold: anything else - a slash, a
    # space, a quote - would be a path or a word where one is expected.
    description=\"$(printf '%s' \"$description\" \\
        | tr -c '[:alnum:]' '-' | sed 's/--*/-/g; s/^-//; s/-$//')\"
    name=\"$stamp${description:+-$description}\"
    btrfs subvolume snapshot -r / \"$snapshots/$name\"
    log \"created $snapshots/$name\"
}

# list: what is there, oldest first, which is how the names sort.
list() {
    require_snapshots
    ls -1 \"$snapshots\"
}

# cleanup [KEEP]: delete the oldest, keep the newest KEEP.
cleanup() {
    local wanted=\"${1:-$keep}\" total deleted=0 snapshot
    case \"$wanted\" in
        ''|*[!0-9]*) die \"cleanup takes a number - how many snapshots to keep - not '$wanted'\" ;;
    esac
    [ \"$wanted\" -ge 1 ] \\
        || die 'keep at least one snapshot: deleting the newest leaves nothing to roll back to'
    require_snapshots
    total=\"$(ls -1 \"$snapshots\" | wc -l)\"
    # The names begin with the time they were taken, so the oldest are the first
    # lines and `head -n -KEEP' is everything but the newest KEEP.
    for snapshot in $(ls -1 \"$snapshots\" | head -n \"-$wanted\"); do
        btrfs subvolume delete \"$snapshots/$snapshot\"
        deleted=$((deleted + 1))
    done
    log \"kept the newest $wanted, deleted $deleted of $total\"
}

[ \"$(id -un)\" = root ] || die 'snapshots belong to root: run this with sudo'

command=\"${1:-}\"
if [ \"$#\" -gt 0 ]; then
    shift
fi
case \"$command\" in
    create) create \"$@\" ;;
    list) list ;;
    cleanup) cleanup \"$@\" ;;
    *) usage ;;
esac
"
          (image-snapshot-dir) (image-snapshot-dir) (image-snapshot-keep)
          (image-snapshot-dir) (image-snapshot-keep) (image-snapshot-dir)))

(define (image-snapshot-service)
  "Return the runit service that takes the daily snapshot and cleans up after it.

runit has no cron, so the schedule is a service that runs in the foreground and
sleeps between snapshots - runsv restarts it if it ever dies.  The first snapshot
is taken as soon as the machine starts, which is what makes the state a fresh
install booted into one a rollback can return to, and the cleanup runs straight
after it, so a machine that is never looked at still keeps only the newest ones."
  (format #f "#!/bin/sh
# ====== Heks-Linux snapshots, once a day ======
#
# auto-generated file, DO NOT EDIT!

exec 2>&1

while :; do
    /usr/local/bin/~a create daily || echo '~a: the daily snapshot failed'
    /usr/local/bin/~a cleanup || echo '~a: the cleanup failed'
    sleep 86400
done
"
          (image-snapshot-filename) (image-snapshot-filename)
          (image-snapshot-filename) (image-snapshot-filename)))

(define (image-setup-script)
  "Return heks-setup: the stores, and the desktop, on the machine that will use them.

This is the half of the build the medium does not carry.  Guix and Nix are not in
the image - they are a few gigabytes a person downloading an installer should not
have to fetch before they have a disk - so the machine that is installed installs
them itself, once, and renders its own desktop.

It is safe to run again: every step asks for what it needs and does nothing when
it is already there.  On a booted system runit has the two daemons running
already; in a chroot - the installer's case - the only thing that can start them
is this script."
  (let ((user (image-user)))
    (format #f "#!/bin/bash
# ====== Heks-Linux first setup ======
#
# auto-generated file, DO NOT EDIT!

set -euo pipefail

LOG=/var/log/heks-setup.log
install -d -m 755 \"$(dirname \"$LOG\")\"
touch \"$LOG\"

log() { printf '[heks-setup] %s\\n' \"$*\" | tee -a \"$LOG\"; }
phase() { log ''; log \"========== $* ==========\"; }
die() { log \"FAILED: $*\"; log \"the whole record is $LOG\"; exit 1; }
trap 'die \"line $LINENO: $BASH_COMMAND\"' ERR

if [ \"$(id -un)\" != root ]; then
    echo 'heks-setup installs stores and renders a home: run it as root' >&2
    exit 1
fi

user=\"${1:-~a}\"
id -u \"$user\" >/dev/null 2>&1 || die \"no such account: $user\"
home=\"$(getent passwd \"$user\" | cut -d: -f6)\"
[ -n \"$home\" ] || die \"$user has no home directory\"

phase 'the network'
# Both stores arrive over it, and this machine may well have been installed
# without one: the installer runs this phase when the network is there and says
# so when it is not, and a person runs it by hand later.  Asking first is what
# turns ten minutes of failing downloads into one sentence.
if command -v ping >/dev/null 2>&1 && ! ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
    die 'no network: guix and nix arrive over it - connect this machine, then run heks-setup again'
fi

phase 'the stores'
# Guix is not a Void package.  It arrives from its own installer, which does not
# know runit, so the daemon's service is written here rather than expected.
if [ -x /var/guix/profiles/per-user/root/current-guix/bin/guix ]; then
    log 'guix is already installed'
else
    curl -fsSL https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh -o /tmp/guix-install.sh
    # The installer reads one answer per question: return to continue, one per
    # signing key it cannot find, the build farms, and whether to write a Guix
    # prompt into every .bashrc.  An empty line is the yes it documents
    # (`yes '' | guix-install.sh'); the prompt question is always the last, and
    # this desktop's shell is heks-bash's, so that one is the no.
    #
    # shortcut: the answers are positional, so an installer that gains or loses
    # a question shifts every answer; read its questions again when it changes.
    printf '\\ny\\ny\\ny\\ny\\nn\\n' | bash /tmp/guix-install.sh \\
        || log 'the guix installer stopped at init detection: the runit service below is what starts the daemon'
    log 'the guix installer is done'
fi
# Nothing below asks anything.  A command that tries reads end-of-file and
# stops where it stands instead of waiting for a keyboard on the console the
# wizard is drawing on: an install waiting for input is an install that never
# ends.
exec </dev/null

install -d -m 755 /etc/sv/guix-daemon
cat > /etc/sv/guix-daemon/run <<'HEKS_GUIX'
#!/bin/sh
exec /var/guix/profiles/per-user/root/current-guix/bin/guix-daemon \\
    --build-users-group=guixbuild \\
    --substitute-urls=\"https://ci.guix.gnu.org https://bordeaux.guix.gnu.org\"
HEKS_GUIX
chmod +x /etc/sv/guix-daemon/run
ln -sfn /etc/sv/guix-daemon /etc/runit/runsvdir/default/
ln -sfn /etc/sv/nix-daemon /etc/runit/runsvdir/default/ 2>/dev/null || log 'nix-daemon service missing'

# On a booted machine runit has both of these running and this changes nothing.
# Under the installer there is no init at all, so they are started here and the
# sockets are waited for: a store that is not answering is a store whose next
# command fails with an error about a socket nobody reads.
stores_answer() { [ -S /var/guix/daemon-socket/socket ] && [ -S /nix/var/nix/daemon-socket/socket ]; }
if stores_answer; then
    log 'both stores already answer'
else
    /var/guix/profiles/per-user/root/current-guix/bin/guix-daemon \\
        --build-users-group=guixbuild > /var/log/guix-daemon.log 2>&1 &
    # The medium's PATH carries no /nix, so the target's own daemon is named by
    # its path: a bare name is a command that does not exist in a chroot.
    /nix/var/nix/profiles/default/bin/nix-daemon > /var/log/nix-daemon.log 2>&1 &
    for _ in $(seq 1 60); do
        stores_answer && break
        sleep 1
    done
    stores_answer || die 'a store did not come up: see /var/log/guix-daemon.log and /var/log/nix-daemon.log'
    log 'both stores answer: guix and nix can install here'
fi

phase 'the desktop'
# As the account, because that is whose profile and whose home these are: a home
# rendered by root is a home the desktop cannot write to.
# Each step says when it starts.  A pull of the pinned channels is minutes of
# download and a render is an hour of builds, and a console that shows nothing
# cannot tell a slow step from a stuck one.
log 'pulling the pinned channels'
runuser -u \"$user\" -- bash -lc 'cd $HOME/Hacking/heks-linux && guix pull --channels=channels.scm'
log 'installing maak and guile into the account'
runuser -u \"$user\" -- bash -lc 'guix install maak guile'
log 'rendering the desktop'
/usr/local/bin/~a \"$user\"

phase 'is it ready?'
missing=0
check_path() {
    if [ -e \"$1\" ]; then log \"ok      $1 ($2)\"; else log \"MISSING $1 ($2)\"; missing=$((missing + 1)); fi
}
check_command() {
    if runuser -u \"$user\" -- bash -lc \"command -v $1 >/dev/null 2>&1\"; then
        log \"ok      $1 on the user's PATH\"
    else
        log \"MISSING $1 on the user's PATH\"; missing=$((missing + 1))
    fi
}
~a
[ \"$missing\" -eq 0 ] || die \"$missing thing(s) missing: the desktop is not finished\"
log \"ready: the stores are built and $user's desktop is rendered\"
log 'reboot to start the session the login prompt offers'
"
            user
            (image-payload-script-filename)
            (image-rendered-verify-lines))))

(define (image-installer-script)
  "Return @file{heks-install}: the wizard the medium puts this system on a disk with.

It lives in @code{(heks-linux installer)}, which reads this module for the name,
the version and the account it installs - so it is looked up when the build is
rendered rather than imported here, and the two modules stay one-way."
  ((@ (heks-linux installer) installer-script)))

(define (image-description)
  "Return the build as @code{(filename . contents)} pairs.

A description is a directory, not a file: the package list, the script that runs
inside the target, and the two scripts that drive void-mklive.  Returning it as
data keeps the renderer and the spec reading the same thing."
  (list (cons (image-packages-filename)
              (string-join (image-packages) "\n"))
        (cons (image-config-script-filename) (image-config-script))
        (cons (image-rootfs-script-filename) (image-rootfs-script))
        (cons (image-iso-script-filename) (image-iso-script))))

(define* (install-config-link! #:key name dir target)
  "Point @var{name} inside @var{dir} at @var{target}, and write nothing else.

A symlink is what runit follows: the runlevel directory names services, and the
path in the link is the one the image will have, not the one this machine
rendering it has.  Re-rendering replaces the link, so a rename does not leave two."
  (unless (dry-run?)
    (ensure-directory-tree! dir)
    (let ((link (format #f "~a/~a" dir name)))
      (catch 'system-error
             (lambda () (delete-file link))
             (lambda (key . args) #f))
      (symlink target link))))

(define* (install-image-config #:key (dir (image-description-dir)))
  "Write the build into @var{dir} and return the directory.

It refuses a target this tree cannot build before it writes anything, so a musl
build fails at the render and not an hour into mkrootfs.sh."
  (ensure-supported-libc!)
  (ensure-directory-tree! dir)
  (for-each (lambda (entry)
              (install-config-file!
               #:name (car entry)
               #:dir dir
               #:contents (cdr entry)
               #:perms (if (string=? (car entry) (image-packages-filename))
                         420
                         493)))
            (image-description))
  (install-config-file! #:name "config.toml"
                        #:dir (format #f "~a/root/etc/greetd" dir)
                        #:contents (greetd-config)
                        #:perms 420)
  (install-config-file! #:name (image-greeter-config-filename)
                        #:dir (format #f "~a/~a" dir (image-payload-dir))
                        #:contents (greetd-config)
                        #:perms 420)
  (install-config-file! #:name (image-payload-script-filename)
                        #:dir (format #f "~a/~a" dir (image-payload-dir))
                        #:contents (image-payload-script)
                        #:perms 493)
  (install-config-file! #:name (image-installer-filename)
                        #:dir (format #f "~a/~a" dir (image-payload-dir))
                        #:contents (image-installer-script)
                        #:perms 493)
  (install-config-file! #:name (image-setup-filename)
                        #:dir (format #f "~a/~a" dir (image-payload-dir))
                        #:contents (image-setup-script)
                        #:perms 493)
  (install-config-file! #:name (image-snapshot-filename)
                        #:dir (format #f "~a/~a" dir (image-payload-dir))
                        #:contents (image-snapshot-script)
                        #:perms 493)
  ;; The service that takes them once a day.  A service is a directory with a
  ;; `run' in it, and the configuration phase enables it like every other one -
  ;; so the file has to be in the payload the rootfs carries.
  (install-config-file! #:name "run"
                        #:dir (format #f "~a/root/etc/sv/~a"
                                      dir (image-snapshot-filename))
                        #:contents (image-snapshot-service)
                        #:perms 493)
  ;; The medium's own half.  build-rootfs.sh never copies this directory, so a
  ;; live-only service or document cannot end up on an installed disk.
  (install-config-file! #:name "run"
                        #:dir (format #f "~a/~a/etc/sv/heks-installer"
                                      dir (image-live-payload-dir))
                        #:contents (image-live-installer-service)
                        #:perms 493)
  (install-config-file! #:name "run"
                        #:dir (format #f "~a/~a/etc/sv/~a"
                                      dir (image-live-payload-dir)
                                      (image-live-gui-filename))
                        #:contents (image-live-gui-service)
                        #:perms 493)
  (install-config-file! #:name (image-live-gui-filename)
                        #:dir (format #f "~a/~a/usr/local/lib/heks-linux"
                                      dir (image-live-payload-dir))
                        #:contents (image-live-gui-menu)
                        #:perms 493)
  ;; Each console's service is linked into the runlevel here rather than with
  ;; `-S', because mklive enables the services it is handed *before* it copies
  ;; the payload: a name it has not seen yet is a name it refuses.  The getty on
  ;; the same console is parked with a `down' file, not replaced: one console
  ;; cannot be both a login prompt and a wizard, or a login prompt and a window.
  (for-each (lambda (console)
              (install-config-file! #:name "down"
                                    #:dir (format #f "~a/~a/etc/sv/agetty-~a"
                                                  dir (image-live-payload-dir)
                                                  (car console))
                                    #:contents ""
                                    #:perms 420)
              (install-config-link! #:name (cdr console)
                                    #:dir (format #f "~a/~a/etc/runit/runsvdir/default"
                                                  dir (image-live-payload-dir))
                                    #:target (format #f "/etc/sv/~a" (cdr console))))
            (image-live-consoles))
  ;; `heks-install` is where the installer is on the installed system, so the
  ;; medium gets the same name pointing into the payload it carries.
  (install-config-file! #:name (image-installer-filename)
                        #:dir (format #f "~a/~a/usr/local/bin"
                                      dir (image-live-payload-dir))
                        #:contents (format #f "#!/bin/sh
exec /usr/local/lib/heks-linux/~a \"$@\"
"
                                           (image-installer-filename))
                        #:perms 493)
  ;; The quickstart and the one command that shows it belong to both systems:
  ;; the medium, where a person is most likely to be lost, and the installed
  ;; machine, where they are a file's width away from being lost again.
  (install-config-file! #:name "quickstart.txt"
                        #:dir (format #f "~a/root~a" dir (image-share-dir))
                        #:contents (image-quickstart)
                        #:perms 420)
  ;; The wizard's palette, beside the quickstart and for the same reason: the
  ;; first screen a person sees is drawn with it.
  (install-config-file! #:name (image-dialog-theme-filename)
                        #:dir (format #f "~a/root~a" dir (image-share-dir))
                        #:contents (image-dialog-theme)
                        #:perms 420)
  (install-config-file! #:name (image-help-filename)
                        #:dir (format #f "~a/root/usr/local/bin" dir)
                        #:contents (format #f "#!/bin/sh
exec less ~a/quickstart.txt
"
                                           (image-share-dir))
                        #:perms 493)
  dir)
