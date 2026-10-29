;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The desktop as a bootable image: an openSUSE Slowroll live ISO carrying
;; this configuration, the editor's and the shell's.
;;
;; The image is a KIWI description, and a KIWI description is four things: an
;; XML file that names the distribution, its repositories and its packages; a
;; config.sh that runs inside the chroot while the image is built; an images.sh
;; that names the file the build produces; and a root/ directory whose contents
;; are copied onto the image's filesystem.  Three of those four are data, so
;; they are written here in Scheme, the way every other surface of this desktop
;; is: the package list comes from @code{(heks-linux packages zypper)}, the
;; locale, timezone and hostname come from the same settings a session reads,
;; and the shell scripts are @code{format} strings that a test can look inside.
;;
;; The ISO is a *live* image: it boots the desktop from a squashfs with a
;; writable overlay, so it asks nothing of the machine it starts on.  It is
;; hybrid-persistent, which means the same file can go on a USB stick and keep
;; what a session did with it.
;;
;; What the image does not carry is the Guix store the renderers run from - it
;; is the size of a small distribution, and building it into the image on the
;; day it is built is the next step rather than this one.  The ISO therefore
;; ships the three checkouts and the editor's configuration already in place,
;; and a first-boot unit that runs the three commands the README documents to
;; render the rest.  That unit needs the network, which is the one thing a live
;; image cannot promise.
;;
;;; Code:

(define-module (heks-linux image)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux packages zypper)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:export (image-name
            image-version
            image-user
            image-user-home
            image-checkouts
            image-upstream
            image-description-dir
            image-description-filename
            image-config-script-filename
            image-images-script-filename
            image-payload-dir
            image-payload-script-filename
            image-payload-unit-filename
            image-payload-state-dir
            image-render-at-build?
            image-required-paths
            image-required-commands
            image-build-log
            image-repositories
            image-base-packages
            image-session-packages
            image-bootstrap-packages
            image-iso-packages
            image-description
            image-description-xml
            image-config-script
            image-images-script
            image-payload-script
            image-payload-unit
            install-image-config))

;; ===========================================
;; What the image is called, and who it belongs to
;; ===========================================

(define image-name
  "heks-linux")

(define image-version
  (make-parameter "0.1.0"))

;; The live user.  One account, created by KIWI, logged in automatically: a
;; live image has no passwords to hand out and nothing to protect.
(define image-user
  (make-parameter "heks"))

