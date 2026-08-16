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
  #:export (heks-linux-flatpak heks-linux-dev-flatpak
                               heks-linux-gaming-flatpak
                               heks-linux-media-flatpak
                               heks-linux-music-flatpak
                               heks-linux-net-flatpak
                               heks-linux-other-flatpak
                               heks-linux-work-flatpak
                               install-flatpak))

(define heks-linux-dev-flatpak
  (make-parameter '(com.github.finefindus.eyedropper com.bardojai.ForgeSparks
                    com.rafaelmardojai.WebfontKitGenerator
                    io.github.fizzyizzy05.binary
                    io.gitlab.liferooter.TextPieces
                    org.gaphor.Gaphor
                    org.gnome.design.Emblem
                    org.gnome.design.Lorem
                    re.sonny.Workbench
                    se.sjoerd.Graphs
                    ;; "flathub com.jetbrains.DataGrip"
                    ;; "flathub com.jetbrains.IntelliJ-IDEA-Ultimate"
                    )))

(define heks-linux-gaming-flatpak
  (make-parameter '("flathub net.retrodeck.retrodeck" org.libretro.RetroArch
                    org.prismlauncher.PrismLauncher page.kramo.Cartridges)))

(define heks-linux-media-flatpak
  (make-parameter '("flathub org.kde.kdenlive" com.github.huluti.Curtail
                    io.github.wartybix.Constrict
                    io.gitlab.adhami3310.Converter
                    org.gnome.gitlab.YaLTeR.VideoTrimmer)))

(define heks-linux-music-flatpak
  (make-parameter '(com.spotify.Client de.haeckerfelix.Shortwave
                                       dev.bragefuglseth.Fretboard
                                       dev.diegovsky.Riff io.bassi.Amberol)))

(define heks-linux-net-flatpak
  (make-parameter '("flathub com.github.hugolabe.Wike"
                    "flathub de.haeckerfelix.Fragments"
                    "flathub org.gnome.Epiphany"
                    com.brave.Browser
                    com.discordapp.Discord
                    com.rtosta.zapzap
                    com.usebruno.Bruno
                    engineer.atlas.Nyxt
                    io.gitlab.news_flash.NewsFlash)))

(define heks-linux-other-flatpak
  (make-parameter '("flathub app.drey.Dialect"
                    "flathub com.github.tchx84.Flatseal"
                    app.drey.Warp
                    com.belmoussaoui.Decoder
                    dev.mufeed.Wordbook
                    io.github.idevecore.Valuta
                    io.gitlab.adhami3310.Impression
                    net.nokyan.Resources
                    org.gnome.Solanum
                    org.signal.Signal)))

(define heks-linux-work-flatpak
  (make-parameter '("flathub com.slack.Slack")))

(define heks-linux-flatpak
  (let* ((xs (delete-duplicates (append (heks-linux-dev-flatpak)
                                        (heks-linux-gaming-flatpak)
                                        (heks-linux-media-flatpak)
                                        (heks-linux-music-flatpak)
                                        (heks-linux-net-flatpak)
                                        (heks-linux-other-flatpak)
                                        (heks-linux-work-flatpak)))))
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
