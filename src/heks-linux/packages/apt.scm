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

(define-module (heks-linux packages apt)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:export (heks-linux-apt heks-linux-cli-apt
                           heks-linux-desktop-apt
                           heks-linux-dev-apt
                           heks-linux-dict-apt
                           heks-linux-font-apt
                           heks-linux-graphics-apt
                           heks-linux-lib-apt
                           heks-linux-media-apt
                           heks-linux-music-apt
                           heks-linux-net-apt
                           heks-linux-other-apt
                           heks-linux-power-user-apt
                           heks-linux-printing-apt
                           install-apt))

(define heks-linux-cli-apt
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
                              xxd
                              xxd
                              ;; msedit
                              ;; onefetch
                              ;; p7zip
                              ;; p7zip-plugins
                              ;; rg
                              )))

(define heks-linux-desktop-apt
  (make-parameter '(blueman brightnessctl
                            clipman
                            fyi
                            network-manager-applet
                            rofi
                            rofimoji
                            slurp
                            swaybg
                            swayidle
                            swaylock
                            wev
                            wf-recorder
                            wdisplays
                            wshowkeys
                            zenity
                            zenity
                            ;; cairo-dock
                            ;; cairo-dock-plug-ins
                            ;; mako
                            ;; NetworkManager-tui
                            ;; niri
                            )))

(define heks-linux-dev-apt
  (make-parameter '(cmake diffutils
                          gh
                          git
                          gnuplot
                          graphviz
                          httpie
                          just
                          kubectl
                          patch
                          podman-compose
                          python3-pip
                          remmina
                          sbcl
                          shfmt
                          sqlitebrowser
                          stress
                          stress-ng
                          ;; drill
                          ;; nodejs-bash-language-server
                          ;; python3-wxpython4
                          ;; ShellCheck
                          ;; sqlite
                          )))

(define heks-linux-dict-apt
  (make-parameter '(aspell aspell-ca
                           aspell-en
                           aspell-es
                           aspell-nl
                           aspell-pt
                           ;; enchant
                           ;; enchant2-devel
                           ;; enchant-aspell
                           )))

(define heks-linux-font-apt
  (make-parameter '(fonts-font-awesome fonts-ibm-plex
                                       fonts-iosevka
                                       fonts-noto-color-emoji
                                       ;; ibm-plex-fonts-all
                                       ;; google-android-emoji-fonts
                                       ;; google-noto-color-emoji-fonts
                                       ;; google-noto-emoji-fonts
                                       )))

(define heks-linux-graphics-apt
  (make-parameter '(feh gimp inkscape)))

(define heks-linux-lib-apt
  (make-parameter '(nghttp2 pkgconf
                            ;; ImageMagick
                            ;; libavif
                            ;; libvterm
                            ;; libvterm-devel
                            ;; libvterm-tools
                            ;; libwebp
                            ;; pkgconf-pkg-config
                            )))

(define heks-linux-media-apt
  (make-parameter '(ffmpeg mpc
                           mpd
                           obs-studio
                           playerctl
                           vlc
                           yt-dlp
                           ;; blender
                           ;; cheese
                           ;; libavcodec-freeworld
                           )))

(define heks-linux-music-apt
  (make-parameter '(audacity lilypond pavucontrol qpwgraph
                             ;; ardour8
                             )))

(define heks-linux-net-apt
  (make-parameter '(openvpn wireshark
                            ;; darkhttpd
                            )))

(define heks-linux-other-apt
  (make-parameter '()))

(define heks-linux-power-user-apt
  (make-parameter '(direnv distrobox emacs-pgtk texinfo texlive)))

(define heks-linux-printing-apt
  (make-parameter '(cups cups-browsed hp-ppd printer-driver-all)))

(define heks-linux-apt
  (let* ((xs (delete-duplicates (append (heks-linux-cli-apt)
                                        (heks-linux-desktop-apt)
                                        (heks-linux-dev-apt)
                                        (heks-linux-dict-apt)
                                        (heks-linux-font-apt)
                                        (heks-linux-graphics-apt)
                                        (heks-linux-lib-apt)
                                        (heks-linux-media-apt)
                                        (heks-linux-music-apt)
                                        (heks-linux-net-apt)
                                        (heks-linux-other-apt)
                                        (heks-linux-power-user-apt)
                                        (heks-linux-printing-apt)))))
    (sort xs
          (lambda (a b)
            (string<? (if (symbol? a)
                          (symbol->string a) a)
                      (if (symbol? b)
                          (symbol->string b) b))))))

(define (install-apt)
  (let* ((cmd (format #f "sudo apt-get install -y ~a"
                      (string-join (map (lambda (s)
                                          (format #f "~a" s)) heks-linux-apt)
                                   " "))))
    (format #t "\nExecuting command: ~a\n" cmd)
    (syscall cmd)))