(define (image-user-home)
  "Return the live user's home directory inside the image.

It is spelled out rather than computed from @code{(getenv \"HOME\")} because it
is a path *inside another filesystem*: the one the build is not running in."
  (format #f "/home/~a" (image-user)))

;; ===========================================
;; What is pre-loaded, and from where
;; ===========================================

(define image-upstream
  ;; The projects are cloned from their own home, at the branches they are
  ;; developed on: an ISO is a snapshot of work in progress, and `git log' in
  ;; the checkout is the honest answer to "what is on this disc".
  (make-parameter "https://codeberg.org/jjba23"))

(define image-checkouts
  ;; The three repositories, in the order the bootstrap installs them: the
  ;; desktop first, because the editor's and the shell's installs run through
  ;; its task runner.
  (make-parameter
   '(("heks-linux" . "trunk")
     ("heks-emacs" . "trunk")
     ("heks-bash" . "trunk"))))

(define image-description-dir
  ;; Where `install-image-config' renders the description.  `dist/' is already
  ;; ignored by git, so a build leaves no untracked files behind.
  (make-parameter "dist/image"))

(define image-description-filename
  (make-parameter "config.xml"))

(define image-config-script-filename
  (make-parameter "config.sh"))

(define image-images-script-filename
  (make-parameter "images.sh"))

;; The overlay: everything under here is copied onto the image's `/'.  The
;; bootstrap lives here because it is a file the image has before it is booted,
;; and because it is written by this module rather than by hand.
(define image-payload-dir
  (make-parameter "root/usr/local/lib/heks-linux"))

(define image-payload-script-filename
  (make-parameter "heks-render"))

(define image-payload-unit-filename
  (make-parameter "heks-render.service"))

;; Where the bootstrap records that it has run.  One definition, because the
;; script writes the marker and the unit's condition reads it: two spellings of
;; the same path would mean a unit that runs on every boot for ever.
(define image-payload-state-dir
  (make-parameter "/var/lib/heks-linux"))

;; ===========================================
;; The distribution the image is made of
;; ===========================================

;; Slowroll is a rolling release that only takes maintenance updates, which is
;; the same trade the desktop itself makes: current software, and a base that
;; does not move under it every week.  Both repositories are `imageinclude'd, so
;; the image can install from them on the day it boots rather than only on the
;; day it was built.
(define (image-repositories)
  "Return the KIWI @code{<repository>} elements for the image."
  `((repository (@ (type "rpm-md") (alias "slowroll-oss") (priority "1")
                   (imageinclude "true"))
                (source (@ (path "https://download.opensuse.org/slowroll/repo/oss/"))))
    (repository (@ (type "rpm-md") (alias "slowroll-non-oss") (priority "2")
                   (imageinclude "true"))
                (source (@ (path "https://download.opensuse.org/slowroll/repo/non-oss/"))))))

;; What has to be in the image before anything else can be: the package
;; manager's own ground, and the release package that tells zypper what
;; distribution it is looking at.
(define image-bootstrap-packages
  '(ca-certificates
    cracklib-dict-full
    diffutils
    filesystem
    gawk
    glibc-locale
    grep
    gzip
    openSUSE-release
    procps
    shadow
    udev
    xz))

;; The base system and the desktop stack the session is drawn on.  `gnome_basic'
;; rather than `gnome': the image wants the Wayland plumbing - GDM, mesa,
;; pipewire, the portals, the fonts - and not a second desktop's worth of
;; applications beside the one it is shipping.
;;
;; The four packages after the patterns are the image's own workshop, and they
;; are here on purpose:
;;
;; - `git' clones the three checkouts inside the build, `curl' and `gpg2' are
;;   what a person or a script fetches and verifies with.  An image without them
;;   builds nothing and then cannot finish itself.
;; - `nix' and `guix' are the two stores this desktop's programs come from.
;;   openSUSE packages both properly - daemon, build users, systemd units,
;;   profile scripts - so this is not an installer run behind the distribution's
;;   back: it is the distribution's own packaging, which is what makes a store
;;   that survives a reboot and a zypper update.
;;
;; `dracut-kiwi-oem-repart' is the initrd module that grows the installed
;; system's filesystem to the size of the disk on its first boot.  Without it an
;; installed image keeps the size it was built at, which is the difference
;; between a system and a demo.
(define image-base-packages
  '(patterns-base-base
    patterns-base-enhanced_base
    patterns-gnome-gnome_basic
    curl
    git
    gpg2
    guix
    nix
    dracut-kiwi-oem-repart))

;; The session's own applications: the compositor, the bar, the editor, the
;; shell's tools - the categories of the package list that a live session
;; actually uses.  What is left out is left out on purpose: `dev' is a compiler
;; and rpm-build, `graphics' is GIMP and Inkscape, `music' is Ardour, and
;; `power-user' is texlive.  None of them is what a live image is for, and all
;; of them are one `maak install-zypper' away on the installed system.
(define (image-session-packages)
  "Return the packages the live session itself needs."
  ;; `nm-tray' is the second network applet the desktop list carries, and two
  ;; applets in one tray is one icon short of a bug: the one that has no icon in
  ;; this theme is the one to leave out, and it is not the GNOME applet the rest
  ;; of the session is drawn on.
  (remove (lambda (package) (equal? package 'nm-tray))
          (delete-duplicates
           (append (heks-linux-session-zypper)
                   (heks-linux-cli-zypper)
                   (heks-linux-desktop-zypper)
                   (heks-linux-font-zypper)
                   (heks-linux-net-zypper)
                   (heks-linux-other-zypper)
                   ;; Three packages the music and media lists carry among the
                   ;; studios: the mixer, the media player and the bridge to the
                   ;; bar's glyph.
                   '(pavucontrol playerctl mpv mpv-mpris yt-dlp)))))

;; A live image boots from its own initrd: `dracut-kiwi-live' is the module that
;; finds the squashfs on the medium and mounts the overlay over it.
(define image-iso-packages
  '(dracut-kiwi-live))

;; ===========================================
;; The description
;; ===========================================

(define (image-package-elements packages)
  "Return @var{packages} as KIWI @code{<package name=…/>} elements.

The package lists are Guile data and carry a string where a name is not a valid
symbol - \"7zip\" - so both spellings are accepted here rather than at every
call site."
  (map (lambda (package)
         `(package (@ (name ,(if (symbol? package)
                                 (symbol->string package)
                                 package)))))
       packages))

(define (image-description)
  "Return the KIWI description of the image, as SXML.

The element order is the schema's, not a preference: a description is read by
KIWI's validator before it is read by anybody else."
  `(image (@ (schemaversion "8.5") (name ,image-name))
          (description (@ (type "system"))
                       (author "Josep Bigorra")
                       (contact "jjbigorra@gmail.com")
                       (specification "The Heks GNU/Linux desktop as a live openSUSE Slowroll image: Niri, the Waybar bar, Emacs and Bash, installed and configured."))
          (preferences
           ;; Two artefacts from one description.
           ;;
           ;; The ISO is the one you can try: read-only, with a writable overlay
           ;; so the session writes where it likes without touching the machine,
           ;; and hybrid-persistent so the same file on a stick keeps what a
           ;; session did with it.
           ;;
           ;; The OEM image is the one you keep: a real disk image with the
           ;; filesystem and the bootloader already in place, which
           ;; `dracut-kiwi-oem-repart' grows to the size of the disk it lands on
           ;; at its first boot - and `installiso' adds the boot entry that
           ;; writes it out to a machine's disk from the ISO itself.  That is
           ;; what makes this installable rather than only demonstrable: the
           ;; system is built here, once, and installed by copying it.
           (type (@ (image "iso") (primary "true") (flags "overlay")
                    (hybridpersistent "true")
                    (hybridpersistent_filesystem "ext4")
                    (mediacheck "true")))
           (type (@ (image "oem") (filesystem "btrfs") (installiso "true"))
                 (oemconfig (oem-resize "true")
                            (oem-boot-title "Heks GNU/Linux")))
           (version ,(image-version))
           (packagemanager "zypper")
           (locale ,(heks-linux-language))
           (keytable ,(heks-linux-keyboard-layout))
           (timezone ,(heks-linux-timezone))
           ;; Documentation is a gigabyte of the disc the ISO is written to and
           ;; nothing a live session reads.
           (rpm-excludedocs "true")
           (bootsplash-theme "bgrt")
           (bootloader-theme "openSUSE"))
          ;; One account, and it is the one GDM logs in: the live user owns the
          ;; checkouts and the editor's configuration that `config.sh' puts in
          ;; this home.  The password is the user name, because a live image's
          ;; account is not a secret - it is the thing sudo asks for.
          (users (user (@ (name ,(image-user))
                          (password ,(image-user))
                          (pwdformat "plain")
                          (home ,(image-user-home))
                          (groups "users,wheel")
                          (shell "/bin/bash"))))
          ,@(image-repositories)
          (packages (@ (type "bootstrap"))
                    ,@(image-package-elements image-bootstrap-packages))
          (packages (@ (type "image"))
                    ,@(image-package-elements
                       (append image-base-packages
                               (image-session-packages))))
          (packages (@ (type "iso"))
                    ,@(image-package-elements image-iso-packages))))

(define (xml-escape text)
  "Return @var{text} with the four characters XML cannot carry as they are.

A description is read by a person as often as by KIWI - a diff of one line is a
diff nobody reads - so the text is written out rather than escaped wholesale by
@code{sxml->xml}."
  (let loop ((characters (string->list text)) (escaped '()))
    (if (null? characters)
        (list->string (reverse escaped))
        (loop (cdr characters)
              (append (reverse
                       (cond ((char=? (car characters) #\&) (string->list "&amp;"))
                             ((char=? (car characters) #\<) (string->list "&lt;"))
                             ((char=? (car characters) #\>) (string->list "&gt;"))
                             ((char=? (car characters) #\") (string->list "&quot;"))
                             (else (list (car characters)))))
                      escaped)))))

(define (xml-element-attributes element)
  "Return the @code{(@ (name value) …)} attributes of an SXML @var{element}."
  (let ((second (and (pair? (cdr element)) (cadr element))))
    (if (and (pair? second) (eq? '@ (car second)))
        (cdr second)
        '())))

(define (xml-element-children element)
  "Return the children of an SXML @var{element}, minus any attribute list."
  (let ((rest (cdr element)))
    (if (and (pair? rest) (pair? (car rest)) (eq? '@ (car (car rest))))
        (cdr rest)
        rest)))

(define* (xml-element->lines element #:optional (depth 0))
  "Return @var{element} as a list of indented lines, indented from @var{depth}.

Two spaces per level, an element with only text on one line, and every element
with children opened and closed on lines of its own: enough to make a
description reviewable, and nothing that changes what it means."
  (let* ((name (symbol->string (car element)))
         (attributes (map (lambda (attribute)
                            (format #f "~a=\"~a\""
                                    (car attribute)
                                    (xml-escape (format #f "~a" (cadr attribute)))))
                          (xml-element-attributes element)))
         (open (format #f "<~a~a"
                       name
                       (if (null? attributes)
                           ""
                           (format #f " ~a" (string-join attributes " ")))))
         (children (xml-element-children element))
         (pad (make-string (* 2 depth) #\space)))
    (cond ((null? children)
           (list (format #f "~a~a/>" pad open)))
          ((and (null? (cdr children)) (string? (car children)))
           (list (format #f "~a~a>~a</~a>"
                         pad open (xml-escape (car children)) name)))
          (else
           (append (list (format #f "~a~a>" pad open))
                   (append-map (lambda (child)
                                 (xml-element->lines child (+ depth 1)))
                               children)
                   (list (format #f "~a</~a>" pad name)))))))

(define (image-description-xml)
  "Return the KIWI description as XML text, ready to be written to a file."
  (string-join (append (list "<?xml version=\"1.0\" encoding=\"utf-8\"?>")
                       (xml-element->lines (image-description)))
               "\n"))

;; ===========================================
;; What the build runs inside the image
;; ===========================================

(define (image-checkout-script)
  "Return the shell that clones the three projects into the live user's home."
  (string-append
   (format #f "install -d -o ~a -g users ~a/Hacking~%"
           (image-user) (image-user-home))
   (apply string-append
          (map (lambda (checkout)
                 (format #f "git -C ~a/Hacking clone --quiet --depth 1 --branch ~a ~a/~a.git ~a~%"
                         (image-user-home) (cdr checkout) (image-upstream)
                         (car checkout) (car checkout)))
               (image-checkouts)))
   (format #f "chown -R ~a:users ~a/Hacking~%" (image-user) (image-user-home))))

(define (image-emacs-script)
  "Return the shell that installs the editor's configuration.

@code{maak install-emacs-config} needs the task runner, which is a Guile
program from a Guix environment - so this is the copy the editor's own README
calls the manual fallback, done here because a live image that boots without an
editor configuration is not pre-loaded with anything."
  (let ((source (format #f "~a/Hacking/heks-emacs/src" (image-user-home)))
        (target (format #f "~a/.emacs.d" (image-user-home))))
    (format #f "install -d -o ~a -g users ~a
install -o ~a -g users -m 644 ~a/init.el ~a/early-init.el ~a/batch-indent.el ~a/treesit-grammars.el ~a
cp -r ~a/modules ~a/snippets ~a/
chown -R ~a:users ~a
"
            (image-user) target
            (image-user) source source source source target
            source source target
            (image-user) target)))

(define image-build-log
  ;; The build's own record, left in the image on purpose: when a booted system
  ;; is wrong, the first useful file is the one that says how it was made.
  "/var/log/heks-image.log")

(define (image-script-prelude)
  "Return the shell every phase is written in: one log, one way to fail."
  (format #f "#!/bin/bash
# ====== Heks-Linux image build ======
#
# auto-generated file, DO NOT EDIT!
#
# Runs inside the image's chroot while the image is being built: as root, with
# the network up, and with no systemd running - so it may write files and enable
# units, but every daemon it needs it starts by hand.

set -euo pipefail

LOG=~a
install -d -m 755 \"$(dirname \"$LOG\")\"
touch \"$LOG\"

log() { printf '[heks-image] %s\\n' \"$*\" | tee -a \"$LOG\"; }
phase() { log \"\"; log \"========== $* ==========\"; }

# One way to fail, and it names the command that stopped it.  A build that
# leaves a half-made image behind is a build somebody debugs at a login prompt
# an hour later.
die() { log \"FAILED: $*\"; log \"the whole record is $LOG\"; exit 1; }
trap 'die \"line $LINENO: $BASH_COMMAND\"' ERR

# wait_for WHAT PATH [TRIES]: a daemon is up when its socket answers.
wait_for() {
    local what=\"$1\" path=\"$2\" tries=\"${3:-300}\" i=0
    while [ \"$i\" -lt \"$tries\" ]; do
        if [ -S \"$path\" ]; then
            log \"$what is up\"
            return 0
        fi
        sleep 2
        i=$((i + 1))
    done
    die \"$what did not come up at $path\"
}
" image-build-log))

;; Every phase below is a string that starts with its own @code{phase} line, so
;; the build's log reads as the list of things it did rather than as a wall of
;; output from whichever program was loudest.

(define (image-machine-script)
  "Return the phase that makes the machine the desktop's own."
  (format #f "phase \"the machine\"
echo ~a > /etc/hostname

phase \"the login\"
# A system that stops at a login prompt has not shown anyone the desktop, so GDM
# logs the live user in and the session is niri.  The keys are appended rather
# than written over the file, which belongs to the distribution: it has a
# [security] section this script has no business dropping.
install -d -m 755 /etc/gdm
cat >> /etc/gdm/custom.conf <<'HEKS_GDM'

# Heks GNU/Linux: log the live user in.
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=~a
TimedLoginEnable=false
HEKS_GDM

phase \"the services\"
systemctl enable gdm.service
systemctl enable NetworkManager.service
systemctl enable bluetooth.service 2>/dev/null || true
systemctl disable sshd.service 2>/dev/null || true
systemctl set-default graphical.target

# The two stores, and the two units the packaging gets subtly wrong for a
# desktop.  `guix-publish' is enabled by its package and serves the store on the
# network, which a laptop has no reason to do; the guix package also ships a
# unit that bind-mounts /gnu/store read-only, which is right for a machine that
# only runs store items and wrong for one whose owner installs them - so the
# daemon is enabled and neither of those is.
systemctl enable guix-daemon.service
systemctl disable guix-publish.service 2>/dev/null || true
systemctl mask gnu-store.mount 2>/dev/null || true
# The socket, not the service: the daemon then starts when something asks it to,
# rather than sitting in a live image's memory from the first second.
systemctl enable nix-daemon.socket
"
          (heks-linux-hostname)
          (image-user)))

(define (image-store-script)
  "Return the phase that makes both stores usable inside the chroot.

The two daemons are what the rest of the build installs through, and this chroot
has no systemd to start them: they are started here, by hand, and waited for by
their own sockets.  Without them `guix pull' and `nix profile install' fail on a
socket that is not there, which reads like a network problem."
  (format #f "phase \"the build users\"
# The packages create their build users in their own install scripts, which run
# in this chroot; sysusers is the second chance, and tmpfiles is what creates
# /var/lib/nix and the store's runtime directories.
systemd-sysusers || die \"could not create the build users\"
systemd-tmpfiles --create || log \"tmpfiles had nothing to create\"

phase \"the two daemons\"
# /proc is what guix-daemon isolates builds with and what nix-daemon needs to
# fork; KIWI usually has it mounted already, and mounting it twice is harmless.
mountpoint -q /proc || mount -t proc proc /proc || log \"no /proc: builds may fail\"

if [ ! -e /var/lib/nix/nix/db ]; then
    nix-store --init || die \"could not initialise the nix store\"
fi

nix-daemon --daemon &
# The packaging's own wrapper, which prefers the daemon of a newer `guix pull'
# over the one the RPM installed - the same choice the systemd unit makes.
run_guix_daemon.sh &

wait_for nix-daemon /var/lib/nix/nix/daemon-socket/socket
wait_for guix-daemon /var/guix/daemon-socket/socket
"))

(define (image-desktop-script)
  "Return the phase that installs and renders the desktop itself.

Everything here runs as the live user, because that is whose profiles and whose
home these are: a home rendered by root is a home the desktop cannot write to,
and a store installed by root is a store the desktop cannot extend.

The order is the README's order - pull the pinned channels, install the task
runner, render - and then the three tasks a reconfigure does not cover: the
icons and cursors (which are copied out of the Guix store), the wallpaper
collection (which is a git clone), and the two programs that come from Nix
rather than Guix.
  "
  (let ((user (image-user)))
    (format #f "phase \"the task runner\"
runuser -u ~a -- bash -lc 'guix pull --channels=\"$HOME/Hacking/heks-linux/channels.scm\"'
runuser -u ~a -- bash -lc 'guix install maak guile'

phase \"the desktop\"
runuser -u ~a -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak home-reconfigure'

phase \"the shell\"
runuser -u ~a -- bash -lc 'cd \"$HOME/Hacking/heks-bash\" && maak install-bash'

phase \"what a reconfigure does not cover\"
# The icon themes and the cursors are copied out of the Guix store and the
# wallpapers are a checkout: neither is a config file, and both are what a
# desktop looks like when it has none.
runuser -u ~a -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak install-icon-files'
runuser -u ~a -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak install-wallpaper-files'
# The dock and the window the bar opens come from nix-jointhefreeworld, pinned
# by the checkout's own revision.
runuser -u ~a -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak install-heks-toon'
runuser -u ~a -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak install-lambdock'

phase \"the editor's own packages\"
# heks-emacs bootstraps Elpaca on its first start and clones its packages then.
# Doing it here is the difference between an editor that works and an editor
# that works after a download; it is advisory because a failure leaves exactly
# the behaviour there would have been without this phase.
log \"installing elpaca packages: this is the long one\"
runuser -u ~a -- bash -lc 'emacs --batch -l \"$HOME/.emacs.d/init.el\" --eval \"(elpaca-wait)\" >/dev/null 2>&1' \\
    || log \"elpaca bootstrap failed: the editor will fetch its packages on first start\"
"
            user user user user user user user user user)))

(define image-required-paths
  ;; What "ready to go" means, as files: one per program whose absence would
  ;; otherwise be found at a login prompt.  Each is written by a task above, so
  ;; a phase that silently did nothing is a build that stops here.
  '((".config/niri/config.kdl" . "the compositor's configuration")
    (".config/waybar/config.jsonc" . "the bar's configuration")
    (".config/waybar/style.css" . "the bar's stylesheet")
    (".config/rofi/config.rasi" . "the launcher's configuration")
    (".config/mako/config" . "the notifications' configuration")
    (".config/btop/btop.conf" . "the monitor's configuration")
    (".bashrc" . "the shell")
    (".emacs.d/init.el" . "the editor")
    (".local/bin/heks-language-label" . "the bar's layout label")
    (".local/bin/heks-wallpaper" . "the wallpaper engine")
    (".local/share/icons" . "the icon themes")
    (".config/digital-art-dreams" . "the wallpaper collection")))

(define image-required-commands
  ;; And what "ready to go" means, as programs on the live user's PATH.  The
  ;; first two are the stores themselves: an image that renders a desktop but
  ;; cannot install into it is a photograph of one.
  '("guix" "nix" "maak" "heks-toon" "lambdock" "emacs" "niri" "waybar" "wezterm"))

(define (image-verify-script)
  "Return the phase that decides whether the image is finished.

This is the difference between a build that succeeded and a build that stopped
producing output: every promise above is checked as a file or a command, and the
build fails with the list of what is missing rather than shipping an image that
looks nearly right until somebody logs in."
  (format #f "phase \"is it ready?\"
missing=0

check_path() {
    if [ -e ~a/$1 ]; then
        log \"ok      $1 ($2)\"
    else
        log \"MISSING $1 ($2)\"
        missing=$((missing + 1))
    fi
}

check_command() {
    if runuser -u ~a -- bash -lc \"command -v $1 >/dev/null 2>&1\"; then
        log \"ok      $1 on the user's PATH\"
    else
        log \"MISSING $1 on the user's PATH\"
        missing=$((missing + 1))
    fi
}

~a
~a

[ \"$missing\" -eq 0 ] || die \"$missing thing(s) missing from the image\"
# The marker the unit below reads: this image has been rendered, so the unit has
# nothing left to do even where it is enabled.
install -d -m 755 ~a
date -Is > ~a/rendered
log \"ready: every program the desktop needs is installed and rendered\"
"
          (image-user-home)
          (image-user)
          (apply string-append
                 (map (lambda (required)
                        (format #f "check_path \"~a\" \"~a\"~%"
                                (car required) (cdr required)))
                      image-required-paths))
          (apply string-append
                 (map (lambda (command)
                        (format #f "check_command ~a~%" command))
                      image-required-commands))
          (image-payload-state-dir)
          (image-payload-state-dir)))

(define (image-cleanup-script)
  "Return the phase that keeps the image from shipping the build's leftovers.

Both stores keep everything ever downloaded or built.  Collecting here is safe -
what a profile reaches stays - and it is the difference between an image that
carries the desktop and an image that carries the build of it too.
  "
  (format #f "phase \"the size of it\"
runuser -u ~a -- bash -lc 'guix gc' || log \"guix gc skipped\"
runuser -u ~a -- bash -lc 'nix-store --gc' || log \"nix gc skipped\"
runuser -u ~a -- bash -lc 'nix-collect-garbage --delete-older-than 0d' || log \"nix-collect-garbage skipped\"
rm -rf /var/cache/zypp/packages /tmp/* /root/.cache /root/.guix-profile 2>/dev/null || true
log \"done\"
" (image-user) (image-user) (image-user)))

(define (image-payload-install-script)
  "Return the phase that installs the re-render tool, and decides its unit.

The tool itself is always installed: it is what a person runs after a channel
pin moves.  The unit is only enabled on the builds that skip the rendering on
purpose, because on every other build it is a service that starts once, finds
the marker and does nothing."
  (format #f "phase \"re-rendering it later\"
install -m 755 /usr/local/lib/heks-linux/~a /usr/local/bin/~a
install -m 644 /usr/local/lib/heks-linux/~a /usr/lib/systemd/system/~a
~a
"
          (image-payload-script-filename)
          (image-payload-script-filename)
          (image-payload-unit-filename)
          (image-payload-unit-filename)
          (if (image-render-at-build?)
              "log \"the build rendered the desktop: the unit stays disabled\""
              "systemctl enable heks-render.service")))

(define (image-config-script)
  "Return @file{config.sh}: the whole build, in the order it happens.

Each phase is logged and each phase is checkable: the machine, the login, the
services, the build users, the two daemons, the three checkouts, the editor, the
desktop, the question of whether any of it worked, and the size of what is left.
A build that skips the question is a build that has never been run.
  "
  (string-append (image-script-prelude)
                 (image-machine-script)
                 "\n"
                 (image-store-script)
                 "\nphase \"the three checkouts\"\n"
                 (image-checkout-script)
                 "\nphase \"the editor\"\n"
                 (image-emacs-script)
                 "\n"
                 (image-desktop-script)
                 "\n"
                 (image-payload-install-script)
                 "\n"
                 (image-verify-script)
                 "\n"
                 (image-cleanup-script)))

(define (image-images-script)
  "Return @file{images.sh}: what the build does to the files it produced.

KIWI calls this last, once per artefact, with the name it gave the image in
@code{$1}.  Both kinds are named here - the ISO you boot and the raw image you
install - because a file people copy to a stick should say what it is."
  (format #f "#!/bin/bash
# ====== Heks-Linux image names ======
#
# auto-generated file, DO NOT EDIT!

set -euo pipefail

image=\"$1\"
# KIWI hands over a path; a bare name is still a path, and `dirname' answers for
# both - `${image%%/*}' answers with the name itself when there is no slash.
dir=\"$(dirname \"$image\")\"
arch=\"$(uname -m)\"

case \"$image\" in
    *.iso) target=\"$dir/~a-~a-live.$arch.iso\" ;;
    *.raw|*.qcow2) target=\"$dir/~a-~a-install.$arch.${image##*.}\" ;;
    # A build may produce other things (a `.changes', a compressed image): they
    # keep the name KIWI gave them.
    *) exit 0 ;;
esac

[ \"$image\" = \"$target\" ] || mv \"$image\" \"$target\"
echo \"Heks GNU/Linux: $target\"
" image-name (image-version) image-name (image-version)))

;; ===========================================
;; Rendering it again
;; ===========================================

(define (image-payload-script)
  "Return @file{heks-render}: the desktop's files, rendered on demand.

The image is built with this already done - that is what the last phase of
@file{config.sh} checks - so this is not the first boot: it is the way to do it
again.  A channel pin moves, a home is lost, a palette switch goes wrong, and the
answer is one command rather than a reinstall.

It renders exactly what the build renders, in the same order, because two lists
that are meant to be the same list are two lists that will disagree."
  (let ((user (image-user)))
    (format #f "#!/bin/bash
# ====== Heks-Linux re-render ======
#
# auto-generated file, DO NOT EDIT!
#
# Renders the desktop's own files again: the dotfiles, the shell, the icons and
# the two programs that come from Nix.

set -euo pipefail

if [ \"$(id -un)\" != root ]; then
    echo \"heks-render renders another user's home: run it as root\" >&2
    exit 1
fi

STATE=~a
user=~a

runuser -u \"$user\" -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak home-reconfigure'
runuser -u \"$user\" -- bash -lc 'cd \"$HOME/Hacking/heks-bash\" && maak install-bash'
runuser -u \"$user\" -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak install-icon-files'
runuser -u \"$user\" -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak install-heks-toon'
runuser -u \"$user\" -- bash -lc 'cd \"$HOME/Hacking/heks-linux\" && maak install-lambdock'

install -d -m 755 \"$STATE\"
date -Is > \"$STATE/rendered\"
echo \"Heks GNU/Linux is rendered: log out and back in to see it.\"
" (image-payload-state-dir) user)))

(define image-render-at-build?
  ;; Where the rendering happens.  A build that renders is an image you can hand
  ;; to somebody; a build that does not is a two-gigabyte ISO that finishes
  ;; itself on the first boot with a network, which is what you want while
  ;; working on the description itself.
  (make-parameter #t))

(define (image-payload-unit)
  "Return the unit that renders the desktop on the first boot, if it was not.

It exists for the builds that skip the rendering on purpose, so it is only
enabled by @code{image-render-at-build?} being @code{#f}.  The condition is the
marker both the build and @file{heks-render} write: an image that was rendered
leaves it behind, and the unit then has nothing to do even where it is enabled."
  (format #f "[Unit]
Description=Render the Heks GNU/Linux desktop
Documentation=file:/usr/local/lib/heks-linux/~a
After=network-online.target
Wants=network-online.target
ConditionPathExists=!~a/rendered

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/~a

[Install]
WantedBy=multi-user.target
" (image-payload-script-filename)
          (image-payload-state-dir)
          (image-payload-script-filename)))

;; ===========================================
;; Building it
;; ===========================================

(define* (install-image-config #:key (dir (image-description-dir)))
  "Write the KIWI description for @var{dir} and return the directory.

Four files, of which three are the description and one is the overlay that
@file{config.sh} installs: a description is a directory, not a configuration
file, and KIWI expects exactly this shape."
  (ensure-directory-tree! dir)
  (install-config-file! #:name (image-description-filename)
                        #:dir dir
                        #:contents (image-description-xml))
  (install-config-file! #:name (image-config-script-filename)
                        #:dir dir
                        #:contents (image-config-script)
                        #:perms 493)
  (install-config-file! #:name (image-images-script-filename)
                        #:dir dir
                        #:contents (image-images-script)
                        #:perms 493)
  (install-config-file! #:name (image-payload-script-filename)
                        #:dir (format #f "~a/~a" dir (image-payload-dir))
                        #:contents (image-payload-script)
                        #:perms 493)
  (install-config-file! #:name (image-payload-unit-filename)
                        #:dir (format #f "~a/~a" dir (image-payload-dir))
                        #:contents (image-payload-unit))
  dir)
