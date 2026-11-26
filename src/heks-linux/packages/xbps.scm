;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The Void Linux package list, and the backend that installs it.
;;
;; xbps is the reason this list can be curated instead of assembled: there are
;; no patterns, no recommends and no desktop metapackage, so what is written
;; here is the whole of what a Void machine receives from its distribution.
;; That changes what an omission means.  On a distribution with patterns, a
;; missing entry is often pulled in by something else; here, a program that is
;; not named is not installed, which is why the lists below are short and why
;; every name is a program a surface in this tree actually runs.
;;
;; The backend has the same shape as the zypper one so the rest of the tree does
;; not care which of them a machine uses: a name, a package set, the spelling of
;; a name, a shape check on it, and an installer handed an argument vector.
;;
;;; Code:

(define-module (heks-linux packages xbps)
  #:declarative? #t
  #:use-module (heks-linux greeter)
  #:use-module (heks-linux logging)
  #:use-module (heks-linux packages)
  #:export (heks-linux-repository-xbps
            heks-linux-xbps
            heks-linux-session-xbps
            heks-linux-desktop-xbps
            heks-linux-cli-xbps
            heks-linux-dev-xbps
            heks-linux-font-xbps
            xbps-package-name
            xbps-install-args
            xbps-backend
            install-xbps))

;; ===========================================
;; The repositories
;; ===========================================

