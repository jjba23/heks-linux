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
  #:export (heks-linux-dnf heks-linux-other-dnf
                           heks-linux-graphics-dnf
                           heks-linux-power-user-dnf
                           heks-linux-lib-dnf
                           heks-linux-net-dnf
                           heks-linux-font-dnf
                           install-dnf))

(define heks-linux-graphics-dnf
  (make-parameter '(gimp inkscape)))

(define heks-linux-media-dnf
  (make-parameter '(obs-studio blender vlc libavcodec-freeworld yt-dlp)))

(define heks-linux-other-dnf
  (make-parameter '(blueman cmatrix
                            cbonsai
                            wdisplays
                            msedit
                            wshowkeys
                            ed
                            distrobox
                            git
                            p7zip
                            p7zip-plugins
                            python3-pip
                            python3-wxpython4
                            cairo-dock
                            cairo-dock-plug-ins-unstable
                            wev
                            cheese)))

(define heks-linux-power-user-dnf
  (make-parameter '(alacritty kitty
                              bat
                              most
                              texinfo
                              texlive
                              emacs-pgtk
                              niri
                              feh
                              rg
                              rofi
                              rofimoji
                              fastfetch
                              cpufetch
                              fyi
                              direnv
                              btop
                              onefetch
                              swayidle
                              swaybg
                              swaylock
                              fzf
                              mako
                              brightnessctl
                              zenity)))

(define heks-linux-dev-dnf
  (make-parameter '(gh just
                       shfmt
                       ShellCheck
                       kubectl
                       httpie
                       sbcl
                       drill
                       podman-compose
                       remmina
                       stress
                       stress-ng
                       fedora-packager
                       fedpkg
                       copr-cli
                       rpmdevtools
                       patch
                       diffutils
                       rpm-devel
                       rpmlint
                       nodejs-bash-language-server)))

(define heks-linux-lib-dnf
  (make-parameter '(network-manager-applet NetworkManager-tui
                                           pkgconf
                                           pkgconf-pkg-config
                                           xxd
                                           ImageMagick
                                           libavif
                                           libwebp
                                           gnuplot
                                           graphviz
                                           libvterm-devel
                                           libvterm-tools
                                           libvterm
                                           zenity
                                           clipman
                                           xxd
                                           cmake)))

(define heks-linux-music-dnf
  (make-parameter '(lilypond pavucontrol ardour8 qpwgraph audacity)))

(define heks-linux-dict-dnf
  (make-parameter '(aspell aspell-ca
                           aspell-en
                           aspell-es
                           aspell-nl
                           aspell-pt
                           enchant
                           enchant2-devel
                           enchant-aspell)))

(define heks-linux-net-dnf
  (make-parameter '(wireshark openvpn darkhttpd)))

(define heks-linux-font-dnf
  (make-parameter '(ibm-plex-fonts-all google-android-emoji-fonts
                                       google-noto-emoji-fonts
                                       google-noto-color-emoji-fonts)))

(define heks-linux-dnf
  (let* ((xs (delete-duplicates (append (heks-linux-graphics-dnf)
                                        (heks-linux-other-dnf)
                                        (heks-linux-power-user-dnf)
                                        (heks-linux-dev-dnf)
                                        (heks-linux-lib-dnf)
                                        (heks-linux-dict-dnf)
                                        (heks-linux-net-dnf)
                                        (heks-linux-font-dnf)
                                        (heks-linux-music-dnf)
                                        (heks-linux-media-dnf)))))
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
    (display (format #f "\nExecuting command: ~a\n" cmd))
    (syscall cmd)))

