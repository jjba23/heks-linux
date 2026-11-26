;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The Debian package list, and the backend that installs it.
;;
;; Debian is the second target: Void with runit and xbps is the path this tree
;; was written on, and an apt machine runs the same modules with one package
;; manager swapped and one init system answered instead of assumed.  What is
;; *not* shared is the names.  Void's `mesa-dri' is Debian's `libgl1-mesa-dri',
;; Void's `fd' is Debian's `fd-find', Void's `elogind' and `polkit' are Debian's
;; `polkitd' and systemd's own logind, and `guile', `rust' and `ninja' are
;; versioned or suffixed on Debian.  A list copied across installs nothing: apt
;; resolves the whole command or none of it.
;;
;; Which is why a name here is a package only if a Debian repository the machine
;; has carries it, exactly as in the zypper list.  `apt-cache policy NAME'
;; answers from the indexes the machine already has, and is the minute each name
;; below deserves:
;;
;;   apt-cache policy fd-find libgl1-mesa-dri polkitd
;;
;; A name Debian does not carry is a name for the documentation, not for this
;; list: `rmpc', `wbg' and `socklog-void' are Void packages, and the pages under
;; `docs/' that describe Debian say what to install instead.
;;
;; Two Debianisms worth knowing before editing this file:
;;
;; - Debian splits a program from its data and its plugins, and installs the
;;   recommends it thinks a package wants.  This list names every program the
;;   desktop runs and passes `--no-install-recommends', because a desktop built
;;   out of recommends is a desktop nobody can read.
;; - `fd-find' installs `fdfind', not `fd', because Debian already had an `fd'
;;   (fdclone's).  The editor's own doctor names `fd', so a Debian machine
;;   either links it once or lives with `fdfind'; the Debian page in `docs/'
;;   says so where a person will read it.
;;
;;; Code:

(define-module (heks-linux packages apt)
  #:declarative? #t
  #:use-module (heks-linux packages)
  #:export (heks-linux-apt
            heks-linux-session-apt
            heks-linux-desktop-apt
            heks-linux-cli-apt
            heks-linux-dev-apt
            heks-linux-font-apt
            apt-package-name
            apt-install-args
            apt-backend
            install-apt))

;; ===========================================
;; The session: what has to exist before a window can be drawn
;; ===========================================

;; The same session the Void list describes, in Debian's spellings.  The seat,
;; the session id and `loginctl' come from systemd-logind, which is already
;; there on a Debian machine - so there is no elogind to install, and the power
;; menu keeps working because it asks logind the same question either way.
;;
;; EGL reaches a compositor in the same three pieces as on Void, under Debian's
;; names: `libegl1' is the loader and `libgl1-mesa-dri' is the drivers behind
;; it.  A machine with the compositors and neither draws nothing.
;;
;; Debian calls the X11 satellite `xwayland' and starts it from the session;
;; `xwayland-satellite' is not a Debian package.
(define heks-linux-session-apt
  (make-parameter '(dbus
                    polkitd
                    rtkit
                    network-manager
                    pipewire
                    ;; Debian splits the PulseAudio-compatible server out of
                    ;; pipewire: without it an application that speaks libpulse
                    ;; has no sound, and Void's pipewire ships the same server in
                    ;; the same package.
                    pipewire-pulse
                    wireplumber
                    xdg-desktop-portal
                    xdg-desktop-portal-gtk
                    xdg-desktop-portal-gnome
                    libegl1
                    libgl1-mesa-dri
                    niri
                    labwc
                    xwayland
                    swaybg
                    swayidle
                    wev
                    wl-clipboard
                    brightnessctl
                    kitty
                    zenity
                    ;; What every desktop assumes: xdg-open for a launcher that
                    ;; opens a file, and the user directories the session's own
                    ;; settings name - the screenshots directory among them.
                    xdg-utils
                    xdg-user-dirs
                    ;; The login prompt, which Debian packages as two programs
                    ;; like Void: greetd authenticates and tuigreet draws.
                    greetd
                    tuigreet)))

;; ===========================================
;; The desktop: the programs a session is used with
;; ===========================================

;; What a session is used with, minus the two the distribution does not carry.
;; `rmpc' is not a Debian package - the MPD client is built from its own source
;; and the Debian page says how - and `wl-screenrec' is not one either, so the
;; capture module's `wf-recorder' fallback is what a Debian machine records
;; with.  mpd is here because a client with no server is a window with nothing
;; in it.
(define heks-linux-desktop-apt
  (make-parameter '(cava
                    emacs
                    ffmpeg
                    grim
                    mpd
                    mpv
                    pavucontrol
                    playerctl
                    satty
                    slurp
                    wf-recorder)))

