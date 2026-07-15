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

(define-module (heks-linux packages flatpak)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:export (heks-linux-flatpak install-flatpak))

(define heks-linux-music-flatpak
  (make-parameter '(dev.diegovsky.Riff com.spotify.Client io.bassi.Amberol
                                       de.haeckerfelix.Shortwave
                                       dev.bragefuglseth.Fretboard)))

(define heks-linux-gaming-flatpak
  (make-parameter '(org.libretro.RetroArch "flathub net.retrodeck.retrodeck"
                                           org.prismlauncher.PrismLauncher
                                           page.kramo.Cartridges)))

(define heks-linux-net-flatpak
  (make-parameter '(com.brave.Browser com.usebruno.Bruno
                                      engineer.atlas.Nyxt
                                      "flathub org.gnome.Epiphany"
                                      "flathub com.github.hugolabe.Wike"
                                      com.rtosta.zapzap
                                      com.discordapp.Discord
                                      io.gitlab.news_flash.NewsFlash
                                      "flathub de.haeckerfelix.Fragments")))

(define heks-linux-media-flatpak
  (make-parameter '("flathub org.kde.kdenlive" io.gitlab.adhami3310.Converter
                    org.gnome.gitlab.YaLTeR.VideoTrimmer
                    io.github.wartybix.Constrict com.github.huluti.Curtail)))

(define heks-linux-other-flatpak
  (make-parameter '("flathub com.github.tchx84.Flatseal"
                    com.belmoussaoui.Decoder
                    io.gitlab.adhami3310.Impression
                    net.nokyan.Resources
                    "flathub app.drey.Dialect"
                    io.github.idevecore.Valuta
                    dev.mufeed.Wordbook
                    org.signal.Signal
                    org.gnome.Solanum
                    app.drey.Warp)))

(define heks-linux-work-flatpak
  (make-parameter '("flathub com.slack.Slack")))

(define heks-linux-dev-flatpak
  (make-parameter '(io.github.fizzyizzy05.binary org.gnome.design.Emblem
                    org.gnome.design.Lorem
                    com.rafaelmardojai.WebfontKitGenerator
                    re.sonny.Workbench
                    org.gaphor.Gaphor
                    io.gitlab.liferooter.TextPieces
                    se.sjoerd.Graphs
                    com.github.finefindus.eyedropper
                    ;; "flathub com.jetbrains.IntelliJ-IDEA-Ultimate"
                    ;; "flathub com.jetbrains.DataGrip"
                    com.mardojai.ForgeSparks)))

(define heks-linux-flatpak
  (let* ((xs (delete-duplicates (append (heks-linux-music-flatpak)
                                        (heks-linux-dev-flatpak)
                                        (heks-linux-gaming-flatpak)
                                        (heks-linux-net-flatpak)
                                        (heks-linux-work-flatpak)
                                        (heks-linux-other-flatpak)
                                        (heks-linux-media-flatpak)))))
    (sort xs
          (lambda (a b)
            (string<? (if (symbol? a)
                          (symbol->string a) a)
                      (if (symbol? b)
                          (symbol->string b) b))))))

(define (install-flatpak)
  (for-each (lambda (pkg)
              (let* ((cmd (format #f "flatpak install --user -y ~a" pkg)))
                (format #t "\nExecuting command: ~a\n" cmd)
                (syscall cmd))) heks-linux-flatpak))
