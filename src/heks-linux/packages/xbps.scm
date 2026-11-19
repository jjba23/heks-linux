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
  #:use-module (heks-linux packages)
  #:export (heks-linux-xbps
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
                    niri
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
                    zenity)))

;; ===========================================
;; The desktop: the programs a session is used with
;; ===========================================

;; Deliberately not a desktop environment.  There is no GNOME, no KDE and no
;; metapackage that would bring either, because the session is Niri plus the
;; shell - a bar, a launcher, a notification daemon and a lock screen that are
;; one program - and everything else is a program that was asked for.
(define heks-linux-desktop-xbps
  (make-parameter '(cava
                    ffmpeg
                    mpv
                    pavucontrol
                    playerctl
                    rmpc)))

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
                    jq
                    ripgrep
                    ;; yq is the YAML half of what jq does for JSON.
                    yq)))

;; ===========================================
;; Development
;; ===========================================

;; What the project's own tasks need, and what the editor's bridges look for.
;; The two package managers are here because this tree installs its shell, its
;; dock and its editor's packages from them - Void packages nix with a runit
;; service, and Guix arrives from its own installer.
(define heks-linux-dev-xbps
  (make-parameter '(cargo
                    clang
                    curl
                    distrobox
                    flatpak
                    gcc
                    git
                    guile
                    lldb
                    make
                    nix
                    pkg-config
                    podman
                    rust
                    wget)))

;; ===========================================
;; The fonts the session cannot start without
;; ===========================================

;; A compositor does not depend on a font, so a machine with none draws
;; rectangles.  These are the three families that cover Latin text and the
;; interface's glyph fallbacks; the desktop's own three faces - JuliaMono, Work
;; Sans and Source Serif 4 - are not Void packages and are installed by the
;; session's own task, which is where the rest of the branding already lives.
(define heks-linux-font-xbps
  (make-parameter '(dejavu-fonts-ttf
                    liberation-fonts-ttf
                    noto-fonts-ttf)))

(define (xbps-package-name package)
  "Return @var{package}'s name.
A category spells a name as a symbol, except where the name is not a valid
symbol such as \"7zip\"; both are accepted here rather than at every call site."
  (if (symbol? package)
    (symbol->string package)
    package))

(define heks-linux-xbps
  (package-sorted-set
   (append (heks-linux-session-xbps)
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
                   #:packages (lambda () heks-linux-xbps)
                   #:name-of xbps-package-name
                   #:name-valid? package-name?
                   #:install (lambda (packages)
                               (let ((argv (xbps-install-args packages)))
                                 (run-package-command (car argv)
                                                      (cdr argv))))))

(define (install-xbps)
  "Install every package in @code{heks-linux-xbps} with xbps.
The list is the deduplicated union of the category lists declared in this
module, so a package needed by two categories is installed once.  This is the
one task that needs administrator rights, and it prompts for them."
  (package-backend-install xbps-backend heks-linux-xbps))
