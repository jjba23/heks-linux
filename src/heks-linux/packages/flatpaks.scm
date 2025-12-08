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

;; Commentary:

;; It should be fine to install things like:
;; flatpak install -y com.example.org
;;
;; but if you run into conflicts, you can specify the remote
;; flatpak install -y flathub com.example.org

;; Code:

(define-module (heks-linux packages flatpaks)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 string-fun)
  #:export (heks-linux-flatpaks install-flatpaks))

(define heks-linux-music-flatpaks
  (make-parameter '(dev.diegovsky.Riff com.spotify.Client)))

(define heks-linux-gaming-flatpaks
  (make-parameter '(com.valvesoftware.Steam org.libretro.RetroArch
                                            org.prismlauncher.PrismLauncher)))

(define heks-linux-net-flatpaks
  (make-parameter '(com.brave.Browser com.usebruno.Bruno com.rtosta.zapzap
                                      com.discordapp.Discord)))

(define heks-linux-media-flatpaks
  (make-parameter '("flathub org.kde.kdenlive")))

(define heks-linux-other-flatpaks
  (make-parameter '("flathub com.github.tchx84.Flatseal")))

(define heks-linux-flatpaks
  (append (heks-linux-music-flatpaks)
          (heks-linux-gaming-flatpaks)
          (heks-linux-net-flatpaks)
          (heks-linux-other-flatpaks)
          (heks-linux-media-flatpaks)))

(define (install-flatpaks)
  (for-each (lambda (pkg)
              (let* ((cmd (format #f "flatpak install -y ~a" pkg)))
                (display (format #f "\nExecuting command: ~a\n" cmd))
                (syscall cmd))) heks-linux-flatpaks))
