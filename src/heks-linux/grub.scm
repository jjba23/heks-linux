;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The screen a machine draws before any of this tree runs: GRUB, themed in the
;; palette the wizards and the login prompt use, and given the entries a person
;; actually reaches for when something is wrong.
;;
;; Three parts, and each is text in this module rather than a file somebody edits
;; on the machine:
;;
;; @itemize
;; @item the *theme* (@file{/boot/grub/themes/heks/theme.txt}) - a green-on-black
;; menu over the rain in @file{matrix.png}, with the keys named under it, because
;; the one thing a boot menu never says is that @kbd{e} edits an entry and
;; @kbd{c} is a command line;
;; @item @file{/etc/default/grub}, which is the timeout, the theme and the
;; kernel command line the install worked out;
;; @item @file{/etc/grub.d/40_custom}, the entries @code{grub-mkconfig} does not
;; generate: a verbose boot, the splash, a rescue shell, the firmware's own
;; settings, and a screen that says what this system is.
;; @end itemize
;;
;; The theme is text and one picture: GRUB cannot draw a font it does not carry,
;; so the decoration is a bitmap of the same glyphs the rain is made of, drawn
;; once and shipped with the payload.  Nothing here is a copy of a distribution's
;; theme.
;;
;;; Code:

(define-module (heks-linux grub)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:export (grub-theme-name
            grub-theme-dir
            grub-theme-filename
            grub-theme-path
            grub-theme
            grub-background-filename
            grub-background-path
            grub-background-source
            grub-timeout
            grub-distributor
            grub-defaults-path
            grub-defaults
            grub-entries-path
            grub-entries))

;; One word: it is a directory name, a value in @file{/etc/default/grub} and the
;; prefix of every file the theme owns.
(define grub-theme-name
  "heks")

