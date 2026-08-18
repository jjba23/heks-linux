;;; heks-linux

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; heks-linux is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; heks-linux is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with heks-linux.  If not, see <https://www.gnu.org/licenses/>.

(define-module (heks-linux packages dnf)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:export (heks-linux-dnf heks-linux-cli-dnf
                           heks-linux-desktop-dnf
                           heks-linux-dev-dnf
                           heks-linux-dict-dnf
                           heks-linux-font-dnf
                           heks-linux-graphics-dnf
                           heks-linux-lib-dnf
                           heks-linux-media-dnf
                           heks-linux-music-dnf
                           heks-linux-net-dnf
                           heks-linux-other-dnf
                           heks-linux-power-user-dnf
                           install-dnf))

(define heks-linux-cli-dnf
  (make-parameter '(alacritty bat
                              btop
                              cbonsai
                              cmatrix
                              cpufetch
                              ed
                              fastfetch
                              fzf
                              kitty
                              most
                              msedit
                              onefetch
                              p7zip
                              p7zip-plugins
                              rg
                              xxd
                              xxd)))

(define heks-linux-desktop-dnf
  (make-parameter '(blueman brightnessctl
                            cairo-dock
                            cairo-dock-plug-ins-unstable
                            clipman
                            fyi
                            mako
                            network-manager-applet
                            NetworkManager-tui
                            niri
                            rofi
                            rofimoji
                            swaybg
                            swayidle
                            swaylock
                            wev
                            wdisplays
                            wshowkeys
                            zenity
                            zenity)))

(define heks-linux-dev-dnf
  (make-parameter '(cmake copr-cli
                          diffutils
                          drill
                          fedora-packager
                          fedpkg
                          gh
                          git
                          gnuplot
                          graphviz
                          httpie
                          just
                          kubectl
                          nodejs-bash-language-server
                          patch
                          podman-compose
                          python3-pip
                          python3-wxpython4
                          remmina
                          rpm-devel
                          rpmdevtools
                          rpmlint
                          sbcl
                          ShellCheck
                          shfmt
                          sqlite
                          sqlitebrowser
                          stress
                          stress-ng)))

(define heks-linux-dict-dnf
  (make-parameter '(aspell aspell-ca
                           aspell-en
                           aspell-es
                           aspell-nl
                           aspell-pt
                           enchant
                           enchant-aspell
                           enchant2-devel)))

(define heks-linux-font-dnf
  (make-parameter '(google-android-emoji-fonts google-noto-color-emoji-fonts
                                               google-noto-emoji-fonts
                                               ibm-plex-fonts-all)))

(define heks-linux-graphics-dnf
  (make-parameter '(feh gimp inkscape)))

(define heks-linux-lib-dnf
  (make-parameter '(ImageMagick libavif
                                libvterm
                                libvterm-devel
                                libvterm-tools
                                libwebp
                                nghttp2
                                pkgconf
                                pkgconf-pkg-config)))

(define heks-linux-media-dnf
  (make-parameter '(blender cheese
                            libavcodec-freeworld
                            obs-studio
                            playerctl
                            vlc
                            yt-dlp)))

(define heks-linux-music-dnf
  (make-parameter '(ardour8 audacity lilypond pavucontrol qpwgraph)))

(define heks-linux-net-dnf
  (make-parameter '(darkhttpd openvpn wireshark)))

(define heks-linux-other-dnf
  (make-parameter '()))

(define heks-linux-power-user-dnf
  (make-parameter '(direnv distrobox emacs-pgtk texinfo texlive)))

(define heks-linux-dnf
  (let* ((xs (delete-duplicates (append (heks-linux-cli-dnf)
                                        (heks-linux-desktop-dnf)
                                        (heks-linux-dev-dnf)
                                        (heks-linux-dict-dnf)
                                        (heks-linux-font-dnf)
                                        (heks-linux-graphics-dnf)
                                        (heks-linux-lib-dnf)
                                        (heks-linux-media-dnf)
                                        (heks-linux-music-dnf)
                                        (heks-linux-net-dnf)
                                        (heks-linux-other-dnf)
                                        (heks-linux-power-user-dnf)))))
    (sort xs
          (lambda (a b)
            (string<? (if (symbol? a)
                          (symbol->string a) a)
                      (if (symbol? b)
                          (symbol->string b) b))))))

(define (install-dnf)
  (let* ((cmd (format #f "sudo dnf install -y ~a"
                      (string-join (map (lambda (s)
                                          (format #f "~a" s)) heks-linux-dnf)
                                   " "))))
    (format #t "\nExecuting command: ~a\n" cmd)
    (syscall cmd)))
