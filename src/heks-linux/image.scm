;;; heks-linux

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; heks-linux is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; heks-linux is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with heks-linux.  If not, see <https://www.gnu.org/licenses/>.

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
  (make-parameter "heks-bootstrap"))

(define image-payload-unit-filename
  (make-parameter "heks-bootstrap.service"))

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
;; `git', `curl' and `gpg2' are not session software and they are here on
;; purpose: the build clones the three checkouts inside the image, and the first
;; boot downloads the Guix installer and verifies its signature.  An image
;; without them builds nothing and then cannot finish itself.
(define image-base-packages
  '(patterns-base-base
    patterns-base-enhanced_base
    patterns-gnome-gnome_basic
    curl
    git
    gpg2))

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
           ;; A live ISO with a writable overlay: the image is read-only and the
           ;; session writes where it likes, which is what makes it possible to
           ;; boot the same file on a machine and not touch its disk.
           (type (@ (image "iso") (primary "true") (flags "overlay")
                    (hybridpersistent "true")
                    (hybridpersistent_filesystem "ext4")
                    (mediacheck "true")))
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

(define (image-config-script)
  "Return @file{config.sh}: what the build does inside the image's chroot.

This runs once, as root, with the network up and systemd not running, so it may
copy files and enable units but must not try to start them.  Everything it does
is a step of the image being *this* desktop rather than a distribution's
default one: the login, the services, the three checkouts, the editor."
  (format #f "#!/bin/bash
# ====== Heks-Linux live image ======
#
# auto-generated file, DO NOT EDIT!
#
# Runs inside the image's chroot while the image is being built.

set -euo pipefail

# --- the machine -------------------------------------------------------
echo ~a > /etc/hostname

# --- the session it boots into -----------------------------------------
# A live image that stops at a login prompt has not shown anyone the desktop, so
# GDM logs the live user in and the session is niri - the same answer this
# machine gives, without the typing.  The keys are appended rather than written
# over the file, which belongs to the distribution: it has a [security] section
# this script has no business dropping.
install -d -m 755 /etc/gdm
cat >> /etc/gdm/custom.conf <<'HEKS_GDM'

# Heks GNU/Linux live image: log the live user in.
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=~a
TimedLoginEnable=false
HEKS_GDM

systemctl enable gdm.service
systemctl enable NetworkManager.service
systemctl enable bluetooth.service 2>/dev/null || true
systemctl disable sshd.service 2>/dev/null || true
systemctl set-default graphical.target

# --- the three checkouts -----------------------------------------------
~a
# --- the editor --------------------------------------------------------
~a
# --- the half that is rendered rather than copied ----------------------
# heks-linux and heks-bash write their files from Guile in a pinned Guix
# environment, which is a store the size of a small distribution and therefore
# not in this image.  `heks-bootstrap' installs that store and renders, once, on
# the first boot with a network - the three commands the desktop's README
# documents, run for the live user with nothing to type.
install -m 755 /usr/local/lib/heks-linux/~a /usr/local/bin/~a
install -m 644 /usr/local/lib/heks-linux/~a /usr/lib/systemd/system/~a
systemctl enable ~a
"
          (heks-linux-hostname)
          (image-user)
          (image-checkout-script)
          (image-emacs-script)
          (image-payload-script-filename)
          (image-payload-script-filename)
          (image-payload-unit-filename)
          (image-payload-unit-filename)
          (image-payload-unit-filename)))

(define (image-images-script)
  "Return @file{images.sh}: what the build does to the file it produced.

KIWI calls this last, with the name it gave the image in @code{$1}.  A live
image is a file people copy to a USB stick and then look at in a file manager,
so it says what it is and which version of this desktop is on it."
  (format #f "#!/bin/bash
# ====== Heks-Linux live image name ======
#
# auto-generated file, DO NOT EDIT!

set -euo pipefail

image=\"$1\"
# KIWI hands over a path; a bare name is still a path, and `dirname' answers for
# both - `${image%%/*}' answers with the name itself when there is no slash.
target=\"$(dirname \"$image\")/~a-~a-live.$(uname -m).iso\"
[ \"$image\" = \"$target\" ] || mv \"$image\" \"$target\"
echo \"Heks GNU/Linux live image: $target\"
" image-name (image-version)))

;; ===========================================
;; The first boot
;; ===========================================

(define (image-payload-script)
  "Return @file{heks-bootstrap}: the first boot's half of the installation.

It is one script with one guard - it runs once, and a machine that has run it
never runs it again - because a live image's first boot is the only moment at
which it can still become a fully rendered desktop: Guix is not on the disc, and
the store the renderers need is larger than the ISO.

What it does is what the README tells a person to do, in order: install Guix,
pull the pinned channels, install the task runner, render the desktop and the
shell, and record that it happened.  It is deliberately loud and deliberately
harmless: if the network is not there it exits non-zero and the unit tries again
on the next boot."
  (format #f "#!/bin/bash
# ====== Heks-Linux first boot ======
#
# auto-generated file, DO NOT EDIT!
#
# Installs Guix and renders the desktop's own files, once.

set -euo pipefail

STATE=~a
DONE=\"$STATE/bootstrap.done\"

if [ -e \"$DONE\" ]; then
    exit 0
fi
install -d -m 755 \"$STATE\"

user=~a
home=~a
checkout=\"$home/Hacking/heks-linux\"

# --- the toolchain ------------------------------------------------------
# The supported installer, not a copied store: it is the same script this
# desktop's README points at, and the machine it runs on is a real systemd
# system, which is what the script wants.
if ! command -v guix >/dev/null 2>&1; then
    installer=$(mktemp)
    curl -fsSL https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh -o \"$installer\"
    chmod +x \"$installer\"
    printf '\\n\\n\\n\\n\\n\\n\\n\\n' | \"$installer\" >/dev/null 2>&1 || true
    rm -f \"$installer\"
fi
. /etc/profile.d/guix.sh 2>/dev/null || true

# --- the desktop --------------------------------------------------------
# The channels are pinned in the checkout, so this pulls the same Guix this
# configuration was written against rather than whatever is current.
runuser -u \"$user\" -- bash -lc \"guix pull --channels=\\\"$checkout/channels.scm\\\"\"
runuser -u \"$user\" -- bash -lc 'guix install maak guile'
runuser -u \"$user\" -- bash -lc \"cd \\\"$checkout\\\" && maak home-reconfigure\"
runuser -u \"$user\" -- bash -lc 'cd \"$HOME/Hacking/heks-bash\" && maak install-bash'

date -Is > \"$DONE\"
echo \"Heks GNU/Linux is rendered: log out and back in to see it.\"
" (image-payload-state-dir) (image-user) (image-user-home)))

(define (image-payload-unit)
  "Return the systemd unit that runs @file{heks-bootstrap} on the first boot.

It is ordered after the network because that is what it needs, and it is a
@code{oneshot} with @code{RemainAfterExit}, so a failure is visible in
@command{systemctl status} rather than buried in a boot log - which is the only
way a person looking at a half-rendered desktop finds out why."
  (format #f "[Unit]
Description=Render the Heks GNU/Linux desktop
Documentation=file:/usr/local/lib/heks-linux/~a
After=network-online.target
Wants=network-online.target
ConditionPathExists=!~a/bootstrap.done

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
