#!/bin/bash
# heks-linux
#
# SPDX-License-Identifier: MIT
# Copyright © Josep Bigorra <jjbigorra@gmail.com>

# ====== a disk that does not exist ======
#
# heks-install is one shell script that turns six answers into a disk, and the
# failures it has had were all ordering: a filesystem made before the partition
# it lives on existed, a mountpoint made before its parent was mounted, an ESP
# mounted before the boot partition it sits inside.  Each of those only happens
# on a real disk, and "a machine with a spare disk" is not something a test can
# ask for.  So the tools are stubs, the devices are directories, and the machine
# is this one.
#
#   fake-disk.sh SCRIPT MODE SCRATCH ANSWERS
#
# SCRIPT is the rendered heks-install.  It is sourced, not run: the script only
# enters through `main' when it is executed, so sourcing gives its functions and
# its top-level setup - the log, the lock, the answers' defaults - and then this
# harness sets the answers and calls `work'.  MODE is the firmware the answers
# name, SCRATCH is where the fake devices and the record of what was done live,
# and ANSWERS is a file of the keystrokes the screens ask for.
#
# Four things are modelled, because they are what the real commands fail on:
#
# - a partition does not exist until the kernel has been told about the new
#   table.  `parted` writes the table, `partprobe` is what makes /dev/vda1
#   appear, and `mkfs` on a partition that `parted` made but nothing probed is
#   the "no such device or address" it is on a real disk;
# - a device has to exist before anything is written to it, so a filesystem
#   created on a partition that was never made fails here too;
# - a mountpoint has to exist before it is mounted on, and mounting a filesystem
#   over a directory hides what was in it.  That is the trap a layout falls into
#   when it makes a mountpoint before mounting its parent: /boot/efi made while
#   only the root subvolume is mounted is gone the moment /boot is mounted over
#   it, and the mount under it then fails;
# - what runs inside the new system is recorded and not run: the programs are
#   the installed system's, and there is no installed system here.
#
# Every mount and every chroot is printed as it happens, in the order it
# happened, so a spec can say what was done in what order.  SCRIPT's exit status
# is this script's.

set -euo pipefail

script=$1
firmware=$2
scratch=$3
answers=$4

mkdir -p "$scratch/devs" "$scratch/stash" "$scratch/bin"

# A PATH of our own: the tools the script and this harness need, and nothing
# else.  `dialog' is deliberately not among them, so the wizard takes the plain
# path - one question, one line of stdin - which is what a person on a medium
# without dialog sees.
for tool in awk basename cat dirname grep install ls mkdir mktemp mv rm sed \
            sync tar tee touch tr; do
    found=$(command -v "$tool") \
        || { printf 'fake-disk: %s is not on PATH\n' "$tool" >&2; exit 1; }
    ln -sf "$found" "$scratch/bin/$tool"
done
PATH=$scratch/bin
export PATH

# The machine: one disk, empty, that is not the one this system runs from.
fake_disk=${FAKE_DISK:-/dev/vda}
fake_size=${FAKE_SIZE:-34359738368}

name() { printf '%s' "$1" | tr '/' '-'; }
tree_of() { printf '%s/devs/%s' "$scratch" "$(name "$1")"; }
last() { local word=''; for word in "$@"; do :; done; printf '%s' "$word"; }

