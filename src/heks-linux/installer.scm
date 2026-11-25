;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The installer: one plan, and one wizard that carries it out.
;;
;; The plan is data - which partitions, which filesystems, which lines fstab,
;; the kernel command line and the initramfs get - and it exists twice over,
;; because a boot mode is a different disk layout.  *UEFI comes first*: it is
;; the firmware a modern machine has, it is the mode the wizard starts on, and
;; it is the one that needs an EFI System Partition, a GPT label and GRUB's EFI
;; target.  MBR is the second entry, for a machine whose firmware has no EFI at
;; all: no ESP, a DOS label, the boot flag on the first partition and GRUB's
;; i386-pc target written into the disk's own MBR.
;;
;; Both modes build the same system: a LUKS2 container holding BTRFS, with the
;; root, the homes and the snapshots as three subvolumes, and the kernel and
;; initramfs on a partition of their own outside the encryption.  `/boot` stays
;; out of the container because Void's GRUB cannot derive an Argon2 key and so
;; cannot read a kernel from inside it; the initramfs, which can, asks for the
;; passphrase once.
;;
;; The wizard asks for what it cannot guess - the disk, the passphrase, the
;; machine's name and the user's - and defaults everything else.  It accepts no
;; answer that could be a typo of another disk: the target is typed out, the
;; medium the live system runs from is refused, and the passphrase travels in a
;; file only its owner can read and is shredded as soon as the volume exists,
;; so it is never on a command line and never in `ps'.

;;; Code:

(define-module (heks-linux installer)
  #:declarative? #t
  #:use-module (heks-linux image)
  #:use-module (heks-linux boot)
  #:use-module (heks-linux platform)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (installer-boot-modes
            installer-boot-mode
            installer-efi?
            installer-boot-mode-label
            installer-esp-size
            installer-boot-size
            installer-pbkdf-memory
            installer-bootloader-id
            installer-target
            installer-log
            installer-lock
            installer-script-filename
            installer-payload-dir
            installer-partitions
            installer-subvolumes
            installer-fstab
            installer-grub-cmdline
            installer-dracut-conf
            installer-grub-install-command
            installer-mount-commands
            installer-projects-base
            installer-project-sources
            installer-extras
            installer-extras-checklist
            installer-extras-dispatch
            installer-script
            install-installer-config))

;; ===========================================
;; The boot modes
;; ===========================================

;; UEFI first: it is what the machine the desktop is meant for has, and it is
;; the mode the wizard preselects.  MBR is the fallback for firmware without
;; EFI, and it is offered second rather than not at all.
(define (installer-boot-modes)
  "Return the boot modes the wizard offers, in the order it offers them."
  '(uefi mbr))

(define installer-boot-mode
  (make-parameter 'uefi))

(define (installer-efi? mode)
  "Return @code{#t} when @var{mode} boots from EFI firmware."
  (eq? mode 'uefi))

(define (installer-boot-mode-label mode)
  "Return the line the menu shows for @var{mode}."
  (case mode
    [(uefi) "UEFI (recommended)"]
    [(mbr) "Legacy MBR (no EFI firmware)"]
    [else (symbol->string mode)]))

;; The two partitions outside the encrypted volume, in MiB.  A gigabyte of ESP
;; holds several kernels and an EFI shell with room to spare; a gigabyte of
;; /boot holds the kernels and initramfs of a machine that never prunes them.
(define installer-esp-size
  (make-parameter 1024))

(define installer-boot-size
  (make-parameter 1024))

;; Argon2id's cost, in KiB.  1 GiB is the price of a passphrase guess, and only
;; the initramfs runs this KDF in this layout, so GRUB's early-boot heap is not
;; the limit.  Lower it on a machine with less memory.
(define installer-pbkdf-memory
  (make-parameter 1048576))

(define installer-bootloader-id
  (make-parameter "heks"))

;; Where the payload is unpacked.  It is a parameter because the spec renders
;; the plan without a disk to mount.
(define installer-target
  (make-parameter "/mnt"))

(define installer-log
  (make-parameter "/var/log/heks-install.log"))

;; One wizard at a time.  The lock is taken before a disk is read, because two
;; wizards on one machine is a partition table written under the other's feet.
(define installer-lock
  (make-parameter "/run/heks-install.lock"))

;; Where the medium carries the installed system heks-install unpacks.
(define installer-payload-dir
  (make-parameter "/usr/local/lib/heks-linux"))

(define installer-script-filename
  (make-parameter "heks-install"))

;; ===========================================
;; The plan, as data
;; ===========================================

(define (installer-partitions mode)
  "Return @var{mode}'s partitions, in the order they sit on the disk.

Each partition is an alist: its @code{number}, its @code{kind} (one of
@code{efi}, @code{boot} and @code{root}), the @code{size} in MiB (@code{rest}
for the last one), its @code{filesystem}, the @code{label} it is formatted with
and the @code{mount} it lands on.  The root partition carries its
@code{encryption}, because that is the one thing both modes must agree on."
  (case mode
    [(uefi)
     (list (list (cons 'number 1)
                 (cons 'kind 'efi)
                 (cons 'size (installer-esp-size))
                 (cons 'filesystem "vfat")
                 (cons 'label "EFI")
                 (cons 'mount "/boot/efi")
                 (cons 'parted-type "fat32")
                 (cons 'firmware-flag "esp"))
           (list (cons 'number 2)
                 (cons 'kind 'boot)
                 (cons 'size (installer-boot-size))
                 (cons 'filesystem "ext4")
                 (cons 'label "boot")
                 (cons 'mount "/boot")
                 (cons 'parted-type "ext4"))
           (list (cons 'number 3)
                 (cons 'kind 'root)
                 (cons 'size "rest")
                 (cons 'encryption 'luks)
                 (cons 'filesystem 'btrfs)
                 (cons 'label "heks")
                 (cons 'mount "/")))]
    [(mbr)
     (list (list (cons 'number 1)
                 (cons 'kind 'boot)
                 (cons 'size (installer-boot-size))
                 (cons 'filesystem "ext4")
                 (cons 'label "boot")
                 (cons 'mount "/boot")
                 (cons 'parted-type "ext4")
                 ;; Without an EFI System Partition there is nothing to boot
                 ;; from but the disk itself, so the firmware is told which
                 ;; partition holds the boot code.
                 (cons 'bootable? #t)
                 (cons 'firmware-flag "boot"))
           (list (cons 'number 2)
                 (cons 'kind 'root)
                 (cons 'size "rest")
                 (cons 'encryption 'luks)
                 (cons 'filesystem 'btrfs)
                 (cons 'label "heks")
                 (cons 'mount "/")))]
    [else (error "unknown boot mode:" mode)]))

(define (installer-subvolumes)
  "Return the BTRFS subvolumes inside the encrypted volume, as name/mount pairs.

Three subvolumes, not one: a snapshot of @code{@@} then holds the system without
every home directory, and @code{/.snapshots} is a place to put them that is not
inside the subvolume being snapshotted."
  '(("@" "/")
    ("@home" "/home")
    ("@snapshots" "/.snapshots")))

;; ===========================================
;; The files the installed system boots with
;; ===========================================

(define (installer-subvolume-options mount)
  "Return the mount options the subvolume mounted at @var{mount} gets.

@code{compress=zstd,noatime} is the point of the filesystem; the hardening is
per mountpoint.  A home directory holds no device nodes and no setuid programs,
and a snapshots directory holds neither and no executables either - the same
reasoning as the fstab the guide used to spell by hand."
  (cond
    [(string=? mount "/") "compress=zstd,noatime"]
    [(string=? mount "/.snapshots")
     "compress=zstd,noatime,nodev,nosuid,noexec"]
    [else "compress=zstd,noatime,nodev,nosuid"]))

(define (installer-esp-fstab-line esp)
  "Return the fstab line that mounts @var{esp} at @file{/boot/efi}.

@code{umask=0077} is the option FAT needs: the ESP is a filesystem any user can
read, and the kernel and its command line are not something to hand out."
  (format #f "UUID=~a  /boot/efi  vfat  umask=0077,nodev,nosuid,noexec  0 2\n"
          esp))

(define (installer-fstab mode uuids)
  "Return @file{/etc/fstab} for @var{mode}, with @var{uuids} filled in.

@var{uuids} is an alist of the identifiers the install collected:
@code{root} for the BTRFS filesystem inside the volume, @code{boot} for the
boot partition and, on UEFI, @code{esp}.  They are strings, so the script can
pass the shell variables it read from @code{blkid} instead.

The subvolume rows come from @code{installer-subvolumes}, so the file mounts
exactly what the installer created."
  (let ((root (assq-ref uuids 'root))
        (boot (assq-ref uuids 'boot))
        (esp (assq-ref uuids 'esp)))
    (string-append
     "# /etc/fstab -- written by heks-install\n"
     (string-join
      (map (lambda (subvolume)
             (format #f "UUID=~a  ~a  btrfs  ~a,subvol=~a  0 0\n"
                     root (second subvolume)
                     (installer-subvolume-options (second subvolume))
                     (first subvolume)))
           (installer-subvolumes))
      "")
     (format #f "UUID=~a  /boot  ext4  defaults,nodev,nosuid,noexec  0 2\n"
             boot)
     (if (installer-efi? mode)
       (installer-esp-fstab-line esp)
       ""))))

(define* (installer-grub-cmdline #:key luks root)
  "Return the value GRUB writes for @code{GRUB_CMDLINE_LINUX_DEFAULT}.

The initramfs is what opens the volume - GRUB never does in this layout - so
the line names the LUKS container by UUID and the BTRFS filesystem to mount as
root, with the subvolume it lives on.

The last word is about the screen the question is asked on: plymouth's splash is
off, so dracut asks for the passphrase on the console, where a machine its
graphics cannot draw on still asks it.  @code{splash} in this value instead is
what a machine does to get the theme (see @code{(heks-linux boot)})."
  (format #f
          "rd.luks.uuid=~a root=UUID=~a rootflags=subvol=@,compress=zstd,noatime rw ~a"
          luks root plymouth-kernel-argument))

(define (installer-dracut-conf)
  "Return @file{/etc/dracut.conf.d/10-crypt.conf}.

Both modules are named because neither is visible from the environment dracut
runs in: the container is opened before root exists, so the module that opens it
has to be in the initramfs dracut is building, and so does the filesystem it
mounts afterwards."
  "add_dracutmodules+=\" crypt \"
filesystems+=\" btrfs \"
")

(define (installer-grub-install-command mode device)
  "Return the @code{grub-install} argv that installs @var{mode}'s boot loader.

UEFI writes an EFI binary into the ESP and tells the firmware about it; MBR
writes its first stage into the disk's own boot sector, which is why it needs
the disk and not a partition."
  (if (installer-efi? mode)
    (list "grub-install" "--target=x86_64-efi" "--efi-directory=/boot/efi"
          (string-append "--bootloader-id=" (installer-bootloader-id)))
    (list "grub-install" "--target=i386-pc" device)))

;; ===========================================
;; The disk, as the commands that build it
;; ===========================================

(define (installer-subvolume-root? subvolume)
  "Return @code{#t} when @var{subvolume} is the one mounted at @file{/}."
  (string=? (second subvolume) "/"))

(define (installer-subvolume-mount subvolume)
  "Return the command that mounts @var{subvolume} at its mountpoint.

The root subvolume lands on the target itself; the others on the directory
their mountpoint names inside it."
  (format #f "mount -o ~a,subvol=~a /dev/mapper/cryptroot ~a"
          (installer-subvolume-options (second subvolume))
          (first subvolume)
          (if (installer-subvolume-root? subvolume)
            "\"$target\""
            (format #f "\"$target~a\"" (second subvolume)))))

(define (installer-mount-commands mode)
  "Return the commands that lay out and mount @var{mode}'s encrypted BTRFS root.

They are shell lines, in the order the script runs them, and they speak in this
script's own variables: @code{$disk} for the whole disk, @code{$esp_part},
@code{$boot_part} and @code{$root_part} for its partitions, @code{$target} for
the mount point and @code{$keyfile} for the file holding the passphrase.
Returning lines rather than a string keeps the order testable while the script
prints it.
"
  (let* ((esp (installer-esp-size))
         (boot (installer-boot-size))
         ;; Where each partition starts and ends, in MiB.  The disk's first
         ;; megabyte is left alone: the partition table lives there and a
         ;; partition starting at 0 is one partprobe away from being ignored.
         ;; The last partition ends at `100%', not at `-1': parted reads its own
         ;; options before its arguments, so a bare `-1' is the option it
         ;; refuses and the command never partitions anything.
         (esp-start 1)
         (esp-end (+ esp-start esp))
         (boot-start (if (installer-efi? mode) esp-end 1))
         (boot-end (+ boot-start boot))
         (root-start boot-end)
         ;; Partition paths differ by disk: /dev/vda1 but /dev/nvme0n1p1.  The
         ;; script decides the suffix, so the commands name its result.
         ;;
         ;; The table and the filesystems on it are two lists because they are
         ;; two moments: `parted' writes a table the kernel has not read yet,
         ;; and /dev/vda1 does not exist until something asks it to.  Formatting
         ;; before that probe is "no such device or address" on the ESP, and an
         ;; install stopped there with the table written and nothing else.
         (table
          (if (installer-efi? mode)
            (list "parted -s \"$disk\" mklabel gpt"
                  (format #f "parted -s \"$disk\" unit MiB mkpart ESP fat32 ~a ~a"
                          esp-start esp-end)
                  (format #f "parted -s \"$disk\" unit MiB mkpart boot ext4 ~a ~a"
                          boot-start boot-end)
                  (format #f "parted -s \"$disk\" unit MiB mkpart root ~a 100%"
                          root-start)
                  "parted -s \"$disk\" set 1 esp on")
            (list "parted -s \"$disk\" mklabel msdos"
                  (format #f "parted -s \"$disk\" unit MiB mkpart primary ext4 ~a ~a"
                          boot-start boot-end)
                  (format #f "parted -s \"$disk\" unit MiB mkpart primary ~a 100%"
                          root-start)
                  "parted -s \"$disk\" set 1 boot on")))
         (formats
          (if (installer-efi? mode)
            (list "mkfs.vfat -F32 -n EFI \"$esp_part\""
                  "mkfs.ext4 -L boot \"$boot_part\"")
            (list "mkfs.ext4 -L boot \"$boot_part\""))))
    (append
     (list
      ;; A disk that held something is not a disk that is empty: the old
      ;; signatures survive a rewrite of the table and confuse blkid later.
      "wipefs -a \"$disk\""
      "swapoff -a || true")
     table
     (list "partprobe \"$disk\""
           "udevadm settle || true")
     formats
     (list
      ;; The key comes from a file, never from the command line: `ps' is
      ;; world-readable, and a passphrase in argv is on the record.
      "step 'creating the encrypted volume (argon2id, a few seconds)' \\"
      "    cryptsetup luksFormat --type luks2 --pbkdf argon2id \\"
      "    --pbkdf-memory \"$pbkdf_memory\" --pbkdf-parallel 4 \\"
      "    --key-file \"$keyfile\" \"$root_part\""
      "cryptsetup open --key-file \"$keyfile\" \"$root_part\" cryptroot"
      "shred -u \"$keyfile\""
      "step 'making the filesystem' mkfs.btrfs -L heks /dev/mapper/cryptroot"
      "mount /dev/mapper/cryptroot \"$target\"")
     ;; The subvolumes come from one list, so what is created here is what
     ;; fstab mounts and what the summary promises.
     (map (lambda (subvolume)
            (format #f "btrfs subvolume create \"$target/~a\""
                    (first subvolume)))
          (installer-subvolumes))
     (list "umount \"$target\""
           "mkdir -p \"$target\"")
     (list (installer-subvolume-mount (find installer-subvolume-root?
                                            (installer-subvolumes))))
     (list (format #f "mkdir -p ~a"
                   (string-join
                    (append (map (lambda (subvolume)
                                   (format #f "\"$target~a\""
                                           (second subvolume)))
                                 (remove installer-subvolume-root?
                                         (installer-subvolumes)))
                            (list "\"$target/boot\""))
                    " "))
           "mount \"$boot_part\" \"$target/boot\"")
     ;; The ESP's mountpoint is made after the boot partition is mounted, not
     ;; with the others: /boot/efi lives inside the boot partition, so one made
     ;; before this mount is hidden by it, and the mount under it is then a path
     ;; that does not exist.
     (if (installer-efi? mode)
       (list "mkdir -p \"$target/boot/efi\""
             "mount \"$esp_part\" \"$target/boot/efi\"")
       '())
     (map installer-subvolume-mount
          (remove installer-subvolume-root? (installer-subvolumes))))))

;; ===========================================
;; The wizard
;; ===========================================

;; ===========================================
;; What the new system can be ready with
;; ===========================================

;; The two projects the desktop is built from that are not heks-*; the medium
;; carries the three that are, cloned at build time from image-upstream.
(define installer-projects-base
  (make-parameter "https://github.com/jjba23"))

(define (installer-project-sources)
  "Return every project the desktop is made of, as @code{(NAME . URL)} pairs.

The three heks projects come from the checkout base the image was built from;
the shell and the dock have their own pages.  One list, so the install-time
cloner and the build-time cloner cannot disagree about where the desktop comes
from."
  (append (map (lambda (checkout)
                 (cons (car checkout)
                       (format #f "~a/~a.git" (image-upstream) (car checkout))))
               (image-checkouts))
          (map (lambda (project)
                 (cons project
                       (format #f "~a/~a.git" (installer-projects-base)
                               project)))
               '("lambdock" "whelk"))))

(define (installer-extras)
  "Return what the wizard offers after the disk is written, as data.

Each extra is an alist: its @code{key} (the tag the checklist returns), the
@code{label} the checklist shows, whether it is @code{default?} and the shell
that carries it out inside the new system.

The defaults are the cheap and the necessary: the checkouts, because the two
builds below read them.  The two that pull gigabytes or compile an editor for an
hour are offered off, because a wizard that starts a one-hour build unless told
otherwise is not a friendly wizard.  The Flatpak set is off for the same reason:
it registers Flathub and pulls its applications, which is a few gigabytes it
would be rude to decide for somebody - but it is one keystroke away, which is
what \"out of the box\" means here: the wizard can hand over a machine with the
desktop's applications on it."
  (list (list (cons 'key 'checkouts)
              (cons 'default? #t)
              (cons 'label "Clone lambdock and whelk into ~/Hacking")
              (cons 'command "clone_or_update_all"))
        (list (cons 'key 'packages)
              (cons 'default? #f)
              (cons 'label "Install the workstation package sets (network, a few GB)")
              (cons 'command
                    (string-append
                     "run_as_user \"cd $home/Hacking/heks-linux && maak install-xbps\""
                     " \\\n"
                     "|| log 'the package sets did not install: run maak install-xbps after booting'")))
        (list (cons 'key 'flatpak)
              (cons 'default? #f)
              (cons 'label "Install the Flatpak applications (Flathub, a few GB)")
              (cons 'command
                    (string-append
                     "run_as_user \"cd $home/Hacking/heks-linux && maak install-flatpak\""
                     " \\\n"
                     "|| log 'the Flatpak applications did not install: run maak install-flatpak after booting'")))
        (list (cons 'key 'emacs)
              (cons 'default? #f)
              (cons 'label "Build Emacs master with PGTK (network, about an hour)")
              (cons 'command
                    (string-append
                     "[ -d \"$home/Scratch/emacs-build/.git\" ] \\\n"
                     "|| run_as_user \"git clone --depth 1 https://github.com/emacs-mirror/emacs.git $home/Scratch/emacs-build\"\n"
                     "run_as_user \"cd $home/Hacking/heks-emacs && maak emacs-update\" \\\n"
                     "|| log 'the Emacs build did not finish: run maak emacs-update after booting'")))))

(define (installer-extras-checklist)
  "Return the @code{dialog --checklist} items for the extras, as one string.

A tag becomes the argument @code{has_extra} asks about, so it is written without
quotes and the label - a sentence, so it can hold spaces - in single quotes."
  (string-join
   (map (lambda (extra)
          (format #f "~a '~a' ~a"
                  (assq-ref extra 'key)
                  (assq-ref extra 'label)
                  (if (assq-ref extra 'default?) "on" "off")))
        (installer-extras))
   " "))

(define (installer-indent text spaces)
  "Return @var{text} with every line indented by @var{spaces} spaces."
  (let ((pad (make-string spaces #\space)))
    (string-join (map (lambda (line) (string-append pad line))
                      (string-split text #\newline))
                 "\n")))

(define (installer-extras-dispatch)
  "Return the shell that runs the extras the checklist left on."
  (string-join
   (map (lambda (extra)
          (format #f "if has_extra ~a; then\n    log ~s\n~a\nfi"
                  (assq-ref extra 'key)
                  (assq-ref extra 'label)
                  (installer-indent (assq-ref extra 'command) 4)))
        (installer-extras))
   "\n"))

(define (installer-clone-commands)
  "Return one @code{clone_or_update} line per project the desktop is made of."
  (string-join
   (map (lambda (project)
          (format #f "clone_or_update ~a ~a" (car project) (cdr project)))
        (installer-project-sources))
   "\n"))

(define (installer-careful-lines)
  "Return the helpers that make the script answerable to a person.

Two of them are safety: @code{is_target_disk} refuses the disk the live system
is running from, and @code{type_confirm} takes the one answer that cannot be
given by accident.  @code{disk_details} is what the screens that ask about a disk
show about it - the size, the bus, the model, the table and what it already
holds - so a disk is chosen by what it is rather than by the letter it was
given.  The rest are the screen the questions are asked on, and they fall back
to plain prompts on a medium without dialog - a medium that cannot draw a menu
can still install."
  "
# --- the screen ---------------------------------------------------------------
# Every screen wears the same title, so a person scrolling back through a
# terminal knows which program asked.
backtitle='Heks GNU/Linux installer'
ui=dialog
command -v dialog >/dev/null 2>&1 || ui=plain

# The questions, in the order main asks them.  The list is the count as well as
# the order: every screen's title says how far along the wizard is, because a
# wizard that answers \"how much longer\" before it is asked is one a person
# finishes rather than one they abandon.  A question added without a line here is
# a screen somebody notices, not a count that quietly lies.
questions='mode disk network passphrase timezone locale keymap identity admin rootpass extras summary'
ask_total=0
for asked in $questions; do
    ask_total=$((ask_total + 1))
done
ask_count=0
screen_title='Heks GNU/Linux'

# screen TITLE: the title this question wears, in $screen_title.

# It sets a variable rather than printing: the title is used as an argument to a
# question, and a question is asked inside a command substitution - a subshell,
# where the count it just incremented would be forgotten by the next screen.
screen() {
    ask_count=$((ask_count + 1))
    screen_title=\"$1 ($ask_count/$ask_total)\"
}

# The palette this medium ships - green ink on a dark screen, warm title - read
# by dialog from the one file both systems keep.  A medium without it is not a
# failure: dialog draws its own colours and the wizard goes on.
if [ -r <theme> ]; then
    DIALOGRC=<theme>
    export DIALOGRC
fi

ui_msg() {
    if [ \"$ui\" = dialog ]; then
        dialog --stdout --backtitle \"$backtitle\" --title 'Heks GNU/Linux' --msgbox \"$1\" 0 0
    else
        printf '\\n%s\\n\\n' \"$1\"
        read -r -p 'press enter to continue ' _ || true
    fi
}

# yesno PROMPT [TITLE]: yes is the exit status, no is not.
ui_yesno() {
    local prompt=\"$1\" title=\"${2:-Heks GNU/Linux}\"
    if [ \"$ui\" = dialog ]; then
        dialog --backtitle \"$backtitle\" --title \"$title\" --yesno \"$prompt\" 0 0
    else
        local answer
        read -r -p \"$prompt [y/N] \" answer || return 1
        case \"$answer\" in
            [yY]*) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# menu TITLE PROMPT TAG LABEL [TAG LABEL ...]: the chosen tag on stdout.
ui_menu() {
    local title=\"$1\" prompt=\"$2\" rows
    shift 2
    # As tall as its list.  Left to itself, dialog gives a two-disk machine one
    # visible row and a scroll bar, and a person picking a disk should not have
    # to scroll through two of them; a list longer than the screen still
    # scrolls.
    rows=$(( $# / 2 ))
    if [ \"$ui\" = dialog ]; then
        dialog --stdout --backtitle \"$backtitle\" --title \"$title\" --menu \"$prompt\" 0 0 \"$rows\" \"$@\"
    else
        local tag label choice
        # The questions go to stderr and only the answer to stdout: this is
        # called inside a command substitution, and a menu printed there lands
        # in the answer - which made every plain-medium choice the text of the
        # menu it was chosen from.
        printf '\\n%s\\n%s\\n\\n' \"$title\" \"$prompt\" >&2
        while [ \"$#\" -gt 0 ]; do
            tag=\"$1\" label=\"$2\"
            shift 2
            printf '  %s) %s\\n' \"$tag\" \"$label\" >&2
        done
        read -r -p 'choice: ' choice || return 1
        printf '%s\\n' \"$choice\"
    fi
}

# checklist TITLE PROMPT TAG LABEL ONOFF [TAG LABEL ONOFF ...]: chosen tags.
ui_checklist() {
    local title=\"$1\" prompt=\"$2\" lines
    shift 2
    lines=$(( $# / 3 ))
    if [ \"$ui\" = dialog ]; then
        dialog --stdout --backtitle \"$backtitle\" --title \"$title\" --checklist \"$prompt\" 0 0 \"$lines\" \"$@\"
    else
        local tag label state defaults='' chosen=''
        printf '\\n%s\\n%s\\n\\n' \"$title\" \"$prompt\" >&2
        while [ \"$#\" -gt 0 ]; do
            tag=\"$1\" label=\"$2\" state=\"$3\"
            shift 3
            printf '  %s) [%s] %s\\n' \"$tag\" \"$state\" \"$label\" >&2
            if [ \"$state\" = on ]; then
                defaults=\"$defaults $tag\"
            fi
        done
        read -r -p 'keep which? (tags separated by spaces, empty for the defaults) ' chosen >&2 \\
            || return 1
        printf '%s\\n' \"${chosen:-$defaults}\"
    fi
}

# input TITLE PROMPT DEFAULT: the answer on stdout.
ui_input() {
    if [ \"$ui\" = dialog ]; then
        dialog --stdout --backtitle \"$backtitle\" --title \"$1\" --inputbox \"$2\" 0 0 \"$3\"
    else
        local answer
        # The title first, as dialog draws it: a medium without dialog still says
        # which question this is and how many are left.
        printf '\\n%s\\n' \"$1\" >&2
        printf '\\n%s\\n' \"$2\" >&2
        read -r -p \"[$3] \" answer || return 1
        printf '%s\\n' \"${answer:-$3}\"
    fi
}

# password TITLE PROMPT: the answer on stdout, never echoed.
ui_password() {
    if [ \"$ui\" = dialog ]; then
        dialog --stdout --insecure --backtitle \"$backtitle\" --title \"$1\" --passwordbox \"$2\" 0 0
    else
        local answer
        read -r -s -p \"$2 \" answer || return 1
        printf '\\n' >&2
        printf '%s\\n' \"$answer\"
    fi
}

# --- the hand, not the screen -------------------------------------------------
# Everything below runs inside the new system, as the account it was installed
# for: a home rendered by root is a home its owner cannot write to.
run_as_user() {
    chroot \"$target\" runuser -u \"$user_name\" -- bash -lc \"$1\"
}

# Was EXTRA left on on the checklist?
has_extra() {
    case \" $extras \" in
        *\" $1 \"*) return 0 ;;
    esac
    return 1
}

# Is this machine on the network?  The stores are the one phase that needs it,
# so the question is asked once, before the disk is written, and answered in the
# summary the person confirms.  The manager that made the connection knows
# whether it has one, which is what counts on a network that drops ICMP; ping
# answers where something else brought the network up.  A medium with neither is
# given the benefit of the doubt: skipping the stores is not a thing to do to a
# machine that could have fetched them.
network_ready() {
    if command -v nmcli >/dev/null 2>&1 &&
        [ \"$(nmcli -t -f STATE general 2>/dev/null)\" = connected ]; then
        return 0
    fi
    command -v ping >/dev/null 2>&1 || return 0
    ping -c1 -W2 1.1.1.1 >/dev/null 2>&1
}

# --- the network --------------------------------------------------------------
# The medium carries NetworkManager, and the wizard drives it rather than asking
# a person to open another console and type nmcli: the stores and the extras are
# what needs the network, and a laptop whose card is fine but unjoined finishes
# offline whether or not anybody wanted that.

# The wired and wireless interfaces NetworkManager can see, as DEVICE TYPE.
net_interfaces() {
    nmcli -t -f DEVICE,TYPE device status 2>/dev/null \\
        | grep -E ':(ethernet|wifi)$' | tr ':' ' '
}

# interface_type DEVICE: ethernet or wifi, as NetworkManager spells it.
interface_type() {
    local device type
    while read -r device type; do
        if [ \"$device\" = \"$1\" ]; then
            printf '%s\\n' \"$type\"
            return 0
        fi
    done <<EOF
$(net_interfaces)
EOF
}

# The networks one interface can hear, strongest first, one SSID per line: what
# a person picks from is what the radio hears now, not what it heard at boot.
wifi_networks() {
    nmcli -t -f SSID device wifi list ifname \"$1\" 2>/dev/null \\
        | awk 'NF && !seen[$0]++'
}

# A lease is not instant, and the phase after this one asks whether there is a
# network at all: ten seconds of asking is the difference between connected and
# connected-before-anybody-noticed.
wait_for_network() {
    local tries=10
    while [ \"$tries\" -gt 0 ]; do
        network_ready && return 0
        sleep 1
        tries=$((tries - 1))
    done
    return 1
}

# join_wifi DEVICE: pick a network, join it, and ask for the password only when
# joining without one failed - nothing here has to know what the network's
# security field says, and an open network is one screen shorter.
join_wifi() {
    local device=\"$1\"
    local -a items=()
    local ssid password line
    # A radio can be there and switched off: the soft block a laptop's key
    # combination leaves behind looks exactly like a machine with no wireless.
    rfkill unblock wifi >/dev/null 2>&1 || true
    nmcli device wifi rescan ifname \"$device\" >/dev/null 2>&1 || true
    while IFS= read -r line; do
        [ -n \"$line\" ] || continue
        items+=(\"$line\" \"$line\")
    done <<EOF
$(wifi_networks \"$device\")
EOF
    if [ ${#items[@]} -gt 0 ]; then
        ssid=\"$(ui_menu 'Wireless' 'Which network?' \"${items[@]}\" \\
            other 'A network this list does not show')\" || return 1
        [ \"$ssid\" = other ] && ssid=''
    fi
    if [ -z \"$ssid\" ]; then
        ssid=\"$(ui_input 'Wireless' \"The network's name (SSID).\" '')\" \\
            || return 1
        [ -n \"$ssid\" ] || return 1
    fi
    if nmcli device wifi connect \"$ssid\" ifname \"$device\" >/dev/null 2>&1; then
        return 0
    fi
    password=\"$(ui_password 'Wireless' \"Password for $ssid.\")\" || return 1
    # shortcut: nmcli takes the pre-shared key as an argument, so it is in `ps'
    # for the second the join takes.  This medium has one account, and the
    # profile NetworkManager writes is 0600 in both systems; a booted machine
    # that grows other users wants `nmcli --ask' instead.
    if nmcli device wifi connect \"$ssid\" password \"$password\" ifname \"$device\" \\
        >/dev/null 2>&1; then
        password=''
        return 0
    fi
    password=''
    ui_msg \"Could not join $ssid.

Check the password and that the network is in range: the wizard tries again when
you pick a network.\"
    return 1
}

# join_ethernet DEVICE: a cable is either there or it is not; NetworkManager's
# own profile does the rest.
join_ethernet() {
    nmcli device connect \"$1\" >/dev/null 2>&1 || true
}


# clone_or_update NAME URL: the checkout in the user's Hacking directory,
# pulled when it is already there and cloned when it is not.
clone_or_update() {
    local name=\"$1\" url=\"$2\" dest=\"$home/Hacking/$1\"
    if [ -d \"$dest/.git\" ]; then
        run_as_user \"git -C $dest pull --ff-only\" || log \"could not update $name\"
    else
        run_as_user \"git clone --depth 1 $url $dest\" || log \"could not clone $name\"
    fi
}

clone_or_update_all() {
<clone_commands>
}

# The disk the live system is running from cannot be the target: erasing it
# would take the installer with it, mid-write.
is_target_disk() {
    local disk=\"$1\" root_source root_disk
    if [ -n \"$(lsblk -no MOUNTPOINT \"$disk\" 2>/dev/null | tr -d '[:space:]')\" ]; then
        return 0
    fi
    root_source=\"$(findmnt -no SOURCE / 2>/dev/null || true)\"
    if [ -n \"$root_source\" ]; then
        root_disk=\"$(lsblk -dpno NAME \"$root_source\" 2>/dev/null || true)\"
        [ -n \"$root_disk\" ] && [ \"$root_disk\" = \"$disk\" ] && return 0
    fi
    return 1
}

# What a person picks a disk by.  A row that says nothing but `/dev/sda' is what
# makes somebody erase the wrong disk: the same letter names the old spinning
# disk, the new enclosure and the card reader somebody left plugged in, and a
# menu of three bare device names is a menu of three identical rows.  So a row
# carries what the machine knows about the disk - the size, how it is attached,
# the name the disk gives itself, the table on it and the filesystems it already
# holds - and a disk a person recognises is a disk they do not erase by accident.
#
# Every field may be missing: a virtio disk reports no transport, a disk that was
# never partitioned reports no table, and a row with a short field is still a row
# a person can pick.
disk_details() {
    local disk=\"$1\" size bus model table contents
    size=\"$(lsblk -dbno SIZE \"$disk\" 2>/dev/null | awk '{ printf \"%d\", $1 / 1073741824 }')\"
    bus=\"$(lsblk -dno TRAN \"$disk\" 2>/dev/null | tr -d '[:space:]')\"
    # No transport is a disk that is not on a bus this kernel names - a virtio
    # disk, a loop device - and its rotation flag still says what it is.
    [ -n \"$bus\" ] || bus=\"$(lsblk -dno ROTA \"$disk\" 2>/dev/null | tr -d '[:space:]')\"
    case \"$bus\" in
        0) bus=ssd ;;
        1) bus=disk ;;
    esac
    model=\"$(lsblk -dno MODEL \"$disk\" 2>/dev/null | sed 's/[[:space:]]*$//')\"
    table=\"$(lsblk -dno PTTYPE \"$disk\" 2>/dev/null | tr -d '[:space:]')\"
    # The filesystems of the disk and of its partitions, each named once: what a
    # disk holds now is the fact a person recognises it by.
    contents=\"$(lsblk -rno FSTYPE \"$disk\" 2>/dev/null \\
        | awk 'NF && !seen[$0]++ { printf \"%s%s\", separator, $0; separator = \", \" }')\"
    printf '%s  %s GiB' \"$disk\" \"${size:-0}\"
    [ -z \"$bus\" ] || printf '  %s' \"$bus\"
    [ -z \"$model\" ] || printf '  %s' \"$model\"
    [ -z \"$table\" ] || printf '  %s' \"$table\"
    printf '  %s\\n' \"${contents:-empty}\"
}

# One menu entry is one keystroke away from the wrong disk; the name is the one
# answer that cannot be given by accident.
type_confirm() {
    local disk=\"$1\" wanted answer details
    wanted=\"$(basename \"$disk\")\"
    # The same description the menu showed, on the screen that erases it: this is
    # the moment to notice that the 476 GiB Samsung is not the 32 GiB stick
    # somebody meant to use.
    details=\"$(disk_details \"$disk\")\"
    answer=\"$(ui_input \"Erase $wanted\" \\
        \"$details

This ERASES $wanted and everything on it: the partition table, every filesystem and the data in them.  Type ERASE to continue.\" \"\")\" || return 1
    [ \"$answer\" = ERASE ]
}
")

(define (installer-questions-lines)
  "Return the questions, in the order the wizard asks them.

Everything with a default is a default; the disk, the passphrase, the machine's
name and the user's with the password it gets are the four answers a person has
to give, root's password is the fifth, and whether the account administers the
machine is a sixth that arrives on."
  "
# --- the questions ------------------------------------------------------------
mode=\"$default_mode\"
disk=\"\"
hostname=\"heks-linux\"
# The clock and the language default to the ones the desktop declares, so the
# wizard and the render that follows it cannot disagree; the answer replaces
# them, because it is the one fact about this machine the medium cannot know.
timezone='<timezone>'
locale='<locale>'
keymap='<keymap>'
user_name=\"<placeholder>\"
passphrase=\"\"
userpass=\"\"
# Whether the account administers this machine.  It is a question with a default
# of yes, because the person who installs a desktop is the one who configures
# it, and an account that cannot install a package is a machine that needs
# root's password to be used.
admin=\"yes\"
rootpass=\"\"
extras=''
home=''

# The first screen is not a question: it says what this is, what it will do and
# what it cannot undo.
ask_welcome() {
    ui_msg \"Welcome to Heks GNU/Linux.

This medium puts the desktop on a disk of your choosing, and it carries
everything the install needs: the disk tools, the system it unpacks, and this
wizard.  Take your time, there is nothing here that hurries you.

This wizard asks for what it cannot know - the firmware, the disk, the network
when the machine has none, the disk passphrase, the timezone, the language, the
keyboard, the host name, the user and its password, whether that account
administers the machine, and root's password - and defaults the rest, and then
that disk holds one encrypted BTRFS system with this desktop on it.  The screen
titles count them for you.

The network is the only one you can skip: a cable, or a wireless
network and its password, because the steps below that fetch are fetched over
it.  That connection travels to the new system, so the machine is online the
first time it boots.

The disk is ERASED: everything on it goes.
The passphrase is asked once, at boot, by the initramfs.
The clock and the language are yours, not the medium's.
The account is the one the desktop was rendered for, renamed.
Root's password is replaced here: the image arrives with void-mklive's published
one, which is not a password on a machine you have installed.

After the disk is written it installs the two stores the desktop runs on - guix
and nix, a few gigabytes - and renders the desktop for your account.  That is the
one step the install cannot do offline: with no network the machine still
installs and boots, and heks-setup finishes the job when you are online.  With
one, it also upgrades the new system to what the repositories carry, so the first
boot is not spent downloading what already exists.

The medium can also leave the new system ready with the rest of the projects,
the package sets, the Flatpak applications and the editor, if you want them -
that list comes before anything is written.

Lost?  Type heks-help in a shell: it opens the quickstart this medium carries.\"
}

main_menu() {
    local choice
    choice=\"$(ui_menu 'Heks GNU/Linux' \\
        'Install the desktop on this machine, or work from the medium first.' \\
        install 'Guided install: one disk, encrypted, erased' \\
        shell 'A shell on the live medium' \\
        reboot 'Reboot')\" || exit 0
    case \"$choice\" in
        install) ;;
        shell) exec bash -li ;;
        reboot) reboot ;;
    esac
}

ask_mode() {
    local choice
    screen 'Firmware'
    choice=\"$(ui_menu \"$screen_title\" \\
        \"This machine booted from $default_mode.  The disk is laid out for the firmware it booted from.\" \\
        \"$default_mode\" \"$(mode_label \"$default_mode\")\" \\
        \"$other_mode\" \"$(mode_label \"$other_mode\")\")\" || die 'cancelled'
    mode=\"$choice\"
}

ask_disk() {
    local tag line choice size_gib
    local -a items=()
    while read -r line; do
        [ -n \"$line\" ] || continue
        if is_target_disk \"$line\"; then
            log \"refuse the disk this medium runs from: $line\"
            continue
        fi
        tag=\"$(basename \"$line\")\"
        # The row is the disk's own name and its own details, worked out as the
        # list is built: a description rendered once and repeated would be read
        # as a fact about every disk in the menu.  A tag and a label are two
        # arguments, kept as two array elements: the description has spaces in
        # it, and a menu handed one long string splits it at every one, which is
        # a screen asking between \"GiB\" and \"sata\" instead of between disks.
        items+=(\"$tag\" \"$(disk_details \"$line\")\")
    done <<EOF
$(lsblk -dpno NAME)
EOF
    if [ ${#items[@]} -eq 0 ]; then
        die 'no disk to install on: attach one, or free the one this medium runs from'
    fi
    # A disk too small is not a choice, it is a trap: the encrypted layout needs
    # room for the system before there is room for anything of yours.  Asking
    # again costs one screen; finding out two minutes into the copy costs the
    # installer and the disk.
    screen 'Where should it live?'
    while :; do
        # No SC2086: the array is what keeps one disk's description one argument.
        choice=\"$(ui_menu \"$screen_title\" \\
            'The whole disk is used: everything on it is erased.

Size, bus, model, table and contents are what the machine reports about each disk.' \\
            \"${items[@]}\")\" || die 'cancelled'
        disk=\"/dev/$choice\"
        [ -b \"$disk\" ] || die \"$disk is not a block device\"
        size_gib=\"$(lsblk -dbno SIZE \"$disk\" 2>/dev/null | awk '{ printf \"%d\", $1 / 1073741824 }')\"
        if [ \"${size_gib:-0}\" -lt 8 ]; then
            ui_msg \"$disk is ${size_gib:-0} GiB.

The encrypted BTRFS layout needs at least 8 GiB before there is room for the
system, so this disk cannot hold it.  Choose another one.\"
            continue
        fi
        if [ \"${size_gib:-0}\" -lt 20 ]; then
            ui_msg \"$disk is ${size_gib} GiB.

The system fits and little else will: the desktop's own packages are a few
gigabytes.  The install is not stopped, it is just going to be a small machine.\"
        fi
        log \"the target is $disk (${size_gib:-0} GiB)\"
        break
    done
}

# The network, before anything is written: a machine that is already online - a
# cable, usually - has nothing to answer here, and one that is not is offered
# the interfaces it actually has.  Nothing about the install depends on this
# answer except the two phases that fetch: the stores and the extras.
ask_network() {
    local -a items=()
    local device type choice
    # Counted before the questions it may not ask: a machine that is already
    # online skips this screen, and the ones after it still know where they are.
    screen 'The internet'
    if network_ready; then
        log 'the machine is already on the network'
        return 0
    fi
    if ! command -v nmcli >/dev/null 2>&1; then
        ui_msg 'This medium carries no NetworkManager, so the wizard cannot bring a network up for you.

Everything except the desktop stores installs without one: carry on, or set it up
in a shell (ip link, dhcpcd) and the wizard will use it.'
        return 0
    fi
    while read -r device type; do
        [ -n \"$device\" ] || continue
        items+=(\"$device\" \"$device ($type)\")
    done <<EOF
$(net_interfaces)
EOF
    if [ ${#items[@]} -eq 0 ]; then
        ui_msg 'No wired and no wireless interface on this machine.

Everything except the desktop stores installs without a network.'
        return 0
    fi
    while :; do
        choice=\"$(ui_menu \"$screen_title\" \\
            'Everything except the desktop stores installs without a network.  Bring one up first?

A wireless network asks for its name and password; a cable only has to be plugged in.' \\
            \"${items[@]}\" skip 'Carry on without a network')\" || choice=skip
        [ \"$choice\" = skip ] && return 0
        case \"$(interface_type \"$choice\")\" in
            wifi)
                join_wifi \"$choice\" || continue
                ;;
            *)
                join_ethernet \"$choice\"
                ;;
        esac
        if wait_for_network; then
            log \"the network is up on $choice\"
            ui_msg \"The machine is on the network.

The stores and the extras will be fetched during the install; the connection
travels to the new system as well, so the machine is online when it boots.\"
            return 0
        fi
        ui_msg \"$choice has no address yet.

Check the cable, or pick the interface again - a wireless network is asked for
its name and its password.  Carrying on without a network is also an answer:
everything except the desktop stores installs offline.\"
    done
}

ask_passphrase() {
    local first second
    screen 'Encryption'
    while :; do
        first=\"$(ui_password \"$screen_title\" \\
            'Passphrase for the disk.  It is asked once, at boot, and typed there with a US keyboard: use letters and digits you can find blind.')\" \\
            || die 'cancelled'
        if [ \"${#first}\" -lt 8 ]; then
            ui_msg 'The passphrase is shorter than 8 characters.'
            continue
        fi
        second=\"$(ui_password 'Encryption' 'The same passphrase again.')\" \\
            || die 'cancelled'
        [ \"$first\" = \"$second\" ] && break
        ui_msg 'The two passphrases differ.'
    done
    passphrase=\"$first\"
    # A file only its owner can read, and never a command line.
    keyfile=\"$(mktemp /tmp/heks-key.XXXXXX)\"
    ( umask 077; printf '%s' \"$passphrase\" > \"$keyfile\" )
    passphrase=\"\"
}

# The clock and the language: the two facts about a machine that the medium
# cannot know.  The payload carries the values the image was built with, and a
# wizard that left them there would put every machine in one city speaking one
# language.  Both answers are checked before they are taken - the timezone by its
# shape and then against the zone database, the language by the shape of a locale
# name - because a typo here is a machine whose clock is wrong and whose programs
# have no language, and neither says a word until it boots.  The shape check
# comes first because the answer becomes a link target inside the new system.
ask_timezone() {
    local answer
    screen 'The clock'
    while :; do
        answer=\"$(ui_input \"$screen_title\" \\
            \"The timezone this machine is in, as the zone database names it: Europe/Amsterdam, America/Sao_Paulo, Asia/Tokyo.  UTC is a clock that never moves.

A wrong answer is a wrong hour, not a broken machine.\" \"$timezone\")\" \\
            || die 'cancelled'
        if printf '%s' \"$answer\" | grep -Eq '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$' &&
            [ -e \"/usr/share/zoneinfo/$answer\" ]; then
            timezone=\"$answer\"
            log \"the clock: $timezone\"
            return 0
        fi
        ui_msg \"\\\"$answer\\\" is not a timezone.

The list is /usr/share/zoneinfo, and a name there is a continent and a city:
Europe/Amsterdam, America/Sao_Paulo, Asia/Tokyo - or UTC for a clock that never
moves.\"
    done
}

ask_locale() {
    local answer
    screen 'The language'
    while :; do
        answer=\"$(ui_input \"$screen_title\" \\
            \"The language the system speaks, as a locale name: a lowercase language, an underscore and a capitalised country.  $locale is what this desktop is built for.

It is written to /etc/locale.conf with .UTF-8 after it, which is what every program reads.\" \"$locale\")\" \\
            || die 'cancelled'
        if printf '%s' \"$answer\" | grep -Eq '^[a-z][a-z]_[A-Z][A-Z]$'; then
            locale=\"$answer\"
            log \"the language: $locale\"
            return 0
        fi
        ui_msg \"\\\"$answer\\\" is not a locale.

Two lowercase letters, an underscore and two capitals: nl_NL, en_US, de_DE,
pt_PT.\"
    done
}

# The console's keymap: Void takes it from `KEYMAP' in /etc/rc.conf, and the
# session's layout from this tree's own settings, so the answer is checked
# against the keymaps the system actually carries and written in both places.
# The name is a file under /usr/share/kbd/keymaps, two or three directories
# down - i386/qwerty/us.map.gz, mac/... - which is why the check is a glob and
# not a list of layouts somebody wrote down here.
keymap_exists() {
    local candidate
    for candidate in /usr/share/kbd/keymaps/\"$1\".map* \\
                     /usr/share/kbd/keymaps/*/\"$1\".map* \\
                     /usr/share/kbd/keymaps/*/*/\"$1\".map* \\
                     /usr/share/kbd/keymaps/*/*/*/\"$1\".map*; do
        [ -e \"$candidate\" ] && return 0
    done
    return 1
}

ask_keymap() {
    local answer
    screen 'The keyboard'
    while :; do
        answer=\"$(ui_input \"$screen_title\" \\
            \"The layout of this keyboard, as kbd names it: us, fr, de, es, pt-latin1.  $keymap is what this desktop is built for.

It reaches the console through /etc/rc.conf and the session through the desktop's own settings, so both speak the same layout.\" \"$keymap\")\" \\
            || die 'cancelled'
        if printf '%s' \"$answer\" | grep -Eq '^[a-z0-9][a-z0-9_-]*$' &&
            keymap_exists \"$answer\"; then
            keymap=\"$answer\"
            log \"the keyboard: $keymap\"
            return 0
        fi
        ui_msg \"\\\"$answer\\\" is not a keymap.

The list is /usr/share/kbd/keymaps, and a name there is the layout's own:
us, fr, de, es, pt-latin1.  Type one of those.\"
    done
}

ask_identity() {
    local first second answer
    screen 'Hostname'
    while :; do
        answer=\"$(ui_input \"$screen_title\" \\
            'The name this machine answers to: letters, digits, dots and dashes.' \"$hostname\")\" \\
            || die 'cancelled'
        # The hostname becomes /etc/hostname, the settings the desktop render
        # reads, and a line in the resolver's file: a shape it cannot have is a
        # machine that introduces itself as nothing.
        if printf '%s' \"$answer\" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9.-]*$' &&
            [ \"${#answer}\" -le 253 ]; then
            hostname=\"$answer\"
            break
        fi
        ui_msg \"\\\"$answer\\\" is not a hostname.

Letters, digits, dots and dashes, starting with a letter or a digit:
heks-linux, box, workstation.local.\"
    done
    while :; do
        answer=\"$(ui_input 'User' \\
            'The account the desktop was rendered for: lowercase letters, digits, underscore and dash.' \"$placeholder_user\")\" \\
            || die 'cancelled'
        # The account name is a path, a command line and the owner of the
        # settings the render reads; the shape is the one useradd accepts.
        if printf '%s' \"$answer\" | grep -Eq '^[a-z_][a-z0-9_-]*$' &&
            [ \"${#answer}\" -le 32 ]; then
            user_name=\"$answer\"
            break
        fi
        ui_msg \"\\\"$answer\\\" is not a user name.

Lowercase letters, digits, underscore and dash, starting with a letter or an
underscore, at most 32 characters: joe, joe_b, heks-1.\"
    done
    while :; do
        first=\"$(ui_password 'User password' \"Password for $user_name.\")\" \\
            || die 'cancelled'
        if [ -z \"$first\" ]; then
            ui_msg 'An empty password is not a password.'
            continue
        fi
        second=\"$(ui_password 'User password' 'The same password again.')\" \\
            || die 'cancelled'
        [ \"$first\" = \"$second\" ] && break
        ui_msg 'The two passwords differ.'
    done
    userpass=\"$first\"
    home=\"/home/$user_name\"
}

# Whether that account administers the machine.  It is the one question here
# whose answer is a permission, so it is asked in the open rather than decided
# for somebody: yes puts the account in wheel and uncomments sudoers' %wheel
# rule, which are the two halves of one right and are written together or not at
# all.  sudo still asks for the account's own password - the rule is not a
# NOPASSWD one - because an administration right that never asks is a machine
# anybody at the keyboard can change.
ask_admin() {
    local choice
    screen 'Administration'
    choice=\"$(ui_menu \"$screen_title\" \\
        \"Should $user_name administer this machine?

Yes is what a desktop's owner wants: sudo runs from the first login, and it asks
for $user_name's own password - the one typed a moment ago - every time.

No leaves root's password as the only way in.  Either way the account gets the
device groups its hardware needs, and either way nothing here is passwordless.\" \\
        yes 'Yes: sudo, with the account password' \\
        no 'No: only root changes the system')\" || die 'cancelled'
    admin=\"$choice\"
    log \"administration for $user_name: $admin\"
}

# Root's own account.  The desktop account administers the machine through sudo,
# so this is not what makes the machine usable - it is what makes it reachable
# when that account cannot log in.  The rootfs carries void-mklive's default
# (`voidlinux'), which is a published password and so not one at all: the
# installer replaces it with one only this machine knows.
ask_rootpass() {
    local first second
    screen 'Root account'
    while :; do
        first=\"$(ui_password \"$screen_title\" \\
            'Password for root.  The desktop account administers this machine through sudo; this one is the way back in when that account cannot log in.

It is typed here rather than left as the image carries it: void-mklive sets root to the published password voidlinux, which is not a password at all on a machine anybody can reach a console of.')\" \\
            || die 'cancelled'
        if [ -z \"$first\" ]; then
            ui_msg 'An empty password is not a password.'
            continue
        fi
        second=\"$(ui_password 'Root account' 'The same password again.')\" \\
            || die 'cancelled'
        [ \"$first\" = \"$second\" ] && break
        ui_msg 'The two passwords differ.'
    done
    rootpass=\"$first\"
}

# The extras are one screen: space toggles, Enter accepts, and the defaults are
# the ones the next phase can do without pulling a gigabyte.
ask_extras() {
    screen 'A few last things'
    extras=\"$(ui_checklist \"$screen_title\" \\
        \"What else should the new system be ready with?

The first is the cheap one; the three below it pull from the network, and the
account's password is asked again by sudo while they run.\" \\
        <extras_checklist>)\" || extras='' 
}

ask_summary() {
    local network_note=''
    screen 'The plan'
    if ! network_ready; then
        network_note='
No network here: the install finishes without it, and the stores and the desktop
are set up after the first boot, with heks-setup.'
    fi
    ui_yesno \"Install to $disk?

Disk:        $(disk_details \"$disk\")
Firmware:    $mode
Partitions:  $(partition_summary)
Hostname:    $hostname
Timezone:    $timezone
Locale:      $locale
Keyboard:    $keymap
User:        $user_name
Admin:       $admin
Encryption:  LUKS2, BTRFS inside it
Also:        ${extras:-nothing else}$network_note

Everything on $disk is destroyed.\" \"$screen_title\" || exit 0
}
")

(define (installer-run-lines)
  "Return the phases that carry the answers out, and the entry point.

@code{work} assumes the answers hold and writes the disk; @code{main} asks for
them and then calls it.  The split is what lets the spec run the phases: the
fake disk sources this script and calls @code{work} with the answers set,
instead of answering every screen with a keyboard that is not there."
  "
# --- the work -----------------------------------------------------------------
# The phases, in the order they must run.  They speak in this script's own
# variables: $disk and $mode from the answers, $target for the mount point,
# $payload for the system the medium carries.
work() {
log \"installing on $disk ($mode)\"
log \"  hostname: $hostname\"
log \"  clock: $timezone\"
log \"  language: $locale\"
log \"  keyboard: $keymap\"
log \"  user: $user_name\"
log \"  also: ${extras:-nothing else}\"
log \"  encryption: LUKS2, BTRFS inside it\"

# A disk is named /dev/vda1 or /dev/nvme0n1p1: the suffix depends on whether
# the disk's own name ends in a digit.
sep=''
case \"$disk\" in
    *[0-9]) sep=p ;;
esac
if [ \"$mode\" = uefi ]; then
    esp_part=\"${disk}${sep}1\"
    boot_part=\"${disk}${sep}2\"
    root_part=\"${disk}${sep}3\"
else
    boot_part=\"${disk}${sep}1\"
    root_part=\"${disk}${sep}2\"
fi

phase 'the payload'
[ -r \"$payload\" ] || die \"the installed system is not on this medium ($payload)\"

phase 'the disk'
<mount_commands>

phase 'the system'
step 'unpacking the installed system (a few minutes)' tar -xpf \"$payload\" -C \"$target\"

phase 'the files'
luks_uuid=\"$(cryptsetup luksUUID \"$root_part\")\"
root_uuid=\"$(blkid -s UUID -o value /dev/mapper/cryptroot)\"
boot_uuid=\"$(blkid -s UUID -o value \"$boot_part\")\"
esp_uuid=\"\"
if [ \"$mode\" = uefi ]; then
    esp_uuid=\"$(blkid -s UUID -o value \"$esp_part\")\"
fi
[ -n \"$luks_uuid\" ] && [ -n \"$root_uuid\" ] && [ -n \"$boot_uuid\" ] \\
    || die 'the disk did not report its identifiers'

cat > \"$target/etc/fstab\" <<EOF
<fstab>
EOF
if [ \"$mode\" = uefi ]; then
    cat >> \"$target/etc/fstab\" <<EOF
<esp_fstab>
EOF
fi
install -d \"$target/etc/default\"
cat > \"$target/etc/default/grub\" <<EOF
GRUB_CMDLINE_LINUX_DEFAULT=\"<cmdline>\"
# The boot menu names this system rather than the distribution under it: the
# grub package ships \"Void\" here, and this file is written over it.  The word
# is Heks and not Heks GNU/Linux: grub's 10_linux writes the menu entry as the
# distributor it reads followed by \" GNU/Linux\", so the whole name here was a
# menu that read \"Heks GNU/Linux GNU/Linux\".
GRUB_DISTRIBUTOR=\"Heks\"
GRUB_DISABLE_OS_PROBER=true
EOF
install -d \"$target/etc/dracut.conf.d\"
cat > \"$target/etc/dracut.conf.d/10-crypt.conf\" <<EOF
<dracut>
EOF
printf '%s\\n' \"$hostname\" > \"$target/etc/hostname\"
# The clock and the language are the person's answers, not the medium's: the
# payload arrives with whatever the image was built with, and these two lines are
# the whole of what a Void system reads for them - a link into the zone database,
# and one line in locale.conf that every program takes its language from.
ln -sfn \"/usr/share/zoneinfo/$timezone\" \"$target/etc/localtime\" \\
    || log \"no zone database on this medium: the installed system keeps the one it carries\"
printf 'LANG=%s.UTF-8\\n' \"$locale\" > \"$target/etc/locale.conf\"
# The console reads its layout from KEYMAP in /etc/rc.conf - Void sources that
# file in its runit stages - and the payload carries no such file, so it is
# written here; a payload that ever does carry one keeps the rest of it and has
# the line replaced rather than doubled.
if [ -f \"$target/etc/rc.conf\" ] && grep -q '^KEYMAP=' \"$target/etc/rc.conf\"; then
    sed -i \"s|^KEYMAP=.*|KEYMAP=$keymap|\" \"$target/etc/rc.conf\"
else
    [ -s \"$target/etc/rc.conf\" ] \\
        || printf '# /etc/rc.conf -- written by heks-install\\n' >> \"$target/etc/rc.conf\"
    printf 'KEYMAP=%s\\n' \"$keymap\" >> \"$target/etc/rc.conf\"
fi
log \"the clock is $timezone, the language is $locale, the keyboard is $keymap\"
log 'fstab, the kernel command line and the initramfs are written'

phase 'the bootloader'
for tree in proc sys dev run; do
    mount --rbind \"/$tree\" \"$target/$tree\" 2>/dev/null || true
done
install -d \"$target/sys/firmware/efi/efivars\"
mount -t efivarfs none \"$target/sys/firmware/efi/efivars\" 2>/dev/null \\
    || log 'no efivarfs: the firmware variables will not be written'
# The new system gets a resolver of its own, because the setup that may follow
# runs inside it and talks to the network.  A machine with no network never got
# one written on the medium, and `install' of a file that is not there - or of a
# dangling symlink into /run, which is what NetworkManager leaves behind -
# stopped the install on the line before GRUB.  Installing with no network is a
# supported thing to do, so the file is written rather than required.
if [ -s /etc/resolv.conf ]; then
    install -D -m 644 /etc/resolv.conf \"$target/etc/resolv.conf\"
else
    printf 'nameserver 1.1.1.1\\nnameserver 9.9.9.9\\n' > \"$target/etc/resolv.conf\"
    log 'the medium has no resolver: the new system carries a public one'
fi
# The connection this install was brought up with is the one the machine will
# want after the reboot, and asking for the wifi password a second time on a
# machine that just typed it is what makes an install feel unfinished.  The
# profiles are the medium's own, copied root-owned and private: a pre-shared key
# lives inside them, which is also why they are not world-readable in either
# system.
if [ -d /etc/NetworkManager/system-connections ]; then
    install -d -m 700 \"$target/etc/NetworkManager/system-connections\"
    copied=''
    for profile in /etc/NetworkManager/system-connections/*.nmconnection; do
        [ -e \"$profile\" ] || continue
        # A profile the medium cannot read is one the new system asks for again,
        # not a reason to stop: this runs after the disk is written and one line
        # before GRUB, and a disk with no boot loader on it is the worse failure.
        if install -m 600 \"$profile\" \"$target/etc/NetworkManager/system-connections/\"; then
            copied=1
        else
            log \"could not copy $profile: the new system will ask for that network again\"
        fi
    done
    [ -z \"$copied\" ] || log 'the network connection this install used travels to the new system'
fi
if [ \"$mode\" = uefi ]; then
    step 'writing the EFI boot loader' \\
        chroot \"$target\" grub-install --target=x86_64-efi --efi-directory=/boot/efi \\
        --bootloader-id=<bootloader_id> \\
        || die 'grub-install could not write the EFI binary: check that this machine booted from EFI firmware'
else
    step 'writing the boot sector' \\
        chroot \"$target\" grub-install --target=i386-pc \"$disk\" \\
        || die 'grub-install could not write the boot sector'
fi
step 'building the boot menu' chroot \"$target\" grub-mkconfig -o /boot/grub/grub.cfg \\
    || die 'grub-mkconfig could not write the boot menu'
step 'building the initramfs (the slow one)' chroot \"$target\" xbps-reconfigure -fa \\
    || die 'xbps-reconfigure could not build the initramfs'
log 'the boot loader and the initramfs are built for this disk'

phase 'the user'
if [ \"$user_name\" != '<placeholder>' ]; then
    chroot \"$target\" usermod -l \"$user_name\" '<placeholder>'
    chroot \"$target\" groupmod -n \"$user_name\" '<placeholder>'
    chroot \"$target\" usermod -d \"/home/$user_name\" -m \"$user_name\"
fi
# `-c SHA512' is not a preference, and leaving it out is a machine nobody can
# log into.  shadow's chpasswd takes the PAM route unless it is told the crypt
# method, and Void installs its `chage' PAM stack as /etc/pam.d/chpasswd, whose
# password line is `pam_permit': that route returns success without writing
# anything, so the account keeps the locked hash the image built it with and
# every prompt - greetd and the consoles both - refuses every password.  Void's
# own live scripts write their passwords the same way, with `-c SHA512', which
# is also the algorithm Void's `passwd' uses.
printf '%s:%s\\n' \"$user_name\" \"$userpass\" | chroot \"$target\" chpasswd -c SHA512
userpass=\"\"
# Root's the same way, and for the same reason - `-c SHA512' is what makes
# chpasswd write a hash instead of walking the PAM stack that writes nothing.
# The rootfs carries void-mklive's published `voidlinux'; this replaces it, so
# the machine's root account is one only the person who installed it can use.
printf '%s:%s\\n' root \"$rootpass\" | chroot \"$target\" chpasswd -c SHA512
rootpass=\"\"
# The desktop's account administers its own machine only if that is the answer
# it gave.  Void's sudoers ships the wheel line commented out, so the group and
# the uncommented rule are the two halves of one permission, and both are
# written here or neither is.  The rule is `%wheel ALL=(ALL) ALL' and not a
# NOPASSWD one: sudo asks for the account's own password, which is what makes
# this an administration right rather than a machine anybody at the keyboard
# can change.
if [ \"$admin\" = yes ]; then
    if [ -f \"$target/etc/sudoers\" ]; then
        sed -i 's|^# %wheel ALL=(ALL) ALL|%wheel ALL=(ALL) ALL|' \"$target/etc/sudoers\"
    else
        log 'no sudoers on this payload: the account is in wheel, and there is no sudo to use it with'
    fi
    chroot \"$target\" usermod -aG wheel,video,audio,input,kvm,plugdev \"$user_name\" || true
else
    # The image builds the account in wheel, and the group's own rule is still
    # commented out: taking it out of the group is what makes the answer real.
    chroot \"$target\" gpasswd -d \"$user_name\" wheel || true
fi
# The desktop is rendered from this tree's settings, read from the account's own
# file as that account: the machine's answers go where the render looks, before
# it runs, or a machine installed in Lisbon becomes a desktop rendered in
# Amsterdam.  The file is the render's own format - the settings module's
# parameters called with the answer - and it is handed to the user with the
# directory that holds it, so the render can read and rewrite it.
#
# The ids are the target's own, read out of its own database: the account was
# renamed inside the chroot a few lines up, so this script cannot resolve the
# name it has now, and a `chown' by that name would leave the file root's while
# saying nothing about it.
user_id=\"$(chroot \"$target\" id -u \"$user_name\")\"
group_id=\"$(chroot \"$target\" id -g \"$user_name\")\"
# ~/.config goes to the account whole, and not only the one directory this
# phase writes in: the render runs *as* the account and makes a directory per
# surface under it, so a ~/.config this script created as root is a render that
# can write none of them.  That was a real bug here - `install -d' left the
# parent to root and only the leaf was handed over - and it reaches the person
# as a compositor that exits with `error creating config directory
# \"/home/heks/.config/niri\": Permission denied (os error 13)' at their first
# login.
install -d -m 755 \"$target$home/.config/heks-linux\"
cat > \"$target$home/.config/heks-linux/local-settings.scm\" <<EOF
;; heks-linux: the answers heks-install was given for this machine.
(heks-linux-timezone \"$timezone\")
(heks-linux-language \"$locale\")
(heks-linux-keyboard-layout \"$keymap\")
(heks-linux-hostname \"$hostname\")
EOF
chown -R \"$user_id:$group_id\" \"$target$home/.config\" \\
    || die 'the answers are written but cannot be handed to the account: the desktop cannot be rendered for it'
log 'the answers travel to the desktop: timezone, language, keymap, hostname'

phase 'the desktop'
# The stores are not in the image.  Guix and Nix are installed here, on the
# machine that will keep them, and the desktop is rendered with them: that is
# what makes the medium small and the build minutes rather than hours, and it is
# why this phase is the one that needs the network.  With none, it is skipped and
# said so - an install that spends ten minutes watching a download fail looks
# broken rather than offline, and the machine it leaves behind boots all the same.
desktop_ready=0
if network_ready; then
    log \"set the desktop up for $user_name: the two stores, then the render\"
    if chroot \"$target\" /usr/local/bin/heks-setup \"$user_name\"; then
        desktop_ready=1
    else
        log \"the desktop is not set up: boot the machine, switch to a console with Ctrl+Alt+F2, log in and run heks-setup $user_name\"
    fi
else
    log 'no network: the stores and the desktop are set up after the first boot, with heks-setup'
fi

phase 'the extras'
# Every one of them runs through `maak', which lives in the store the phase above
# installs: without it there is nothing to run them with, and saying so is better
# than three commands failing on a missing program.
if [ \"$desktop_ready\" = 0 ]; then
    log 'the extras are skipped: they need the stores heks-setup installs'
else
<extras_dispatch>
fi

phase 'the update'
# The payload is a rootfs built the day the medium was built, and the
# repositories have moved since: the first boot should not be spent fetching the
# packages that already exist, so with a network the whole system is upgraded
# inside the target, once, before anybody is handed a login prompt.  Without one
# it is said and left to heks-setup, because an install that waits on a download
# that cannot happen reads as a broken installer rather than an offline one.
if network_ready; then
    step 'upgrading the new system to what the repositories carry' \\
        chroot \"$target\" xbps-install -Suy --yes \\
        || log 'the new system was not updated: run xbps-install -Suy after booting'
    # An upgrade that replaced the kernel replaced the files the boot menu names,
    # and a menu pointing at a kernel that is no longer there is a machine that
    # does not boot.  Rewriting it costs a second and is the difference between
    # an update and an update the machine survives.
    step 'writing the boot menu again for the kernels the update brought' \\
        chroot \"$target\" grub-mkconfig -o /boot/grub/grub.cfg \\
        || log 'the boot menu may name an older kernel: run grub-mkconfig after booting'
else
    log 'no network: the new system keeps the packages the medium carries'
fi

phase 'done'
sync
umount -R \"$target\" || true
cryptsetup close cryptroot || true
for tree in run dev sys proc; do
    umount -R \"$target/$tree\" 2>/dev/null || true
done
# The console coming back after the last box reads as a failure; the next step is
# the power-off (and the medium out), so the last screen is a question.
if ui_yesno \"Heks GNU/Linux is installed on $disk.

Firmware:    $mode
Hostname:    $hostname
User:        $user_name
Also:        ${extras:-nothing else}

Remove the medium before starting the machine again: the passphrase is asked
once, by the initramfs.
If the desktop was not set up here: boot it, press Ctrl+Alt+F2 for a console,
log in as $user_name and run heks-setup $user_name.
The whole install is recorded in $LOG.

Power the machine off now?\"; then
    poweroff || log 'the machine did not power off: shut it down from the console'
fi
}

# --- the entry point ----------------------------------------------------------
# One program, one way in: the answers are asked in the order the questions list
# names, and the work follows them.  Nothing above this line touches a disk.
main() {
ask_welcome
main_menu
ask_mode
ask_disk
type_confirm \"$disk\" || { log 'not confirmed: nothing was written'; exit 0; }
ask_network
ask_passphrase
ask_timezone
ask_locale
ask_keymap
ask_identity
ask_admin
ask_rootpass
ask_extras
ask_summary
work
}
")

(define (installer-size-label mib)
  "Return @var{mib} as the summary counts it: whole GiB where it is one."
  (if (and (positive? mib) (zero? (remainder mib 1024)))
    (format #f "~a GiB" (quotient mib 1024))
    (format #f "~a MiB" mib)))

(define (installer-disk-case)
  "Return the shell @code{case} that runs @var{mode}'s layout for the chosen mode.

Both layouts are in the one script, selected by the answer the firmware and the
person gave: UEFI's ESP and GPT on one arm, MBR's boot flag and DOS label on the
other, and no arm for a mode that does not exist."
  (string-append
   "case \"$mode\" in\n"
   (string-join
    (map (lambda (mode)
           (format #f "~a)\n~a\n    ;;"
                   mode
                   (string-join
                    (map (lambda (line) (string-append "    " line))
                         (installer-mount-commands mode))
                    "\n")))
         (installer-boot-modes))
    "\n")
   "\n    *) die \"unknown boot mode $mode\" ;;\nesac"))

(define* (installer-fill template #:key (values '()))
  "Return @var{template} with every @code{<name>} in @var{values} replaced.

The wizard is written as the shell it is, with the pieces the plan computes
left as markers: a template somebody can read as a script is worth more than a
script assembled from thirty `format' calls, and the spec reads the filled
result either way."
  (fold (lambda (entry filled)
          (string-replace-substring filled
                                    (format #f "<~a>" (car entry))
                                    (cdr entry)))
        template
        values))

(define (installer-script)
  "Return @file{heks-install}: the wizard, as one shell script.

The plan and the questions are rendered into it rather than left to a second
implementation, so the disk this script lays out is the disk the spec read."
  (let ((placeholder (image-user))
        (uuids '((root . "$root_uuid") (boot . "$boot_uuid"))))
    (string-append
     (format #f "#!/bin/bash
# ====== Heks-Linux installer ======
#
# auto-generated file, DO NOT EDIT!
#
# One disk, encrypted, erased, and the desktop this medium carries on it.

# -E as well as -e: the phases are a function, and bash does not carry an ERR
# trap into a function without errtrace - the failure would exit silently,
# which is the one thing this script must not do.
set -eEuo pipefail

LOG=~a
install -d -m 755 \"$(dirname \"$LOG\")\"
touch \"$LOG\"

log() { printf '[heks-install] %s\\n' \"$*\" | tee -a \"$LOG\"; }
# The phases are numbered, so a person reading the screen knows how far along
# the install is even though dialog cannot draw a progress bar while a command
# holds the console.
steps=0
phase() {
    steps=$((steps + 1))
    log ''
    log \"========== phase $steps: $* ==========\"
}
# step DESCRIPTION COMMAND [ARGUMENT ...]: say what is about to run, run it, and
# say how long it took.  The failure message is the caller's - wrap the call in
# `|| die ...' - because what a failed command means is written where that
# command is, not in here.
step() {
    local description=\"$1\" started status
    shift
    log \"  .. $description\"
    started=$SECONDS
    \"$@\"
    status=$?
    log \"  ok $description ($((SECONDS - started))s)\"
    return $status
}
# A failure is said twice over.  On stderr, because stdout may be a command
# substitution holding an answer and a message written into that is swallowed;
# and on the screen, because a wizard that vanishes leaves a person with a login
# prompt and half a disk, with nothing to say what happened.  The screen waits
# for the acknowledgement, so the last thing on the console is the failure.
die() {
    log \"FAILED: $*\" >&2
    log \"the whole record is $LOG\" >&2
    if command -v ui_msg >/dev/null 2>&1; then
        ui_msg \"The install stopped.

$*

Nothing after this point ran, and ${disk:-the disk} may be half written.  The
whole record is $LOG: read it, then run heks-install again.\" >/dev/null || true
    fi
    exit 1
}
trap 'die \"line $LINENO: $BASH_COMMAND\"' ERR

target=~a
placeholder_user=~a
payload=~a

if [ \"$(id -un)\" != root ]; then
    echo 'heks-install partitions a disk and writes another system: run it as root' >&2
    exit 1
fi

# One wizard at a time.  The medium starts this on the console and offers it
# again from its window, and two of them on one machine is a partition table
# written under the other's feet - the filesystems, the LUKS header and the
# tarball unpack all happen after the confirmation, and none of it is guarded by
# anything else.
exec 9>~a
flock -n 9 || die 'another heks-install is already running'

# Which firmware this machine booted from decides the mode it starts on.
if [ -d /sys/firmware/efi ]; then
    default_mode=uefi
    other_mode=mbr
else
    default_mode=mbr
    other_mode=uefi
fi

# How expensive the passphrase may be is a question about this machine, not about
# the layout: Argon2id locking a gibibyte of memory is right on a workstation and
# is a machine that cannot boot when its initramfs has to allocate that much on a
# laptop with two.  The answer is the most this machine can afford, up to the
# cost the plan asks for, and it is logged so the value is never a mystery.
pbkdf_limit=~a
mem_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo 2>/dev/null || echo 0)
if [ \"${mem_kb:-0}\" -ge 4194304 ]; then
    pbkdf_memory=$pbkdf_limit
elif [ \"${mem_kb:-0}\" -ge 2097152 ]; then
    pbkdf_memory=524288
else
    pbkdf_memory=262144
fi

mode_label() {
    case \"$1\" in
        uefi) printf 'UEFI (recommended)\\n' ;;
        mbr) printf 'Legacy MBR (no EFI firmware)\\n' ;;
        *) printf '%s\\n' \"$1\" ;;
    esac
}

partition_summary() {
    if [ \"$mode\" = uefi ]; then
        printf 'ESP <esp_size>, /boot <boot_size> ext4, rest LUKS2 + BTRFS'
    else
        printf '/boot <boot_size> ext4, rest LUKS2 + BTRFS'
    fi
}
"
             (installer-log)
             (installer-target)
             placeholder
             (format #f "~a/~a-~a-rootfs.~a.tar.xz"
                     (installer-payload-dir) image-name (image-version)
                     (xbps-arch))
             (installer-lock)
             (installer-pbkdf-memory))
     (installer-fill
      (string-append (installer-careful-lines)
                     (installer-questions-lines)
                     "\n"
                     (installer-run-lines))
      #:values
      (list (cons 'mount_commands (installer-disk-case))
            (cons 'extras_checklist (installer-extras-checklist))
            (cons 'extras_dispatch (installer-extras-dispatch))
            (cons 'clone_commands (installer-clone-commands))
            (cons 'theme (format #f "~a/~a" (image-share-dir)
                                 (image-dialog-theme-filename)))
            (cons 'esp_size (installer-size-label (installer-esp-size)))
            (cons 'boot_size (installer-size-label (installer-boot-size)))
            (cons 'fstab (installer-fstab 'mbr uuids))
            (cons 'esp_fstab (installer-esp-fstab-line "$esp_uuid"))
            (cons 'cmdline (installer-grub-cmdline #:luks "$luks_uuid"
                                                   #:root "$root_uuid"))
            (cons 'dracut (installer-dracut-conf))
            (cons 'bootloader_id (installer-bootloader-id))
            (cons 'placeholder placeholder)
            ;; The clock and the language start at the ones the desktop
            ;; declares: the wizard and the render that follows it read the
            ;; answer from one place, and a machine that changed its mind here
            ;; has one file to change there.
            (cons 'timezone (heks-linux-timezone))
            (cons 'locale (heks-linux-language))
            (cons 'keymap (heks-linux-keyboard-layout))))
     ;; The medium runs this file; the spec's fake disk sources it, and a
     ;; sourced file that runs the questions would be answering them from the
     ;; test's own stdin.  Entering through `main' is what makes it a program.
     "
if [ \"${BASH_SOURCE[0]}\" = \"$0\" ]; then
    main \"$@\"
fi
")))

;; ===========================================
;; Writing it
;; ===========================================

(define* (install-installer-config #:key (dir (image-payload-dir)))
  "Write @file{heks-install} into @var{dir} and return the path.

It is written executable: the medium runs it as root, and the rootfs build
installs the same file into @file{/usr/local/bin}."
  (ensure-directory-tree! dir)
  (install-config-file! #:name (installer-script-filename)
                        #:dir dir
                        #:contents (installer-script)
                        #:perms 493)
  (format #f "~a/~a" dir (installer-script-filename)))