;; Void keeps its non-free tree in a repository of its own: the CPU microcode,
;; the firmware a wireless card cannot do without, and the drivers whose licence
;; keeps them out of main.  `void-repo-nonfree' is the package that adds it to
;; xbps's configuration, so it is enabled by installing this one entry - on the
;; medium, on the installed system it unpacks, and on any Void machine that runs
;; `maak install-xbps'.
;;
;; It is on by default because a machine whose wireless card needs a firmware
;; blob should not have to find out there is a second repository first, and
;; because adding a repository installs nothing by itself: the non-free packages
;; a machine takes are still the ones somebody asked for.
(define heks-linux-repository-xbps
  (make-parameter '("void-repo-nonfree")))

;; ===========================================
;; The session: what has to exist before a window can be drawn
;; ===========================================

;; The login session, the compositor and the terminal it opens.  elogind is
;; systemd's logind as a standalone daemon - it is what owns the seat, the
;; session id and `loginctl', which is the one command the shell's power menu
;; needs and the one thing on this list that has no replacement.
;;
;; The portals are the Wayland answers to X11's implicit access: a screenshot,
;; a file chooser and a screencast each go through one.  Both the GTK and the
;; GNOME portal are named because programs ask for different ones and a missing
;; portal is a dialog that never appears.
(define heks-linux-session-xbps
  (make-parameter '(dbus
                    elogind
                    polkit
                    rtkit
                    NetworkManager
                    pipewire
                    wireplumber
                    xdg-desktop-portal
                    xdg-desktop-portal-gtk
                    xdg-desktop-portal-gnome
                    ;; What the two compositors below draw with.  EGL reaches a
                    ;; machine in three pieces and Void hands a compositor one
                    ;; of them: `libglvnd' is the loader - wlroots depends on
                    ;; it, and niri opens one at runtime - `mesa' is the
                    ;; implementation behind the loader, and `mesa-dri' is the
                    ;; drivers behind that.  mesa does not depend on mesa-dri,
                    ;; so a machine with both compositors and neither of these
                    ;; has everything but a renderer: labwc exits with `unable
                    ;; to create renderer' and niri with the EGL error above it,
                    ;; on hardware as much as in a virtual machine.  mesa-dri is
                    ;; also where llvmpipe lives, so a machine whose GPU nothing
                    ;; drives draws its desktop in software rather than not at
                    ;; all.
                    mesa
                    mesa-dri
                    niri
                    ;; The second session the prompt offers: a stacking
                    ;; compositor for the person who drags windows where they
                    ;; belong.  Its configuration is rendered by
                    ;; (heks-linux labwc) with the rest of the desktop.
                    labwc
                    ;; X11 applications reach the session through this
                    ;; satellite; niri never speaks X11 itself.
                    xwayland-satellite
                    swaybg
                    swayidle
                    ;; wbg is the wallpaper engine's alternative renderer:
                    ;; layer-shell only, so it needs nothing from wlroots and
                    ;; works on Niri as-is.
                    wbg
                    ;; wev is how a keybinding is found: the input event names
                    ;; are what niri's config has to spell.
                    wev
                    wl-clipboard
                    brightnessctl
                    kitty
                    ;; The shell's menus and the capture scripts ask a question
                    ;; through zenity; without it a keybinding that needs an
                    ;; answer does nothing at all.
                    zenity
                    ;; xdg-open is what every launcher reaches for when it is
                    ;; asked to open a file or a link, and xdg-user-dirs is what
                    ;; makes the directories the session's own settings name -
                    ;; the screenshots directory among them - exist at all.  Two
                    ;; packages every desktop assumes and a curated list has to
                    ;; say out loud.
                    xdg-utils
                    xdg-user-dirs)))

;; ===========================================
;; The desktop: the programs a session is used with
;; ===========================================

;; Deliberately not a desktop environment.  There is no GNOME, no KDE and no
;; metapackage that would bring either, because the session is Niri plus the
;; shell - a bar, a launcher, a notification daemon and a lock screen that are
;; one program - and everything else is a program that was asked for.
;;
;; The capture stack is the list (heks-linux capture) drives: grim and slurp for
;; the region, satty to annotate it, wf-recorder for video and ffmpeg for the
;; GIF.  All five are Void packages, which is why none of them is a Flatpak;
;; wl-screenrec, the recorder the module prefers when it is installed, is not
;; packaged, and the module already falls back when it is absent.
;;
;; Emacs is the editor this tree is built around: heks-emacs carries its
;; configuration, and the editor itself is a program the session installs.
(define heks-linux-desktop-xbps
  (make-parameter '(cava
                    ;; The server rmpc is a client for: a window with nothing in
                    ;; it is what a machine without it gets.
                    mpd
                    emacs
                    ffmpeg
                    grim
                    mpv
                    pavucontrol
                    playerctl
                    rmpc
                    satty
                    slurp
                    wf-recorder)))

;; ===========================================
;; The command line
;; ===========================================

(define heks-linux-cli-xbps
  (make-parameter '("7zip"
                    bat
                    btop
                    cmatrix
                    ed
                    fastfetch
                    ;; fd is what dired and the project search reach for before
                    ;; find(1), and heks-emacs' doctor names it.
                    fd
                    fzf
                    gifsicle
                    ;; htop is the monitor a console gets without a desktop:
                    ;; btop is the session's, and an install in progress or a
                    ;; recovery shell has neither btop's colours nor its config.
                    htop
                    jq
                    ;; heks-help opens the quickstart with less, and a Void base
                    ;; carries no pager: without it the one command a lost
                    ;; person is told to type answers "command not found".
                    less
                    ;; mg is Emacs in a terminal - the same keys, no window, no
                    ;; daemon - for a console that has no session to open a
                    ;; frame on.  ed stays for the machine that has nothing
                    ;; else.
                    mg
                    ripgrep
                    ;; yq is the YAML half of what jq does for JSON.
                    yq
                    ;; The two archive formats nothing else on this list opens.
                    ;; 7zip reads every format and writes none of these, and a
                    ;; machine that cannot make a .zip is a machine somebody
                    ;; curses on the first day.
                    unzip
                    zip)))

;; ===========================================
;; Development
;; ===========================================

;; What the project's own tasks need, and what the editor's bridges look for.
;; The two package managers are here because this tree installs its shell, its
;; dock and its editor's packages from them - Void packages nix with a runit
;; service, and Guix arrives from its own installer.
;;
;; llvm is the package that carries clang, clang-tools-extra and lldb on Void:
;; the three have no template of their own, and the editor's clangd arrives with
;; them.  pandoc and gradle are here because Void packages both, which is why
;; they left the Nix list; distrobox is not, and is a program a machine installs
;; for itself.
(define heks-linux-dev-xbps
  (make-parameter '(cargo
                    curl
                    flatpak
                    gcc
                    git
                    ;; gpg verifies the Guix installer's download and decrypts
                    ;; the ECA key; wget is what that installer downloads with.
                    gnupg
                    gradle
                    guile
                    llvm
                    make
                    ;; ninja is the backend Meson and CMake drive, and
                    ;; heks-toon's own build needs it: Void packages it as
                    ;; `ninja', Debian as `ninja-build'.
                    ninja
                    nix
                    pandoc
                    pkg-config
                    podman
                    rust
                    wget)))