# Does DEVICE exist?  Only /dev is the disk's; a mount of /proc or of an
# efivarfs names no device at all.  A stub fails the way the command it stands
# for fails - a return, not an exit - so the script's own `trap' says what
# happened and the screen shows it, as on a real disk.
present() {
    case "$1" in
        /dev/*)
            [ -d "$(tree_of "$1")" ] && return 0
            printf '%s: %s: no such device or address\n' \
                   "${FUNCNAME[1]:-fake-disk}" "$1" >&2
            return 1 ;;
    esac
}

# DEVICE now exists and holds nothing: a new filesystem, or a freshly opened
# container.
fresh() {
    rm -rf "$(tree_of "$1")"
    mkdir -p "$(tree_of "$1")"
}

mkdir -p "$(tree_of "$fake_disk")"
pending=$scratch/partitions
: > "$pending"

# The partitions the table holds but the kernel has not been told about yet.
# This is the whole point of the harness: `parted' writes them here, and only a
# probe publishes them as devices.
publish() {
    local dev index
    while read -r dev index; do
        [ -n "$dev" ] || continue
        mkdir -p "$scratch/devs/${dev}${sep}${index}"
    done < "$pending"
}

wipefs() { :; }
swapoff() { :; }
shred() {
    local word
    for word in "$@"; do
        case "$word" in
            -*) ;;
            *) rm -f "$word" ;;
        esac
    done
}

parted() {
    local dev='' command=''
    # parted -s "$disk" [unit MiB] COMMAND ...
    while [ $# -gt 0 ]; do
        case "$1" in
            -s|-m) shift ;;
            -a*) shift 2 ;;
            *) break ;;
        esac
    done
    dev=$1
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            unit) shift 2 ;;
            -*) shift ;;
            *) break ;;
        esac
    done
    present "$dev" || return 1
    command=$1
    shift
    case "$command" in
        mklabel)
            # A new table: whatever partitions the disk had are gone.
            for word in "$scratch"/devs/"$(name "$dev")"[0-9]*; do
                [ -d "$word" ] && rm -rf "$word"
            done
            : > "$pending" ;;
        mkpart)
            # The table holds the partition; the device node is the kernel's to
            # publish, and `partprobe' is what asks it to.
            count=$(grep -c "^$(name "$dev") " "$pending" || true)
            printf '%s %s\n' "$(name "$dev")" "$((count + 1))" >> "$pending" ;;
        set) : ;;
        *)
            printf 'fake-disk: parted %s: not modelled\n' "$command" >&2
            exit 1 ;;
    esac
}

partprobe() {
    present "$1" || return 1
    publish
}

# `udevadm settle' waits for the nodes udev is making, so it publishes them too.
udevadm() {
    case "${1:-}" in
        settle) publish ;;
    esac
}

mkfs.vfat() { present "$(last "$@")" || return 1; fresh "$(last "$@")"; }
mkfs.ext4() { present "$(last "$@")" || return 1; fresh "$(last "$@")"; }
mkfs.btrfs() { present "$(last "$@")" || return 1; fresh "$(last "$@")"; }

cryptsetup() {
    local what=$1
    shift
    case "$what" in
        luksFormat) present "$(last "$@")" || return 1 ;;
        luksUUID) printf '6666-luks\n' ;;
        open)
            local src='' opened=''
            while [ $# -gt 0 ]; do
                case "$1" in
                    --key-file) shift 2 ;;
                    -*) shift ;;
                    *) if [ -z "$src" ]; then src=$1; else opened=$1; fi; shift ;;
                esac
            done
            [ -n "$opened" ] || { printf 'fake-disk: cryptsetup open: no name\n' >&2; return 1; }
            present "$src" || return 1
            fresh "/dev/mapper/$opened" ;;
        close) : ;;
        *)
            printf 'fake-disk: cryptsetup %s: not modelled\n' "$what" >&2
            exit 1 ;;
    esac
}

btrfs() {
    [ "$1" = subvolume ] \
        || { printf 'fake-disk: btrfs %s: not modelled\n' "$1" >&2; return 1; }
    shift
    [ "$1" = create ] \
        || { printf 'fake-disk: btrfs subvolume %s: not modelled\n' "$1" >&2; return 1; }
    shift
    # btrfs refuses to create a subvolume whose parent is not there, and so does
    # mkdir: the layout's own mountpoints are what this checks.
    mkdir "$(last "$@")"
}

# The identifiers a filesystem would report, one per device the layout makes.
blkid() {
    case "$(last "$@")" in
        /dev/mapper/cryptroot) printf '5555-root\n' ;;
        "${boot_part:-}") printf '1111-boot\n' ;;
        "${esp_part:-}") printf '2222-esp\n' ;;
        *) printf '9999-unknown\n' ;;
    esac
}

# --- the machine ------------------------------------------------------------

id() {
    case "${1:-}" in
        -un|-nu) printf 'root\n' ;;
        *) printf 'uid=0(root) gid=0(root)\n' ;;
    esac
}

flock() { :; }
sync() { :; }
ping() { return 0; }
findmnt() { printf '/dev/medium1\n'; }

# The disks on the machine, and how big the one under test is.  The mountpoints
# are empty: this disk is not the one the live system runs from.
lsblk() {
    case "$*" in
        "-dpno NAME") printf '%s\n' "$fake_disk" ;;
        *SIZE*) printf '%s\n' "$fake_size" ;;
        *) : ;;
    esac
}

chroot() {
    local root=$1
    shift
    [ -n "$root" ] || { printf 'fake-disk: chroot: no target\n' >&2; return 1; }
    printf 'chroot %s\n' "$*"
}

# --- the mounts -------------------------------------------------------------

# What a mount hid, per mountpoint: a mounted filesystem has a root of its own,
# and the directory underneath is not in it.
hidden_for() { printf '%s/stash/%s' "$scratch" "$(name "$1")"; }

mount() {
    local src='' dst='' hidden
    while [ $# -gt 0 ]; do
        case "$1" in
            -o|-t) shift 2 ;;
            -*) shift ;;
            *) if [ -z "$src" ]; then src=$1; else dst=$1; fi; shift ;;
        esac
    done
    [ -n "$dst" ] || { printf 'fake-disk: mount: no mountpoint\n' >&2; return 1; }
    present "$src" || return 1
    if [ ! -d "$dst" ]; then
        printf 'mount: %s: mount point does not exist\n' "$dst" >&2
        return 1
    fi
    printf 'mount %s %s\n' "$src" "$dst"
    hidden=$(hidden_for "$dst")
    mkdir -p "$hidden"
    if [ -n "$(ls -A "$dst")" ]; then
        shopt -s dotglob nullglob
        mv "$dst"/* "$hidden"/
        shopt -u dotglob nullglob
    fi
}

umount() {
    local dst='' hidden word
    for word in "$@"; do
        case "$word" in
            -*) ;;
            *) dst=$word ;;
        esac
    done
    [ -n "$dst" ] || { printf 'fake-disk: umount: no mountpoint\n' >&2; return 1; }
    printf 'umount %s\n' "$dst"
    hidden=$(hidden_for "$dst")
    [ -d "$hidden" ] || return 0
    if [ -n "$(ls -A "$hidden")" ]; then
        shopt -s dotglob nullglob
        mv "$hidden"/* "$dst"/
        shopt -u dotglob nullglob
    fi
    rm -rf "$hidden"
}

# --- the medium -------------------------------------------------------------

# The system the medium carries, as a tarball: the directories a rootfs has, and
# the two files the installer edits - sudoers with Void's commented-out wheel
# line, and the setup command it runs in the target.
rootfs=$scratch/rootfs
medium() {
    local tree
    for tree in boot dev etc/default home proc root run sys usr/local/bin \
                var/log; do
        mkdir -p "$rootfs/$tree"
    done
    printf '%s\n' '# %wheel ALL=(ALL) ALL' > "$rootfs/etc/sudoers"
    : > "$rootfs/usr/local/bin/heks-setup"
    # Named as the installer names it; the content is an uncompressed tar, which
    # tar reads back either way.
    install -d -m 755 "$(dirname "$payload")"
    tar -cf "$payload" -C "$rootfs" .
}

# --- the install ------------------------------------------------------------

exec 0< "$answers"

# shellcheck source=/dev/null
. "$script"

# The answers a person would have typed.  The questions are the script's and are
# checked as text; what is run here is the work they carry out.
mode=$firmware
disk=$fake_disk
hostname=box
user_name=joe
home=/home/joe
userpass=hunter2hunter2
extras=checkouts
keyfile=$scratch/key
: > "$keyfile"

# /mnt exists on the medium; the script only makes its own target after the
# first mount, because that mount is what proves the container opened.
mkdir -p "$target"
medium

work
