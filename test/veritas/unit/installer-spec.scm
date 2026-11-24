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
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 format)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 textual-ports)
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

(define (mkpart-lines mode)
  "Return the @code{parted} lines that create a partition of @var{mode}'s disk."
  (filter (lambda (line) (contains? line "mkpart"))
          (installer-mount-commands mode)))

(define (last-mkpart mode)
  "Return the @code{parted} line that creates @var{mode}'s last partition."
  (let ((lines (mkpart-lines mode)))
    (list-ref lines (- (length lines) 1))))

;; --- the fake disk ----------------------------------------------------------
;;
;; Everything above reads the rendered strings.  What follows *runs* them:
;; `test/installer/fake-disk.sh' sources the rendered script with the disk tools
;; stubbed and a directory standing in for each device, sets the answers a person
;; would have typed, and calls the phases.  The failures a real disk gives - a
;; partition the kernel has not been told about, a mountpoint hidden under the
;; mount above it - are failures here, without root and without a disk.
;;
;; Each mode gets a directory of its own, and the install runs once per mode:
;; `install-result' remembers the answer, so the cases can ask what happened
;; without installing a second time.

(define (find-bash)
  "Return the bash this environment can run.

The suite runs in a Guix container, where @file{/usr/bin/env} is not there: a
script whose shebang names it cannot start, so bash is spelled out from
@env{PATH} like the capture spec does."
  (let loop ((dirs (string-split (or (getenv "PATH") "") #\:)))
    (cond [(null? dirs) "bash"]
          [(file-exists? (string-append (car dirs) "/bash"))
           (string-append (car dirs) "/bash")]
          [else (loop (cdr dirs))])))

(define (scratch-of mode)
  "Return the directory a fake install of @var{mode} writes everything in."
  (format #f "/tmp/heks-installer-~a-~a" (getpid) mode))

(define (install-run mode)
  "Run @var{mode}'s install on the fake disk, and return @code{(STATUS . OUTPUT)}.

@var{output} is everything the run printed, stderr folded in: the mount lines in
the order they were mounted, the commands run inside the new system, and the
sentence a failure gave.  The script is rendered with every path under the
scratch directory, so nothing outside it is written to."
  (let* ((dir (scratch-of mode))
         (script (format #f "~a/heks-install" dir))
         (answers (format #f "~a/answers" dir)))
    ;; A scratch directory left by an earlier run - of this process or of one
    ;; whose pid this one has been given - is a fake disk with partitions
    ;; already on it and a target tree half written.  The run starts from
    ;; nothing every time, which is also what a real medium does.
    (system* "rm" "-rf" dir)
    (false-if-exception (mkdir dir))
    (call-with-output-file script
                           (lambda (port)
                             (parameterize ((installer-target (format #f "~a/target" dir))
                                            (installer-log (format #f "~a/heks-install.log" dir))
                                            (installer-lock (format #f "~a/heks-install.lock" dir))
                                            (installer-payload-dir (format #f "~a/payload" dir)))
                               (display (installer-script) port))))
    ;; A blank line per screen that only says something and waits for a key: the
    ;; run enters at the phases, so no question consumes these.
    (call-with-output-file answers
                           (lambda (port) (display "\n\n\n" port)))
    (let* ((port (open-input-pipe
                  (format #f "~a test/installer/fake-disk.sh ~a ~a ~a ~a 2>&1"
                          (find-bash) script mode dir answers)))
           (output (get-string-all port))
           (status (close-pipe port)))
      (cons (status:exit-val status) output))))

(define install-runs (make-hash-table))

(define (install-result mode)
  "Return @var{mode}'s install run, running it once and remembering it."
  (or (hash-ref install-runs mode)
    (let ((result (install-run mode)))
      (hash-set! install-runs mode result)
      result)))

(define (exit-status mode)
  "Return the exit status of @var{mode}'s fake install."
  (car (install-result mode)))

(define (output-of mode)
  "Return everything @var{mode}'s fake install printed."
  (cdr (install-result mode)))

(define (line-position mode needle)
  "Return the position of the first line of @var{mode}'s run holding @var{needle}.

This is how a case says what was done in what order: where the boot partition was
mounted, against where the ESP inside it was, against where GRUB ran."
  (list-index (lambda (line) (contains? line needle))
              (string-split (output-of mode) #\newline)))

(define (installed-file mode path)
  "Return what @var{path} holds inside @var{mode}'s installed system."
  (call-with-input-file (format #f "~a/target/~a" (scratch-of mode) path)
                        get-string-all))

(define (installed-link mode path)
  "Return where @var{path} points inside @var{mode}'s installed system."
  (readlink (format #f "~a/target/~a" (scratch-of mode) path)))

(define (step-position mode needle)
  "Return where @var{needle} sits among @var{mode}'s own layout steps."
  (list-index (lambda (step) (contains? step needle))
              (installer-mount-commands mode)))

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
          #:name "Root is the @ subvolume, not the top level")
        (assert-true (contains? cmdline "splash")
          #:name "And the boot screen is asked for, which is what starts plymouth")))

    (test "The Wizard Says What It Is Doing"
      ;; dialog cannot draw a progress bar while a command has the console, so
      ;; the line before a command is what tells a person the install is not
      ;; hung - and it is the line that ends up in the log they read afterwards.
      (let ((script (script)))
        (assert-true (contains? script "steps=$((steps + 1))")
          #:name "The phases are numbered as they are entered")
        (assert-true (contains? script "step()")
          #:name "One helper announces a command, runs it and times it")
        (for-each (lambda (what)
                    (assert-true (contains? script (string-append "step '" what))
                      #:name (string-append what " is announced")))
                  '("unpacking the installed system"
                    "creating the encrypted volume"
                    "making the filesystem"
                    "writing the EFI boot loader"
                    "building the boot menu"
                    "building the initramfs")))
      (assert-true (contains? (script) "hostname: $hostname")
        #:name "The answers are written down before the disk is touched"))

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

(define (localization-suite)
  (suite "The clock and the language"
    (test "The Wizard Asks For The Timezone And The Locale"
      ;; The payload carries the values the image was built with, which is one
      ;; machine's answer given to every machine.  These two are asked, and both
      ;; are checked against what the system actually has: a typo here is a clock
      ;; that is wrong and programs with no language, and neither says anything
      ;; until the machine is installed and booted.
      (let ((script (script)))
        (assert-true (contains? script "ask_timezone")
          #:name "There is a question for the timezone")
        (assert-true (contains? script "ask_locale")
          #:name "And one for the language")
        (assert-true (contains? script "/usr/share/zoneinfo/$answer")
          #:name "The answer is checked against the zone database before it is taken")
        (assert-true (contains? script "/usr/share/zoneinfo/$timezone")
          #:name "And the clock is a link into that database")
        (assert-true (contains? script "target/etc/locale.conf")
          #:name "The language is written where the system reads it")))

    (test "The Machine's Answers Are Asked Before The Disk Is Written"
      ;; After the encryption, before the account: the disk's answers first, then
      ;; the machine's - clock, language, keyboard - then the person's.
      (assert-true (not (eq? #f (string-contains (script)
                                                 "ask_passphrase
ask_timezone
ask_locale
ask_keymap
ask_identity")))
        #:name "They sit between the passphrase and the account"))

    (test "The Defaults Are The Ones The Desktop Declares"
      ;; One place for the machine's own settings: a wizard that invented its own
      ;; default would disagree with the render that runs after it.
      (let ((script (script)))
        (assert-true (contains? script
                                (format #f "timezone='~a'" (heks-linux-timezone)))
          #:name "The timezone default is heks-linux-timezone")
        (assert-true (contains? script
                                (format #f "locale='~a'" (heks-linux-language)))
          #:name "The locale default is heks-linux-language")))

    (test "A Wrong Answer Is Asked For Again, With What Was Expected"
      (let ((script (script)))
        (assert-true (contains? script "is not a timezone")
          #:name "The timezone screen says what the list is")
        (assert-true (contains? script "is not a locale")
          #:name "The locale screen says what a locale name looks like")))

    (test "The Timezone Is A Name, Not A Path"
      ;; The answer becomes a link target inside the new system, so a name that
      ;; could climb out of the zone database is refused by its shape before the
      ;; database is even asked about it.
      (assert-true (contains? (script)
                              "grep -Eq '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$'")
        #:name "The answer has to look like a zone name first"))))

(define (keymap-suite)
  (suite "The keymap"
    (test "The Wizard Asks For The Console Keymap"
      ;; Void reads the console's layout from `KEYMAP' in /etc/rc.conf, and the
      ;; session's from this tree's own settings.  One answer, written where each
      ;; of them looks, so the console and the session cannot disagree.
      (let ((script (script)))
        (assert-true (contains? script "ask_keymap")
          #:name "There is a question for it")
        (assert-true (contains? script "/usr/share/kbd/keymaps")
          #:name "The answer is checked against the keymaps the system carries")
        (assert-true (contains? script "target/etc/rc.conf")
          #:name "It is written where Void reads it")
        (assert-true (contains? script "KEYMAP=")
          #:name "As the variable Void documents")))

    (test "The Keymap Default Is The One The Desktop Declares"
      (assert-true (contains? (script)
                              (format #f "keymap='~a'"
                                      (heks-linux-keyboard-layout)))
        #:name "The default is heks-linux-keyboard-layout"))

    (test "A Layout The System Does Not Carry Is Asked For Again"
      (assert-true (contains? (script) "is not a keymap")
        #:name "The screen says what the list is"))))

(define (safety-suite)
  (suite "What the wizard must not do to a disk"
    (test "The Medium It Runs From Is Never A Target"
      ;; The live system holds its root on the very disk the user is asked to
      ;; choose, so a mistaken answer would erase the medium mid-install.
      (assert-true (contains? (script) "is_target_disk")
        #:name "The script asks whether a disk is the running system's")
      (assert-true (contains? (script) "refuse the disk this medium runs from")
        #:name "It says why it refused"))

    (test "One Installer Runs At A Time"
      ;; The medium starts this on the console and offers it again from its
      ;; window, so two wizards can be asked of one machine at once - and
      ;; everything after the confirmation writes a disk.
      (assert-true (contains? (script) "flock -n")
        #:name "The script takes a lock before it reads a disk")
      (assert-true (let ((lock (string-contains (script) "flock -n"))
                         (disk (string-contains (script) "is_target_disk")))
                     (and lock disk (< lock disk)))
        #:name "And holds it before anything is partitioned"))

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

    (test "A Medium Without Dialog Still Answers Correctly"
      ;; The plain fallbacks drew their menus and prompts on stdout, and every
      ;; caller reads the answer from a command substitution: the chosen tag came
      ;; back as the text of the menu it was chosen from, so a medium without
      ;; dialog answered with the menu it was shown.  The questions go to stderr
      ;; now, and stdout carries the answer alone.
      (let ((script (script)))
        (assert-true (contains? script "printf '\\n%s\\n%s\\n\\n' \"$title\" \"$prompt\" >&2")
          #:name "The menu is drawn on stderr")
        (assert-true (contains? script "printf '%s\\n' \"$choice\"")
          #:name "And stdout carries the chosen tag alone")
        (assert-true (contains? script "printf '\\n%s\\n' \"$2\" >&2")
          #:name "An input box asks on stderr too")))

    (test "The Medium Offers A Menu Before It Erases Anything"
      (assert-true (contains? (script) "menu")
        #:name "The wizard is a menu, not a list of questions")
      (assert-true (contains? (script) "command -v dialog")
        #:name "It uses dialog when the medium carries it")
      (assert-true (contains? (script) "Guided install")
        #:name "The first entry is the guided install"))

    (test "A Menu Is As Tall As The List It Draws"
      ;; dialog's own height gives a two-disk machine one visible row and a
      ;; scroll bar: the disk screen showed one disk and made a person scroll
      ;; for the other.  The list is counted first and asked for as tall as it
      ;; is; dialog still clips it to the screen when the list is longer.
      (assert-true (contains? (script) "rows=$(( $# / 2 ))")
        #:name "The menu counts the tags and labels it was given")
      (assert-true (contains? (script) "--menu \"$prompt\" 0 0 \"$rows\"")
        #:name "and asks for a list that tall")
      (assert-true (not (contains? (script) "--menu \"$prompt\" 0 0 0"))
        #:name "Not for a list of no rows, which dialog fills with a scroll bar")
      (assert-true (contains? (script) "lines=$(( $# / 3 ))")
        #:name "The extras checklist counts its triples the same way"))

    (test "The Number In Every Title Survives The Question"
      ;; A question is asked inside a command substitution - a subshell - and a
      ;; `screen' that echoed its title there would increment a counter the next
      ;; screen never sees, so every question would say 1/9.  The title is set as
      ;; a variable first, and read as one.
      (let ((script (script)))
        (assert-true (contains? script "ui_input \"$screen_title\"")
          #:name "The title is read as a variable, outside the subshell")
        (assert-true (not (contains? script "$(screen"))
          #:name "And the counter is never incremented where nobody sees it")
        (assert-true (contains? script "for asked in $questions")
          #:name "The total is counted from the list, not written beside it")))

    (test "A Failure Is Said Out Loud, Not Swallowed"
      ;; The install stopped on a parted line and the only trace was the log:
      ;; the console came back as a login prompt and the window redrew its
      ;; menu, so a failed install looked like a machine that stopped for no
      ;; reason.  A crash goes to stderr - a command substitution cannot eat it
      ;; - and stays on the screen until it has been read.
      (assert-true (contains? (script) "log \"FAILED: $*\" >&2")
        #:name "The failing command is named on stderr")
      (assert-true (contains? (script) "The install stopped")
        #:name "The screen says the install stopped")
      (assert-true (contains? (script) "$LOG: read it")
        #:name "And where the whole record is")
      (assert-true (contains? (script) "command -v ui_msg")
        #:name "The screen is only asked for once there is one to ask"))))

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

    (test "The Last Partition Ends Where Parted Can Hear It"
      ;; parted parses its own options before its arguments, so a bare `-1' as
      ;; the end of the last partition is read as the option `-1' and the whole
      ;; command is refused before it partitions anything.  The install stopped
      ;; there with two partitions on the disk and nothing else, which is why
      ;; the last end is spelled out as a percentage instead.
      (assert-true (not (any (lambda (line) (contains? line " -1"))
                             (mkpart-lines 'uefi)))
        #:name "No UEFI partition is ended with a bare -1")
      (assert-true (not (any (lambda (line) (contains? line " -1"))
                             (mkpart-lines 'mbr)))
        #:name "Nor is an MBR one")
      (assert-true (string-suffix? "100%" (last-mkpart 'uefi))
        #:name "The UEFI root partition takes the rest of the disk")
      (assert-true (string-suffix? "100%" (last-mkpart 'mbr))
        #:name "And so does the MBR one"))

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
        #:name "Its password is the one the wizard asked for"))

    (test "The Done Screen Offers To Power The Machine Off"
      ;; Handing the console back read as a failed install; the last screen is a
      ;; question, and yes powers the machine off.
      (let ((script (script)))
        (assert-true (contains? script "Power the machine off now?")
          #:name "The last screen is a question, not an acknowledgement")
        (assert-true (contains? script "poweroff || log")
          #:name "Yes powers it off, and a refusal is logged rather than trapped")
        (assert-true (contains? script "Remove the medium")
          #:name "The screen says to remove the medium first")
        (assert-true (contains? script "The whole install is recorded in $LOG")
          #:name "The log path stays on it")
        (assert-true (contains? script "run heks-setup $user_name")
          #:name "And so does the setup fallback")))))

(define (disk-suite)
  (suite "Choosing the disk"
    (test "The Disk Menu Describes The Disk, Not Only Its Name"
      ;; The menu is the one place a person sees these disks before one of them
      ;; is erased, and a row that says nothing but `/dev/sda' is what makes
      ;; somebody pick the wrong one: the same letter names the old spinning
      ;; disk, the new enclosure and the card reader left plugged in.  So the row
      ;; carries what the machine knows - the size, how the disk is attached,
      ;; what it calls itself, the table on it and the filesystems it holds.
      (let ((script (script)))
        (assert-true (contains? script "disk_details()")
          #:name "There is a helper that describes a disk")
        (assert-true (contains? script "lsblk -dno MODEL")
          #:name "The name the disk gives itself is shown")
        (assert-true (contains? script "lsblk -dno TRAN")
          #:name "And how it is attached")
        (assert-true (contains? script "lsblk -dno PTTYPE")
          #:name "And its partition table, so a disk with one is recognisable")
        (assert-true (contains? script "lsblk -rno FSTYPE")
          #:name "And the filesystems it already holds")))

    (test "Every Disk In The Menu Is Described"
      ;; The description is made per disk as the list is built, so the menu
      ;; cannot show a description of one disk against another - a label
      ;; rendered once and repeated would be read as a fact about every row.
      ;;
      ;; And it is one argument.  A description is several words wide - "108 GiB
      ;; sata VBOX HARDDISK msdos ext4" - and a menu built as one long string is
      ;; handed to dialog unquoted, which splits it at every space: the fields
      ;; became tags and labels of their own, and the screen asked a person to
      ;; choose between "loop0", "4" and "GiB" instead of between disks.
      (let ((script (script)))
        (assert-true (contains? script "items+=(\"$tag\" \"$(disk_details \"$line\")\")")
          #:name "The row is the disk's own name and its own details")
        (assert-true (contains? script "\"${items[@]}\")\" || die 'cancelled'")
          #:name "And the menu is given them as arguments, not as one long string")
        (assert-true (not (contains? script "disks=\"$disks"))
          #:name "Nothing builds the menu by gluing words into a string")
        (assert-true (contains? script "Size, bus, model, table")
          #:name "The screen says what the columns are")))

    (test "The Confirmation And The Summary Name The Disk They Will Erase"
      ;; The typed confirmation is the last screen before the table is written,
      ;; and "This ERASES /dev/sda" is worth less than the same sentence with the
      ;; disk's size and contents in it: that is the moment to notice that the
      ;; 476 GiB Samsung is not the 32 GiB stick somebody meant to use.
      (let ((script (script)))
        (assert-true (contains? script "type_confirm \"$disk\"")
          #:name "The confirmation is given the disk, so it can describe it")
        (assert-true (contains? script "details=\"$(disk_details \"$disk\")\"")
          #:name "And names what the disk is before it is erased")
        (assert-true (contains? script "Disk:        $(disk_details \"$disk\")")
          #:name "The summary carries the same description")))))

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
      (assert-equal #:expect '(checkouts packages flatpak emacs)
        #:got (map (lambda (extra)
                     (assq-ref extra 'key))
                   (installer-extras))
        #:name "Checkouts, then the package sets, the Flatpak apps, then Emacs"))

    (test "Only The Cheap And Useful Extras Are On By Default"
      ;; A wizard that starts a one-hour build unless told otherwise is not a
      ;; friendly wizard.
      (assert-true (extra-field 'checkouts 'default?)
        #:name "Cloning the rest of the projects is offered on")
      (assert-true (not (extra-field 'packages 'default?))
        #:name "The workstation package sets are off by default")
      (assert-true (not (extra-field 'flatpak 'default?))
        #:name "The Flatpak applications are off by default")
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

    (test "The Flatpak Extra Hands Over A Machine With The Applications On It"
      ;; The tree declares the Flatpak applications the desktop uses; this extra
      ;; is what puts them there, so a person who wants them does not have to
      ;; boot first and look the task up.
      (assert-true (contains? (extra-field 'flatpak 'command)
                              "maak install-flatpak")
        #:name "It runs the task that registers Flathub and installs them"))

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

    (test "The Stores Are Built On The Machine That Keeps Them"
      ;; The image carries Void and the tools, not guix and nix: the stores are a
      ;; few gigabytes, and a person downloading an installer should not fetch
      ;; them before they have a disk.
      (let ((script (script)))
        (assert-true (contains? script "heks-setup")
          #:name "The setup command is what the phase runs")
        (assert-true (contains? script "heks-setup \"$user_name\"")
          #:name "It is given the account that was created, not the image's")
        (assert-true (not (contains? script "guix-daemon --build-users-group"))
          #:name "The installer does not need to start the stores itself")))

    (test "The Extras Wait For The Stores They Run Through"
      ;; Every extra is a `maak' task, and maak arrives with the store the setup
      ;; installs: without it there is nothing to run them with.
      (let ((script (script)))
        (assert-true (contains? script "desktop_ready")
          #:name "The setup reports whether it finished")
        (assert-true (contains? script "the extras are skipped")
          #:name "And the extras say so instead of failing three times")))

    (test "Every Screen Says Which Installer It Is"
      (assert-true (contains? (script) "--backtitle")
        #:name "The wizard is titled on every screen")
      (assert-true (contains? (script) "Heks GNU/Linux")
        #:name "And names the thing being installed"))))

(define (run-suite)
  (suite "The install, run against a disk that does not exist"
    (test "Both Firmwares Install Through To The Done Screen"
      ;; The phases are shell, and shell that names a device that is not there,
      ;; or a mountpoint that was hidden, stops at that line.  This is the whole
      ;; install, run: the table, the container, the unpacking, the boot loader,
      ;; the account and the extras, with the disk tools stubbed.
      (assert-equal #:expect 0
        #:got (exit-status 'uefi)
        #:name "The UEFI install runs from the first phase to the last")
      (assert-equal #:expect 0
        #:got (exit-status 'mbr)
        #:name "And so does the MBR one"))

    (test "The ESP Is Mounted Before GRUB Writes To It"
      ;; Two ordering failures took installs down and both are this shape:
      ;; /boot/efi lives inside /boot, so an ESP mountpoint made before the boot
      ;; partition is mounted is gone the moment /boot is mounted over it - the
      ;; mount under it then fails with "mount point does not exist" - and GRUB's
      ;; EFI binary has nowhere to go until the ESP is there.  The device numbers
      ;; say which order this is: vda1 is the ESP, vda2 the boot partition.
      (assert-true (< (line-position 'uefi "mount /dev/vda2 ")
                      (line-position 'uefi "mount /dev/vda1 "))
        #:name "The boot partition is mounted before the ESP inside it")
      (assert-true (< (line-position 'uefi "mount /dev/vda1 ")
                      (line-position 'uefi "chroot grub-install"))
        #:name "And the ESP is mounted before GRUB is installed into it")
      (assert-equal #:expect #f
        #:got (line-position 'mbr "/boot/efi")
        #:name "An MBR disk mounts no ESP at all"))

    (test "The Partitions Are Probed Before Anything Formats Them"
      ;; `parted' writes a table the kernel has not read: /dev/vda1 does not
      ;; exist until something asks it to, and formatting before that probe is
      ;; "no such device or address" on the ESP with the table already written.
      ;; The order is read off the plan, and the run above is where a disk
      ;; enforces it: the fake disk publishes a partition only when it is probed.
      (assert-true (< (step-position 'uefi "mkpart root")
                      (step-position 'uefi "partprobe"))
        #:name "The table is written before the kernel is told about it")
      (assert-true (< (step-position 'uefi "partprobe")
                      (step-position 'uefi "mkfs.vfat"))
        #:name "And the kernel knows the partitions before they are formatted")
      (assert-true (< (step-position 'mbr "mkpart primary")
                      (step-position 'mbr "mkfs.ext4"))
        #:name "An MBR disk is probed before its boot partition is formatted"))

    (test "The Installed System Is Written For The Disk It Found"
      ;; The files the new system boots with are written by the run, from the
      ;; identifiers the disk reported and the answers that were given.
      (assert-true (contains? (installed-file 'uefi "etc/fstab") "/boot/efi")
        #:name "A UEFI fstab mounts the ESP")
      (assert-true (not (contains? (installed-file 'mbr "etc/fstab") "/boot/efi"))
        #:name "An MBR fstab has no ESP to mount")
      (assert-true (contains? (installed-file 'uefi "etc/fstab") "subvol=@home")
        #:name "The subvolumes the layout made are the ones fstab mounts")
      (assert-true (not (contains? (installed-file 'uefi "etc/sudoers")
                                   "# %wheel"))
        #:name "The wheel line is uncommented, so the account can administer")
      (assert-equal #:expect "box\n"
        #:got (installed-file 'uefi "etc/hostname")
        #:name "The hostname is the answer the wizard was given")
      (assert-true (contains? (installed-file 'uefi "etc/default/grub")
                              "rd.luks.uuid=")
        #:name "The kernel command line names the container by UUID")
      (assert-true (contains? (installed-file 'uefi "etc/default/grub")
                              "GRUB_DISTRIBUTOR=\"Heks GNU/Linux\"")
        #:name "And the boot menu names this system, not the distribution under it"))

    (test "The Clock And The Language Are The Answers, Not The Medium's"
      ;; The payload is a rootfs that carries whatever the image was built with.
      ;; The two answers replace it, which is why they are written after the
      ;; unpacking and not by the build.
      (assert-equal #:expect "LANG=en_US.UTF-8\n"
        #:got (installed-file 'uefi "etc/locale.conf")
        #:name "The language the wizard was given is the one the system speaks")
      (assert-equal #:expect "/usr/share/zoneinfo/Europe/Madrid"
        #:got (installed-link 'uefi "etc/localtime")
        #:name "The clock is the timezone the wizard was given"))

    (test "The New System Is Updated Before The Machine Is Handed Over"
      ;; The payload is a rootfs from the day the medium was built, and the
      ;; repositories have moved since.  With a network the whole system is
      ;; upgraded inside the target, before anybody is handed a login prompt;
      ;; without one it is said and left for heks-setup, because an install that
      ;; waits on a download that cannot happen reads as a broken installer.
      (let ((script (script)))
        (assert-true (contains? script "chroot \"$target\" xbps-install -Suy")
          #:name "The upgrade runs inside the installed system")
        (assert-true (contains? script "no network: the new system keeps the packages")
          #:name "Offline it is skipped and said so")
        (assert-true (let ((extras (string-contains script "phase 'the extras"))
                           (update (string-contains script "phase 'the update"))
                           (done (string-contains script "phase 'done")))
                       (and extras update done (< extras update) (< update done)))
          #:name "It runs after the extras and before the last screen"))
      (assert-true (not (eq? #f (line-position 'uefi "xbps-install -Suy")))
        #:name "And the fake install runs it, against the online machine it is"))

    (test "The Console Layout Is The Answer, In Void's Own File"
      ;; Void sources /etc/rc.conf in its runit stages and takes the console's
      ;; keymap from KEYMAP there; the session's layout comes from the tree's
      ;; settings, which is why the same answer is written twice.
      (assert-true (contains? (installed-file 'uefi "etc/rc.conf") "KEYMAP=es")
        #:name "The console's keymap is the one the wizard was given"))

    (test "The Answers Travel To The Desktop The Medium Renders"
      ;; The render reads this tree's settings as the account it renders for, so
      ;; the machine's own answers are written where it looks, before it runs:
      ;; otherwise a machine installed in Lisbon gets a desktop in Amsterdam.
      (assert-equal #:expect
        (string-append
         ";; heks-linux: the answers heks-install was given for this machine.\n"
         "(heks-linux-timezone \"Europe/Madrid\")\n"
         "(heks-linux-language \"en_US\")\n"
         "(heks-linux-keyboard-layout \"es\")\n"
         "(heks-linux-hostname \"box\")\n")
        #:got (installed-file
               'uefi "home/joe/.config/heks-linux/local-settings.scm")
        #:name "The four answers are the settings the render reads")
      (assert-true (< (line-position 'uefi "the answers travel to the desktop")
                      (line-position 'uefi "heks-setup"))
        #:name "And they are there before the render is started"))

    (test "A Hostname And A User Name Are Checked Before They Are Used"
      ;; Both answers become paths, a command line and a file the render reads:
      ;; a quote or a slash in either is an install that stops, or worse.  The
      ;; shapes are the ones the system accepts, checked where they are typed.
      (let ((script (script)))
        (assert-true (contains? script "is not a hostname")
          #:name "The hostname has a shape and a screen that says so")
        (assert-true (contains? script "is not a user name")
          #:name "So does the account's name")))

    (test "The Rendered Script Parses Before A Medium Runs It"
      ;; The wizard is a template before it is a script, and a quoting mistake in
      ;; it is a medium that boots into a syntax error.  `bash -n' is the check
      ;; that costs nothing and finds it.
      (let ((path (format #f "/tmp/heks-install-~a.sh" (getpid))))
        (call-with-output-file path
                               (lambda (port)
                                 (display (installer-script) port)))
        (assert-equal #:expect 0
          #:got (status:exit-val (system* (find-bash) "-n" path))
          #:name "bash reads heks-install without a complaint")))))

(define (offline-suite)
  (suite "Installing with no network"
    (test "A Medium Without A Resolver Still Installs"
      ;; The failure this replaced: `install -D /etc/resolv.conf' on a machine
      ;; that never got one written - no DHCP, so nothing to copy, and
      ;; NetworkManager's symlink into /run points nowhere - stopped the whole
      ;; install one line before GRUB.  Offline is a supported way to install,
      ;; so the file is written rather than required.
      (let ((script (script)))
        (assert-true (contains? script "[ -s /etc/resolv.conf ]")
          #:name "The medium's own resolver is copied only when there is one")
        (assert-true (contains? script "nameserver 1.1.1.1")
          #:name "And the new system is given a resolver when there is not")
        (assert-true (contains? script "the medium has no resolver")
          #:name "Saying so in the record")))

    (test "The Stores Are Skipped, Not Attempted, Without A Network"
      ;; heks-setup fetches a few gigabytes.  On an offline machine every one of
      ;; those fetches fails slowly, so the phase is asked about first: ten
      ;; minutes of failing downloads reads as a broken installer, and the
      ;; machine it leaves behind boots all the same.
      (let ((script (script)))
        (assert-true (contains? script "network_ready")
          #:name "The script asks whether the machine is on the network")
        (assert-true (contains? script "no network: the stores")
          #:name "And says why the desktop is not set up here")
        (assert-true (contains? script "run heks-setup $user_name")
          #:name "Pointing at the command that finishes the job after boot")))

    (test "The Summary Says What An Offline Install Will Not Do"
      (assert-true (contains? (script) "No network here")
        #:name "The answer the person confirms carries the warning"))

    (test "A Connection Is Counted Even Where Ping Is Blocked"
      ;; A hotel or a campus network that drops ICMP is still a network, and the
      ;; question this answers decides whether the stores are fetched.  The
      ;; manager that made the connection knows; ping is the fallback for a
      ;; network something else brought up.
      (assert-true (contains? (script) "nmcli -t -f STATE general")
        #:name "NetworkManager is asked before anything is pinged"))))

(define (network-suite)
  (suite "The network, before the disk is written"
    (test "The Wizard Brings A Network Up Instead Of Asking For A Console"
      ;; Two phases fetch - the stores and the extras - and a laptop whose card
      ;; is fine but unjoined finishes offline whether or not anybody wanted
      ;; that.  The medium carries NetworkManager, so the wizard drives it.
      (let ((script (script)))
        (assert-true (contains? script "ask_network")
          #:name "There is a question for it, and main asks it")
        (assert-true (contains? script "nmcli")
          #:name "It brings the interface up with the manager the medium runs")
        (assert-true (contains? script "device wifi connect")
          #:name "A wireless network is joined, not described")))

    (test "A Machine That Is Already Online Is Not Asked"
      ;; A wired machine gets its lease on its own, and a wizard that stops to
      ;; ask about a network that is already there is a wizard nobody trusts.
      (let ((script (script)))
        (assert-true (contains? script "network_ready; then")
          #:name "The first thing the question does is ask whether it is needed")
        (assert-true (contains? script "the machine is already on the network")
          #:name "And says so in the record")))

    (test "The Interfaces Offered Are The Ones The Machine Has"
      (let ((script (script)))
        (assert-true (contains? script "nmcli -t -f DEVICE,TYPE device status")
          #:name "NetworkManager is asked what it sees")
        (assert-true (and (contains? script "ethernet") (contains? script "wifi"))
          #:name "Wired and wireless are the two kinds offered")))

    (test "An Open Network Is One Screen Shorter"
      ;; Joining without a password is tried first: nothing in the wizard has to
      ;; parse what the network's security field says, and a secured network is
      ;; the one that then asks.
      (let ((script (script)))
        (assert-true (contains? script "device wifi connect \"$ssid\" ifname")
          #:name "The join without a password comes first")
        (assert-true (contains? script "Password for")
          #:name "A secured network is asked for its password")
        (assert-true (contains? script "shortcut: nmcli takes the pre-shared key")
          #:name "And the one place it lands on a command line is written down")))

    (test "A Radio Can Be Off And Still Be There"
      ;; A soft block from the laptop's own key combination looks exactly like a
      ;; machine with no wireless card.
      (assert-true (contains? (script) "rfkill unblock wifi")
        #:name "The wizard unblocks the radio before it scans"))

    (test "The Connection Travels To The Installed System"
      ;; Asking for the wifi password again on a machine that just typed it is
      ;; what makes an install feel unfinished.
      (let ((script (script)))
        (assert-true (contains? script "target/etc/NetworkManager/system-connections")
          #:name "The profiles are copied into the new system")
        (assert-true (contains? script "install -m 600")
          #:name "Root-owned and private, because a pre-shared key lives in them")))

    (test "A Connection That Cannot Be Read Is Said, Not Fatal"
      ;; The copy runs after the disk is partitioned and mounted, so a profile
      ;; the medium cannot read - a file made by a different account, a machine
      ;; whose /etc keeps them private - must not take the install down with it.
      ;; The new system asks for that network again; the disk still gets a boot
      ;; loader.
      (assert-true (contains? (script) "the new system will ask for that network again")
        #:name "The profile is left behind, and the reason is in the record"))))

(define (spec)
  ;; Both installs run before the suite, in this process rather than inside a
  ;; fiber: the runner runs the cases concurrently, and two installs forked from
  ;; the same fiber scheduler wait on each other's pipes.  They run once, and the
  ;; cases read what they left behind.
  (install-result 'uefi)
  (install-result 'mbr)
  (veritas-run (boot-suite) (mount-suite) (localization-suite) (keymap-suite)
    (safety-suite)
    (finish-suite)
    (disk-suite) (extras-suite) (offline-suite) (network-suite) (run-suite)))
