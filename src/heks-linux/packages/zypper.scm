;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

(define-module (heks-linux packages zypper)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:export (heks-linux-zypper heks-linux-cli-zypper
                              heks-linux-desktop-zypper
                              heks-linux-session-zypper
                              heks-linux-dev-zypper
                              heks-linux-dict-zypper
                              heks-linux-font-zypper
                              heks-linux-graphics-zypper
                              heks-linux-lib-zypper
                              heks-linux-media-zypper
                              heks-linux-music-zypper
                              heks-linux-net-zypper
                              heks-linux-other-zypper
                              heks-linux-power-user-zypper
                              install-zypper))

(define heks-linux-cli-zypper
  (make-parameter '(bat
                              btop
                              cbonsai
                              cmatrix
                              cpufetch
                              ed
                              fastfetch
                              fzf
                              gifsicle
                              msedit
                              onefetch
                              "7zip"
                              p7zip
                              ripgrep
                              wezterm
                              xxd)))

(define heks-linux-desktop-zypper
  (make-parameter '(blueman brightnessctl
                            clipman
                            fyi
                            mako
                            cockpit
                            myrlyn
                            nm-tray
                            NetworkManager-applet
                            NetworkManager-tui
                            niri
                            rofi
                            ;; python-rofimoji
                            swaybg
                            swayidle
                            swaylock
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
  ;; The session itself: the display manager, the bar, the editor, the audio
  ;; stack and the portals a Wayland desktop needs to work at all.  These are
  ;; the packages a machine had to get some other way - from a distribution's
  ;; desktop pattern, or by hand - before this list named them, which meant a
  ;; fresh Slowroll with nothing but this list installed had no bar and no
  ;; editor.  They are also what a live image has to carry to boot into the
  ;; desktop rather than into a prompt.
  (make-parameter '(NetworkManager
                    emacs
                    fontconfig
                    gdm
                    guile
                    pipewire
                    pipewire-pulseaudio
                    polkit
                    waybar
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
                          pastel
                          gdb
                          gnuplot
                          graphviz
                          httpie
                          just
                          kubernetes-client
                          ;; nodejs-bash-language-server
                          meson
                          ninja
                          gcc
                          pkg-config
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
                          osc
                          patch
                          podman-compose
                          python3-pip
                          python3-wxPython
                          remmina
                          rpm-devel
                          rpmdevtools
                          rpmlint
                          sbcl
                          ShellCheck
                          shfmt
                          sqlite3
                          sqlitebrowser
                          ;; stress
                          stress-ng)))

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
                                                 intel-one-mono-fonts
                                                 dejavu-fonts
                                                 fontawesome-fonts
                                                 fetchmsttfonts
                                                 gnu-free-fonts
                                                 ibm-plex-fonts)))

(define heks-linux-graphics-zypper
  (make-parameter '(feh gimp inkscape)))

(define heks-linux-lib-zypper
  (make-parameter '(ImageMagick libavif16
                                libvterm0
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
                           wf-recorder
                           slurp)))

(define heks-linux-power-user-zypper
  (make-parameter '(direnv distrobox texinfo texlive)))

(define heks-linux-zypper
  (let* ((xs (delete-duplicates (append (heks-linux-cli-zypper)
                                        (heks-linux-desktop-zypper)
                                        (heks-linux-session-zypper)
                                        (heks-linux-dev-zypper)
                                        (heks-linux-dict-zypper)
                                        (heks-linux-font-zypper)
                                        (heks-linux-graphics-zypper)
                                        (heks-linux-lib-zypper)
                                        (heks-linux-media-zypper)
                                        (heks-linux-music-zypper)
                                        (heks-linux-net-zypper)
                                        (heks-linux-other-zypper)
                                        (heks-linux-power-user-zypper)))))
    (sort xs
          (lambda (a b)
            (string<? (if (symbol? a)
                          (symbol->string a) a)
                      (if (symbol? b)
                          (symbol->string b) b))))))

(define (install-zypper)
  "Install every package in @code{heks-linux-zypper} with the system package
manager.
The list is the deduplicated union of the category lists declared in this
module, so a package needed by two categories is installed once.  This is the
one task that needs administrator rights, and it prompts for them."
  (let* ((cmd (format #f "sudo zypper --quiet --color install -y ~a"
                      (string-join (map (lambda (s)
                                          (format #f "~a" s))
                                        heks-linux-zypper) " "))))
    (format #t "\nExecuting command: ~a\n" cmd)
    (syscall cmd)))
