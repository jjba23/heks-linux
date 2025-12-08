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

(define-module (maak)
  #:declarative? #t
  #:use-module (maak maak))

(define (guix-pull)
  ($ '("guix pull" "--channels=channels.scm")
     #:verbose? #t)
  ($ '("hash guix")
     #:verbose? #t))

(define (install-alacritty)
  (remkdir-p "~/.config/alacritty")
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(heks-linux alacritty) install-alacritty))'")
                               #:verbose? #t))

(define (install-waybar)
  (remkdir-p "~/.config/waybar")
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(heks-linux waybar) install-waybar))'")
                               #:verbose? #t))

(define (install-rofi)
  (remkdir-p "~/.config/rofi")
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                     "'((@(heks-linux rofi) install-rofi))'")
                               #:verbose? #t))

(define (install-niri)
  (remkdir-p "~/.config/niri")
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                     "'((@(heks-linux niri) install-niri))'")
                               #:verbose? #t))

(define (install-mako)
  (remkdir-p "~/.config/mako")
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                     "'((@(heks-linux mako) install-mako))'")
                               #:verbose? #t))

(define (install-git)
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                     "'((@(heks-linux git) install-git))'")
                               #:verbose? #t))

(define (install-flatpaks)
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(heks-linux packages flatpaks) install-flatpaks))'")
                               #:verbose? #t))

(define (update-flatpaks)
  ($ '("flatpak update -y")
     #:verbose? #t))

(define (install-dnfs)
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(heks-linux packages dnfs) install-dnfs))'")
                               #:verbose? #t))

(define (update-dnfs)
  ($ '("sudo dnf update -y")
     #:verbose? #t))

(define (install-wallpapers)
  (mkdir-p "~/.local/bin")
  (delete-file-recursively "~/.config/digital-art-dreams")
  ($ '("git clone ssh://git@codeberg.org/jjba23/digital-art-dreams.git ~/.config/digital-art-dreams"))
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(heks-linux wallpaper) install-wallpapers))'")
                               #:verbose? #t))

(define (default)
  "Default task to run, call program's help."
  (list-tasks))

(define (fmt)
  "Format Scheme source code files according to the Guix style guide."
  ($ '("find . -maxdepth 8 -name '*.scm'" "-type f -exec guix style -f {} \\;")
     #:verbose? #t))

(define (repl)
  "Development REPL."
  (manifest-shell '("guile -L ./src"
                    "-c '((@ (ares server) run-nrepl-server))'")))


(define (reconfigure)
  "Complete system reconfigure."
  (install-alacritty)
  (install-waybar)
  (install-niri)
  (install-mako)
  (install-git)
  (update-flatpaks)
  (install-flatpaks)
  (update-dnfs)
  (install-dnfs)
  (install-wallpapers))
