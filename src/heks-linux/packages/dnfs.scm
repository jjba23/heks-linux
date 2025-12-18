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

(define-module (heks-linux packages dnfs)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 string-fun)
  #:export (heks-linux-dnfs heks-linux-other-dnfs
                            heks-linux-graphics-dnfs
                            heks-linux-power-user-dnfs
                            heks-linux-lib-dnfs
                            heks-linux-net-dnfs
                            install-dnfs))

(define heks-linux-graphics-dnfs
  (make-parameter '(gimp inkscape)))

(define heks-linux-media-dnfs
  (make-parameter '(obs-studio blender vlc libavcodec-freeworld yt-dlp)))

(define heks-linux-other-dnfs
  (make-parameter '(blueman wdisplays wshowkeys)))

(define heks-linux-power-user-dnfs
  (make-parameter '(alacritty emacs-pgtk
                              niri
                              rg
                              rofi
                              rofimoji
                              fastfetch
                              fyi
                              direnv
                              swayidle
                              swaybg
                              swaylock
                              fzf
                              mako
                              brightnessctl
                              zenity)))

(define heks-linux-dev-dnfs
  (make-parameter '(gh just shfmt ShellCheck kubectl httpie sbcl nodejs-bash-language-server)))

(define heks-linux-lib-dnfs
  (make-parameter '(network-manager-applet pkgconf pkgconf-pkg-config xxd
                                           libvterm-devel
                                           libvterm-tools
                                           libvterm
                                           cmake)))

(define heks-linux-music-dnfs
  (make-parameter '(lilypond pavucontrol)))

(define heks-linux-dict-dnfs
  (make-parameter '(aspell aspell-ca
                           aspell-en
                           aspell-es
                           aspell-nl
                           aspell-pt
                           enchant
                           enchant2-devel
                           enchant-aspell)))

(define heks-linux-net-dnfs
  (make-parameter '(wireshark openvpn darkhttpd)))

(define heks-linux-dnfs
  (append (heks-linux-graphics-dnfs)
          (heks-linux-other-dnfs)
          (heks-linux-power-user-dnfs)
          (heks-linux-dev-dnfs)
          (heks-linux-lib-dnfs)
          (heks-linux-dict-dnfs)
          (heks-linux-net-dnfs)
          (heks-linux-music-dnfs)
          (heks-linux-media-dnfs)))

(define (install-dnfs)
  (let* ((cmd (format #f "sudo dnf install -y ~a"
                      (string-join (map (lambda (s)
                                          (format #f "~a" s)) heks-linux-dnfs)
                                   " "))))
    (display (format #f "\nExecuting command: ~a\n" cmd))
    (syscall cmd)))
