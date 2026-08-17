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

(define-module (heks-linux packages zypper)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:export (heks-linux-zypper heks-linux-cli-zypper
                              heks-linux-desktop-zypper
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
                              7zip
                              p7zip
                              ripgrep
                              xxd)))

(define heks-linux-desktop-zypper
  (make-parameter '(blueman brightnessctl
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
                            zenity)))

(define heks-linux-dev-zypper
  (make-parameter '(build cmake
                          diffutils
                          drill
                          gh
                          git
                          gnuplot
                          graphviz
                          httpie
                          just
                          kubectl
                          bash-language-server
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
                          stress
                          stress-ng)))

(define heks-linux-dict-zypper
  (make-parameter '(aspell aspell-ca
                           aspell-en
                           aspell-es
                           aspell-nl
                           aspell-pt
                           enchant
                           libenchant-2-0
                           libenchant-2-devel)))

(define heks-linux-font-zypper
  (make-parameter '(google-noto-coloremoji-fonts google-noto-sans-fonts
                                                 ibm-plex-fonts)))

(define heks-linux-graphics-zypper
  (make-parameter '(feh gimp inkscape)))

(define heks-linux-lib-zypper
  (make-parameter '(ImageMagick libavif
                                libvterm
                                libvterm-devel
                                libvterm-tools
                                libwebp
                                nghttp2
                                pkgconf)))

(define heks-linux-media-zypper
  (make-parameter '(blender cheese
                            ffmpeg
                            obs-studio
                            playerctl
                            vlc
                            yt-dlp)))

(define heks-linux-music-zypper
  (make-parameter '(ardour audacity lilypond pavucontrol qpwgraph)))

(define heks-linux-net-zypper
  (make-parameter '(darkhttpd openvpn wireshark)))

(define heks-linux-other-zypper
  (make-parameter '()))

(define heks-linux-power-user-zypper
  (make-parameter '(direnv distrobox emacs-x11 texinfo texlive)))

(define heks-linux-zypper
  (let* ((xs (delete-duplicates (append (heks-linux-cli-zypper)
                                        (heks-linux-desktop-zypper)
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
  (let* ((cmd (format #f "sudo zypper install -y ~a"
                      (string-join (map (lambda (s)
                                          (format #f "~a" s))
                                        heks-linux-zypper) " "))))
    (format #t "\nExecuting command: ~a\n" cmd)
    (syscall cmd)))
