;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

(define-module (heks-linux packages zypper)
  #:declarative? #t
  #:use-module (heks-linux packages)
  #:export (heks-linux-zypper heks-linux-cli-zypper
                              heks-linux-desktop-zypper
                              heks-linux-session-zypper
                              heks-linux-dev-zypper
                              heks-linux-rust-zypper
                              heks-linux-debug-zypper
                              heks-linux-profile-zypper
                              heks-linux-database-zypper
                              heks-linux-scheme-zypper
                              heks-linux-jvm-zypper
                              heks-linux-dict-zypper
                              heks-linux-font-zypper
                              heks-linux-graphics-zypper
                              heks-linux-lib-zypper
                              heks-linux-media-zypper
                              heks-linux-music-zypper
                              heks-linux-net-zypper
                              heks-linux-other-zypper
                              heks-linux-power-user-zypper
                              zypper-package-name
                              zypper-install-args
                              zypper-backend
                              install-zypper))

(define heks-linux-cli-zypper
  (make-parameter '(bat
                    btop
                    cbonsai
                    cmatrix
                    cpufetch
                    ;; .dmg disk images: dmg2img unwraps a
                    ;; compressed .dmg into the HFS+ image inside it,
                    ;; and 7z (above) opens either.  Nothing here
                    ;; writes a .dmg back; that needs libdmg-hfsplus,
                    ;; which none of the repositories carry.
                    dmg2img
                    ed
                    fastfetch
                    ;; fd is what dired and the project search reach for
                    ;; before find(1), and heks-emacs' doctor names it.
                    fd
                    fzf
                    gifsicle
                    msedit
                    onefetch
                    ;; opencode is the terminal chat that speaks the providers
                    ;; ECA's own login does not cover, and Slowroll packages it.
                    opencode
                    "7zip"
                    ripgrep
                    wezterm
                    xxd
                    ;; yq is the YAML half of what jq does for JSON.
                    yq)))

(define heks-linux-desktop-zypper
  (make-parameter '(brightnessctl
                    fyi
                    cockpit
                    myrlyn
                    NetworkManager-tui
                    niri
                    swaybg
                    swayidle
                    ;; wbg is the wallpaper engine's alternative
                    ;; renderer: layer-shell only, so it needs nothing
                    ;; from wlroots and works on Niri as-is.
                    wbg
                    wev
                    wl-clipboard
                    rmpc
                    cava
                    wdisplays
                    ;; wshowkeys
                    zenity)))

(define heks-linux-session-zypper
  ;; The session itself: the display manager, the editor, the audio stack and
  ;; the portals a Wayland desktop needs to work at all.  These are the packages
  ;; a machine had to get some other way - from a distribution's desktop
  ;; pattern, or by hand - before this list named them, which meant a fresh
  ;; Slowroll with nothing but this list installed had no editor.  They are also
  ;; what a live image has to carry to boot into the desktop rather than into a
  ;; prompt.
  ;;
  ;; The bar is not here: the shell that draws it is whelk, which no openSUSE
  ;; repository carries, so it comes from `packages/nix.scm' with the rest of
  ;; the collection.
  (make-parameter '(NetworkManager
                    emacs
                    fontconfig
                    gdm
                    guile
                    pipewire
                    pipewire-pulseaudio
                    polkit
                    ;; The bar's power-profile reading is powerprofilesctl, and
                    ;; the module goes quiet when nothing provides it; the
                    ;; daemon is what backs the toggle as well as the reading.
                    power-profiles-daemon
                    wireplumber
                    xdg-desktop-portal-gnome
                    xdg-desktop-portal-gtk
                    xdg-user-dirs)))

(define heks-linux-dev-zypper
  (make-parameter '(build cmake
                          diffutils
                          ldns
                          gh
                          git
                          ;; git-delta: the diff viewer Git's output is read
                          ;; through.  It is installed here, not in
                          ;; packages/nix.scm, because Slowroll packages it.
                          git-delta
                          pastel
                          gdb
                          ;; clang and its tools: the clang package carries
                          ;; clangd (the C and C++ language server), clang-tidy
                          ;; and clang-format, and clang-tools the analysis
                          ;; scripts around them.  heks-toon (meson) and Guix
                          ;; (autotools) are the C in this tree.
                          clang
                          clang-tools
                          ;; The autotools Guix is built with, for a checkout
                          ;; of it that has to run ./bootstrap.
                          autoconf
                          automake
                          libtool
                          gettext-tools
                          gnuplot
                          graphviz
                          httpie
                          just
                          kubernetes-client
                          ;; The editor's language servers that openSUSE
                          ;; packages: Lua and TOML.  Everything else -
                          ;; yaml-language-server, nil, marksman, the VS Code
                          ;; JSON/CSS/HTML set, TypeScript, Pyright, Meson,
                          ;; CMake and Bash (openSUSE dropped its package) - is
                          ;; declared in packages/nix.scm and installed by
                          ;; `maak install-nix-packages'.
                          lua-language-server
                          nodejs-default
                          taplo
                          meson
                          ninja
                          gcc
                          ;; pkgconf-pkg-config is the /usr/bin/pkg-config shim
                          ;; the installed pkgconf provides the engine for.
                          pkgconf-pkg-config
                          gtk4-devel
                          gtk4-layer-shell-devel
                          guile-devel
                          flatpak-builder
                          wayland-devel
                          wayland-protocols-devel
                          rpm-build
                          rpmdevtools
                          osc
                          rpmlint
                          patch
                          ;; openSUSE packages compose as docker-compose; podman
                          ;; drives it through its docker-compatible socket.
                          docker-compose
                          python313-pip
                          python313-wxPython
                          remmina
                          rpm-devel
                          sbcl
                          ShellCheck
                          shfmt
                          sqlite3
                          sqlitebrowser
                          ;; stress
                          stress-ng)))