;; ===========================================
;; The fonts the session cannot start without
;; ===========================================

;; A compositor does not depend on a font, so a machine with none draws
;; rectangles.  DejaVu, Liberation and Noto cover Latin text and the interface's
;; glyph fallbacks; font-adobe-source-serif-pro is Source Serif 4, the face the
;; session renders prose in, and the one of the desktop's three faces Void
;; carries.  JuliaMono and Work Sans have no Void package, so they stay outside
;; the distribution list: a machine installs them itself, and the fontconfig
;; fallbacks cover the gap until it does.
(define heks-linux-font-xbps
  (make-parameter '(dejavu-fonts-ttf
                    font-adobe-source-serif-pro
                    liberation-fonts-ttf
                    noto-fonts-ttf
                    ;; Emoji in colour, and CJK: a session that draws a page of
                    ;; Japanese as boxes and a face as a rectangle is a session
                    ;; with a fallback list that stops at Latin.
                    noto-fonts-emoji
                    noto-fonts-cjk)))

(define (xbps-package-name package)
  "Return @var{package}'s name.
A category spells a name as a symbol, except where the name is not a valid
symbol such as \"7zip\"; both are accepted here rather than at every call site."
  (if (symbol? package)
    (symbol->string package)
    package))

;; The login prompt is part of the session, not an optional extra: a machine
;; with niri and no greeter boots to a console that has to be told what to run.
;; (heks-linux greeter) owns the prompt, so the packages come from there and
;; there is one place to read what logging in needs.
(define (heks-linux-xbps)
  "Return the packages this tree installs on a Void machine."
  (package-sorted-set
   (append (heks-linux-repository-xbps)
           (heks-linux-session-xbps)
           greeter-packages
           ;; The machine's log.  Void ships no syslog daemon, and every service
           ;; that has a log/run hands its output to one anyway: on a machine
           ;; without socklog those lines are thrown away, and what is left on
           ;; the console the prompt is drawn on is the kernel's own printk.
           logging-packages
           (heks-linux-desktop-xbps)
           (heks-linux-cli-xbps)
           (heks-linux-dev-xbps)
           (heks-linux-font-xbps))
   xbps-package-name))

(define (xbps-install-args packages)
  "Return the argument vector that installs @var{packages} with xbps.

@code{sudo} is an argument rather than the beginning of a shell line, and every
package name is the argument @code{xbps-install} receives: a name that was
checked by @code{package-name?} is never interpolated into a command.
@code{-S} is the repository sync - a machine that has not synced installs
yesterday's index and then reports a package that does not exist."
  (append (list "sudo" "xbps-install" "-S" "--yes")
          (map xbps-package-name packages)))

;; The xbps backend: Void's own package manager.
(define xbps-backend
  (package-backend 'xbps
                   #:packages (lambda () (heks-linux-xbps))
                   #:name-of xbps-package-name
                   #:name-valid? package-name?
                   #:install (lambda (packages)
                               (let ((argv (xbps-install-args packages)))
                                 (run-package-command (car argv)
                                                      (cdr argv))))))

(define (install-xbps)
  "Install every package @code{heks-linux-xbps} names with xbps.
The list is the deduplicated union of the category lists declared in this
module, so a package needed by two categories is installed once.  This is the
one task that needs administrator rights, and it prompts for them."
  (package-backend-install xbps-backend (heks-linux-xbps)))
