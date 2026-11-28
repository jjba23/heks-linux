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
  #:use-module (heks-linux grub)
  #:use-module (heks-linux logging)
  #:use-module (heks-linux boot)
  #:use-module (heks-linux platform)
  #:use-module (heks-linux services)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? haystack needle)
  "Return @code{#t} when @var{needle} occurs in the string @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

(define (how-many haystack needle)
  "Return how many times @var{needle} occurs in @var{haystack}."
  (let loop ((start 0) (count 0))
    (let ((at (string-contains haystack needle start)))
      (if at
        (loop (+ at (string-length needle)) (+ count 1))
        count))))

(define (mentions-any? text needles)
  "Return the first of @var{needles} that occurs in @var{text}, or @code{#f}."
  (find (lambda (needle) (contains? text needle)) needles))

(define (name-character? char)
  "Return @code{#t} when @var{char} can be part of a shell variable's name."
  (or (char-alphabetic? char) (char-numeric? char) (char=? char #\_)))

(define (shell-variables-read text)
  "Return every variable @var{text} reads by bare name, without duplicates.

@code{${name:-default}} is left out: the default answers @code{set -u}, so that
form cannot stop a script.  @code{$1} and @code{$@} are not names and are left
out with it."
  (let loop ((index 0) (found '()))
    (let ((at (string-index text #\$ index)))
      (if (not at)
        (reverse (delete-duplicates found))
        (let ((next (and (< (+ at 1) (string-length text))
                      (string-ref text (+ at 1)))))
          (cond
            ;; ${name} is a read; ${name:-default} is a read that cannot be
            ;; unbound, so only the first form is one.
            [(and next (char=? next #\{))
             (let* ((start (+ at 2))
                    (stop (string-index text #\} start))
                    (body (and stop (substring text start stop)))
                    (colon (and body (string-index body #\:)))
                    (name (and body (substring body 0 (or colon (string-length body))))))
               (loop (min (string-length text) (1+ (or stop at)))
                     (if (and name (> (string-length name) 0)
                           (not colon)
                           (every name-character? (string->list name)))
                       (cons name found)
                       found)))]
            [(and next (name-character? next) (not (char-numeric? next)))
             (let ((stop (or (string-index text
                                           (lambda (char) (not (name-character? char)))
                                           (+ at 1))
                           (string-length text))))
               (loop stop (cons (substring text (+ at 1) stop) found)))]
            [else (loop (+ at 1) found)]))))))

(define (shell-variables-set text)
  "Return every name @var{text} gives a value: an assignment, a `for', a `read'."
  (delete-duplicates
   (append (fold-matches "(^|[^A-Za-z_0-9-])([A-Za-z_][A-Za-z_0-9]*)=" text '()
                         (lambda (match found)
                           (cons (match:substring match 2) found)))
           (fold-matches "for[ \t]+([A-Za-z_][A-Za-z_0-9]*)[ \t]+in" text '()
                         (lambda (match found)
                           (cons (match:substring match 1) found)))
           (fold-matches "read[ \t]+(-[a-zA-Z]+[ \t]+)*([A-Za-z_][A-Za-z_0-9]*)" text '()
                         (lambda (match found)
                           (cons (match:substring match 2) found))))))

;; The names bash itself answers for: a script that reads one of these is not
;; reading something nobody set.
(define bash-provided-variables
  '("BASH_COMMAND" "EUID" "HOME" "IFS" "LINENO" "OLDPWD" "PATH" "PPID" "PWD"
    "RANDOM" "SECONDS" "SHELL" "UID" "USER"))

(define (shell-code-only text)
  "Return @var{text} with its comments cut away.

A `#' begins a comment where a word begins, and the shell reads nothing after it,
so a `$name' there is documentation and not a read.  Stripping it keeps a comment
that names a variable from being reported as an unbound one.

shortcut: a `#' inside a quoted string is cut as well; the build's scripts quote
none, and a mistake here can only hide a read, never invent one."
  (let loop ((index 0) (start 0) (lines '()))
    (let ((newline (string-index text #\newline index)))
      (let* ((line (substring text start (or newline (string-length text))))
             (hash (string-index line #\#))
             (kept (if (and hash
                         (or (zero? hash)
                           (char-whitespace? (string-ref line (1- hash)))))
                     (substring line 0 hash)
                     line))
             (lines (cons kept lines)))
        (if (not newline)
          (string-join (reverse lines) "\n")
          (loop (1+ newline) (1+ newline) lines))))))

(define (unbound-variables text)
  "Return the variables @var{text} reads and never sets.

The configuration phase runs inside the target with @code{set -u}, and it is
written by a renderer: a name it reads and the renderer forgets to give it stops
the build in the middle of a phase, after an hour of downloads, with
@code{home: unbound variable} and nothing else to say.  A test that only asks
whether the script parses (`bash -n') answers yes to that one."
  (let* ((code (shell-code-only text))
         (set (shell-variables-set code)))
    (filter (lambda (name)
              (not (or (member name set) (member name bash-provided-variables))))
            (shell-variables-read code))))

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
        ;; Void's kernel packages carry their version, so a pinned one ages out
        ;; and the image keeps booting a kernel the repository has moved past.
        ;; `linux-mainline' is the metapackage void-packages points at the newest
        ;; mainline kernel, and it is one word that does not need a bump.
        (assert-equal #:expect "linux-mainline"
          #:got (image-kernel)
          #:name "The image follows Void's newest mainline kernel")
        (assert-true (packaged? "niri")
          #:name "The compositor is on the image")
        (assert-true (packaged? "greetd")
          #:name "The login daemon is on the image")
        (assert-true (packaged? "tuigreet")
          #:name "The prompt is the terminal greeter, which needs no GPU")
        (assert-true (packaged? "guile")
          #:name "The language the desktop is written in is on the image")
        (assert-true (packaged? "nix")
          #:name "The shell comes from Nix, so the store is on the image")
        (assert-true (packaged? "git")
          #:name "The build clones the checkouts with the image's own git")
        (assert-true (packaged? "curl")
          #:name "And fetches with the image's own curl")
        (assert-true (packaged? "wget")
          #:name "The Guix installer downloads its key and tarball with wget")
        (assert-true (packaged? "gnupg")
          #:name "And verifies the download with gpg")
        (assert-true (packaged? "cryptsetup")
          #:name "The image can open a LUKS2 volume")
        ;; Non-free is enabled by a package: `void-repo-nonfree' adds the
        ;; repository to xbps's configuration, so an install that carries it
        ;; can take the microcode, the firmware and the drivers main does not.
        (assert-true (packaged? "void-repo-nonfree")
          #:name "Void's non-free repository is enabled on the image")
        (assert-true (packaged? "chrony")
          #:name "The clock is kept right from the first boot")
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
        ;; A card without its firmware is a device that never appears, and
        ;; nothing on a live medium can know which card the machine has.
        (assert-true (packaged? "linux-firmware")
          #:name "The firmware every network card loads is on the medium")
        (assert-true (packaged? "wpa_supplicant")
          #:name "And the supplicant NetworkManager joins wireless with")
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

The image does not carry a prompt of its own: it carries what
(heks-linux greeter) names, and the file greetd reads."
  (list (assert-true (contains? (text-of (image-config-script-filename))
                                "install -m 644 /usr/local/lib/heks-linux/greetd.toml /etc/greetd/config.toml")
          #:name "The image installs the greeter's own file where greetd reads it")
        (assert-true (contains? (text-of (image-config-script-filename))
                                "install -m 644 /usr/local/lib/heks-linux/tuigreet.toml /etc/tuigreet/config.toml")
          #:name "The prompt's own settings are installed where tuigreet reads them")
        (assert-true (contains? (greetd-config) "command = \"tuigreet --cmd")
          #:name "And the file starts the terminal prompt with the session as its one argument")
        (assert-true (packaged? "tuigreet")
          #:name "The terminal prompt is on the image")
        (assert-true (not (packaged? "gtkgreet"))
          #:name "There is no GTK greeter: the prompt has no compositor to draw in")
        (assert-true (packaged? "cage")
          #:name "cage stays for the medium's own window on tty2, and not for the prompt")))

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
          ;; plymouthd starts in the initramfs whenever the plymouth module is in
          ;; it, and the command line is the only switch: `getargbool 1
          ;; plymouth.enable' is what dracut asks.  The medium carries the
          ;; package, so a medium booted without this is a black screen on a
          ;; machine whose graphics cannot draw, which is the machine a medium is
          ;; most often booted on.
          (assert-true (contains? iso (format #f "-C \"~a\"" plymouth-kernel-argument))
            #:name "The medium asks for its passphrase the same way: on the console")
          ;; void-mklive's scripts open with `. ./lib.sh', so they only work from
          ;; their own directory: run from the checkout they die on the first
          ;; function the missing library would have defined.
          (assert-true (contains? rootfs "cd \"$mklive\"")
            #:name "The rootfs build stands in void-mklive's own directory")
          (assert-true (contains? iso "cd \"$mklive\"")
            #:name "And so does the medium's")
          (assert-true (< (string-contains rootfs "cd \"$mklive\"")
                          (string-contains rootfs "./mkrootfs.sh"))
            #:name "Before it runs the tool")
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
          ;; A repository publishes its packages before the index that names
          ;; them, and an install caught in between asks for a version whose
          ;; files are already gone: the build asked twice, dropping the index
          ;; the chroot cached so the second sync fetches the one written after
          ;; the packages were.
          (assert-true (contains? rootfs "rm -f \"$work\"/var/db/xbps/*-repodata*")
            #:name "A failed install drops the index the mirror served")
          (assert-equal #:expect 2
            #:got (how-many rootfs "xbps-install -Suy --yes $packages")
            #:name "And asks for the packages a second time")
          (assert-true (contains? rootfs "chroot \"$work\" /bin/bash /usr/local/lib/heks-linux/config.sh")
            #:name "Where the configuration phase runs"))))

(define (service-cases)
  "Return the cases for the init system.

Void has runit, so a service is a symlink into the supervisor's directory.  Not
into /var/service: that path is a chain of symlinks into /run, which is empty
while a chroot is being built, so linking through it fails and stops the build.
What must not appear is the systemd spelling: a script that calls systemctl on a
runit machine is a script that did nothing and said nothing."
  (let ((config (image-config-script)))
    (list (assert-true (contains? config "ln -sfn /etc/sv/greetd /etc/runit/runsvdir/default/")
            #:name "The login daemon is enabled the runit way")
          ;; greetd owns the first console, and Void's getty for that console is
          ;; a second program writing to the same screen: two prompts are no
          ;; prompt.  The other consoles keep theirs, which is what makes
          ;; Ctrl+Alt+F4 a login with a shell on it.
          (assert-true (contains? config
                                  "rm -f /etc/runit/runsvdir/default/agetty-tty1")
            #:name "The getty on greetd's console is stopped")
          (assert-true (not (contains? config "agetty-tty4"))
            #:name "And the consoles greetd does not take keep their getty")
          (assert-true (contains? config "ln -sfn /etc/sv/NetworkManager /etc/runit/runsvdir/default/")
            #:name "And so is the network")
          ;; A clock that started from the firmware's idea of the time fails
          ;; every certificate check - the store's first fetch included - with
          ;; an error about TLS rather than about the time.
          (assert-true (contains? config "ln -sfn /etc/sv/chronyd /etc/runit/runsvdir/default/")
            #:name "And the clock, before anything verifies a certificate")
          (assert-true (not (contains? config "/var/service"))
            #:name "And nothing links through /var/service, which a chroot does not have")
          (assert-true (contains? (image-setup-script)
                                  "[ -x \"/etc/sv/$service/run\" ]")
            #:name "The Guix daemon's service is written, because its installer knows only systemd")
          (assert-true (contains? (image-setup-script)
                                  "ln -sfn \"/etc/sv/$service\" /etc/runit/runsvdir/default/")
            #:name "And both are linked where runit reads them, so a reboot starts them")
          (assert-true (contains? (image-setup-script)
                                  "for service in guix-daemon nix-daemon")
            #:name "Nix's included, which arrives with its package disabled")
          (assert-true (not (contains? config "systemctl"))
            #:name "Nothing calls systemctl")
          (assert-true (not (contains? config "zypper"))
            #:name "Nothing calls zypper")
          (assert-true (not (contains? config "kiwi"))
            #:name "And nothing mentions KIWI"))))

;;; The account the image builds is in wheel, and wheel is only half of a
;;; permission: sudoers has to carry a line for it, and Void's sudo ships that
;;; line commented out - as `# %wheel ALL=(ALL:ALL) ALL' in the version this image
;;; carries, with tabs in older ones.  A machine whose account cannot sudo is a
;;; machine whose own tasks stop at the first one, because every install path in
;;; this tree runs `sudo xbps-install' or `sudo apt-get'.  So the rule is a file
;;; this tree writes, in the include directory sudo documents, and sudo is on the
;;; image for the rule to mean anything.
(define (admin-cases)
  "Return the cases for the account's administration right."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-admin-spec-~a" (getpid))))
         (rule (format #f "~a/root~a" directory (image-wheel-sudoers-path)))
         (text (and (file-exists? rule) (call-with-input-file rule get-string-all)))
         (config (image-config-script)))
    (list (assert-true (packaged? "sudo")
            #:name "The image carries sudo, which every install task in this tree runs")
          (assert-true (contains? text "%wheel ALL=(ALL:ALL) ALL")
            #:name "And the payload carries the wheel rule, so the account in wheel can administer")
          (assert-true (not (contains? text "NOPASSWD"))
            #:name "It asks for the account's own password: an administration right, not an open machine")
          (assert-equal #:expect 288
            #:got (stat:perms (stat rule))
            #:name "0440, the mode sudo accepts for a sudoers file, and the one a payload copy does not keep for itself")
          (assert-true (contains? config
                                  (format #f "check_path ~s" (image-wheel-sudoers-path)))
            #:name "And the build checks that it is in the image it packs"))))

(define (slurp-or-empty path)
  "Return @var{path}'s contents, or the empty string when it is not there.

A case that reads a file the build did not write fails on the assertion that
names it rather than on an exception that says nothing about the image."
  (if (file-exists? path)
    (call-with-input-file path get-string-all)
    ""))

;;; A machine installed from this medium boots into a session before it has a
;;; store to render one with: `heks-setup' is what writes every file of the
;;; desktop, and it needs Guix first - which needs a network.  So the image
;;; carries the three files a session cannot do without, rendered at build time
;;; by the same modules that render the rest, and the account's home gets them
;;; before its first login.  They are not a second source of truth: they are the
;;; same renderer's output, and `heks-render' writes every one of them again for
;;; the machine it actually is.
(define (first-home-cases)
  "Return the cases for the home the image carries."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-first-home-spec-~a" (getpid))))
         (home (format #f "~a/root/usr/local/lib/heks-linux/~a"
                       directory (image-home-dir)))
         (config (image-config-script))
         (niri (format #f "~a/.config/niri/config.kdl" home)))
    (list (assert-true (file-exists? niri)
            #:name "The compositor's configuration travels with the image")
          (assert-true (contains? (slurp-or-empty niri) "binds {")
            #:name "With the keybindings: a session with none is a black screen")
          (assert-true (contains? (slurp-or-empty niri) "spawn-sh-at-startup")
            #:name "And the programs a session starts with")
          (assert-true (file-exists? (format #f "~a/.config/kitty/kitty.conf" home))
            #:name "The terminal's own settings are there, so the first window is not somebody else's")
          (assert-true (file-exists? (format #f "~a/.config/whelk/settings.scm" home))
            #:name "And the bar's, for the account that will start it")
          ;; The rest of the session's surfaces travel with the same promise: a
          ;; first login that opens a second session, shows a notification, or
          ;; draws a toolkit window is one where those files are already there.
          ;; Without them the session starts and every surface wears the
          ;; toolkit's or the program's own defaults instead of this desktop.
          (assert-true (file-exists? (format #f "~a/.config/labwc/rc.xml" home))
            #:name "The stacking session's compositor has its configuration")
          (assert-true (file-exists? (format #f "~a/.config/labwc/autostart" home))
            #:name "And the programs it starts with, or it draws an empty desktop")
          (assert-true (file-exists? (format #f "~a/.config/mako/config" home))
            #:name "A notification is this desktop's, not mako's default box")
          (assert-true (file-exists? (format #f "~a/.config/gtk-3.0/settings.ini" home))
            #:name "GTK 3 wears the palette in the first window it draws")
          (assert-true (file-exists? (format #f "~a/.config/gtk-4.0/settings.ini" home))
            #:name "And so does GTK 4")
          ;; GTK reads dconf before a settings file, and nothing on this desktop
          ;; manages dconf: the session runs these two writers, so the scripts
          ;; have to be in the account the session starts in.
          (assert-true (file-exists?
                        (format #f "~a/.local/bin/write-gtk-dconf-settings" home))
            #:name "The toolkit's dconf writer is there for the session to run")
          (assert-true (file-exists?
                        (format #f "~a/.local/bin/write-heks-linux-dconf-settings" home))
            #:name "And the settings writer beside it")
          (assert-true (file-exists? (format #f "~a/.config/lambdock/settings.scm" home))
            #:name "The dock's definition travels, so the dock is this desktop's")
          (assert-true (file-exists? (format #f "~a/.config/waybar/config.jsonc" home))
            #:name "And the fallback bar's, for a machine without the shell")
          (assert-true (contains? config
                                  (format #f "check_path ~s"
                                          (image-home-path ".config/labwc/rc.xml")))
            #:name "And the build checks the stacking session's file, not only the tiling one")
          (assert-true (contains? config
                                  (format #f "check_path ~s"
                                          (image-home-path ".config/lambdock/settings.scm")))
            #:name "And the dock's, which the session starts when it is installed")
          ;; The build renders this tree's defaults, not the builder's desktop: a
          ;; machine's own overrides live in its $XDG_CONFIG_HOME, and an image
          ;; that carried them would be somebody's palette handed to everybody.
          (assert-true (contains? config "the account's own files")
            #:name "The configuration phase gives them to the account")
          ;; The account is the image's own, so its home is rendered into the
          ;; script rather than left to a variable: `$home' is what the scripts
          ;; that are handed an account read, and here nothing would set it.
          (assert-true (contains? config
                                  (format #f "cp -a /usr/local/lib/heks-linux/home/. ~s"
                                          (string-append (image-user-home) "/")))
            #:name "By copying them into its home, where a session reads them")
          (assert-true (contains? config
                                  (format #f "chown -R ~a:users ~s"
                                          (image-user) (image-user-home)))
            #:name "Owned by the account, because a file root kept is one the session cannot write")
          (assert-equal #:expect '()
            #:got (unbound-variables config)
            #:name "And every variable it reads is one it sets, which `set -u' answers for")
          (assert-true (contains? config
                                  (format #f "check_path ~s"
                                          (image-home-path ".config/niri/config.kdl")))
            #:name "And the build checks the payload carries them"))))

(define (logging-cases)
  "Return the cases for the machine's log.

Void ships no syslog daemon, and every service Void ships hands its output to
`vlogger', which is syslog(3): with nothing on /dev/log those lines are thrown
away rather than shown, so a machine can be logged into and impossible to
diagnose.  What does reach the console - the one greetd draws the prompt on - is
the kernel's own printk, and every daemon that falls back to /dev/kmsg.  These
cases hold the build to both halves: a syslog to write to, and a console
loglevel that keeps the kernel off the prompt."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-logging-spec-~a" (getpid))))
         (config (image-config-script))
         (sysctl (format #f "~a/root~a" directory (console-sysctl-path)))
         (snapshot-log (format #f "~a/root/etc/sv/~a/log/run"
                               directory (image-snapshot-filename))))
    (list (assert-true (packaged? "socklog-void")
            #:name "The syslog Void documents for runit is on the image")
          (assert-true (contains? config "ln -sfn /etc/sv/socklog-unix /etc/runit/runsvdir/default/")
            #:name "The daemon on /dev/log is enabled the runit way")
          (assert-true (contains? config "ln -sfn /etc/sv/nanoklogd /etc/runit/runsvdir/default/")
            #:name "And so is the one that forwards the kernel's ring buffer to it")
          (assert-true (file-exists? sysctl)
            #:name "The console loglevel is a rendered drop-in, not a hand edit")
          (assert-true (contains? (console-sysctl) "kernel.printk = 3 4 1 7")
            #:name "It keeps errors, warnings, notices and the boot's chatter off the screen")
          (assert-true (contains? (console-sysctl) "/etc/sysctl.d")
            #:name "The file says where it is read from")
          (assert-true (contains? config
                                  (format #f "check_path ~s" (console-sysctl-path)))
            #:name "The build checks that it is in the image it packs")
          (assert-true (contains? config
                                  (format #f "useradd -m -G wheel,video,audio,input,kvm,plugdev,~a"
                                          logging-group))
            #:name "And the account that owns the machine can read /var/log/socklog")
          ;; A service of this tree's that talks without a log/run talks on the
          ;; console greetd is drawing on: the daily snapshot says so when it
          ;; fails, and that is once a day for the life of the machine.
          (assert-true (file-exists? snapshot-log)
            #:name "The snapshot service has a log service of its own")
          (assert-true (contains? (log-service (image-snapshot-filename))
                                  "exec vlogger -t heks-snapshot -p daemon")
            #:name "Which hands its lines to syslog with the service's name on them")
          (assert-true (catch #t
                              (lambda ()
                                (log-service "not a name; rm -rf /")
                                #f)
                              (lambda (key . args) #t))
            #:name "A tag that is not a service name is refused, not interpolated"))))

(define (session-list-cases)
  "Return the cases for the sessions the prompt lists.

F3 at the prompt reads /usr/share/wayland-sessions as the greeter's own account
and starts the chosen entry's Exec line.  So the list is three promises at once:
the entries are system files, the commands are the ones that start a session on
runit, and both sessions this tree offers are in it.  niri's packaged entry is
the reason the middle one has to be checked - its Exec is `niri-session', a
wrapper that looks for a service manager and exits without starting the
compositor when it finds none."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-sessions-spec-~a" (getpid))))
         (config (image-config-script)))
    (list (assert-true (packaged? "labwc")
            #:name "The floating session's compositor is on the image")
          (append-map
           (lambda (session)
             (let* ((filename (greeter-session-filename session))
                    (path (format #f "~a/~a" greeter-session-dir filename))
                    (rendered (format #f "~a/root~a" directory path))
                    (entry (greeter-session-entry session)))
               (list (assert-true (file-exists? rendered)
                       #:name (format #f "~a is rendered into the payload" filename))
                     (assert-true (contains? entry (format #f "Exec=~a" (cadr session)))
                       #:name (format #f "~a starts its session itself" (car session)))
                     (assert-true (not (contains? entry "niri-session"))
                       #:name (format #f "~a does not hand the session to a service manager" (car session)))
                     (assert-true (contains? config (format #f "check_path \"~a\"" path))
                       #:name (format #f "The build checks that ~a is in the image it packs" filename))
                     (assert-true (contains? config (format #f "check_command ~a" (caddr session)))
                       #:name (format #f "And that ~a is installed" (car session))))))
           greeter-sessions)
          ;; The packages' entries go, before the prompt reads the directory: one
          ;; is a lie about how the session starts and the other is the same
          ;; session offered twice.
          (assert-true (contains? (image-sessions-core-service)
                                  "rm -f /usr/share/wayland-sessions/niri.desktop")
            #:name "niri's packaged entry is removed at stage 1")
          (assert-true (contains? (image-sessions-core-service)
                                  "rm -f /usr/share/wayland-sessions/labwc.desktop")
            #:name "And so is labwc's, which is the entry this tree already lists")
          (assert-true (file-exists? (format #f "~a/root/etc/runit/core-services/~a"
                                             directory
                                             (image-sessions-core-service-filename)))
            #:name "The script that does it is in the payload"))))

(define (session-cases)
  "Return the cases for how the desktop is rendered.

The rendering is not part of the build any more: the image carries the tools, and
`heks-setup' builds the stores and renders the home on the machine that will use
it.  These cases follow the work to its new home rather than dropping it."
  (let ((setup (image-setup-script))
        (render (image-payload-script)))
    (list (assert-true (contains? setup "runuser -u \"$user\" -- bash -lc")
            #:name "The desktop is rendered as the account, not as root")
          ;; Guix's installer reads one answer per question and stops a console
          ;; install dead at the first one nobody is sitting in front of.  The
          ;; answers travel on stdin, in the order the installer asks them, and
          ;; the last is the no: this desktop's shell belongs to heks-bash, not
          ;; to a block the Guix installer appends to every .bashrc.
          (assert-true (contains? setup
                                  "printf '\\ny\\ny\\ny\\ny\\nn\\n' | bash \"$guix_installer\"")
            #:name "The Guix installer is given its answers, not a keyboard")
          (assert-true (contains? setup "exec </dev/null")
            #:name "And nothing after it can wait for one")
          ;; The first thing it asks is whether there is a network at all: a
          ;; machine installed offline runs this by hand, and ten minutes of
          ;; failing downloads reads as a broken setup rather than one with no
          ;; way to reach the stores.
          (assert-true (contains? setup "no network: guix and nix arrive over it")
            #:name "A machine with no network is told so in one sentence")
          ;; The medium carries the home this tree rendered at build time, and
          ;; this is where an installed machine gets it: before the network
          ;; phase, because that phase is where a machine with no network stops,
          ;; and a desktop that needs no download is the point of carrying it.
          ;; Nothing is clobbered - a file the account already has is the newer
          ;; one, and the render below writes every one of them again.
          (assert-true (contains? setup
                                  "cp -an /usr/local/lib/heks-linux/home/. \"$home/\"")
            #:name "The medium's home is handed to the account")
          (assert-true (not (contains? setup
                                       "cp -a /usr/local/lib/heks-linux/home/. \"$home/\""))
            #:name "Without overwriting a file the account already has")
          (assert-true (< (string-contains setup "cp -an /usr/local/lib/heks-linux/home")
                          (string-contains setup "phase 'the network'"))
            #:name "Before the network phase, which is where an offline machine stops")
          ;; And the check at the end holds the render to the same surfaces: a
          ;; render that wrote the tiling session and stopped there would pass a
          ;; check that only named it.
          (assert-true (contains? setup "check_path \"$home/.config/labwc/rc.xml\"")
            #:name "The setup checks the second session's configuration")
          (assert-true (contains? setup "check_path \"$home/.config/lambdock/settings.scm\"")
            #:name "And the dock's")
          ;; Guix's installer builds as an unprivileged user through newuidmap and
          ;; newgidmap.  Debian puts those in a package of its own, so a Debian
          ;; installed by Debian's installer has neither, and the setup stops at
          ;; "Missing commands: newgidmap" having installed nothing - the exact
          ;; failure the Debian page's first step exists to prevent.
          (assert-true (contains? setup "command -v newgidmap")
            #:name "The setup asks for the mapping tools the Guix installer needs")
          (assert-true (contains? setup
                                  "apt-get install -y --no-install-recommends uidmap")
            #:name "And installs Debian's package for them when apt is the manager")
          (assert-true (contains? setup "log 'pulling the pinned channels'")
            #:name "The long steps say when they start, so a slow one reads as slow")
          ;; Void packages nix itself, so its daemon lives in /usr/bin and
          ;; /nix/var/nix/profiles/default is the empty directory the official
          ;; installer would have filled.  Naming that path started nothing and
          ;; the store it should have started never answered: the daemon is the
          ;; one this machine carries, whatever path it is at.
          (assert-true (contains? setup "command -v nix-daemon")
            #:name "The Nix daemon is found on the machine, not assumed to be in a profile")
          (assert-true (not (contains? setup "/nix/var/nix/profiles/default/bin/nix-daemon"))
            #:name "And not named by the path only Nix's own installer makes")
          (assert-true (contains? setup "pull --channels=channels.scm")
            #:name "From the pinned channels, not from whatever is current")
          ;; `guix' on a PATH is not yet a thing for an account that has never
          ;; pulled: the binaries are named, so a machine where /etc/profile.d
          ;; was not read is a machine where the pull still happens.
          (assert-true (contains? setup
                                  "/var/guix/profiles/per-user/root/current-guix/bin/guix")
            #:name "Root's guix is named by path, not found on a PATH")
          (assert-true (contains? setup
                                  ".config/guix/current/bin/guix install")
            #:name "And the account's own is what installs into its profile")
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

(define (store-cases)
  "Return the cases for the two stores the desktop is built from.

A store is three things and all three can be missing: the settings that let its
commands run, a daemon that answers while the machine is on, and the link that
makes runit start that daemon again after a reboot.  These cases hold the build
and the setup to the three, because a desktop whose shell cannot be installed
after the first reboot is one that worked once, on the day it was installed."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-stores-spec-~a" (getpid))))
         (setup (image-setup-script))
         (nix-conf (format #f "~a/root/etc/nix/nix.conf" directory)))
    (list
     ;; Void's `nix' package writes a nix.conf with the build users group in it
     ;; and nothing else, so `nix profile add .#whelk' - the command every task
     ;; that installs the shell runs - stops with a message about an
     ;; experimental feature.  The file is the image's, so a fresh install has
     ;; it before anything asks the store for a package.
     (assert-true (file-exists? nix-conf)
       #:name "The payload carries /etc/nix/nix.conf")
     (assert-true
       (and (file-exists? nix-conf)
         (contains? (call-with-input-file nix-conf get-string-all)
                    "experimental-features = nix-command flakes"))
       #:name "With the two features `nix profile' and the flake need")
     (assert-true (contains? setup "experimental-features = nix-command flakes")
       #:name "And a machine installed before the file was carried gets the line")
     ;; The daemon is started by hand while the setup runs, in a chroot with no
     ;; init; the link is what makes the next boot start it again.
     (assert-true (contains? setup "for service in guix-daemon nix-daemon")
       #:name "Both daemons are enabled at boot, not only started once")
     (assert-true (contains? setup "check_service guix-daemon")
       #:name "The setup checks the link it made for Guix")
     (assert-true (contains? setup "check_service nix-daemon")
       #:name "And the one Void's package never makes")
     (assert-true (contains? setup "check_store guix")
       #:name "And that each store answers when it is asked")
     (assert-true (contains? setup "check_store nix")
       #:name "Both of them")
     ;; A daemon started with a client's environment is the bug this phase had.
     ;; A login shell exports NIX_REMOTE=daemon for the `nix' command, and a
     ;; daemon that inherits it resolves its own store to the socket it is about
     ;; to bind - "daemon socket path ... is the same as the store's socket
     ;; path; this will fail" - and answers nothing afterwards, which leaves a
     ;; machine whose every session install fails on a store that is there.
     (assert-true (contains? setup "env -u NIX_REMOTE")
       #:name "The daemon is started without the client's NIX_REMOTE")
     (assert-true (contains? setup "-u NIX_DAEMON_SOCKET_PATH")
       #:name "And without an inherited socket, state or store directory")
     (assert-true (contains? setup "sv start nix-daemon")
       #:name "On the machine itself runit starts it, not a second copy")
     (assert-true (contains? setup "in_chroot || ! command -v sv")
       #:name "And the chroot is told apart from the machine by its own inodes")
     ;; The question a store answers is not "is there a socket file": it is
     ;; whether a client can ask it for something.  Nix's socket path follows
     ;; settings a machine may have changed, so the client is pointed at the
     ;; daemon rather than at a path this tree would have to guess.
     (assert-true (contains? setup "--store daemon store ping")
       #:name "The store is asked, not a socket looked at")
     (assert-true (not (contains? setup "/nix/var/nix/daemon-socket"))
       #:name "And its socket path is not guessed here")
     (assert-true (contains? setup "guix_answers && answers=yes")
       #:name "The last phase asks that question too, not for a version string")
     ;; The machine that could not finish the desktop finishes it itself: the core
     ;; service the installer leaves is removed here, when the stores, the render
     ;; and the links are all there.
     (assert-true (contains? setup
                             "rm -f \"/etc/runit/core-services/50-heks-firstboot.sh\"")
       #:name "A finished setup removes the first boot's own attempt")
     (assert-true (< (string-contains setup "desktop is not finished")
                     (string-contains setup "rm -f \"/etc/runit/core-services"))
       #:name "Only after the phase decided everything is there")
     ;; Guix 1.5 warns that a channel with an introduction "is not trusted"
     ;; unless it is one of the channels the account trusts, or one the running
     ;; guix already has: on a fresh machine the installer's guix has the
     ;; official one only, so the first pull after a disk is written says so.
     ;; The account's trusted list is the checkout's channels.scm, written
     ;; before the pull; /etc/guix/channels.scm is the same list as the
     ;; machine's default, so a bare `guix pull' keeps the pins instead of
     ;; falling back to Guix's master alone.
     (assert-true (contains? setup
                             "/etc/guix/channels.scm")
       #:name "The pinned channels are the machine's own default")
     (assert-true (contains? setup
                             ".config/guix/trusted-channels.scm")
       #:name "And the account trusts the collection before it pulls it")
     ;; The installer is one shell script served by one host, and that host was
     ;; the whole failure: git.savannah.gnu.org answered nothing at all on a
     ;; machine with a working network, and the run died on it after a minute of
     ;; waiting.  So the mirrors are tried in order, Codeberg's first - the host
     ;; this tree already fetches its own checkouts from - and a dead one costs
     ;; seconds rather than a timeout.
     (assert-true (contains? setup
                             "https://codeberg.org/guix/guix/raw/branch/master/etc/guix-install.sh")
       #:name "The Guix installer comes from Codeberg's mirror of Guix")
     (assert-true (< (string-contains setup "https://codeberg.org/guix/guix/raw")
                     (string-contains setup "https://git.savannah.gnu.org/cgit/guix.git/plain"))
       #:name "Before Savannah, which is the fallback and not the first try")
     (assert-true (contains? setup "--connect-timeout 10")
       #:name "A host that does not answer is given ten seconds, not eighty")
     ;; A download that stopped halfway is a script that runs half of itself: the
     ;; last line of an installer is where the install is, so `bash -n' is what
     ;; says the file is a whole program before it is given root's shell.
     (assert-true (contains? setup "bash -n \"$guix_installer\"")
       #:name "And a download that is not a whole script is never run")
     (assert-true (contains? setup "no guix installer could be fetched")
       #:name "With every mirror failing, the setup says which command to run again"))))

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
          (assert-true (contains? config
                                  "check_path \"/etc/tuigreet/config.toml\" \"the way the prompt looks\"")
            #:name "And the file the prompt draws itself with")
          ;; The phrase with the apostrophe is what used to end a single-quoted
          ;; message early and swallow the checks written after it.  Both scripts
          ;; name it now - the image carries the compositor's own file, and the
          ;; setup checks the one it rendered - and both quote it as one
          ;; double-quoted word, which is what makes the apostrophe harmless.
          (assert-true (contains? config
                                  (format #f "check_path ~s ~s"
                                          (image-home-path ".config/niri/config.kdl")
                                          "the compositor's configuration, before a store can render it"))
            #:name "The compositor's file is expected by the build, in a message that cannot end a quote")
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
          ;; Void's shadow package gives every account tool the `chage' PAM
          ;; stack, whose password line is `pam_permit'; shadow's chpasswd walks
          ;; PAM unless it is handed a crypt method, so a stock Void machine
          ;; answers `chpasswd user:password' with success and changes nothing.
          ;; The payload carries shadow's own file, and /etc/pam.d is in its
          ;; `conf_files', so a package upgrade leaves it in place.
          (assert-true (contains? (image-chpasswd-pam) "password\tinclude\t\tsystem-auth")
            #:name "The payload carries shadow's own chpasswd stack, and its password line is the machine's own")
          (assert-true (contains? config "check_path \"/etc/pam.d/chpasswd\"")
            #:name "And the build checks that it is in the image it packs")
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
        (quickstart (image-quickstart))
        (directory (install-image-config
                    #:dir (format #f "/tmp/heks-image-live-spec-~a" (getpid)))))
    (list (assert-true (not (member "greetd" (image-live-services)))
            #:name "No graphical prompt competes for the console")
          ;; mklive enables the services it is handed before it copies the
          ;; payload, so a service of this tree's own is a name it refuses - and
          ;; the build stopped on exactly that.  The medium still quits its
          ;; splash: the link travels in the payload's own half.
          (assert-true (not (member "plymouth-quit" (image-live-services)))
            #:name "A service of this tree's is never handed to mklive")
          (assert-true (equal? "/etc/sv/plymouth-quit"
                               (readlink (format #f "~a/~a/etc/runit/runsvdir/default/plymouth-quit"
                                                 directory (image-live-payload-dir))))
            #:name "And its runlevel link is in the payload the medium carries")
          (assert-true (contains? iso
                                  (format #f "-S \"~a\""
                                          (string-join (image-live-services) " ")))
            #:name "The medium is handed the services it actually starts")
          (assert-true (string-prefix? "#!/bin/sh" service)
            #:name "The tty1 service starts with its interpreter, not a blank line")
          (assert-true (contains? service "heks-install")
            #:name "tty1 runs the installer")
          ;; elogind, and every daemon that logs before there is a syslog to
          ;; write to, logs to /dev/kmsg; the kernel prints that on the console
          ;; the wizard draws on, and one line of it leaves the first screen half
          ;; drawn.  The console loglevel belongs to the kernel, not to a tty, so
          ;; lowering it here silences every kmsg writer on both consoles the
          ;; medium draws on - and dmesg still keeps everything.
          (assert-true (contains? service "dmesg -n 3")
            #:name "And silences the kernel console it draws on")
          (assert-true (contains? service "exec agetty")
            #:name "And gives the console back when it exits")
          (assert-true (contains? quickstart "sudo heks-install")
            #:name "The quickstart says how to install")
          (assert-true (contains? quickstart "US keyboard")
            #:name "And warns about the keyboard the passphrase is typed on")
          (assert-true (contains? quickstart "Alt+F2")
            #:name "And says how to reach the medium's window")
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

(define (medium-console-cases)
  "Return the cases for who owns the medium's consoles.

Void's agetty services are symlinks into agetty-generic, and mklive copies the
payload into the target with @command{cp -rfpP}, which follows a symlink at the
*destination*: a payload that shipped @file{etc/sv/agetty-tty1/run} did not
replace tty1's service, it overwrote the one script every console shares.  All
six then ran the installer - each redirected at tty1 - and each logged the live
account in when the installer died: six logins in the first second of stage 2,
which started logind through dbus before the supervised one had the name.  From
then on elogind restarted every second and said so on the kernel console, over
the wizard and over what the person at the keyboard was typing.

The other half of it is the environment: runsv starts a service with a PATH and
nothing else, and the installer draws with dialog, which exits before the first
screen when TERM is not set.  That is why the medium booted to a shell instead of
the wizard.

A console now belongs to one service - the wizard on tty1, the window on tty2 -
and the getty on that console is parked with a @file{down} file rather than
replaced: the file is new, so the copy that follows a destination symlink cannot
touch the script the other consoles share."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-console-spec-~a" (getpid))))
         (live (format #f "~a/~a" directory (image-live-payload-dir)))
         (consoles (image-live-consoles))
         (service (image-live-installer-service))
         (gui (image-live-gui-service))
         (menu (image-live-gui-menu)))
    (list (assert-true (contains? service "TERM=")
            #:name "The installer is given a terminal type, because runsv gives it none")
          (assert-true (contains? gui "XDG_RUNTIME_DIR=")
            #:name "And the window is given the socket directory a compositor needs")
          ;; One console, one owner.  A getty beside a wizard is two readers of
          ;; one keyboard, which is what the medium did on all six consoles.
          (assert-equal #:expect '()
            #:got (remove (lambda (console)
                            (and (file-exists?
                                  (format #f "~a/etc/sv/~a/run" live (cdr console)))
                              (file-exists?
                               (format #f "~a/etc/sv/agetty-~a/down" live (car console)))
                              (equal? (format #f "/etc/sv/~a" (cdr console))
                                      (false-if-exception
                                       (readlink
                                        (format #f "~a/etc/runit/runsvdir/default/~a"
                                                live (cdr console)))))))
                          consoles)
            #:name "Every console the medium draws on owns a service, parks its getty and is started")
          (assert-equal #:expect '()
            #:got (filter (lambda (console)
                            (file-exists?
                             (format #f "~a/etc/sv/agetty-~a/run" live (car console))))
                          consoles)
            #:name "And none of them writes over the getty script every console shares")
          (assert-true (contains? gui "cage -s")
            #:name "The window is a compositor's, and Alt+F1 still reaches the installer")
          ;; A machine the kernel does not drive - a VM with no DRM device - must
          ;; not leave a compositor respawning on tty2: the console's getty is
          ;; what it gets instead.
          (assert-true (and (contains? gui "/dev/dri/card")
                         (contains? gui "exec agetty"))
            #:name "And a machine with no device to draw on gets the console back")
          (assert-true (and (contains? menu "heks-install")
                         (contains? menu "runuser -u anon"))
            #:name "The window offers the install and a shell, and the shell is the medium's account")
          (assert-true (contains? menu "heks-help")
            #:name "And the quickstart, from the command that opens it")
          ;; Live only: what an installed machine keeps is not a menu of the
          ;; medium's choices, and a file that reaches a disk is one nobody can
          ;; remove.
          (assert-true (not (file-exists?
                             (format #f "~a/~a/usr/local/lib/heks-linux/~a"
                                     directory (image-payload-dir)
                                     (image-live-gui-filename))))
            #:name "The window is the medium's alone: a disk never gets it"))))

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

(define (isolation-cases)
  "Return the cases for what the build does to the machine it runs on.

The build mounts the host's /proc, /sys and /dev inside the target, and
void-mklive mounts loop devices and a FAT image of its own, all as root.  A
build that dies - a full disk, an OOM kill, a terminal closed at the wrong
moment - must not leave any of that behind: the next run's `rm -rf' of the work
directory would walk into the host's own /dev, and the machine that did it is a
machine where every command that writes to /dev/null fails.  So the build takes
a mount namespace for itself, removes what it mounted on the way out, and never
deletes or packs across a mountpoint."
  (let ((rootfs (image-rootfs-script))
        (iso (image-iso-script)))
    (list (assert-true (contains? rootfs "exec unshare --mount --propagation private")
            #:name "The rootfs build runs in a mount namespace of its own")
          (assert-true (contains? iso "exec unshare --mount --propagation private")
            #:name "And so does the medium's")
          (assert-true (< (string-contains rootfs "unshare --mount")
                          (string-contains rootfs "./mkrootfs.sh"))
            #:name "Before it mounts or builds anything")
          (assert-true (< (string-contains iso "unshare --mount")
                          (string-contains iso "./mklive.sh"))
            #:name "And likewise before the medium's tool runs")
          ;; A host without unshare still builds; it is told what it gave up
          ;; rather than refused, because the mounts are the risk and not a
          ;; missing convenience.
          (assert-true (contains? rootfs "no mount namespace")
            #:name "A host that cannot isolate says so")
          (assert-true (contains? rootfs "mount --rbind")
            #:name "The host's pseudo filesystems are bound in recursively")
          (assert-true (contains? rootfs "--make-rslave")
            #:name "As a slave, so the target cannot unmount the host's own")
          (assert-true (< (string-contains rootfs "mount_pseudofs")
                          (string-contains rootfs "chroot \"$work\" /bin/bash"))
            #:name "The mounts are in place before the configuration phase")
          (assert-true (contains? rootfs "trap umount_pseudofs")
            #:name "And go away when the build does, however it ends")
          (assert-true (contains? rootfs "is still a mount")
            #:name "A mount a dead build left behind stops the next build")
          (assert-true (contains? rootfs "rm -rf --one-file-system")
            #:name "Nothing deletes across a mountpoint")
          (assert-true (contains? rootfs "tar -C \"$work\" --one-file-system")
            #:name "And the tarball cannot contain the host's /proc, /sys or /dev")
          ;; /tmp is a tmpfs on most machines, which is RAM: a gigabyte of base
          ;; rootfs and a squashfs beside it swap the machine before they fill
          ;; the disk.
          (assert-true (and (contains? rootfs "tmp=\"$here/tmp\"")
                         (contains? rootfs "export TMPDIR=\"$tmp\""))
            #:name "Temporary files stay on the disk the build is on")
          (assert-true (and (contains? iso "tmp=\"$here/tmp\"")
                         (contains? iso "export TMPDIR=\"$tmp\""))
            #:name "For the medium as well")
          (assert-true (contains? iso "export ROOTDIR=\"$here\"")
            #:name "void-mklive builds beside the build, not inside its checkout")
          ;; xbps writes a package's INSTALL script into $TMPDIR when it is not
          ;; handed a --rootdir, and void-mklive configures packages by
          ;; chrooting into the target: the build's own TMPDIR is a path that
          ;; does not exist in there, so every package with an INSTALL script
          ;; fails to configure and the base is left half unpacked.
          (assert-true (contains? rootfs "env -u TMPDIR")
            #:name "The target configures its packages with a TMPDIR of its own")
          (assert-true (let ((shim (string-contains rootfs "env -u TMPDIR"))
                             (tool (string-contains rootfs "./mkrootfs.sh")))
                         (and shim tool (< shim tool)))
            #:name "In place before the first package is configured")
          (assert-true (contains? rootfs "the base rootfs never configured")
            #:name "And a base that never configured is refused, not packed")
          ;; GRUB's EFI tool is run through xbps-uchroot rather than chroot, and
          ;; it makes a temporary directory in $TMPDIR of its own: the same leak
          ;; one tool over, at the last step of a medium that took an hour.
          (assert-true (contains? iso "xbps-uchroot")
            #:name "The EFI loader is given a TMPDIR its own target has")
          (assert-true (contains? rootfs "xbps-uchroot")
            #:name "And the wrapper that hands it over is in both scripts")
          (assert-true (contains? rootfs "CDPATH= cd")
            #:name "The build finds its own directory whatever CDPATH says")
          (assert-true (contains? iso "CDPATH= cd")
            #:name "For the medium as well")
          (assert-true (contains? rootfs "nice -n")
            #:name "The build yields the machine while it runs"))))

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
          (assert-true (file-exists? (format #f "~a/root/etc/pam.d/~a" directory
                                             (image-chpasswd-pam-filename)))
            #:name "As is shadow's own chpasswd stack, in place of Void's silent one")
          (assert-true (file-exists? (format #f "~a/~a/~a" directory
                                             (image-payload-dir)
                                             (image-payload-script-filename)))
            #:name "As is the re-render script")
          (assert-true (and (pair? consumed)
                         (every (lambda (path)
                                  (file-exists?
                                   (format #f "~a/root~a" directory path)))
                                consumed))
            #:name "Every file config.sh reads from the payload was rendered")
          ;; The wizard's palette is a payload file like the quickstart: dialog
          ;; refuses to draw at all on a file it cannot parse, so what is
          ;; rendered has to be a whole theme and not a fragment of one.
          (assert-true (file-exists? (format #f "~a/root~a/~a" directory
                                             (image-share-dir)
                                             (image-dialog-theme-filename)))
            #:name "The dialog theme travels with both systems")
          (assert-true (and (contains? (image-dialog-theme) "screen_color")
                         (contains? (image-dialog-theme) "border_color")
                         (contains? (image-dialog-theme) "item_selected_color"))
            #:name "And is a whole theme, which is what dialog requires")
          (assert-true (contains? (image-dialog-theme) "(GREEN,BLACK")
            #:name "Green on the dark, as the medium's console is drawn")
          (assert-true (contains? (format #f "~a" (image-live-gui-menu))
                                  (format #f "~a/~a" (image-share-dir)
                                          (image-dialog-theme-filename)))
            #:name "The medium's window reads the same file"))))

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

(define (parses? text)
  "Return @code{#t} when bash reads @var{text} as a script, without running it.

The generated shell is a template before it is a script, and a quoting mistake in
it is a machine that boots into a syntax error.  `bash -n' costs a second and
finds it."
  (let ((path (format #f "/tmp/heks-script-spec-~a.sh" (getpid))))
    (call-with-output-file path
                           (lambda (port) (display text port)))
    (let ((status (status:exit-val (system* "bash" "-n" path))))
      (delete-file path)
      (zero? status))))

(define (snapshot-cases)
  "Return the cases for the snapshots an installed system keeps of itself.

The layout is one BTRFS filesystem with @ at / and @snapshots at /.snapshots, so
a snapshot of / is the system without anybody's home directory in it.  What was
missing was the thing that takes them: three subvolumes and a mountpoint, and no
snapshot to roll back to."
  (let* ((script (image-snapshot-script))
         (service (image-snapshot-service))
         (directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-snapshot-spec-~a" (getpid)))))
    (list (assert-true (parses? script)
            #:name "The snapshot program is a script bash reads")
          (assert-true (contains? script "btrfs subvolume snapshot -r /")
            #:name "It takes a read-only snapshot of the root subvolume")
          (assert-true (contains? script "/.snapshots")
            #:name "And stores it in the subvolume the installer mounted for them")
          (assert-true (contains? script "btrfs subvolume delete")
            #:name "It can delete one, which is what a cleanup does")
          ;; A snapshot a day with nothing cleaning up is a disk that fills: the
          ;; cleanup keeps the newest and deletes the rest, and it refuses to work
          ;; on a directory that is not the mounted snapshots subvolume - a
          ;; snapshot written into a plain directory is inside the thing it
          ;; snapshots, and a rollback would take it with it.
          (assert-true (contains? script "cleanup")
            #:name "There is a command that cleans up")
          (assert-true (contains? script "keep=14")
            #:name "With a number of snapshots to keep")
          (assert-true (contains? script "mountpoint -q")
            #:name "And a check that the subvolume is mounted where it writes")
          (assert-true (parses? service)
            #:name "The service that runs it is a script sh reads")
          (assert-true (contains? service "heks-snapshot create")
            #:name "The service takes a snapshot")
          (assert-true (contains? service "heks-snapshot cleanup")
            #:name "And cleans the old ones up")
          (assert-true (contains? service "sleep 86400")
            #:name "Once a day, which is what the sleep says")
          ;; The medium's root is a squashfs: there is no BTRFS subvolume to
          ;; snapshot and nothing to roll back to, so a service there would log a
          ;; failure at every boot.
          (assert-true (not (eq? #f (member "heks-snapshot" image-services)))
            #:name "The installed system starts it at boot")
          (assert-true (contains? (image-config-script)
                                  "ln -sfn /etc/sv/heks-snapshot /etc/runit/runsvdir/default/")
            #:name "Enabled the way Void enables a service")
          (assert-true (eq? #f (member "heks-snapshot" (image-live-services)))
            #:name "The medium does not: it has no BTRFS root to snapshot")
          (assert-true (not (eq? #f (member "heks-snapshot" image-required-commands)))
            #:name "And the build refuses an image that does not carry it")
          (assert-true (contains? (image-config-script) "heks-snapshot")
            #:name "The configuration phase installs the program into /usr/local/bin")
          ;; Both are payload files: what the configuration phase installs, and the
          ;; service read where runit reads services.
          (assert-true (file-exists?
                        (format #f "~a/~a/~a" directory (image-payload-dir)
                                (image-snapshot-filename)))
            #:name "The payload carries the program")
          (assert-true (file-exists?
                        (format #f "~a/root/etc/sv/heks-snapshot/run" directory))
            #:name "And the service that runit reads"))))

(define (version-cases)
  "Return the cases for the version the two artefacts are named after.

The ISO and the rootfs tarball were named after a constant in
=image.scm= - =0.1.0= - while the tree was tagged v5.6.0: a file whose name said
a version this project never released, and a downloader with no way to tell
which release they had.  The version is the tag the build came from."
  (list (assert-equal #:expect "5.6.0"
          #:got (image-artefact-version "v5.6.0")
          #:name "The tag's leading v is the tag's spelling, not the version's")
        (assert-equal #:expect "5.5.8"
          #:got (image-artefact-version "5.5.8")
          #:name "A tag without one is used as it is")
        (assert-equal #:expect "5.6.0-3-gbe1de47"
          #:got (image-artefact-version "v5.6.0-3-gbe1de47")
          #:name "A build that is not on the tag says how far off it is")
        (assert-equal #:expect "5.6.0-dirty"
          #:got (image-artefact-version "v5.6.0-dirty")
          #:name "And one made from a modified tree says that too")
        (assert-equal #:expect "nightly-2026-01"
          #:got (image-artefact-version "vnightly/2026-01")
          #:name "A tag a filename cannot hold is folded, not dropped")
        (assert-equal #:expect #f
          #:got (image-artefact-version "")
          #:name "An empty answer is no version at all")
        (assert-equal #:expect #f
          #:got (image-artefact-version #f)
          #:name "And so is a git that could not answer")
        ;; The two artefacts are named by the same parameter the installer
        ;; unpacks the payload by: a medium whose tarball is named one thing and
        ;; whose wizard looks for another cannot install.
        (assert-true (contains? (image-iso-script)
                                (format #f "~a-~a-live" image-name (image-version)))
          #:name "The medium is named after the version the build is at")
        (assert-true (contains? (image-rootfs-script)
                                (format #f "~a-~a-rootfs" image-name (image-version)))
          #:name "And so is the installed system it unpacks")
        ;; An artefact handed to somebody else is only worth what can be
        ;; checked, and the check is `sha256sum -c` on a file that names the
        ;; artefact the way it is written: both are handed off with one.
        (assert-true (contains? (image-iso-script) "checksum \"$out\"")
          #:name "The medium is written with its SHA-256")
        (assert-true (contains? (image-rootfs-script) "checksum \"$out\"")
          #:name "And so is the rootfs the medium installs")
        (assert-true (contains? (image-iso-script) "$base.sha256")
          #:name "The digest names the artefact, so the check works from any directory")))

(define (template-text package)
  "Return the text of @var{package}'s Void template, or the empty string."
  (let ((path (format #f "packaging/void/~a/template" package)))
    (if (file-exists? path)
      (call-with-input-file path get-string-all)
      "")))

(define (template-field package field)
  "Return the value of @var{field} in @var{package}'s template, trimmed, or #f."
  (let* ((prefix (format #f "~a=" field))
         (line (find (lambda (line) (string-prefix? prefix line))
                     (string-split (template-text package) #\newline))))
    (and line (string-trim-both (substring line (string-length prefix))))))

(define (boot-menu-cases)
  "Return the cases for the boot menu the image ships.

The menu is on both systems and the picture is the same file in both: the payload
carries the theme and the entries, and the medium's own GRUB and ISOLINUX menus
take the same rain from void-mklive's splash.  A build that loses either is a
medium that looks like Void's and an installed machine with no rescue shell."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-grub-spec-~a" (getpid))))
         (theme (format #f "~a/root~a" directory (grub-theme-path)))
         (picture (format #f "~a/root~a" directory (grub-background-path)))
         (entries (format #f "~a/root~a" directory (grub-entries-path)))
         (splash (format #f "~a/grub-splash.png" directory)))
    (list (assert-true (file-exists? theme)
            #:name "The payload carries the boot menu's theme")
          (assert-true (file-exists? picture)
            #:name "And the picture it draws")
          (assert-true (file-exists? entries)
            #:name "And the entries grub-mkconfig does not generate")
          (assert-true (file-exists? splash)
            #:name "The medium's own splash is the same picture")
          (assert-true (contains? (image-iso-script) "SPLASH_IMAGE=")
            #:name "Which build-iso.sh hands to void-mklive")
          (assert-true (contains? (image-config-script)
                                  (format #f "check_path \"~a\"" (grub-theme-path)))
            #:name "And the build refuses an image whose menu is missing it"))))

(define (hardening-cases)
  "Return the cases for what the machine refuses and hides.

These are settings and not features: a machine that answers them wrong looks
exactly like one that answers them right until somebody is already on it.  So
they are a rendered file and a package, and the cases that matter are that the
file is there with the lines that mean something, and that the language the
wizard asked for has a locale to be."
  (let* ((directory (install-image-config
                     #:dir (format #f "/tmp/heks-image-hardening-spec-~a" (getpid))))
         (path (format #f "~a/root~a" directory (image-hardening-path))))
    (list (assert-true (file-exists? path)
            #:name "The machine carries its hardening as a rendered drop-in")
          (assert-true (contains? (image-hardening-conf) "kernel.kptr_restrict = 1")
            #:name "Kernel addresses are not readable from user space")
          (assert-true (contains? (image-hardening-conf) "kernel.dmesg_restrict = 1")
            #:name "And the kernel log is root's")
          (assert-true (contains? (image-hardening-conf) "use_tempaddr = 2")
            #:name "A laptop's IPv6 address changes with the network")
          (assert-true (contains? (image-hardening-conf) "fs.protected_symlinks = 1")
            #:name "A link in a shared directory is not a handle on a file")
          (assert-true (contains? (image-hardening-conf) "tcp_syncookies = 1")
            #:name "A SYN flood does not exhaust the queue")
          (assert-true (not (contains? (image-hardening-conf) "ptrace_scope"))
            #:name "And nothing here stops a debugger attaching to a process")
          (assert-true (not (eq? #f (member "glibc-locales" (image-packages))))
            #:name "The locales the language answer needs are in the image"))))

(define (packaging-cases)
  "Return the cases for the Void packages this repository builds.

whelk, Lambdock, heks-toon and Maak are programs of their own, and
`packaging/void/' holds the templates this repository builds with `maak
xbps-build'.  A copy is only worth keeping if it is complete: an empty checksum
is xbps-src stopping at the first package it is asked to build, and a pkgname
that is not the directory's name is a build whose output lands under a name
nobody looks for.  The archival URL is the template's own - GitHub's for the
three that live there, Codeberg's for heks-toon - so what is asked of it is an
https archive that names the version, not one particular forge's path."
  (list (assert-equal #:expect '("heks-toon" "lambdock" "maak" "whelk")
          #:got (sort (scandir "packaging/void"
                               (lambda (name)
                                 (not (member name '("." "..")))))
                      string<?)
          #:name "The shell, the dock, the keyboard window and the runner are here")
        (assert-true (every (lambda (package)
                              (and (string=? package
                                             (or (template-field package "pkgname") ""))
                                (template-field package "version")
                                (contains? (or (template-field package "distfiles") "")
                                           "archive")
                                (= 64 (string-length
                                       (or (template-field package "checksum") "")))
                                #t))
                            '("whelk" "lambdock" "heks-toon" "maak"))
          #:name "Each names its package, its archive and a filled-in checksum")
        ;; xbps-install takes a package name and looks it up in a repository;
        ;; handed the path of a .xbps file it answers `Package ... not found in
        ;; repository pool' and the build stops there, after the four hundred
        ;; and eighty-eight packages before it were installed.  So the files are
        ;; indexed into a repository of their own first - which is what
        ;; xbps-rindex is for - and installed from it by name.
        (assert-true (contains? (image-rootfs-script)
                                "xbps-rindex -a /tmp/heks-xbps/*.xbps")
          #:name "The built packages are indexed into a repository of their own")
        (assert-true (contains? (image-rootfs-script)
                                "xbps-install -R /tmp/heks-xbps -y \"$name\"")
          #:name "And installed from it by name")
        (assert-true (not (contains? (image-rootfs-script)
                                     "xbps-install -y \"$package\""))
          #:name "Never by the path of the file, which xbps cannot look up")
        ;; `maak xbps-build` writes to `dist/xbps`, which is the checkout's own
        ;; directory: the description lives in `dist/image', one level below it,
        ;; so a path taken from there looks in `dist/image/dist/xbps' - a
        ;; directory nothing writes - and the image is packed without the shell
        ;; it was told the build carries.
        (assert-true (contains? (image-rootfs-script)
                                (format #f "[ -d \"$checkout/~a\" ]" (image-xbps-dir)))
          #:name "Only when `maak xbps-build` left one to install")
        (assert-true (not (contains? (image-rootfs-script)
                                     (format #f "\"$here/~a\"" (image-xbps-dir))))
          #:name "Which is not a directory inside the description")
        (assert-true (contains? (image-rootfs-script)
                                "rm -rf \"$work/tmp/heks-xbps\"")
          #:name "And the files do not travel into the image")
        ;; A build that ran without `maak xbps-build' ships a machine with no
        ;; runner, no bar and no dock - which is what a person met after
        ;; installing from the medium: `maak' was not a command at all.  The
        ;; build cannot make the packages, but it can say so in the one place a
        ;; person reads after it finishes.
        (assert-true (contains? (image-rootfs-script)
                                "no collection packages")
          #:name "A build with none of them says so, instead of packing a bare machine")
        ;; The build is the rootfs and the medium both, so what it installs is
        ;; what the installed system keeps: a package the image carries is one
        ;; the distribution upgrades.
        (assert-true (every (lambda (name)
                              (if (member name image-rendered-commands) #t #f))
                            '("whelk" "lambdock" "heks-toon"))
          #:name "The setup check asks for the three on the account's PATH")
        (assert-true (not (contains? (image-config-script) "nix-settings.scm"))
          #:name "Nothing in the render needs a Nix override for the session")
        (assert-true (not (contains? (image-setup-script) "heks-linux-desktop-nix"))
          #:name "And the setup script does not name a Nix category either")
        (assert-true (contains? (image-setup-script) "profile remove")
          #:name "A profile that still holds the three has them taken out")))

(define (identity-cases)
  "Return the cases for the two files that say what a machine is.

@file{/etc/os-release} is the one the desktop's summary reads, and Void's
base-files ships it as a symlink into @file{/usr/lib}, which a package upgrade
rewrites - so the link goes and this tree's file takes its place.
@file{/etc/issue} is what a getty prints above the login prompt on every console
the prompt does not own."
  (let ((config (image-config-script))
        (directory (install-image-config
                    #:dir (format #f "/tmp/heks-image-identity-spec-~a" (getpid)))))
    (list (assert-true (contains? config "rm -f /etc/os-release")
            #:name "The base distribution's symlink is replaced, not written through")
          (assert-true (contains? config
                                  "install -m 644 /usr/local/lib/heks-linux/os-release /etc/os-release")
            #:name "The image installs the file that names this system")
          (assert-true (contains? config
                                  "install -m 644 /usr/local/lib/heks-linux/issue /etc/issue")
            #:name "And the banner its consoles print")
          ;; mklive copies its own /etc/issue into the rootfs before the payload,
          ;; so the payload has to carry one too or the medium's consoles print a
          ;; Void banner naming an installer this medium does not have.
          (assert-true (contains?
                        (call-with-input-file (format #f "~a/root/etc/issue" directory)
                                              get-string-all)
                        "Heks GNU/Linux")
            #:name "The payload's own banner lands last, on the medium as well")
          (assert-true (let ((text (call-with-input-file
                                    (format #f "~a/~a/etc/issue"
                                            directory (image-live-payload-dir))
                                    get-string-all)))
                         (and (contains? text "heks-install")
                           (not (contains? text "void-installer"))))
            #:name "And the medium's consoles say what to run, not void-installer")
          (assert-true (contains? config
                                  "check_path \"/etc/os-release\" \"what the system says it is\"")
            #:name "The readiness check asks for it")
          (assert-true (contains? config
                                  "check_path \"/etc/issue\" \"the banner a getty prints\"")
            #:name "And for the banner, so an image without them fails the build"))))

(define (boot-cases)
  "Return the cases for the boot screen.

The splash is four payload files - a theme, its script, the daemon's settings and
the service that ends it - plus the two packages that read them.  The service is
the half that has no counterpart on the distribution: plymouthd is started by the
initramfs and a runit machine has no unit to quit it."
  (let ((config (image-config-script))
        (directory (install-image-config
                    #:dir (format #f "/tmp/heks-image-boot-spec-~a" (getpid)))))
    (list (for-each (lambda (package)
                      (assert-true (packaged? package)
                        #:name (string-append package " is on the image")))
                    plymouth-packages)
          (assert-true (contains? config
                                  "ln -sfn /etc/sv/plymouth-quit /etc/runit/runsvdir/default/")
            #:name "The service that ends the splash is enabled at boot")
          (assert-true (file-exists?
                        (format #f "~a/root/usr/share/plymouth/themes/~a/~a.script"
                                directory plymouth-theme-name plymouth-theme-name))
            #:name "The theme's script is in the payload")
          (assert-true (file-exists? (format #f "~a/root/etc/plymouth/plymouthd.conf" directory))
            #:name "And the daemon's settings say to use it")
          (assert-true (file-exists? (format #f "~a/root/etc/sv/plymouth-quit/run" directory))
            #:name "And the service is a run script")
          (assert-true (contains? config "check_path \"/etc/plymouth/plymouthd.conf\"")
            #:name "The readiness check asks for the boot screen"))))

(define (login-console-cases)
  "Return the cases for the console an installed machine logs in on, and for
how many eloginds run there.

Two things went wrong on the machines built from earlier trees, and both are
about a second program that nobody asked for.

Void's getty on tty1 is parked with a @file{down} file rather than left
unlinked.  The installer ends with @command{xbps-reconfigure -fa}, which re-runs
runit-void's post-install, and that re-links every getty whose @file{down} file
is absent - so a payload that only deleted the link had its getty back by the
end of the install, drawing a login prompt over greetd's box on the same
console, in the same colours, one keystroke apart.

elogind has a second starter of its own: the package ships a D-Bus activation
file, so a client that asks for @code{org.freedesktop.login1} before the
supervised daemon owns the name gets a second elogind - one Void's wrapper never
mounted a cgroup for, so the session it should register cannot start, which is
a login that fails.  The runit service then finds the pid file taken, exits with
@code{already running as PID}, and runsv starts it again as fast as it can fork.
Stage 1 removes the file, which is the one place a package upgrade cannot put it
back."
  (let ((directory (install-image-config
                    #:dir (format #f "/tmp/heks-image-login-spec-~a" (getpid))))
        (config (image-config-script)))
    (list (assert-true (file-exists?
                        (format #f "~a/root/etc/sv/agetty-tty1/down" directory))
            #:name "The getty on greetd's console is parked, and stays parked across a reconfigure")
          (assert-true (not (file-exists?
                             (format #f "~a/root/etc/sv/agetty-tty1/run" directory)))
            #:name "And the payload writes nothing over the script every console shares")
          (assert-true (not (file-exists?
                             (format #f "~a/root/etc/sv/agetty-tty2/down" directory)))
            #:name "And the consoles that keep a getty keep it")
          (assert-true (let ((file (format #f "~a/root/etc/runit/core-services/~a"
                                           directory (image-elogind-core-service-filename))))
                         (and (file-exists? file)
                           (contains? (call-with-input-file file get-string-all)
                                      "org.freedesktop.login1.service")))
            #:name "Stage 1 takes elogind's D-Bus activation away, so one elogind runs")
          (assert-true (contains? config "ln -sfn /etc/sv/elogind /etc/runit/runsvdir/default/")
            #:name "And the supervised elogind is how the machine starts it"))))

;;; The setup script's two renderings.  The Void image is the path, and its
;;; `heks-setup' is rendered for the target's init system; Debian gets the same
;;; script with the systemd half, which the Debian medium carries.  The suite
;;; pins runit for the rest of the cases, so what they assert is a fact about the
;;; target rather than about the host the suite runs on.
(define (systemd-setup-cases)
  "Return the cases for a setup script rendered for a systemd machine."
  (let ((script (parameterize ((init-system 'systemd))
                  (image-setup-script))))
    (list (assert-true (contains? script "systemctl enable \"$service\"")
            #:name "A systemd machine enables the two units it already has")
          (assert-true (not (contains? script "/etc/sv/guix-daemon"))
            #:name "And nothing writes a runit service it will never read")
          (assert-true (contains? script "[ ! -d /run/systemd/system ]")
            #:name "A chroot with no systemd running is told apart by its /run")
          (assert-true (contains? script
                                  "systemctl is-enabled \"$1\" >/dev/null 2>&1")
            #:name "And the readiness check asks systemd whether it starts")
          ;; Nix is the development tooling, not a requirement: a machine that
          ;; never installed it still gets a rendered desktop, so the script asks
          ;; whether it is there instead of dying when it is not.
          (assert-true (contains? script "nix_available=1")
            #:name "A machine without Nix is asked about, not refused")
          (assert-true (contains? script "nix is not installed")
            #:name "And one sentence says what that means"))))

;;; The machine a script runs on is not the machine that renders it.  The build
;;; runs on whatever a developer has - usually systemd - and describes Void,
;;; whose init system is runit.  `init-system' answers with the host's own init
;;; system, so these cases render the Void image as if the host ran systemd: what
;;; comes out must still be runit, because a config.sh full of `systemctl enable'
;;; stops at its first service with `systemctl: command not found', and the
;;; services it was meant to enable are never enabled at all.
(define (host-init-cases)
  "Return the cases for the Void image rendered on a systemd host."
  (parameterize ((init-system 'systemd))
    (let* ((directory (install-image-config
                       #:dir (format #f "/tmp/heks-image-host-init-spec-~a" (getpid))))
           (config (image-config-script))
           (setup (format #f "~a/root/usr/local/lib/heks-linux/~a"
                          directory (image-setup-filename))))
      (list (assert-true (contains? config
                                    "ln -sfn /etc/sv/greetd /etc/runit/runsvdir/default/")
              #:name "A host running systemd still renders the Void image's services the runit way")
            (assert-true (not (contains? config "systemctl"))
              #:name "And nothing in its configuration phase calls systemctl")
            (assert-true (contains? (call-with-input-file setup get-string-all)
                                    "ln -sfn \"/etc/sv/$service\" /etc/runit/runsvdir/default/")
              #:name "Nor does the setup the medium carries, which runs on the same machine")
            (assert-true (not (contains? (call-with-input-file setup get-string-all)
                                         "systemctl"))
              #:name "Which has no systemd on it either")))))

(define image-suite
  (suite "Void Image Suite"
    (test "The Package List Is A Session" (package-cases))
    (test "The Greeter Is The Terminal Prompt" (greeter-cases))
    (test "The System Says What It Is" (identity-cases))
    (test "The Boot Screen Is Heks" (boot-cases))
    (test "One Login Runs On The Console" (login-console-cases))
    (test "It Is Built By void-mklive" (void-cases))
    (test "Services Are Enabled The Way Void Enables Them" (service-cases))
    (test "A systemd machine gets its own setup script" (systemd-setup-cases))
    (test "The Image Is Rendered For Its Own Init System" (host-init-cases))
    (test "The Account Can Administer The Machine" (admin-cases))
    (test "The First Login Has A Home" (first-home-cases))
    (test "The Machine Has A Log To Write To" (logging-cases))
    (test "The Prompt Offers Every Session" (session-list-cases))
    (test "The Desktop Is Rendered As Its Owner" (session-cases))
    (test "Both Stores Are Installed And Started" (store-cases))
    (test "The Build Checks Itself" (finish-cases))
    (test "The Medium Installs Itself" (installer-cases))
    (test "The Medium Boots Into The Installer" (live-cases))
    (test "One Service Owns The Console" (medium-console-cases))
    (test "It Builds From A Host That Is Not Void" (foreign-host-cases))
    (test "The Build Keeps Its Mounts To Itself" (isolation-cases))
    (test "Nothing From The Old Image Survives" (leftover-cases))
    (test "It Is Rendered Before It Ships" (render-cases))
    (test "The Installed System Snapshots Itself" (snapshot-cases))
    (test "The Machine Is Not A Soft Target" (hardening-cases))
    (test "The Boot Menu Is The Palette, On Both Systems" (boot-menu-cases))
    (test "The Artefacts Are Named After The Tag" (version-cases))
    (test "It Builds The Collection's Void Packages" (packaging-cases))
    (test "The Target Is glibc, For Now" (musl-cases))))

(define (spec)
  (parameterize ((init-system 'runit))
    (veritas-run image-suite)))
