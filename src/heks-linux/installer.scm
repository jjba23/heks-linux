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
  #:use-module (heks-linux platform)
  #:use-module (heks-linux prelude)
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
root, with the subvolume it lives on."
  (format #f
          "rd.luks.uuid=~a root=UUID=~a rootflags=subvol=@,compress=zstd,noatime rw"
          luks root))

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
         (layout
          (if (installer-efi? mode)
            (list "parted -s \"$disk\" mklabel gpt"
                  (format #f "parted -s \"$disk\" unit MiB mkpart ESP fat32 ~a ~a"
                          esp-start esp-end)
                  (format #f "parted -s \"$disk\" unit MiB mkpart boot ext4 ~a ~a"
                          boot-start boot-end)
                  (format #f "parted -s \"$disk\" unit MiB mkpart root ~a 100%"
                          root-start)
                  "parted -s \"$disk\" set 1 esp on"
                  "mkfs.vfat -F32 -n EFI \"$esp_part\""
                  "mkfs.ext4 -L boot \"$boot_part\"")
            (list "parted -s \"$disk\" mklabel msdos"
                  (format #f "parted -s \"$disk\" unit MiB mkpart primary ext4 ~a ~a"
                          boot-start boot-end)
                  (format #f "parted -s \"$disk\" unit MiB mkpart primary ~a 100%"
                          root-start)
                  "parted -s \"$disk\" set 1 boot on"
                  "mkfs.ext4 -L boot \"$boot_part\""))))
    (append
     (list
      ;; A disk that held something is not a disk that is empty: the old
      ;; signatures survive a rewrite of the table and confuse blkid later.
      "wipefs -a \"$disk\""
      "swapoff -a || true")
     layout
     (list "partprobe \"$disk\""
           "udevadm settle || true"
           ;; The key comes from a file, never from the command line: `ps' is
           ;; world-readable, and a passphrase in argv is on the record.
           "cryptsetup luksFormat --type luks2 --pbkdf argon2id \\"
           "    --pbkdf-memory \"$pbkdf_memory\" --pbkdf-parallel 4 \\"
           "    --key-file \"$keyfile\" \"$root_part\""
           "cryptsetup open --key-file \"$keyfile\" \"$root_part\" cryptroot"
           "shred -u \"$keyfile\""
           "mkfs.btrfs -L heks /dev/mapper/cryptroot"
           "mount /dev/mapper/cryptroot \"$target\"")
     ;; The subvolumes come from one list, so what is created here is what
     ;; fstab mounts and what the summary promises.
     (map (lambda (subvolume)
            (format #f "btrfs subvolume create \"$target/~a\""
                    (first subvolume)))
          (installer-subvolumes))
     (list "umount \"$target\""
           ;; The mountpoints have to exist before anything is mounted on
           ;; them, and /boot goes on before /boot/efi: the ESP lives inside
           ;; the boot partition, so mounting them the other way round hides
           ;; the ESP under an empty directory.
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
                            (append (list "\"$target/boot\"")
                                    (if (installer-efi? mode)
                                      (list "\"$target/boot/efi\"")
                                      '())))
                    " "))
           "mount \"$boot_part\" \"$target/boot\"")
     (if (installer-efi? mode)
       (list "mount \"$esp_part\" \"$target/boot/efi\"")
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
otherwise is not a friendly wizard."
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
given by accident.  The rest are the screen the questions are asked on, and they
fall back to plain prompts on a medium without dialog - a medium that cannot
draw a menu can still install."
  "
# --- the screen ---------------------------------------------------------------
# Every screen wears the same title, so a person scrolling back through a
# terminal knows which program asked.
backtitle='Heks GNU/Linux installer'
ui=dialog
command -v dialog >/dev/null 2>&1 || ui=plain

ui_msg() {
    if [ \"$ui\" = dialog ]; then
        dialog --stdout --backtitle \"$backtitle\" --title 'Heks GNU/Linux' --msgbox \"$1\" 0 0
    else
        printf '\\n%s\\n\\n' \"$1\"
        read -r -p 'press enter to continue ' _ || true
    fi
}

ui_yesno() {
    if [ \"$ui\" = dialog ]; then
        dialog --backtitle \"$backtitle\" --title 'Heks GNU/Linux' --yesno \"$1\" 0 0
    else
        local answer
        read -r -p \"$1 [y/N] \" answer || return 1
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
        printf '\\n%s\\n%s\\n\\n' \"$title\" \"$prompt\"
        while [ \"$#\" -gt 0 ]; do
            tag=\"$1\" label=\"$2\"
            shift 2
            printf '  %s) %s\\n' \"$tag\" \"$label\"
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
        printf '\\n%s\\n%s\\n\\n' \"$title\" \"$prompt\"
        while [ \"$#\" -gt 0 ]; do
            tag=\"$1\" label=\"$2\" state=\"$3\"
            shift 3
            printf '  %s) [%s] %s\\n' \"$tag\" \"$state\" \"$label\"
            if [ \"$state\" = on ]; then
                defaults=\"$defaults $tag\"
            fi
        done
        read -r -p 'keep which? (tags separated by spaces, empty for the defaults) ' chosen \\
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
        printf '\\n%s\\n' \"$2\"
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
        printf '\\n'
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

# One menu entry is one keystroke away from the wrong disk; the name is the one
# answer that cannot be given by accident.
type_confirm() {
    local wanted=\"$1\" answer
    answer=\"$(ui_input \"Erase $wanted\" \\
        \"This ERASES $wanted and everything on it: the partition table, every filesystem and the data in them.  Type ERASE to continue.\" \"\")\" || return 1
    [ \"$answer\" = ERASE ]
}
")

(define (installer-questions-lines)
  "Return the questions, in the order the wizard asks them.

Everything with a default is a default; the disk, the passphrase, the machine's
name and the user's are the four answers a person has to give."
  "
# --- the questions ------------------------------------------------------------
mode=\"$default_mode\"
disk=\"\"
hostname=\"heks-linux\"
user_name=\"<placeholder>\"
passphrase=\"\"
userpass=\"\"
extras=''
home=''

# The first screen is not a question: it says what this is, what it will do and
# what it cannot undo.
ask_welcome() {
    ui_msg \"Install Heks GNU/Linux on this machine.

It asks six things - the disk, the firmware, the disk passphrase, the host name,
the user and its password - and then writes one encrypted BTRFS system on the
disk you chose.

The disk is ERASED: everything on it goes.
The passphrase is asked once, at boot, by the initramfs.
The account is the one the desktop was rendered for, renamed.

After the disk is written it installs the two stores the desktop runs on - guix
and nix, a few gigabytes - and renders the desktop for your account.  That needs
the network; without it the machine boots and heks-setup finishes the job later.

The medium can also leave the new system ready with the rest of the projects,
the package sets and the editor, if you want them - that list comes before
anything is written.

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
    choice=\"$(ui_menu 'Firmware' \\
        \"This machine booted from $default_mode.  The disk is laid out for the firmware it booted from.\" \\
        \"$default_mode\" \"$(mode_label \"$default_mode\")\" \\
        \"$other_mode\" \"$(mode_label \"$other_mode\")\")\" || die 'cancelled'
    mode=\"$choice\"
}

ask_disk() {
    local tag disks line choice size_gib
    disks=\"\"
    while read -r line; do
        [ -n \"$line\" ] || continue
        if is_target_disk \"$line\"; then
            log \"refuse the disk this medium runs from: $line\"
            continue
        fi
        tag=\"$(basename \"$line\")\"
        disks=\"$disks $tag $line\"
    done <<EOF
$(lsblk -dpno NAME)
EOF
    if [ -z \"$disks\" ]; then
        die 'no disk to install on: attach one, or free the one this medium runs from'
    fi
    # A disk too small is not a choice, it is a trap: the encrypted layout needs
    # room for the system before there is room for anything of yours.  Asking
    # again costs one screen; finding out two minutes into the copy costs the
    # installer and the disk.
    while :; do
        # shellcheck disable=SC2086
        choice=\"$(ui_menu 'Disk' \\
            'The whole disk is used: everything on it is erased.' \\
            $disks)\" || die 'cancelled'
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

ask_passphrase() {
    local first second
    while :; do
        first=\"$(ui_password 'Encryption' \\
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

ask_identity() {
    local first second
    hostname=\"$(ui_input 'Hostname' \\
        'The name this machine answers to.' \"$hostname\")\" || die 'cancelled'
    user_name=\"$(ui_input 'User' \\
        'The account the desktop was rendered for.' \"$placeholder_user\")\" \\
        || die 'cancelled'
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

# The extras are one screen: space toggles, Enter accepts, and the defaults are
# the ones the next phase can do without pulling a gigabyte.
ask_extras() {
    extras=\"$(ui_checklist 'After the disk' \\
        \"What else should the new system be ready with?

The first is the cheap one; the two below it pull from the network, and the
account's password is asked again by sudo while they run.\" \\
        <extras_checklist>)\" || extras='' 
}

ask_summary() {
    local network_note=''
    if ! ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        network_note='
No network here: the desktop is set up after booting, with heks-setup.'
    fi
    ui_yesno \"Install to $disk?

Firmware:    $mode
Partitions:  $(partition_summary)
Hostname:    $hostname
User:        $user_name
Encryption:  LUKS2, BTRFS inside it
Also:        ${extras:-nothing else}$network_note

Everything on $disk is destroyed.\" || exit 0
}
")

(define (installer-run-lines)
  "Return the phases that carry the answers out."
  "
# --- the work -----------------------------------------------------------------
ask_welcome
main_menu
ask_mode
ask_disk
type_confirm \"$(basename \"$disk\")\" || { log 'not confirmed: nothing was written'; exit 0; }
ask_passphrase
ask_identity
ask_extras
ask_summary

log \"installing on $disk ($mode)\"

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
tar -xpf \"$payload\" -C \"$target\"
log 'the installed system is unpacked'

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
GRUB_DISABLE_OS_PROBER=true
EOF
install -d \"$target/etc/dracut.conf.d\"
cat > \"$target/etc/dracut.conf.d/10-crypt.conf\" <<EOF
<dracut>
EOF
printf '%s\\n' \"$hostname\" > \"$target/etc/hostname\"
log 'fstab, the kernel command line and the initramfs are written'

phase 'the bootloader'
for tree in proc sys dev run; do
    mount --rbind \"/$tree\" \"$target/$tree\" 2>/dev/null || true
done
install -d \"$target/sys/firmware/efi/efivars\"
mount -t efivarfs none \"$target/sys/firmware/efi/efivars\" 2>/dev/null \\
    || log 'no efivarfs: the firmware variables will not be written'
install -D -m 644 /etc/resolv.conf \"$target/etc/resolv.conf\"
if [ \"$mode\" = uefi ]; then
    chroot \"$target\" grub-install --target=x86_64-efi --efi-directory=/boot/efi \\
        --bootloader-id=<bootloader_id> \\
        || die 'grub-install could not write the EFI binary: check that this machine booted from EFI firmware'
else
    chroot \"$target\" grub-install --target=i386-pc \"$disk\" \\
        || die 'grub-install could not write the boot sector'
fi
chroot \"$target\" grub-mkconfig -o /boot/grub/grub.cfg
chroot \"$target\" xbps-reconfigure -fa
log 'the boot loader and the initramfs are built for this disk'

phase 'the user'
if [ \"$user_name\" != '<placeholder>' ]; then
    chroot \"$target\" usermod -l \"$user_name\" '<placeholder>'
    chroot \"$target\" groupmod -n \"$user_name\" '<placeholder>'
    chroot \"$target\" usermod -d \"/home/$user_name\" -m \"$user_name\"
fi
printf '%s:%s\\n' \"$user_name\" \"$userpass\" | chroot \"$target\" chpasswd
userpass=\"\"
# The desktop's account administers its own machine: Void's sudoers ships the
# wheel line commented out, and an installer that forgets it leaves a system
# nobody can configure.
if [ -f \"$target/etc/sudoers\" ]; then
    sed -i 's|^# %wheel ALL=(ALL) ALL|%wheel ALL=(ALL) ALL|' \"$target/etc/sudoers\"
fi
chroot \"$target\" usermod -aG wheel,video,audio,input,kvm,plugdev \"$user_name\" || true

phase 'the desktop'
# The stores are not in the image.  Guix and Nix are installed here, on the
# machine that will keep them, and the desktop is rendered with them: that is
# what makes the medium small and the build minutes rather than hours, and it is
# why this phase needs the network.
log \"set the desktop up for $user_name: the two stores, then the render\"
desktop_ready=1
chroot \"$target\" /usr/local/bin/heks-setup \"$user_name\" \\
    || { desktop_ready=0; log \"the desktop is not set up: boot the machine, switch to a console with Ctrl+Alt+F2, log in and run heks-setup $user_name\"; }

phase 'the extras'
# Every one of them runs through `maak', which lives in the store the phase above
# installs: without it there is nothing to run them with, and saying so is better
# than three commands failing on a missing program.
if [ \"$desktop_ready\" = 0 ]; then
    log 'the extras are skipped: they need the stores heks-setup installs'
else
<extras_dispatch>
fi

phase 'done'
sync
umount -R \"$target\" || true
cryptsetup close cryptroot || true
for tree in run dev sys proc; do
    umount -R \"$target/$tree\" 2>/dev/null || true
done
ui_msg \"Heks GNU/Linux is installed on $disk.

Firmware:    $mode
Hostname:    $hostname
User:        $user_name
Also:        ${extras:-nothing else}

Remove the medium and reboot: the passphrase is asked once, by the initramfs.
If the desktop was not set up here: boot it, press Ctrl+Alt+F2 for a console,
log in as $user_name and run heks-setup $user_name.
The whole install is recorded in $LOG.\"
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

set -euo pipefail

LOG=~a
install -d -m 755 \"$(dirname \"$LOG\")\"
touch \"$LOG\"

log() { printf '[heks-install] %s\\n' \"$*\" | tee -a \"$LOG\"; }
phase() { log ''; log \"========== $* ==========\"; }
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
exec 9>/run/heks-install.lock
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
            (cons 'esp_size (installer-size-label (installer-esp-size)))
            (cons 'boot_size (installer-size-label (installer-boot-size)))
            (cons 'fstab (installer-fstab 'mbr uuids))
            (cons 'esp_fstab (installer-esp-fstab-line "$esp_uuid"))
            (cons 'cmdline (installer-grub-cmdline #:luks "$luks_uuid"
                                                   #:root "$root_uuid"))
            (cons 'dracut (installer-dracut-conf))
            (cons 'bootloader_id (installer-bootloader-id))
            (cons 'placeholder placeholder))))))

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
