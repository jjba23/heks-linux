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
  #:export (heks-linux-apt heks-linux-other-apt
                           heks-linux-graphics-apt
                           heks-linux-power-user-apt
                           heks-linux-lib-apt
                           heks-linux-net-apt
                           heks-linux-font-apt
                           install-apt))

(define heks-linux-graphics-apt
  (make-parameter '(gimp inkscape)))

(define heks-linux-media-apt
  (make-parameter '(obs-studio ;blender
                               vlc
                               ;; libavcodec-freeworld
                               yt-dlp)))

(define heks-linux-other-apt
  (make-parameter '(blueman cmatrix
                            cbonsai
                            wdisplays
                            ;; msedit
                            wshowkeys
                            ed
                            distrobox
                            git
                            nghttp2
                            ;; p7zip
                            ;; p7zip-plugins
                            python3-pip
                            ;; python3-wxpython4

                            wev
                            ;; cheese
                            )))

(define heks-linux-power-user-apt
  (make-parameter '(alacritty kitty
                              bat
                              most
                              texinfo
                              texlive
                              emacs-pgtk
                              ;; niri
                              cairo-dock
                              cairo-dock-plug-ins
                              feh
                              ;; rg
                              rofi
                              rofimoji
                              fastfetch
                              cpufetch
                              fyi
                              direnv
                              btop
                              ;; onefetch
                              swayidle
                              swaybg
                              swaylock
                              fzf
                              ;; mako
                              brightnessctl
                              zenity)))

(define heks-linux-dev-apt
  (make-parameter '(gh just
                       shfmt
                       ;; ShellCheck
                       kubectl
                       httpie
                       sbcl
                       ;; drill
                       podman-compose
                       remmina
                       stress
                       stress-ng
                       patch
                       diffutils
                       ;; sqlite
                       sqlitebrowser
                       ;; nodejs-bash-language-server
                       )))

(define heks-linux-lib-apt
  (make-parameter '(network-manager-applet
                    ;; NetworkManager-tui
                    pkgconf
                    ;; pkgconf-pkg-config
                    xxd
                    ;; ImageMagick
                    ;; libavif
                    ;; libwebp
                    gnuplot
                    graphviz
                    ;; libvterm-devel
                    ;; libvterm-tools
                    ;; libvterm
                    zenity
                    clipman
                    xxd
                    cmake)))

(define heks-linux-music-apt
  (make-parameter '(lilypond pavucontrol ;ardour8
                             qpwgraph audacity)))

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

(define heks-linux-net-apt
  (make-parameter '(wireshark openvpn ;darkhttpd
                              )))

(define heks-linux-font-apt
  (make-parameter '( ;ibm-plex-fonts-all
                     fonts-font-awesome
                    fonts-noto-color-emoji
                    fonts-iosevka
                    fonts-ibm-plex
                    ;; google-android-emoji-fonts
                    ;; google-noto-emoji-fonts
                    ;; google-noto-color-emoji-fonts
                    )))

(define heks-linux-apt
  (let* ((xs (delete-duplicates (append (heks-linux-graphics-apt)
                                        (heks-linux-other-apt)
                                        (heks-linux-power-user-apt)
                                        (heks-linux-dev-apt)
                                        (heks-linux-lib-apt)
                                        (heks-linux-dict-apt)
                                        (heks-linux-net-apt)
                                        (heks-linux-font-apt)
                                        (heks-linux-music-apt)
                                        (heks-linux-media-apt)))))
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
    (display (format #f "\nExecuting command: ~a\n" cmd))
    (syscall cmd)))
