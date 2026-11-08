;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The .deb box: a Distrobox container for programs that ship only as a Debian
;; package, and the program that installs one in it.
;;
;; Two generated files:
;;
;; - @file{~/.config/distrobox/heks-deb.ini} is a @code{distrobox assemble}
;;   manifest that names the image, the guest-side libraries a .deb program
;;   needs before the desktop's audio and GPU reach it, and whether the
;;   proprietary NVIDIA driver is integrated.
;; - @file{~/.local/bin/heks-deb} assembles that box, installs @file{.deb}
;;   files in it with @code{apt-get}, runs a program, and exports one to the
;;   host's launcher.
;;
;; Nothing here copies the host's devices and sockets, because Distrobox already
;; shares them: the home directory, @env{XDG_RUNTIME_DIR} - and with it the
;; Wayland and PipeWire sockets - the D-Bus sessions, @file{/dev/dri} and
;; @file{/dev/nvidia*}, plus the uid, so a program inside the box plays through
;; this session's PipeWire and draws with this machine's GPU, and the files it
;; writes are yours.  What the manifest adds is the half Distrobox cannot: the
;; guest libraries - PipeWire's client libraries, libpulse0 and ALSA's plugins,
;; and Mesa - which a bare Debian image does not carry.
;;
;; The proprietary NVIDIA driver is the one thing not shared on its own, hence
;; @code{nvidia=}: it is detected from @file{/proc/driver/nvidia/version} when
;; the manifest is rendered, and can be overridden in distrobox-settings.scm.

;;; Code:

(define-module (heks-linux distrobox)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-13)
  #:export (distrobox-container-name
            distrobox-image
            distrobox-nvidia?
            distrobox-packages
            distrobox-init?
            distrobox-config-dir
            distrobox-manifest-filename
            distrobox-script-dir
            distrobox-script-filename
            distrobox-expand
            distrobox-manifest
            distrobox-script
            install-distrobox-config))

(define s
  (scriba-auto-logger))

;; ===========================================
;; What the box is
;; ===========================================

(define (distrobox-home)
  "Return the home directory the manifest and the program are rendered for."
  (or (getenv "HOME") "/tmp"))

(define (distrobox-expand path)
  "Return @var{path} with a leading @file{~/} expanded to the home directory.
The program is started from a shell and from the launcher, where a quoted tilde
is a literal character and not a directory, so its paths are absolute by the
time it is written."
  (if (and (string? path) (string-prefix? "~/" path))
    (format #f "~a/~a" (distrobox-home) (substring path 2))
    path))

;; The container's name.  It is also what the program is called in one word -
;; heks-deb - and what the manifest's section is named.
(define distrobox-container-name
  (make-parameter "deb"))

;; Debian stable is what a .deb is built for; a package from an Ubuntu release
;; that needs newer libraries is the one reason to change it.
(define distrobox-image
  (make-parameter "docker.io/library/debian:stable"))

;; The proprietary driver is the only thing Distrobox does not share by
;; itself: Intel and AMD GPUs arrive through /dev/dri, which is bound anyway.
(define (distrobox-nvidia-driver-present?)
  "Return @code{#t} when the proprietary NVIDIA driver is loaded."
  (file-exists? "/proc/driver/nvidia/version"))

(define distrobox-nvidia?
  (make-parameter (distrobox-nvidia-driver-present?)))

;; Installed when the box is first created, because a bare Debian image has
;; nothing to speak to PipeWire with and nothing to drive the GPU.  pactl and
;; glxinfo are here so that checking the result needs no second install.
(define distrobox-packages
  (make-parameter '("libasound2-plugins"
                    "libegl1"
                    "libgl1"
                    "libpulse0"
                    "mesa-utils"
                    "mesa-vulkan-drivers"
                    "pipewire-audio-client-libraries"
                    "pulseaudio-utils"
                    "xdg-utils")))