;; ===========================================
;; The command line
;; ===========================================

;; The same list the Void backend declares, in Debian's names: `fd' is
;; `fd-find', and `7zip' is Debian's own package of that name.  `btop' is a
;; Debian package and so is `fastfetch'; `mg' is the console Emacs and `ed' the
;; editor every machine has.
(define heks-linux-cli-apt
  (make-parameter '("7zip"
                    bat
                    btop
                    cmatrix
                    ed
                    fastfetch
                    fd-find
                    fzf
                    gifsicle
                    htop
                    jq
                    less
                    mg
                    ripgrep
                    yq
                    ;; The two archive formats nothing else here opens.
                    unzip
                    zip)))

;; ===========================================
;; Development
;; ===========================================

;; What this tree's own tasks need and what the editor's bridges look for, in
;; Debian's spellings.  `guile-3.0' is the interpreter package (Debian installs
;; it as `guile'), `rustc' and `cargo' are two packages rather than one `rust',
;; `ninja-build' carries the suffix, and `nix-bin' is the store and its daemon -
;; with `nix-setup-systemd', which is the other half of Debian's packaging: the
;; unit and the store's own directories.  `pkg-config' is the shim Debian keeps
;; pointed at pkgconf.
;;
;; clang, lld and lldb are named separately because Debian packages them
;; separately: Void's single `llvm' carries all three.
(define heks-linux-dev-apt
  (make-parameter '(cargo
                    clang
                    curl
                    flatpak
                    gcc
                    git
                    gnupg
                    gradle
                    guile-3.0
                    lld
                    lldb
                    make
                    ninja-build
                    nix-bin
                    nix-setup-systemd
                    pandoc
                    pkg-config
                    podman
                    rustc
                    wget)))

;; ===========================================
;; The fonts the session cannot start without
;; ===========================================

;; Debian's font packages are the families themselves: DejaVu, Liberation and
;; Noto cover Latin text and the interface's glyph fallbacks, and the emoji face
;; is a package of its own.  JuliaMono and Work Sans have no Debian package
;; either, so they stay outside the distribution list and a machine installs
;; them itself; Source Serif 4 is `fonts-source-serif-pro' where the release
;; carries it, and the Debian page names both cases rather than this list
;; guessing.
(define heks-linux-font-apt
  (make-parameter '(fonts-dejavu
                    fonts-liberation
                    fonts-noto-cjk
                    fonts-noto-color-emoji
                    fonts-noto-core)))

(define (apt-package-name package)
  "Return @var{package}'s name.
A category spells a name as a symbol, except where the name is not a valid
symbol such as \"7zip\"; both are accepted here rather than at every call site."
  (if (symbol? package)
    (symbol->string package)
    package))

(define (heks-linux-apt)
  "Return the packages this tree installs on a Debian machine."
  (package-sorted-set
   (append (heks-linux-session-apt)
           (heks-linux-desktop-apt)
           (heks-linux-cli-apt)
           (heks-linux-dev-apt)
           (heks-linux-font-apt))
   apt-package-name))

(define (apt-install-args packages)
  "Return the argument vector that installs @var{packages} with apt.

@code{sudo} is an argument rather than the beginning of a shell line, and every
package name is the argument @code{apt-get} receives: a name that was checked by
@code{package-name?} is never interpolated into a command.

@option{--no-install-recommends} is the whole of why this is not one line: apt
installs a package's recommends unless it is told not to, and a recommends list
is where a Debian desktop grows a second office suite.  @option{--yes} answers
the confirmation, and the index is not refreshed here - `maak update-apt' is
what refreshes it, and an install that quietly upgraded the machine would be a
task that does more than its name says."
  (append (list "sudo" "apt-get" "install" "--yes" "--no-install-recommends")
          (map apt-package-name packages)))

;; The apt backend: Debian's own package manager.
(define apt-backend
  (package-backend 'apt
                   #:packages (lambda () (heks-linux-apt))
                   #:name-of apt-package-name
                   #:name-valid? package-name?
                   #:install (lambda (packages)
                               (let ((argv (apt-install-args packages)))
                                 (run-package-command (car argv)
                                                      (cdr argv))))))

(define (install-apt)
  "Install every package @code{heks-linux-apt} names with apt.
The list is the deduplicated union of the category lists declared in this
module, so a package needed by two categories is installed once.  This is the
one task that needs administrator rights, and it prompts for them."
  (package-backend-install apt-backend (heks-linux-apt)))
