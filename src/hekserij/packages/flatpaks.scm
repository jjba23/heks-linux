;;; hekserij

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; hekserij is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; hekserij is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with hekserij.  If not, see <https://www.gnu.org/licenses/>.

;; Commentary:

;; It should be fine to install things like:
;; flatpak install -y com.example.org
;;
;; but if you run into conflicts, you can specify the remote
;; flatpak install -y flathub com.example.org

;; Code:

(define-module (hekserij packages flatpaks)
  #:declarative? #t
  #:use-module (hekserij prelude)
  #:use-module (ice-9 string-fun)
  #:export (hekserij-flatpaks install-flatpaks))

(define hekserij-music-flatpaks
  (make-parameter '(dev.diegovsky.Riff com.spotify.Client)))

(define hekserij-gaming-flatpaks
  (make-parameter '(com.valvesoftware.Steam org.libretro.RetroArch
                                            org.prismlauncher.PrismLauncher)))

(define hekserij-net-flatpaks
  (make-parameter '(com.brave.Browser com.usebruni.Bruno com.rtosta.zapzap
                                      com.discordapp.Discord)))

(define hekserij-media-flatpaks
  (make-parameter '("flathub org.kde.kdenlive")))

(define hekserij-other-flatpaks
  (make-parameter '("flathub com.github.tchx84.Flatseal")))

(define hekserij-flatpaks
  (append (hekserij-music-flatpaks)
          (hekserij-gaming-flatpaks)
          (hekserij-net-flatpaks)
          (hekserij-other-flatpaks)
          (hekserij-media-flatpaks)))

(define (install-flatpaks)
  (for-each (lambda (pkg)
              (let* ((cmd (format #f "flatpak install -y ~a" pkg)))
                (display (format #f "\nExecuting command: ~a\n" cmd))
                (syscall cmd))) hekserij-flatpaks))