;; A box with an init is a small system rather than an application container:
;; it has its own systemd, which is what a package whose daemon must run
;; needs, and it loses the host's process integration.
(define distrobox-init?
  (make-parameter #f))

;; ===========================================
;; Where the files go
;; ===========================================

(define distrobox-config-dir
  (make-parameter (format #f "~a/.config/distrobox" (distrobox-home))))

(define distrobox-manifest-filename
  (make-parameter "heks-deb.ini"))

(define distrobox-script-dir
  (make-parameter (format #f "~a/.local/bin" (distrobox-home))))

(define distrobox-script-filename
  (make-parameter "heks-deb"))

;; ===========================================
;; The manifest
;; ===========================================

(define (distrobox-manifest)
  "Return the @code{distrobox assemble} manifest for the .deb box.

@code{replace=false} is deliberate: assembling a box that already exists must
not rebuild it, or every command would undo the programs installed in it."
  (format #f "# ====== Heks-Linux: the .deb box ======
#
# auto-generated file, DO NOT EDIT!  Rendered from (heks-linux distrobox);
# run maak install-distrobox to write it again.
#
# Distrobox shares the home directory, the Wayland and PipeWire sockets and
# /dev/dri with the container, so a program installed in this box uses this
# session's audio and GPU.  nvidia=true is for the proprietary driver, the one
# thing that is not shared on its own.

[~a]
image=~a
additional_packages=\"~a\"
nvidia=~a
init=~a
pull=true
replace=false
start_now=false
"
          (distrobox-container-name)
          (distrobox-image)
          (string-join (distrobox-packages) " ")
          (if (distrobox-nvidia?) "true" "false")
          (if (distrobox-init?) "true" "false")))

;; ===========================================
;; The program
;; ===========================================

(define (script-text . lines)
  "Return @var{lines} as one text, one per line, ending in a newline."
  (string-append (string-join lines "\n") "\n"))

(define (distrobox-script)
  "Return the whole @file{heks-deb} program as text."
  (format #f
          (script-text
           "#!/usr/bin/env bash"
           "# ====== Heks-Linux: the .deb box ======"
           "#"
           "# auto-generated file, DO NOT EDIT!  Rendered from (heks-linux distrobox)."
           "#"
           "# create        create the box from the manifest"
           "# install F...  apt-get install .deb files inside the box"
           "# i386          enable the 32-bit libraries a .deb may ask for"
           "# remove P...   apt-get remove --purge packages inside the box"
           "# run CMD...    run a command inside the box"
           "# shell         a shell inside the box"
           "# export APP    put a .deb program in the host's launcher"
           "# list          every distrobox on this machine"
           "# rm            delete the box, and every program in it"
           "# doctor        what the box needs, and what is missing"
           ""
           "set -uo pipefail"
           ""
           "BOX=\"~a\""
           "MANIFEST=\"~a\""
           "IMAGE=\"~a\""
           "NVIDIA=\"~a\""
           ""
           "die() { printf 'heks-deb: %s\\n' \"$*\" >&2; exit 1; }"
           ""
           "# Assembling a box that is already there is a no-op - the manifest says"
           "# replace=false - so this runs before every command and never rebuilds a"
           "# box that has programs installed in it."
           "ensure() {"
           "    [ -f \"$MANIFEST\" ] || die \"no manifest at $MANIFEST: run maak install-distrobox\""
           "    distrobox list 2>/dev/null | grep -qw \"$BOX\" && return 0"
           "    printf 'assembling the %s box from %s\\n' \"$BOX\" \"$IMAGE\" >&2"
           "    distrobox assemble create --file \"$MANIFEST\" >/dev/null \\"
           "        || die \"could not assemble the $BOX box from $MANIFEST\""
           "}"
           ""
           "cmd_create() { ensure; printf 'the %s box is ready\\n' \"$BOX\"; }"
           ""
           "cmd_install() {"
           "    [ \"$#\" -gt 0 ] || die \"install: name at least one .deb file\""
           "    local file path=()"
           "    for file in \"$@\"; do"
           "        [ -f \"$file\" ] || die \"install: $file does not exist\""
           "        path+=(\"$(realpath -- \"$file\")\")"
           "    done"
           "    ensure"
           "    # The host's home is the container's home, so these paths hold inside"
           "    # the box; apt also pulls the dependencies the package names."
           "    distrobox enter --name \"$BOX\" -- sudo apt-get install -y \"${path[@]}\""
           "}"
           ""
           "# A .deb whose dependencies end in :i386 needs the 32-bit half of Debian,"
           "# which a fresh box does not have: every one of them then answers 'not"
           "# installable'.  The 32-bit Mesa driver is installed here as well, so a"
           "# 32-bit program renders through the GPU instead of falling back to"
           "# software.  Adding an architecture twice is a no-op."
           "cmd_i386() {"
           "    ensure"
           "    distrobox enter --name \"$BOX\" -- sudo dpkg --add-architecture i386"
           "    distrobox enter --name \"$BOX\" -- sudo apt-get update"
           "    distrobox enter --name \"$BOX\" -- sudo apt-get install -y \\"
           "        libgl1:i386 libgl1-mesa-dri:i386 libglx-mesa0:i386"
           "}"
           ""
           "cmd_remove() {"
           "    [ \"$#\" -gt 0 ] || die \"remove: name at least one package\""
           "    ensure"
           "    distrobox enter --name \"$BOX\" -- sudo apt-get remove --purge -y \"$@\""
           "}"
           ""
           "cmd_run() {"
           "    [ \"$#\" -gt 0 ] || die \"run: name a command\""
           "    ensure"
           "    distrobox enter --name \"$BOX\" -- \"$@\""
           "}"
           ""
           "cmd_shell() { ensure; distrobox enter --name \"$BOX\"; }"
           ""
           "cmd_export() {"
           "    [ \"$#\" -gt 0 ] || die \"export: name an application, such as taken_notes\""
           "    ensure"
           "    distrobox enter --name \"$BOX\" -- distrobox-export --app \"$1\""
           "}"
           ""
           "cmd_list() { distrobox list; }"
           ""
           "cmd_rm() { distrobox rm --force \"$BOX\" || die \"could not delete the $BOX box\"; }"
           ""
           "cmd_doctor() {"
           "    local missing=0 socket=\"${XDG_RUNTIME_DIR:-/nonexistent}/pipewire-0\" tool"
           "    for tool in distrobox podman; do"
           "        command -v \"$tool\" >/dev/null 2>&1 \\"
           "            || { printf 'missing: %s (maak install-zypper)\\n' \"$tool\"; missing=1; }"
           "    done"
           "    [ -n \"${WAYLAND_DISPLAY:-}\" ] \\"
           "        || { printf 'session: WAYLAND_DISPLAY is unset; no window will open\\n'; missing=1; }"
           "    [ -S \"$socket\" ] \\"
           "        || { printf 'audio: no PipeWire socket at %s\\n' \"$socket\"; missing=1; }"
           "    [ -d /dev/dri ] \\"
           "        || { printf 'graphics: /dev/dri is absent; the box gets no GPU\\n'; missing=1; }"
           "    if command -v nvidia-smi >/dev/null 2>&1 && [ \"$NVIDIA\" != true ]; then"
           "        printf 'graphics: the NVIDIA driver is loaded but the box was made without it\\n'"
           "        missing=1"
           "    fi"
           "    [ \"$missing\" = 0 ] && printf 'every device the box shares is present\\n'"
           "    return \"$missing\""
           "}"
           ""
           "usage() {"
           "    cat <<'HEKS_DEB'"
           "heks-deb: .deb programs in a container that shares this session"
           ""
           "  heks-deb create            assemble the box from the manifest"
           "  heks-deb install FILE...   install .deb files with apt inside the box"
           "  heks-deb i386              enable 32-bit libraries for a .deb that asks"
           "  heks-deb remove PKG...     remove packages from the box"
           "  heks-deb run CMD [ARG...]  run a command inside the box"
           "  heks-deb shell             a shell inside the box"
           "  heks-deb export APP        export an application to the host launcher"
           "  heks-deb list              every distrobox on this machine"
           "  heks-deb rm                delete the box and everything in it"
           "  heks-deb doctor            what the box needs, and what is missing"
           ""
           "The box shares the host's home, Wayland socket, PipeWire socket and"
           "GPU, so a graphical .deb program opens on this session and plays"
           "through the same sound server as everything else."
           "HEKS_DEB"
           "}"
           ""
           "main() {"
           "    local kind=\"${1:-help}\""
           "    [ $# -gt 0 ] && shift"
           "    case \"$kind\" in"
           "        create) cmd_create ;;"
           "        install) cmd_install \"$@\" ;;"
           "        i386) cmd_i386 ;;"
           "        remove) cmd_remove \"$@\" ;;"
           "        run) cmd_run \"$@\" ;;"
           "        shell) cmd_shell ;;"
           "        export) cmd_export \"$@\" ;;"
           "        list) cmd_list ;;"
           "        rm) cmd_rm ;;"
           "        doctor) cmd_doctor ;;"
           "        help|-h|--help) usage ;;"
           "        *) usage >&2; exit 2 ;;"
           "    esac"
           "}"
           ""
           "main \"$@\"")
          (distrobox-container-name)
          (distrobox-expand
           (format #f "~a/~a" (distrobox-config-dir)
                   (distrobox-manifest-filename)))
          (distrobox-image)
          (if (distrobox-nvidia?) "true" "false")))

;; ===========================================
;; Installing it
;; ===========================================

(define (install-distrobox-config)
  "Write the .deb box manifest and the @file{heks-deb} program.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/distrobox-settings.scm} first, so the image,
the name, the packages and the NVIDIA flag can be changed per machine."
  (log-info s "Installing distrobox configuration")
  (load-local-overrides '(heks-linux distrobox) 'distrobox-settings)
  (install-config-file! #:name (distrobox-manifest-filename)
                        #:dir (distrobox-config-dir)
                        #:contents (distrobox-manifest))
  (install-config-file! #:name (distrobox-script-filename)
                        #:dir (distrobox-script-dir)
                        #:contents (distrobox-script)
                        #:perms 493)
  (log-success s "Installed distrobox configuration"))
