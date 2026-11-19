;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux installer).
;;
;; The installer is two things at once: a plan - which partitions, which
;; filesystems, which lines fstab and the kernel command line get - and one
;; shell script that carries the plan out.  The plan is checked as data here.
;; The script is checked as text, for the things a reader of it has to be able
;; to trust: that it cannot erase the medium it is running from, that the
;; passphrase never lands on a command line, that UEFI is the path it takes
;; first, and that it parses with the shell that will run it.
;;
;; IMPORTANT contributor note:
;;
;; `assert-true' and friends are *pure constructors*: they return a closure the
;; veritas runner later applies to a context.  When such a call sits in a
;; non-final position of a body (inside a `let', say), Guile's optimizer deletes
;; the call and the assertion silently never runs.  Always pass assertions as
;; direct arguments to `test', as this file does.

;;; Code:

(define-module (veritas unit installer-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux installer)
  #:use-module (heks-linux image)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? haystack needle)
  "Return @code{#t} when @var{needle} occurs in the string @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

(define (script)
  "Return the rendered @file{heks-install}."
  (installer-script))

(define (partition-of mode kind)
  "Return @var{mode}'s partition whose @code{kind} is @var{kind}, or @code{#f}."
  (find (lambda (partition)
          (eq? (assq-ref partition 'kind) kind))
        (installer-partitions mode)))

(define (field partition key)
  "Return @var{key}'s value in @var{partition}."
  (assq-ref partition key))

(define (line-with text needle)
  "Return the first line of @var{text} that contains @var{needle}, or #f."
  (find (lambda (line) (contains? line needle))
        (string-split text #\newline)))

(define (uefi-uuids)
  "Return the identifiers a UEFI install collects, as the script's alist."
  '((esp . "1111-2222") (boot . "aaaa-boot") (luks . "bbbb-luks")
    (root . "cccc-root")))

(define (mbr-uuids)
  "Return the identifiers an MBR install collects."
  '((boot . "aaaa-boot") (luks . "bbbb-luks") (root . "cccc-root")))

(define (boot-suite)
  (suite "The boot mode: UEFI first, MBR second"
    (test "UEFI Is The Mode The Installer Offers First"
      ;; The desktop meets modern firmware, so the default is the one that
      ;; needs an EFI System Partition, a GPT label and GRUB's EFI target.
      (assert-equal #:expect '(uefi mbr)
        #:got (installer-boot-modes)
        #:name "UEFI is offered before MBR")
      (assert-equal #:expect 'uefi
        #:got (installer-boot-mode)
        #:name "UEFI is the mode the render starts from")
      (assert-true (installer-efi? 'uefi)
        #:name "UEFI is the EFI mode")
      (assert-true (not (installer-efi? 'mbr))
        #:name "MBR is not"))

    (test "A UEFI Disk Gets An EFI System Partition And A Boot Partition"
      (let ((esp (partition-of 'uefi 'efi))
            (boot (partition-of 'uefi 'boot))
            (root (partition-of 'uefi 'root)))
        (assert-equal #:expect "/boot/efi"
          #:got (field esp 'mount)
          #:name "The ESP is mounted where the kernel and GRUB expect it")
        (assert-equal #:expect "vfat"
          #:got (field esp 'filesystem)
          #:name "The ESP is FAT")
        (assert-equal #:expect "/boot"
          #:got (field boot 'mount)
          #:name "The kernel and initramfs live on their own partition")
        (assert-equal #:expect "ext4"
          #:got (field boot 'filesystem)
          #:name "The boot partition is ext4")
        (assert-equal #:expect 3
          #:got (field root 'number)
          #:name "Root is the last partition, with the rest of the disk")
        (assert-equal #:expect "rest"
          #:got (field root 'size)
          #:name "Root takes what is left")))

    (test "An MBR Disk Boots Itself From Its First Partition"
      (let ((boot (partition-of 'mbr 'boot))
            (root (partition-of 'mbr 'root)))
        (assert-equal #:expect #f
          #:got (partition-of 'mbr 'efi)
          #:name "An MBR layout has no EFI System Partition")
        (assert-equal #:expect 1
          #:got (field boot 'number)
          #:name "The boot partition is the first one")
        (assert-true (field boot 'bootable?)
          #:name "The firmware is told which partition to boot")
        (assert-equal #:expect 2
          #:got (field root 'number)
          #:name "Root follows it")))

    (test "Every Mode Encrypts The Root Filesystem And Puts BTRFS In It"
      (let ((uefi (partition-of 'uefi 'root))
            (mbr (partition-of 'mbr 'root)))
        (assert-equal #:expect 'luks
          #:got (field uefi 'encryption)
          #:name "The root partition is a LUKS container")
        (assert-equal #:expect 'btrfs
          #:got (field uefi 'filesystem)
          #:name "BTRFS is the filesystem inside it")
        (assert-equal #:expect 'btrfs
          #:got (field mbr 'filesystem)
          #:name "The MBR layout is the same encrypted BTRFS system")))

    (test "The Subvolumes Keep The Homes Out Of The Root Snapshot"
      (assert-equal #:expect '(("@" "/") ("@home" "/home") ("@snapshots" "/.snapshots"))
        #:got (installer-subvolumes)
        #:name "Root, home and snapshots are the three subvolumes"))))

(define (mount-suite)
  (suite "The files the installed system boots with"
    (test "fstab Mounts The Encrypted Subvolumes With Their Options"
      (let ((text (installer-fstab 'uefi (uefi-uuids))))
        (assert-true (contains? text
                                "UUID=cccc-root  /  btrfs  compress=zstd,noatime,subvol=@  0 0")
          #:name "Root mounts the @ subvolume of the BTRFS UUID")
        (assert-true (contains? text "subvol=@home")
          #:name "Home mounts its own subvolume")
        (assert-true (contains? text "nodev,nosuid,subvol=@home")
          #:name "Home keeps device nodes and setuid binaries out")
        (assert-true (contains? text "subvol=@snapshots")
          #:name "The snapshots have a mountpoint of their own")
        (assert-true (contains? text "UUID=aaaa-boot  /boot  ext4")
          #:name "The boot partition is mounted by UUID")
        (assert-true (contains? text "UUID=1111-2222  /boot/efi  vfat")
          #:name "The ESP is mounted by its FAT UUID")
        (assert-true (contains? text "umask=0077")
          #:name "The ESP is readable by root alone")))

    (test "An MBR fstab Has No ESP Line"
      (let ((text (installer-fstab 'mbr (mbr-uuids))))
        (assert-true (not (contains? text "/boot/efi"))
          #:name "There is no EFI System Partition to mount")
        (assert-true (contains? text "UUID=aaaa-boot  /boot  ext4")
          #:name "The boot partition is still mounted")))

    (test "The Kernel Opens The Volume By UUID And Mounts The Subvolume"
      ;; GRUB never opens the encrypted volume in this layout - it cannot
      ;; derive an Argon2 key - so initramfs opens it, and the kernel command
      ;; line is what tells it which volume and which subvolume.
      (let ((cmdline (installer-grub-cmdline #:luks "bbbb-luks" #:root "cccc-root")))
        (assert-true (contains? cmdline "rd.luks.uuid=bbbb-luks")
          #:name "The initramfs is told which LUKS container to open")
        (assert-true (contains? cmdline "root=UUID=cccc-root")
          #:name "The kernel is told which BTRFS filesystem is root")
        (assert-true (contains? cmdline "rootflags=subvol=@")
          #:name "Root is the @ subvolume, not the top level")))

    (test "The Initramfs Carries The Crypt Module And The BTRFS Driver"
      (let ((text (installer-dracut-conf)))
        (assert-true (contains? text "add_dracutmodules+=\" crypt \"")
          #:name "dm-crypt is in the initramfs")
        (assert-true (contains? text "filesystems+=\" btrfs \"")
          #:name "BTRFS is in the initramfs")))

    (test "GRUB Is Installed For The Firmware The Disk Boots From"
      (assert-equal #:expect
        '("grub-install" "--target=x86_64-efi" "--efi-directory=/boot/efi"
          "--bootloader-id=heks")
        #:got (installer-grub-install-command 'uefi "/dev/vda")
        #:name "UEFI installs GRUB's EFI target into the ESP")
      (assert-equal #:expect
        '("grub-install" "--target=i386-pc" "/dev/vda")
        #:got (installer-grub-install-command 'mbr "/dev/vda")
        #:name "MBR writes the boot code into the disk's own MBR"))))

(define (safety-suite)
  (suite "What the wizard must not do to a disk"
    (test "The Medium It Runs From Is Never A Target"
      ;; The live system holds its root on the very disk the user is asked to
      ;; choose, so a mistaken answer would erase the medium mid-install.
      (assert-true (contains? (script) "is_target_disk")
        #:name "The script asks whether a disk is the running system's")
      (assert-true (contains? (script) "refuse the disk this medium runs from")
        #:name "It says why it refused"))

    (test "A Disk Is Only Written To After It Is Typed Out"
      ;; One menu entry is one keystroke away from the wrong disk; the name is
      ;; the one answer that cannot be given by accident.
      (assert-true (contains? (script) "type_confirm")
        #:name "The script has a typed confirmation")
      (assert-true (contains? (script) "ERASE")
        #:name "The confirmation box says what it will do"))

    (test "The Passphrase Never Appears On A Command Line"
      ;; `ps' is world-readable: a passphrase in argv is a passphrase on the
      ;; record.  cryptsetup reads the key from a file only its owner can read,
      ;; and the file is made unrecoverable as soon as the volume is formatted.
      (assert-true (contains? (script) "--key-file")
        #:name "cryptsetup reads the key from a file")
      (assert-true (contains? (script) "umask 077")
        #:name "The key file is private from the moment it exists")
      (assert-true (contains? (script) "shred -u")
        #:name "The key file is shredded, not just removed")
      (assert-true (not (contains? (script) "--key-file \"$passphrase\""))
        #:name "The passphrase is not passed as a key directly")
      (assert-true (contains? (script) "passphrase=\"\"")
        #:name "The variable is emptied after it was written out"))

    (test "The Wizard Asks For What It Cannot Guess"
      ;; Everything else has a default; these four do not.
      (assert-true (contains? (script) "Passphrase")
        #:name "It asks for the disk passphrase")
      (assert-true (contains? (script) "Hostname")
        #:name "It asks for the machine's name")
      (assert-true (contains? (script) "userpass")
        #:name "It asks for the user's password")
      (assert-true (contains? (script) "user_name")
        #:name "It asks for the user's name"))

    (test "A Disk Too Small To Hold The System Is Refused"
      ;; The encrypted layout needs room for the system before there is room for
      ;; anything of the person's.  Finding that out two minutes into the copy
      ;; costs the installer and the disk; asking again costs one screen.
      (assert-true (contains? (script) "at least 8 GiB")
        #:name "The smallest disk that can hold the layout is named")
      (assert-true (contains? (script) "Choose another one")
        #:name "And the question is asked again, not answered for them"))

    (test "The Passphrase Cost Follows The Machine's Memory"
      ;; Argon2id locking a gibibyte is right on a workstation and is a machine
      ;; that cannot boot when its initramfs must allocate that much on a laptop
      ;; with two.
      (assert-true (contains? (script) "MemTotal")
        #:name "The machine's memory is read, not assumed")
      (assert-true (contains? (script) "pbkdf_memory=524288")
        #:name "A machine with less memory gets a cheaper KDF"))

    (test "The Passphrase Screen Warns About The Boot Keyboard"
      ;; The initramfs asks for the passphrase with the kernel's own keymap, so a
      ;; passphrase typed on a French layout here is a passphrase nobody can type
      ;; at boot.
      (assert-true (contains? (script) "US keyboard")
        #:name "The screen says which layout the boot prompt uses"))

    (test "The Medium Offers A Menu Before It Erases Anything"
      (assert-true (contains? (script) "menu")
        #:name "The wizard is a menu, not a list of questions")
      (assert-true (contains? (script) "command -v dialog")
        #:name "It uses dialog when the medium carries it")
      (assert-true (contains? (script) "Guided install")
        #:name "The first entry is the guided install"))))

(define (finish-suite)
  (suite "Finishing the install"
    (test "UEFI Mounts The ESP And MBR Does Not"
      (let ((uefi (string-join (installer-mount-commands 'uefi) "\n"))
            (mbr (string-join (installer-mount-commands 'mbr) "\n")))
        (assert-true (contains? uefi "mount \"$esp_part\" \"$target/boot/efi\"")
          #:name "The UEFI branch mounts an EFI System Partition")
        (assert-true (not (contains? mbr "/boot/efi"))
          #:name "The MBR branch never mentions one")
        (assert-true (contains? mbr "mount \"$boot_part\" \"$target/boot\"")
          #:name "Both branches mount the boot partition")
        (assert-true (contains? uefi "mkfs.vfat -F32 -n EFI")
          #:name "Only the UEFI branch formats a FAT partition")
        (assert-true (contains? (script) "case \"$mode\" in")
          #:name "The script chooses the layout by mode, not by guessing")))

    (test "The Layout Is Ordered So Each Step Reads The One Before It"
      ;; A dry-reader can check the order; a disk cannot survive getting it
      ;; wrong - a filesystem created before the table exists lands nowhere, and
      ;; a key shredded before cryptsetup read it is a volume nobody can open.
      (let* ((steps (installer-mount-commands 'uefi))
             (position (lambda (needle)
                         (list-index (lambda (step) (contains? step needle))
                                     steps))))
        (assert-true (< (position "wipefs")
                        (position "parted -s \"$disk\" mklabel"))
          #:name "The disk is wiped before the table is written")
        (assert-true (< (position "mklabel")
                        (position "partprobe"))
          #:name "The kernel is told about the table before it is used")
        (assert-true (< (position "luksFormat")
                        (position "cryptsetup open"))
          #:name "The container is formatted before it is opened")
        (assert-true (< (position "cryptsetup open")
                        (position "mkfs.btrfs"))
          #:name "BTRFS is made inside the open container")
        (assert-true (< (position "shred -u")
                        (position "mkfs.btrfs"))
          #:name "The key is shredded once the container has been opened")
        (assert-true (< (position "subvolume create")
                        (position "subvol=@home"))
          #:name "The subvolumes exist before they are mounted")))

    (test "The Kernel Is Regenerated For The New Disk"
      ;; xbps-reconfigure is what runs dracut again, and a rootfs unpacked
      ;; from the medium carries an initramfs built for someone else's disk.
      (assert-true (contains? (script) "grub-mkconfig -o /boot/grub/grub.cfg")
        #:name "GRUB's configuration is generated inside the target")
      (assert-true (contains? (script) "xbps-reconfigure -fa")
        #:name "Every package is reconfigured, which rebuilds the initramfs"))

    (test "The Installed User Owns The Home The Medium Rendered"
      ;; The rootfs is rendered into one account's home at build time; the
      ;; wizard renames that account rather than starting an empty one.
      (assert-true (contains? (script) "usermod -l")
        #:name "The placeholder account is renamed, not replaced")
      (assert-true (contains? (script) "chpasswd")
        #:name "Its password is the one the wizard asked for"))))

(define (extra-of key)
  "Return the post-install extra called @var{key}, or @code{#f}."
  (find (lambda (extra)
          (eq? (assq-ref extra 'key) key))
        (installer-extras)))

(define (extra-field key field)
  "Return @var{field} of the post-install extra called @var{key}."
  (assq-ref (extra-of key) field))

(define (extras-suite)
  (suite "What the medium offers once the disk is written"
    (test "The Extras Are Offered In The Order That Makes Sense"
      ;; Cloning first: the two builds below read the checkouts.
      (assert-equal #:expect '(checkouts packages emacs)
        #:got (map (lambda (extra)
                     (assq-ref extra 'key))
                   (installer-extras))
        #:name "Checkouts, then the package sets, then Emacs"))

    (test "Only The Cheap And Useful Extras Are On By Default"
      ;; A wizard that starts a one-hour build unless told otherwise is not a
      ;; friendly wizard.
      (assert-true (extra-field 'checkouts 'default?)
        #:name "Cloning the rest of the projects is offered on")
      (assert-true (not (extra-field 'packages 'default?))
        #:name "The workstation package sets are off by default")
      (assert-true (not (extra-field 'emacs 'default?))
        #:name "Building Emacs from master is off by default"))

    (test "The Checkouts Are The Projects The Desktop Is Made Of"
      ;; The medium already carries the three heks projects; the two the shell
      ;; and the dock come from are cloned here, from the page each lives on.
      (let ((projects (map car (installer-project-sources)))
            (script (script)))
        (assert-true (not (eq? #f (member "lambdock" projects)))
          #:name "The dock's project is on the list")
        (assert-true (not (eq? #f (member "whelk" projects)))
          #:name "The shell's project is on the list")
        (assert-true (contains? script
                                "clone_or_update lambdock https://github.com/jjba23/lambdock.git")
          #:name "The dock is cloned from its own page")
        (assert-true (contains? script "clone_or_update whelk")
          #:name "The shell is cloned the same way")
        (assert-true (contains? script "Hacking/$1")
          #:name "Into the home the desktop expects")))

    (test "The Package Extra Installs The Sets The Image Leaves Out"
      ;; The image carries the session and the command line; the workstation
      ;; half - the compilers, the graphics and music sets - is here.
      (assert-true (contains? (extra-field 'packages 'command)
                              "maak install-xbps")
        #:name "It runs the tree's own package task"))

    (test "The Emacs Extra Builds This Tree's Emacs, Not Another One"
      ;; `maak emacs-update' in heks-emacs is the configure line and the build
      ;; the editor's own documentation describes: master, PGTK, native
      ;; compilation.  The installer runs that task rather than a second build.
      (let ((command (extra-field 'emacs 'command)))
        (assert-true (contains? command "maak emacs-update")
          #:name "It runs the editor's own build task")
        (assert-true (contains? command "emacs-mirror")
          #:name "It clones Emacs master when the checkout is missing")))

    (test "The Extras Are A Checklist, Not Another Question Each"
      (assert-true (contains? (script) "--checklist")
        #:name "One screen toggles all of them")
      (assert-true (contains? (script) "has_extra")
        #:name "The script asks which were chosen")
      (assert-true (contains? (script) "What else should the new system be")
        #:name "And asks in a sentence a person can answer"))

    (test "A Renamed Account Gets Its Desktop Rendered Again"
      ;; The rendered files name the account that built the image: a renamed
      ;; home carries a bar whose menus point at a home that is not there.
      (let ((script (script)))
        (assert-true (contains? script "heks-render")
          #:name "The renderer the medium carried is what runs")
        (assert-true (contains? script "render the desktop for")
          #:name "The phase says what it is doing, and for whom")
        (assert-true (contains? script "\"$user_name\"")
          #:name "It renders for the account that was created, not the image's")))

    (test "Every Screen Says Which Installer It Is"
      (assert-true (contains? (script) "--backtitle")
        #:name "The wizard is titled on every screen")
      (assert-true (contains? (script) "Heks GNU/Linux")
        #:name "And names the thing being installed"))))

(define (spec)
  (veritas-run (boot-suite) (mount-suite) (safety-suite) (finish-suite)
    (extras-suite)))
