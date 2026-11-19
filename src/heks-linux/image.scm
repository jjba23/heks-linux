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
            image-live-payload-dir
            image-help-filename
            image-live-services
            image-live-installer-service
            image-quickstart
            image-build-log
            image-base-packages
            image-toolchain-packages
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
;; than a constant: when 6.12 leaves the repositories, the image moves with one
;; line instead of a build that fails at the package step.
(define image-kernel
  (make-parameter "linux6.12"))

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

(define image-required-paths
  '((".config/niri/config.kdl" . "the compositor's configuration")
    (".config/whelk/settings.scm" . "the shell's configuration")
    (".bashrc" . "the shell")
    (".emacs.d/init.el" . "the editor")
    (".local/share/icons/Tela" . "the icon themes")
    (".local/bin/heks-wallpaper" . "the wallpaper engine")))

(define image-required-commands
  '("guix" "nix" "maak" "niri" "whelk" "kitty" "emacs"
    ;; The medium installs itself: these four are what it needs to lay out a
    ;; disk and put this system on it.
    "cryptsetup" "mkfs.btrfs" "mkfs.ext4" "grub-install"
    "parted" "dialog" "heks-install"))

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
(define image-toolchain-packages
  '("curl" "git" "guile" "nix"))

(define (image-packages)
  "Return every package the image carries, deduplicated and sorted.

The session, the desktop, the command line and the fonts come from
@code{(heks-linux packages xbps)}'s own lists, so an image and a hand-installed
machine cannot disagree about what the desktop is.  The greeter is read here
rather than taken from that module's union because mklive.sh is handed names,
not a backend - switch the greeter and the image follows."
  (map xbps-package-name
       (package-sorted-set
        (append (image-base-packages)
                image-toolchain-packages
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
# enable services, and every daemon it needs it starts by hand.

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
;; into /var/service, systemd enables its unit.
(define image-services
  '("dbus" "elogind" "polkitd" "rtkit" "NetworkManager" "greetd"))

;; What the live medium starts, which is not what the installed system starts.
;; The medium exists to install, so it boots into the installer on tty1 and
;; leaves greetd out: a graphical prompt over a desktop that has not been
;; rendered yet is a black screen with a login box on it, and it would want the
;; console the installer draws on.
(define (image-live-services)
  "Return the services the live medium enables at boot."
  (remove (lambda (service)
            (string=? service "greetd"))
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

;; What the build runs as the live user, in order.  Quoting is the shell's:
;; each command is passed to `bash -lc' as one argument.
(define image-desktop-commands
  '("cd $HOME/Hacking/heks-linux && guix pull --channels=channels.scm"
    "guix install maak guile"
    "cd $HOME/Hacking/heks-linux && maak home-reconfigure"
    "cd $HOME/Hacking/heks-bash && maak install-bash"
    "cd $HOME/Hacking/heks-linux && maak install-icon-files"
    "cd $HOME/Hacking/heks-linux && maak install-wallpaper-files"
    "cd $HOME/Hacking/heks-emacs && maak install-emacs-config"
    "cd $HOME/Hacking/heks-linux && maak install-nix-packages"))

(define (image-desktop-lines)
  "Return the desktop phases as the live user's own shell."
  (let ((user (image-user)))
    (string-join
     (map (lambda (command)
            (format #f "runuser -u ~a -- bash -lc '~a'" user command))
          image-desktop-commands)
     "\n")))

(define (image-verify-lines)
  "Return the checks that decide whether the image is finished.

The last phase is the only one that can say no: it counts what is missing and
the script fails if the count is not zero, so an image that was never rendered
does not get packed."
  (let ((home (image-user-home))
        (user (image-user)))
    (string-join
     (append
      (map (lambda (required)
             ;; The message is a person's words, so it is rendered as a
             ;; double-quoted string: "the compositor's configuration" inside
             ;; single quotes ends the quote early and swallows the checks after
             ;; it, which is a readiness check that quietly checks less.
             (format #f "check_path '~a/~a' ~s"
                     home (car required) (cdr required)))
           image-required-paths)
      (list "check_path '/etc/greetd/config.toml' 'the login prompt'")
      (map (lambda (command)
             (format #f "check_command ~a" command))
           image-required-commands))
     "\n")))

(define (image-config-script)
  "Return config.sh: the whole build inside the image, in order.

Every phase is logged and the last one is a question: is the desktop actually
there?  A build that skips the question is a build that has never been run."
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
# The desktop is rendered into one account's home, so the account has to exist
# before anything runs as it.  Its password is locked here: the installer renames
# it and sets the one the person typed, and the live medium has an account of its
# own - nothing logs in as this one until that happens.
if ! id -u ~a >/dev/null 2>&1; then
    useradd -m -G wheel,video,audio,input,kvm,plugdev -s /bin/bash ~a
fi
passwd -l ~a >/dev/null 2>&1 || log \"no passwd tool: the account keeps no password\"
# A login shell reads .bash_profile, not .bashrc - and it is the login shell
# that puts the account's Guix profile on the PATH.  Without this line `bash -lc'
# finds no maak, which is the shape of every phase after this one.
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
             (image-service-lines)
             user user user home home user home
             user home (image-checkout-lines) user home)
     "\n"
     "phase \"the two stores\"
# Void packages nix with its own runit service.  Guix is not a Void package, so
# it arrives from its own installer; the installer does not know runit, which is
# why the daemon's service is written here rather than expected.
ln -sfn /etc/sv/nix-daemon /var/service/ 2>/dev/null || log \"nix-daemon service missing\"
if [ -x /var/guix/profiles/per-user/root/current-guix/bin/guix ]; then
    log \"guix is already installed\"
else
    curl -fsSL https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh -o /tmp/guix-install.sh
    bash /tmp/guix-install.sh \\
        || log \"the guix installer stopped at init detection: the runit service below is what starts the daemon\"
fi
install -d -m 755 /etc/sv/guix-daemon
cat > /etc/sv/guix-daemon/run <<'HEKS_GUIX'
#!/bin/sh
exec /var/guix/profiles/per-user/root/current-guix/bin/guix-daemon \\
    --build-users-group=guixbuild \\
    --substitute-urls=\"https://ci.guix.gnu.org https://bordeaux.guix.gnu.org\"
HEKS_GUIX
chmod +x /etc/sv/guix-daemon/run
ln -sfn /etc/sv/guix-daemon /var/service/

# The build has no init running, so the two daemons everything below talks to -
# guix pull, guix install, nix profile install, maak home-reconfigure - are
# started here by hand.  A chroot that enables a service and never starts it is a
# chroot whose next phase cannot reach the store it just installed.
/var/guix/profiles/per-user/root/current-guix/bin/guix-daemon \\
    --build-users-group=guixbuild > /var/log/guix-daemon.log 2>&1 &
nix-daemon > /var/log/nix-daemon.log 2>&1 &
for _ in $(seq 1 60); do
    [ -S /var/guix/daemon-socket/socket ] && [ -S /nix/var/nix/daemon-socket/socket ] && break
    sleep 1
done
[ -S /var/guix/daemon-socket/socket ] || die \"the guix daemon did not come up: see /var/log/guix-daemon.log\"
[ -S /nix/var/nix/daemon-socket/socket ] || die \"the nix daemon did not come up: see /var/log/nix-daemon.log\"
log \"both stores answer: guix and nix can install into this image\"
"
     "\n"
     (format #f "phase \"the desktop\"
# As the live user, because that is whose profile and whose home these are: a
# home rendered by root is a home the desktop cannot write to.
~a
"
             (image-desktop-lines))
     "\n"
     (format #f "phase \"re-rendering it later\"
install -m 755 /usr/local/lib/heks-linux/~a /usr/local/bin/~a
# The installer travels with the installed system as well as with the medium: a
# disk made from this rootfs can make another one.
install -m 755 /usr/local/lib/heks-linux/~a /usr/local/bin/~a

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
log \"ready: every program the desktop needs is installed and rendered\"
"
             (image-payload-script-filename)
             (image-payload-script-filename)
             (image-installer-filename)
             (image-installer-filename)
             user
             (image-verify-lines)))))

;; ===========================================
;; The two artefacts
;; ===========================================

(define (image-rootfs-script)
  "Return build-rootfs.sh: the installed system, as a tarball.

This is the half void-mklive does not do: mkrootfs.sh builds a base from
packages and stops, so the build unpacks it, installs the desktop with xbps,
runs config.sh in the chroot and packs the result."
  (format #f "#!/bin/bash
# ====== Heks-Linux: the installed system ======
#
# auto-generated file, DO NOT EDIT!

set -euo pipefail

here=\"$(cd \"$(dirname \"$0\")\" && pwd)\"
mklive=\"${MKLIVE_DIR:-$here/void-mklive}\"

# void-mklive installs and queries packages with xbps, which a host that is not
# Void does not carry.  A static build beside this script is what the build uses
# when it is there - the whole point of building from another distribution - and
# a host that has xbps of its own is not disturbed.
if [ -d \"$here/xbps-static/usr/bin\" ]; then
    PATH=\"$here/xbps-static/usr/bin:$PATH\"
    export PATH
fi
arch=\"~a\"
out=\"$here/~a-~a-rootfs.$arch.tar.xz\"
work=\"$here/work-rootfs\"
rootfs=\"$here/work-base.tar.xz\"

[ -x \"$mklive/mkrootfs.sh\" ] || {
    echo \"void-mklive is not here. Clone it first:\" >&2
    echo \"  git clone https://github.com/void-linux/void-mklive $mklive\" >&2
    exit 1
}

echo \"==> the base: mkrootfs.sh ($arch)\"
\"$mklive/mkrootfs.sh\" -b base-system -r \"~a\" -o \"$rootfs\" \"$arch\"

echo \"==> unpacking it\"
rm -rf \"$work\"
install -d \"$work\"
tar -xpf \"$rootfs\" -C \"$work\"
cp /etc/resolv.conf \"$work/etc/resolv.conf\"

echo \"==> the packages xbps does not put in a base\"
chroot \"$work\" xbps-install -Suy --yes $(tr '\\n' ' ' < \"$here/~a\")

echo \"==> the payload\"
# The whole overlay, the way mklive.sh is handed it: whatever config.sh reads has
# been delivered here first, so the two cannot drift apart.
cp -a \"$here/root/.\" \"$work/\"
install -D -m 644 \"$here/~a\" \"$work/usr/local/lib/heks-linux/~a\"

echo \"==> config.sh, inside the target\"
for tree in proc sys dev; do mount --bind /$tree \"$work/$tree\" 2>/dev/null || true; done
chroot \"$work\" /bin/bash /usr/local/lib/heks-linux/config.sh
for tree in proc sys dev; do umount \"$work/$tree\" 2>/dev/null || true; done

echo \"==> packing $out\"
tar -C \"$work\" --xattrs -cJpf \"$out\" .
rm -rf \"$work\" \"$rootfs\"
echo \"Heks GNU/Linux: $out\"
"
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

set -euo pipefail

here=\"$(cd \"$(dirname \"$0\")\" && pwd)\"
mklive=\"${MKLIVE_DIR:-$here/void-mklive}\"

# void-mklive installs and queries packages with xbps, which a host that is not
# Void does not carry.  A static build beside this script is what the build uses
# when it is there - the whole point of building from another distribution - and
# a host that has xbps of its own is not disturbed.
if [ -d \"$here/xbps-static/usr/bin\" ]; then
    PATH=\"$here/xbps-static/usr/bin:$PATH\"
    export PATH
fi
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
rm -rf \"$payload\"
cp -a \"$here/root/.\" \"$payload/\"
# The medium's own half: the service that makes tty1 the installer, and the
# quickstart.  build-rootfs.sh copies `root/' and never this, so nothing here
# reaches an installed disk.
cp -a \"$here/~a/.\" \"$payload/\"
install -D -m 644 \"$rootfs\" \"$payload/usr/local/lib/heks-linux/$(basename \"$rootfs\")\"\n

# mklive.sh writes a hybrid medium: GRUB's BIOS stage in the ISO's own boot
# sector, and an EFI System Partition image beside it, which is what the
# firmware of a modern machine boots.  Nothing here chooses between the two.
\"$mklive/mklive.sh\" \\
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

echo \"Heks GNU/Linux: $out\"
"
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
runuser -u \"$user\" -- bash -lc 'cd $HOME/Hacking/heks-linux && maak install-nix-packages'

echo \"Heks GNU/Linux is rendered: log out and back in to see it.\"
" user)))

;; ===========================================
;; Writing it
;; ===========================================

(define (image-live-installer-service)
  "Return the tty1 service the medium boots into.

Void's agetty on tty1 is replaced rather than added to: one console cannot be
both a login prompt and an installer.

shortcut: the replacement is a file in the payload, so it overwrites Void's
service by path and not by interface - a Void that renames or restructures
agetty-tty1 leaves the medium booting to a login prompt.  Upgrade to a mklive
hook or a service of our own when Void's service directory moves.  The installer draws on tty1, and when it
exits - installed, or cancelled, or refused - the console goes back to being a
login prompt for the live account, which has passwordless sudo."
  "#!/bin/sh
exec >/dev/tty1 2>&1 </dev/tty1
if [ -x /usr/local/bin/heks-install ]; then
    /usr/local/bin/heks-install
fi
exec agetty --autologin anon 38400 tty1
")

(define (image-quickstart)
  "Return the quickstart the medium carries for whoever drops to a shell.

It is plain text on purpose: the one document that has to be readable before
anything is configured, on a console with no pager flags, no fonts and no
colours worth trusting."
  (format #f "Heks GNU/Linux ~a - quickstart

This medium installs the desktop on a disk.  It does not need the network, and
it does not change anything until you say so.

  install        sudo heks-install

The wizard asks six things - the disk, the firmware, the disk passphrase, the
host name and the user with its password - and then shows you the plan.

  At boot, the passphrase is typed with a US keyboard.  Use letters and digits
  you can find blind, and write the passphrase down somewhere else.

  Your disk is erased.  Every disk attached is offered; the one this medium is
  running from is refused.

What it builds: UEFI gets a GPT disk with an EFI System Partition and a boot
partition; legacy firmware gets an MBR disk.  The rest is a LUKS2 container with
BTRFS inside it, and the root, the homes and the snapshots as three subvolumes.
The passphrase is asked once, at boot, by the initramfs.

After it finishes, the medium can also leave the new system ready with
lambdock and whelk, the workstation package sets and Emacs built from master.
Those pull from the network; the first one is on by default.

  live user      anon, with passwordless sudo
  the log        /var/log/heks-install.log
  this text      heks-help, or /usr/local/share/heks-linux/quickstart.txt
  the guide      the installation page of the heks-linux repository

If something goes wrong, the log names the command that stopped: read it, then
run the installer again.  Nothing it does before the confirmation is permanent.
"
          (image-version)))

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
  ;; The medium's own half.  build-rootfs.sh never copies this directory, so a
  ;; live-only service or document cannot end up on an installed disk.
  (install-config-file! #:name "run"
                        #:dir (format #f "~a/~a/etc/sv/agetty-tty1"
                                      dir (image-live-payload-dir))
                        #:contents (image-live-installer-service)
                        #:perms 493)
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
                        #:dir (format #f "~a/root/usr/local/share/heks-linux" dir)
                        #:contents (image-quickstart)
                        #:perms 420)
  (install-config-file! #:name (image-help-filename)
                        #:dir (format #f "~a/root/usr/local/bin" dir)
                        #:contents (format #f "#!/bin/sh
exec less /usr/local/share/heks-linux/quickstart.txt
")
                        #:perms 493)
  dir)