;; The theme lives on /boot, which is outside the encryption in every layout this
;; installer writes, so GRUB can read it before anything has been unlocked.
(define (grub-theme-dir)
  "Return the directory the theme's files are installed in."
  (format #f "/boot/grub/themes/~a" grub-theme-name))

(define (grub-theme-filename)
  "Return the theme's own file, the one @code{GRUB_THEME} names."
  "theme.txt")

(define (grub-theme-path)
  "Return the path @code{GRUB_THEME} points at."
  (format #f "~a/~a" (grub-theme-dir) (grub-theme-filename)))

(define (grub-background-filename)
  "Return the name of the picture the theme draws behind the menu."
  "matrix.png")

(define (grub-background-path)
  "Return the path the picture is installed at, inside the theme's directory."
  (format #f "~a/~a" (grub-theme-dir) (grub-background-filename)))

(define (grub-background-source)
  "Return the picture as this checkout carries it.

It is a @file{.png} of green glyphs on black, 1280x720, with the middle band kept
dark so the menu reads over it: GRUB loads @code{unicode.pf2} and nothing else,
so a background it can draw is a bitmap, and this is the one file in this tree
that is one.  The medium's own GRUB menu uses the same picture, through
void-mklive's splash."
  "resources/grub/matrix.png")

;; Five seconds: long enough to read the menu, short enough that a machine left
;; alone still boots.  A parameter, so a spec can read what the file will say.
(define grub-timeout
  (make-parameter 5))

(define (grub-theme)
  "Return the theme, in GRUB's own theme format.

Every key here is one @code{gfxmenu} reads: the desktop is black with the rain
over it, the title is the system's name in phosphor green, the menu is the same
ink with the selected entry inverted, and two labels under it name the keys -
which is the part a boot menu never says.  A machine whose graphics GRUB cannot
draw on falls back to the text menu, and that is why
@code{GRUB_COLOR_NORMAL} is set in @file{/etc/default/grub} as well."
  "# /boot/grub/themes/heks/theme.txt -- written by Heks-Linux.
#
# Green ink on a black screen, the same palette the wizards, the splash and the
# login prompt use.  The picture is the rain; the band across the middle of it is
# darker so the entries read over it.

desktop-color: \"#000000\"
desktop-image: \"matrix.png\"

title-text: \"HEKS GNU/LINUX\"
title-font: \"Unifont Regular 16\"
title-color: \"#39ff88\"

left: 15%
top: 10%
width: 70%
height: 12%

+ boot_menu {
    left = 22%
    top = 28%
    width = 56%
    height = 46%
    item_font = \"Unifont Regular 16\"
    item_color = \"#39ff88\"
    selected_item_color = \"#001b0b\"
    item_height = 26
    item_spacing = 4
    item_padding = 4
    icon_width = 0
    icon_height = 0
    scrollbar = false
}

+ label {
    left = 0
    top = 84%
    width = 100%
    align = \"center\"
    color = \"#1f7a3d\"
    font = \"Unifont Regular 16\"
    text = \"e edits an entry    c is a command line    m matrix    f firmware    b reboot    p power off\"
}

+ label {
    left = 0
    top = 89%
    width = 100%
    align = \"center\"
    color = \"#14532d\"
    font = \"Unifont Regular 16\"
    text = \"the disk is encrypted: the passphrase is asked once, by the initramfs\"
}

+ label {
    left = 0
    top = 94%
    width = 100%
    align = \"center\"
    color = \"#0b2e1a\"
    font = \"Unifont Regular 16\"
    text = \"HEKS GNU/LINUX - a desktop on Void Linux\"
}

terminal-font: \"Unifont Regular 16\"
terminal-left: 10%
terminal-top: 10%
terminal-width: 80%
terminal-height: 70%
")

;; The menu names this system rather than the distribution under it.  It is
;; @emph{not} @code{heks-name}: grub's @file{10_linux} appends
;; @samp{ GNU/Linux} to this word, so the whole name here was a menu that read
;; @samp{Heks GNU/Linux GNU/Linux}.
(define grub-distributor
  (make-parameter "Heks"))

(define* (grub-defaults #:key (cmdline ""))
  "Return @file{/etc/default/grub}, with @var{cmdline} as the kernel's arguments.

@var{cmdline} is the line the installer worked out for the layout it wrote -
which container, which filesystem, which subvolume - so this file is the one
place a machine's boot arguments live and @code{grub-mkconfig} is what turns
them into every entry in the menu.

The timeout is short and the menu is always shown: a machine that hides its menu
behind a keypress is a machine whose rescue entries nobody finds.  Submenus are
off for the same reason, and GRUB's own recovery entries are off because a
@code{single} on a runit machine boots nothing in particular - the rescue entry
that means something is in @file{/etc/grub.d/40_custom}."
  (format #f "# /etc/default/grub -- written by Heks-Linux; edit (heks-linux grub) instead.
#
# The kernel command line this machine boots with.  grub-mkconfig writes it into
# every entry it generates, and 40_custom's entries add to it.
GRUB_CMDLINE_LINUX_DEFAULT=\"~a\"
GRUB_CMDLINE_LINUX=\"\"

# Five seconds, always shown, and flat: a menu that hides behind a keypress is a
# menu nobody finds the rescue entries in, and a submenu is a second question
# between a person and the kernel.
GRUB_TIMEOUT=~a
GRUB_TIMEOUT_STYLE=menu
GRUB_DISABLE_SUBMENU=y

# The theme, and the colours the text menu falls back to on a machine GRUB
# cannot draw a picture on.
GRUB_THEME=\"~a\"
GRUB_COLOR_NORMAL=\"light-green/black\"
GRUB_COLOR_HIGHLIGHT=\"black/light-green\"
GRUB_GFXMODE=auto

# The menu names this system rather than the distribution under it: grub's
# 10_linux appends \" GNU/Linux\" to the distributor, so this is the word before
# it.  Nothing else on the disk is offered: this is not a dual-boot installer.
GRUB_DISTRIBUTOR=\"~a\"
GRUB_DISABLE_OS_PROBER=true
# 'single' means nothing to runit: the rescue entry is in 40_custom instead.
GRUB_DISABLE_RECOVERY=true
"
          cmdline (grub-timeout) (grub-theme-path) (grub-distributor)))

(define (grub-entries-path)
  "Return the file @code{grub-mkconfig} runs for the entries it does not make."
  "/etc/grub.d/40_custom")

(define (grub-entries)
  "Return @file{/etc/grub.d/40_custom}: the menu entries a person reaches for.

@code{grub-mkconfig} runs every executable script in @file{/etc/grub.d} and
takes what it prints as menu entries.  @code{10_linux} has already written the
entries that boot the kernels it found; this one prints three more for each of
those kernels - a verbose boot, the splash, and a shell - and then the entries
that are not a kernel at all: the firmware's settings, a restart, a power off,
and a screen that says what this system is.

Two decisions worth naming.  The kernels are found by the names Void's kernel
packages use (@file{/boot/vmlinuz-<version>} and
@file{/boot/initramfs-<version>.img}), because a menu entry needs a path and
there is nothing else to ask; a @file{/boot} this does not match prints none of
them rather than a broken entry, and the generated entries still boot the
machine.  And the boot partition is found by UUID at @code{grub-mkconfig} time,
the same way @code{10_linux} does it, because GRUB's own root may be the ESP and
the kernel is not there.

The last entry is the one with the personality: the name in block letters, a
frame of the rain, and where the documentation is.  It clears the screen, so it
also shows the terminal a machine sees when it presses @kbd{c}."
  "#! /bin/sh
# ====== Heks-Linux: the entries the menu does not generate ======
#
# auto-generated file, DO NOT EDIT!
#
# grub-mkconfig runs every executable script in this directory and takes what
# it prints as menu entries.  10_linux has written the ones that boot the
# kernels; these are the ones a person reaches for when something is wrong.

set -eu

. /etc/default/grub 2>/dev/null || :
cmdline=\"${GRUB_CMDLINE_LINUX_DEFAULT:-}\"

# The two things the layouts differ in: the splash is off on this system, and a
# verbose boot is what `quiet` takes away.
quiet_cmdline=\"$(printf '%s' \"$cmdline\" \\
    | sed -e 's/[[:space:]]*plymouth\\.enable=0//g' \\
          -e 's/[[:space:]]*quiet//g' \\
          -e 's/^ *//')\"

# GRUB reads a quoted string as easily as a bare one, and a command line can
# hold a quote only if somebody put one there; escape it rather than break the
# menu.
quote() { printf '%s' \"$1\" | sed -e 's/\\\\/\\\\\\\\/g' -e 's/\"/\\\\\"/g'; }

# Where /boot is, by UUID: GRUB's root is the ESP on a UEFI machine, and the
# kernel is not on it.
boot_source=\"$(findmnt -no SOURCE /boot 2>/dev/null || true)\"
boot_uuid=''
[ -z \"$boot_source\" ] \\
    || boot_uuid=\"$(blkid -s UUID -o value \"$boot_source\" 2>/dev/null || true)\"

if [ -n \"$boot_uuid\" ]; then
    for kernel in /boot/vmlinuz-*; do
        [ -f \"$kernel\" ] || continue
        version=\"${kernel#/boot/vmlinuz-}\"
        initrd=\"/boot/initramfs-${version}.img\"
        [ -f \"$initrd\" ] || continue

        cat <<EOF
menuentry 'Heks GNU/Linux, ${version} (verbose)' --class heks --class gnu-linux --class os {
    search --no-floppy --fs-uuid --set=root ${boot_uuid}
    set gfxpayload=keep
    linux ${kernel} $(quote \"${quiet_cmdline} loglevel=7\")
    initrd ${initrd}
}

menuentry 'Heks GNU/Linux, ${version} (with the splash)' --class heks --class gnu-linux --class os {
    search --no-floppy --fs-uuid --set=root ${boot_uuid}
    set gfxpayload=keep
    linux ${kernel} $(quote \"${quiet_cmdline} quiet splash\")
    initrd ${initrd}
}

menuentry 'Heks GNU/Linux, ${version} (rescue shell)' --class heks --class gnu-linux --class os {
    search --no-floppy --fs-uuid --set=root ${boot_uuid}
    set gfxpayload=keep
    linux ${kernel} $(quote \"${quiet_cmdline} init=/bin/sh rw\")
    initrd ${initrd}
}

EOF
    done
fi

if [ -d /sys/firmware/efi ]; then
    cat <<'EOF'
menuentry 'UEFI firmware settings' --hotkey f --class heks {
    fwsetup
}

EOF
fi

cat <<'EOF'
menuentry 'Restart' --hotkey b --class heks {
    echo 'restarting...'
    reboot
}

menuentry 'Power off' --hotkey p --class heks {
    echo 'powering off...'
    halt
}

menuentry 'Heks: what this is, and the keys' --hotkey m --class heks {
    clear
    set color_normal=light-green/black
    echo ''
    echo '     #   # ###### #   #  ####'
    echo '     #   # #      #  #  #    '
    echo '     ##### #####  ###    ### '
    echo '     #   # #      #  #      #'
    echo '     #   # ###### #   #  ####'
    echo ''
    set color_normal=dark-gray/black
    echo '     01001 1101 0110 1011 0010 1101 0110 1011'
    echo '       1011 0010 1101 0110 0110 1011 0010 11'
    echo '     0010 1101 0110 1011 0101 0110 1011 0010'
    echo '       1101 0110 1011 0010 1011 0010 1101 01'
    echo ''
    set color_normal=light-green/black
    echo '    Heks GNU/Linux - a desktop on Void Linux, runit underneath.'
    echo '    The disk is encrypted; the initramfs asks for the passphrase once.'
    echo ''
    set color_normal=dark-gray/black
    echo '    e   edit this entry (add a kernel argument, or drop one)'
    echo '    c   a GRUB command line, if you want to look around first'
    echo '    f   the firmware settings      b restart      p power off'
    echo '    the installed system has heks-help: the quickstart, offline'
    echo ''
    set color_normal=light-green/black
    echo '    nothing here writes to the disk.  this screen goes back to the menu.'
    sleep 12
}
EOF
")
