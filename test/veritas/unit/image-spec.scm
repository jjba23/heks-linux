;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux image).
;;
;; The build is a directory of shell scripts and a package list, so what can be
;; checked is what a reader of those files would check: that the packages name a
;; session rather than a distribution's idea of one, that the prompt on the
;; image is the one (heks-linux greeter) names, that the services are enabled
;; the way Void enables them, and that nothing from the openSUSE era survives.
;; No test here has run void-mklive; that is what a build machine is for.

;; IMPORTANT contributor note:
;;
;; `assert-true' and friends are *pure constructors*: they return a closure
;; that the veritas runner later applies to a context.  When such a call sits in
;; a non-final position of a body (typically inside a `let'), its return value
;; is unused and Guile's optimizer deletes the call entirely, so the assertion
;; silently never runs.  Always pass assertions as direct arguments to `test',
;; as this file does.

;;; Code:

(define-module (veritas unit image-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux image)
  #:use-module (heks-linux greeter)
  #:use-module (heks-linux platform)
  #:use-module (heks-linux user-settings)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? haystack needle)
  "Return @code{#t} when @var{needle} occurs in the string @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

(define (mentions-any? text needles)
  "Return the first of @var{needles} that occurs in @var{text}, or @code{#f}."
  (find (lambda (needle) (contains? text needle)) needles))

(define (packaged? name)
  "Return @code{#t} when the image carries @var{name}, exactly."
  (not (eq? #f (member name (image-packages)))))

(define (text-of name)
  "Return the rendered contents of @var{name} from the build."
  (let ((entry (assoc name (image-description))))
    (and entry (cdr entry))))

(define (all-build-text)
  "Return every file the build is made of, concatenated.

The failure this guards against is a leftover: a word from the old build in a
script nobody reads, which the next person copies into the new one."
  (string-join (map cdr (image-description)) "\n"))

(define (payload-paths-consumed)
  "Return every distinct path under the payload directory config.sh reads.

Inside the chroot the script installs the desktop's files from
@file{/usr/local/lib/heks-linux}, so the renderer has to have put them there:
a path the script names and the payload does not carry stops the build at that
phase, with nobody watching."
  (let ((prefix "/usr/local/lib/heks-linux/"))
    (let loop ((text (image-config-script)) (found '()))
      (let ((at (string-contains text prefix)))
        (if (not at)
          (reverse found)
          (let* ((tail (substring text (+ at (string-length prefix))))
                 (stop (or (string-index
                            tail
                            (lambda (char)
                              (not (or (char-alphabetic? char)
                                     (char-numeric? char)
                                     (memv char '(#\- #\_ #\. #\/ #\+))))))
                         (string-length tail)))
                 (path (substring tail 0 stop)))
            (let ((full (string-append prefix path)))
              (loop tail
                    (if (or (string-null? path) (member full found))
                      found
                      (cons full found))))))))))

;; ===========================================
;; The suites
;; ===========================================

(define (package-cases)
  "Return the cases for the package list."
  (list (assert-true (packaged? "base-system")
          #:name "Void's own base is the base")
        (assert-true (packaged? "dracut")
          #:name "The initramfs generator is Void's")
        (assert-true (packaged? (image-kernel))
          #:name "The kernel is the one the parameter names")
        (assert-true (packaged? "niri")
          #:name "The compositor is on the image")
        (assert-true (packaged? "greetd")
          #:name "The login daemon is on the image")
        (assert-true (packaged? "gtkgreet")
          #:name "The prompt is drawn by the greeter the tree chose")
        (assert-true (packaged? "cage")
          #:name "And something gives that prompt the screen")
        (assert-true (packaged? "guile")
          #:name "The language the desktop is written in is on the image")
        (assert-true (packaged? "nix")
          #:name "The shell comes from Nix, so the store is on the image")
        (assert-true (packaged? "git")
          #:name "The build clones the checkouts with the image's own git")
        (assert-true (packaged? "curl")
          #:name "And fetches with the image's own curl")
        (assert-true (packaged? "cryptsetup")
          #:name "The image can open a LUKS2 volume")
        (assert-true (packaged? "btrfs-progs")
          #:name "And make and mount the BTRFS inside it")
        (assert-true (packaged? "grub-x86_64-efi")
          #:name "The bootloader the encrypted layout uses is on the image")
        (assert-true (packaged? "dosfstools")
          #:name "The EFI system partition can be formatted")
        (assert-true (packaged? "e2fsprogs")
          #:name "The unencrypted /boot partition can be formatted")
        (assert-true (packaged? "efibootmgr")
          #:name "And its firmware entry written")
        (assert-true (packaged? "parted")
          #:name "The installer writes the partition table with it")
        (assert-true (packaged? "dialog")
          #:name "And draws its menus with it")
        (assert-true (packaged? "grub")
          #:name "GRUB's BIOS modules are there for the MBR second")
        (assert-true (not (packaged? "gdm"))
          #:name "There is no display manager: greetd is the greeter")
        (assert-true (not (packaged? "gnome-shell"))
          #:name "There is no GNOME on a curated image")
        (assert-true (not (packaged? "zypper"))
          #:name "And no openSUSE package manager")))

(define (greeter-cases)
  "Return the cases for the login prompt.

The image does not carry a prompt of its own: it carries whatever
(heks-linux greeter) names, which is why the test switches the greeter and looks
at the list again."
  (let ((tuigreet (parameterize ((greeter 'tuigreet))
                    (image-packages))))
    (list (assert-true (contains? (text-of (image-config-script-filename))
                                  "install -m 644 /usr/local/lib/heks-linux/greetd.toml /etc/greetd/config.toml")
            #:name "The image installs the greeter's own file where greetd reads it")
          (assert-true (contains? (greetd-config) "command = \"cage gtkgreet\"")
            #:name "And the file starts the greeter under the kiosk compositor")
          (assert-true (not (eq? #f (member "tuigreet" tuigreet)))
            #:name "Switching the greeter changes the packages")
          (assert-true (eq? #f (member "cage" tuigreet))
            #:name "And the compositor goes with it: a prompt that draws no window needs none")
          (assert-true (eq? #f (member "gtkgreet" tuigreet))
            #:name "And the greeter that was switched away from is gone"))))

(define (void-cases)
  "Return the cases for the distribution the image is built for."
  (let ((iso (image-iso-script))
        (rootfs (image-rootfs-script)))
    (list (assert-true (contains? iso "mklive.sh")
            #:name "The live medium is built by void-mklive")
          (assert-true (contains? iso "-p \"$(tr")
            #:name "It is handed the package list, not a distribution's pattern")
          (assert-true (contains? iso "-I \"$payload\"")
            #:name "And the payload directory, so the image carries this tree's files")
          (assert-true (contains? iso (xbps-arch))
            #:name "The architecture is the one the platform module names")
          (assert-true (contains? iso (xbps-repository))
            #:name "And the repository is Void's")
          (assert-true (contains? rootfs "mkrootfs.sh")
            #:name "The installed system starts from mkrootfs.sh")
          (assert-true (contains? rootfs "-b base-system")
            #:name "Over a base that boots rather than a container's")
          (assert-true (contains? rootfs "chroot \"$work\" xbps-install")
            #:name "And grows with xbps inside the target")
          (assert-true (contains? rootfs "chroot \"$work\" /bin/bash /usr/local/lib/heks-linux/config.sh")
            #:name "Where the configuration phase runs"))))

(define (service-cases)
  "Return the cases for the init system.

Void has runit, so a service is a symlink into /var/service.  What must not
appear is the systemd spelling: a script that calls systemctl on a runit machine
is a script that did nothing and said nothing."
  (let ((config (image-config-script)))
    (list (assert-true (contains? config "ln -sfn /etc/sv/greetd /var/service/")
            #:name "The login daemon is enabled the runit way")
          (assert-true (contains? config "ln -sfn /etc/sv/NetworkManager /var/service/")
            #:name "And so is the network")
          (assert-true (contains? (image-setup-script)
                                  "ln -sfn /etc/sv/guix-daemon /var/service/")
            #:name "The Guix daemon's service is written, because its installer knows only systemd")
          (assert-true (not (contains? config "systemctl"))
            #:name "Nothing calls systemctl")
          (assert-true (not (contains? config "zypper"))
            #:name "Nothing calls zypper")
          (assert-true (not (contains? config "kiwi"))
            #:name "And nothing mentions KIWI"))))

(define (session-cases)
  "Return the cases for how the desktop is rendered.

The rendering is not part of the build any more: the image carries the tools, and
`heks-setup' builds the stores and renders the home on the machine that will use
it.  These cases follow the work to its new home rather than dropping it."
  (let ((setup (image-setup-script))
        (render (image-payload-script)))
    (list (assert-true (contains? setup "runuser -u \"$user\" -- bash -lc")
            #:name "The desktop is rendered as the account, not as root")
          (assert-true (contains? setup "guix pull --channels=channels.scm")
            #:name "From the pinned channels, not from whatever is current")
          (assert-true (contains? setup "/usr/local/bin/heks-render \"$user\"")
            #:name "The setup hands the rendering to the one renderer")
          (assert-true (contains? render "maak home-reconfigure")
            #:name "Which runs the same task a person runs")
          (assert-true (contains? render "maak install-nix-packages")
            #:name "And fills the shell's store")
          (assert-true (contains? render "maak install-wallpaper-files")
            #:name "The wallpapers are part of the render, not a second script")
          (assert-true (contains? render "maak install-emacs-config")
            #:name "So is the editor's configuration"))))

(define (finish-cases)
  "Return the cases for the two phases that decide the work is done.

There are two now: the build asks whether the image carries what it promises -
the session, the disk tools and the commands that finish the job - and
`heks-setup' asks whether the desktop it rendered is actually there."
  (let ((config (image-config-script))
        (setup (image-setup-script)))
    (list (assert-true (contains? config "is it ready?")
            #:name "The build ends by asking whether it is finished")
          (assert-true (contains? config "$missing thing(s) missing")
            #:name "And refuses an image that is not")
          (assert-true (contains? config
                                  "check_path \"/etc/greetd/config.toml\" \"the login prompt\"")
            #:name "The prompt's own file is checked too")
          (assert-true (not (contains? config "the compositor's configuration"))
            #:name "The build no longer claims the desktop was rendered")
          (for-each (lambda (command)
                      (assert-true (contains? config (string-append "check_command " command))
                        #:name (string-append command " is checked")))
                    image-required-commands)
          ;; The rendered files are the setup's promise, and the message with the
          ;; apostrophe moved with them: "the compositor's configuration" inside
          ;; single quotes ends the quote early and swallows the checks after it.
          (assert-true (contains? setup "the compositor's configuration")
            #:name "The setup checks the desktop it rendered")
          (assert-true (contains? setup "check_path \"$home/")
            #:name "In the home of the account it was given")
          (for-each (lambda (command)
                      (assert-true (contains? setup (string-append "check_command " command))
                        #:name (string-append command " is checked after the setup")))
                    image-rendered-commands))))

(define (installer-cases)
  "Return the cases for the installer the medium carries.

The medium has to be able to put its own system on a disk without a network: a
wizard, a partitioner, and the rootfs it unpacks.  Order matters here too - the
account is created before the desktop is rendered into its home, and the rootfs
is checked before the ISO is built around it."
  (let ((config (image-config-script))
        (iso (text-of "build-iso.sh")))
    (list (assert-true (contains? config "useradd")
            #:name "The build creates the account it renders the desktop into")
          (assert-true (< (string-contains config "useradd")
                          (string-contains config "runuser -u heks"))
            #:name "The account exists before anything runs as it")
          (assert-true (contains? config "heks-install")
            #:name "The installed system carries the installer too")
          ;; The installer renames the account the desktop was rendered for, so
          ;; the re-render has to be told which account to render for: a script
          ;; with one account compiled into it renders a home nobody owns.
          (assert-true (contains? (image-payload-script) "${1:-heks}")
            #:name "The re-render takes the account as its argument")
          ;; The stores are not in the image, so the thing that starts them is
          ;; the setup, and it starts them before it renders anything.
          (assert-true (let ((started (string-contains (image-setup-script)
                                                       "both stores answer"))
                             (rendered (string-contains (image-setup-script)
                                                        "phase 'the desktop'")))
                         (and started rendered (< started rendered)))
            #:name "The stores are started before the desktop is rendered")
          (assert-true (contains? (image-setup-script) "a store did not come up")
            #:name "And a store that does not answer stops the setup")
          (assert-true (not (contains? config "guix pull"))
            #:name "The build pulls nothing: the stores are the machine's own")
          (assert-true (contains? config ".bash_profile")
            #:name "The account's login shell reads its own rc")
          (assert-true (contains? iso "rootfs")
            #:name "The medium carries the system it installs")
          (assert-true (contains? iso
                                  "the medium cannot install without the rootfs")
            #:name "And says so instead of building a medium that cannot"))))

(define (live-cases)
  "Return the cases for what the live medium is, as opposed to what it installs.

A medium exists to install: it boots into the wizard on the console, carries the
document a person reads when they drop to a shell, and keeps both out of the
system it writes to a disk."
  (let ((iso (image-iso-script))
        (rootfs (image-rootfs-script))
        (service (image-live-installer-service))
        (quickstart (image-quickstart)))
    (list (assert-true (not (member "greetd" (image-live-services)))
            #:name "No graphical prompt competes for the console")
          (assert-true (contains? iso
                                  (format #f "-S \"~a\""
                                          (string-join (image-live-services) " ")))
            #:name "The medium is handed the services it actually starts")
          (assert-true (string-prefix? "#!/bin/sh" service)
            #:name "The tty1 service starts with its interpreter, not a blank line")
          (assert-true (contains? service "heks-install")
            #:name "tty1 runs the installer")
          (assert-true (contains? service "exec agetty")
            #:name "And gives the console back when it exits")
          (assert-true (contains? quickstart "sudo heks-install")
            #:name "The quickstart says how to install")
          (assert-true (contains? quickstart "US keyboard")
            #:name "And warns about the keyboard the passphrase is typed on")
          (assert-true (contains? iso
                                  (format #f "cp -a \"$here/~a/.\""
                                          (image-live-payload-dir)))
            #:name "The medium's own half reaches the medium")
          (assert-true (not (contains? rootfs (string-append "$here/"
                                                             (image-live-payload-dir))))
            #:name "And never reaches an installed disk")
          ;; The document and the command that shows it belong to the installed
          ;; system too: they are written into the payload the rootfs build copies.
          (assert-true (contains? (format #f "~a" (image-quickstart)) "heks-help")
            #:name "The quickstart names the command that opens it")
          (assert-true (string? (assoc-ref (image-description) "config.sh"))
            #:name "The build carries a configuration phase"))))

(define (foreign-host-cases)
  "Return the cases for building from a distribution other than Void.

void-mklive is a set of shell scripts that call xbps, and xbps is a Void tool.
The build is meant to run anywhere, so it puts the static xbps it can fetch
beside itself on the PATH - and leaves a host that already has one alone."
  (let ((rootfs (image-rootfs-script))
        (iso (image-iso-script)))
    (list (assert-true (contains? rootfs "xbps-static/usr/bin")
            #:name "The rootfs build finds a static xbps beside itself")
          (assert-true (contains? iso "xbps-static/usr/bin")
            #:name "And so does the medium's")
          (assert-true (contains? rootfs "[ -d \"$here/xbps-static/usr/bin\" ]")
            #:name "Only when it is actually there"))))

(define (leftover-cases)
  "Return the cases for the build this replaced.

The old image was declared to KIWI in XML, ran zypper and logged in through GDM
with autologin.  None of that survives; a word of it in a rendered file is a
word somebody will build on."
  (let ((all (all-build-text))
        (leftovers '("kiwi" "kiwi-ng" "zypper" "patterns-gnome" "gdm"
                     "autologin" "slowroll" "systemctl" "<image")))
    (list (assert-true (not (mentions-any? all leftovers))
            #:name "No openSUSE or KIWI vocabulary survives in the build"))))

(define (render-cases)
  "Return the cases for writing the build out."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-spec-~a" (getpid))))
         (consumed (payload-paths-consumed)))
    (list (assert-true (contains? directory "heks-image-spec")
            #:name "The renderer writes where it was told")
          (assert-true (file-exists? (format #f "~a/~a" directory
                                             (image-packages-filename)))
            #:name "The package list is one file")
          (assert-true (file-exists? (format #f "~a/~a" directory
                                             (image-config-script-filename)))
            #:name "The configuration phase is another")
          (assert-true (file-exists? (format #f "~a/root/etc/greetd/config.toml" directory))
            #:name "And the greeter's file is already in the payload")
          (assert-true (file-exists? (format #f "~a/~a/~a" directory
                                             (image-payload-dir)
                                             (image-payload-script-filename)))
            #:name "As is the re-render script")
          (assert-true (and (pair? consumed)
                         (every (lambda (path)
                                  (file-exists?
                                   (format #f "~a/root~a" directory path)))
                                consumed))
            #:name "Every file config.sh reads from the payload was rendered"))))

(define (musl-cases)
  "Return the cases for the libc seam.

Musl is a parameter away, not a rewrite - but it is refused now, because whelk
and lambdock come from a glibc Nix flake and Flatpak is glibc-only.  The refusal
has to happen before anything is written, not at a login prompt."
  (list (assert-true (eq? 'glibc (target-libc))
          #:name "The image is glibc")
        (assert-true (string=? "x86_64" (xbps-arch))
          #:name "On the architecture Void spells that way, without the musl suffix")
        (assert-true (catch #t
                            (lambda ()
                              (parameterize ((target-libc 'musl))
                                (install-image-config #:dir "/tmp/heks-image-musl-spec"))
                              #f)
                            (lambda (key . args) #t))
          #:name "A musl build is refused, with a reason, before it writes anything")))

(define image-suite
  (suite "Void Image Suite"
    (test "The Package List Is A Session" (package-cases))
    (test "The Greeter Is The One The Tree Chose" (greeter-cases))
    (test "It Is Built By void-mklive" (void-cases))
    (test "Services Are Enabled The Way Void Enables Them" (service-cases))
    (test "The Desktop Is Rendered As Its Owner" (session-cases))
    (test "The Build Checks Itself" (finish-cases))
    (test "The Medium Installs Itself" (installer-cases))
    (test "The Medium Boots Into The Installer" (live-cases))
    (test "It Builds From A Host That Is Not Void" (foreign-host-cases))
    (test "Nothing From The Old Image Survives" (leftover-cases))
    (test "It Is Rendered Before It Ships" (render-cases))
    (test "The Target Is glibc, For Now" (musl-cases))))

(define (spec)
  (veritas-run image-suite))