(define heks-linux-rust-zypper
  ;; The Rust side of the dev list.  The distribution's toolchain is two
  ;; packages - rust for rustc and the standard library, cargo for the build
  ;; tool - and sccache and mold are what makes a rebuild fast, cargo-audit
  ;; reads Cargo.lock for advisories.
  ;;
  ;; rustup is deliberately not here: openSUSE's cargo provides `rust+cargo',
  ;; which rustup conflicts with, so a machine installs one toolchain manager or
  ;; the other and zypper stops on the pair.  The projects that pin a channel
  ;; (lambdock, whelk) get their toolchain from their own Guix manifests, and
  ;; rust-analyzer, clippy and rustfmt come from packages/nix.scm.
  (make-parameter '(cargo
                    cargo-audit
                    lld
                    mold
                    rust
                    sccache)))

(define heks-linux-debug-zypper
  ;; gdb is in the dev list; this is the rest of what a broken program is read
  ;; with: a second debugger, two syscall tracers, the record-and-replay one
  ;; for a bug that will not reproduce, and the DWARF tools that turn an
  ;; address into a line.
  (make-parameter '(binutils
                    dwarves
                    elfutils
                    lldb
                    ltrace
                    patchelf
                    rr
                    strace
                    valgrind)))

(define heks-linux-profile-zypper
  ;; Where the time goes, after `perf' says there is a problem: the sampler and
  ;; its window, the heap profiler, the two cachegrind front ends, the system
  ;; profiler, the eBPF tracer and the benchmark that decides whether the
  ;; change helped.
  (make-parameter '(bpftrace
                    heaptrack
                    hotspot
                    hyperfine
                    kcachegrind
                    massif-visualizer
                    perf
                    sysprof)))

(define heks-linux-database-zypper
  ;; The servers and the client for the three databases a project is likely to
  ;; talk to.  The shells and GUIs Slowroll does not carry - pgcli, mycli,
  ;; usql, dbeaver, duckdb and sqlite-utils - come from packages/nix.scm.
  (make-parameter '(mariadb
                    postgresql
                    valkey)))

(define heks-linux-scheme-zypper
  ;; The Lisp family.  guile and emacs are in the session list, guile-devel and
  ;; sbcl in the dev one; these are the implementations and the Guile modules a
  ;; machine starting from this list would otherwise lack.  guile-lib,
  ;; guile-ssh and chicken are not packaged by Slowroll, so they are declared
  ;; in packages/nix.scm.
  (make-parameter '(clisp
                    ecl
                    guile-gcrypt
                    guile-json
                    racket)))

(define heks-linux-jvm-zypper
  ;; Java and the JVM languages.  The JDK carries its own headers, Maven and
  ;; Ant are the build tools openSUSE packages, and Clojure and Leiningen ride
  ;; on the same JDK.  Kotlin, Gradle, the JDT language server and clojure-lsp
  ;; are not packaged for Slowroll: they are declared in packages/nix.scm.
  ;;
  ;; The JDK is 25, not 21: symbanta is a Spring Boot service that builds
  ;; against 25, and its own flake pins jdk25 for the wrapper.
  (make-parameter '(ant
                    clojure
                    java-25-openjdk-devel
                    leiningen
                    maven)))

(define heks-linux-dict-zypper
  (make-parameter '(aspell aspell-ca
                           aspell-en
                           aspell-es
                           aspell-nl
                           aspell-pt_PT
                           enchant
                           libenchant-2-2
                           enchant-devel)))

(define heks-linux-font-zypper
  (make-parameter '(google-noto-coloremoji-fonts google-noto-sans-fonts
                                                 google-noto-sans-cjk-fonts
                                                 google-worksans-fonts
                                                 texlive-juliamono-fonts
                                                 adobe-sourceserif4-fonts
                                                 dejavu-fonts
                                                 fontawesome-fonts
                                                 fetchmsttfonts
                                                 gnu-free-fonts
                                                 ibm-plex-fonts)))

(define heks-linux-graphics-zypper
  (make-parameter '(feh gimp inkscape
                        ;; png2icns, icns2png and icontainer2icns: the round
                        ;; trip between PNG and .icns.  ImageMagick, in
                        ;; the lib category below, reads and writes icns too, but
                        ;; only this toolkit builds the several sizes an icon
                        ;; carries from a set of PNGs.
                        icns-utils)))

(define heks-linux-lib-zypper
  ;; libavif16 is not here, though it is installed: the update repo's newest
  ;; build needs libSvtAv1Enc4 4.3.0, and the rest of the distribution -
  ;; gstreamer-plugins-bad, ffmpeg's libavcodec63, the installed libavif itself
  ;; - still requires SVT_4.2.0, so the solver refuses the pair.  A library the
  ;; tools below pull in as a dependency is not a tool this list has to name.
  (make-parameter '(ImageMagick libvterm0
                                libvterm-devel
                                libvterm-tools
                                libwebp-devel
                                nghttp2
                                pkgconf)))

(define heks-linux-media-zypper
  (make-parameter '(blender cheese
                            ffmpeg
                            obs-studio
                            playerctl
                            vlc
                            mpv
                            mpv-mpris
                            yt-dlp)))

(define heks-linux-music-zypper
  (make-parameter '(ardour audacity lilypond pavucontrol qpwgraph)))

(define heks-linux-net-zypper
  (make-parameter '(darkhttpd openvpn wireshark)))

(define heks-linux-other-zypper
  (make-parameter '(gramps gramps-lang
                           sshfs
                           cifs-utils
                           gnome-calendar
                           ;; What the capture program drives: grim takes the
                           ;; picture, wl-screenrec is the GPU recorder (still
                           ;; with wf-recorder behind it), and slurp the region.
                           grim
                           wl-screenrec
                           wf-recorder
                           slurp)))

;; distrobox is the container front end and podman is the manager it runs on;
;; podman is named here rather than left to a dependency, because a machine
;; without a container manager answers every distrobox command with an error
;; about the manager instead of about the box.
;;
;; podman-docker is the CLI shim: the editor's container menu runs `docker'
;; commands, and heks-emacs' doctor names docker, while podman stays the daemon
;; that actually runs the containers.  It is not the moby runtime - that would
;; be a second daemon.
(define heks-linux-power-user-zypper
  (make-parameter '(direnv distrobox podman podman-docker texinfo texlive)))

(define (zypper-package-name package)
  "Return @var{package}'s name.
A category spells a name as a symbol, except where the name is not a valid
symbol such as \"7zip\"; both are accepted here rather than at every call site."
  (if (symbol? package)
    (symbol->string package)
    package))

(define heks-linux-zypper
  (package-sorted-set
   (append (heks-linux-cli-zypper)
           (heks-linux-desktop-zypper)
           (heks-linux-session-zypper)
           (heks-linux-dev-zypper)
           (heks-linux-rust-zypper)
           (heks-linux-debug-zypper)
           (heks-linux-profile-zypper)
           (heks-linux-database-zypper)
           (heks-linux-scheme-zypper)
           (heks-linux-jvm-zypper)
           (heks-linux-dict-zypper)
           (heks-linux-font-zypper)
           (heks-linux-graphics-zypper)
           (heks-linux-lib-zypper)
           (heks-linux-media-zypper)
           (heks-linux-music-zypper)
           (heks-linux-net-zypper)
           (heks-linux-other-zypper)
           (heks-linux-power-user-zypper))
   zypper-package-name))

(define (zypper-install-args packages)
  "Return the argument vector that installs @var{packages} with zypper.

@code{sudo} is an argument rather than the beginning of a shell line, and every
package name is the argument zypper receives: a name that was checked by
@code{package-name?} is never interpolated into a command."
  (append (list "sudo" "zypper" "--quiet" "--color" "install" "-y")
          (map zypper-package-name packages)))

;; The zypper backend: the distribution's own package manager.
(define zypper-backend
  (package-backend 'zypper
                   #:packages (lambda () heks-linux-zypper)
                   #:name-of zypper-package-name
                   #:name-valid? package-name?
                   #:install (lambda (packages)
                               (let ((argv (zypper-install-args packages)))
                                 (run-package-command (car argv)
                                                      (cdr argv))))))

(define (install-zypper)
  "Install every package in @code{heks-linux-zypper} with the system package
manager.
The list is the deduplicated union of the category lists declared in this
module, so a package needed by two categories is installed once.  This is the
one task that needs administrator rights, and it prompts for them."
  (package-backend-install zypper-backend heks-linux-zypper))
