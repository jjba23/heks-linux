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

(define* (run-heks-install-config-script func
                                         #:key (mod #f)
                                         (config-suffix? #t))
  (let ((mod (~ "'((@(heks-linux ~a) install-~a~a))'"
                (if mod mod func) func
                (if config-suffix? "-config" ""))))
    (time-machine-manifest-shell (list "guile -L ./src -c" mod)
                                 #:verbose? #t)))

(define (install-alacritty)
  (mkdir-p "~/.config/alacritty")
  (run-heks-install-config-script 'alacritty))

(define (install-waybar)
  (mkdir-p "~/.config/waybar")
  (run-heks-install-config-script 'waybar))

(define (install-rofi)
  (mkdir-p "~/.config/rofi")
  (run-heks-install-config-script 'rofi))

(define (install-niri)
  (mkdir-p "~/.config/niri")
  (run-heks-install-config-script 'niri))

(define (install-mako)
  (mkdir-p "~/.config/mako")
  (run-heks-install-config-script 'mako))

(define (install-git)
  (run-heks-install-config-script 'git))

(define (install-dconf)
  (run-heks-install-config-script 'dconf))

(define (install-fastfetch)
  (mkdir-p "~/.config/fastfetch")
  (run-heks-install-config-script 'fastfetch))

(define (install-gtk)
  (mkdir-p "~/.config/gtk-3.0")
  (run-heks-install-config-script 'gtk3
                                  #:mod 'gtk)
  (mkdir-p "~/.config/gtk-4.0")
  (run-heks-install-config-script 'gtk4
                                  #:mod 'gtk)
  (mkdir-p "~/.local/bin")
  (run-heks-install-config-script 'gtk-dconf
                                  #:mod 'gtk)
  (run-heks-install-config-script 'dconf))

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

(define (install-wallpaper-files)
  (mkdir-p "~/.local/bin")
  ($ '("rm -rf ~/.config/digital-art-dreams"))
  ($ '("git clone https://codeberg.org/jjba23/digital-art-dreams.git ~/.config/digital-art-dreams")))

(define (install-wallpapers)
  (run-heks-install-config-script 'wallpaper))

(define (install-emacs-bridge)
  (mkdir-p "~/.emacs.d")
  (run-heks-install-config-script 'heks-linux-to-emacs-bridge
                                  #:mod 'bridges))

(define (install-bash-bridge)
  (run-heks-install-config-script 'heks-linux-to-bash-bridge
                                  #:mod 'bridges))

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

(define (home-reconfigure)
  "Complete home reconfigure."
  (install-alacritty)
  (install-niri)
  (install-mako)
  (install-git)
  (install-rofi)
  (install-fastfetch)
  (install-gtk)
  (install-dconf)
  (install-wallpapers)
  (install-emacs-bridge)
  (install-bash-bridge)
  (install-waybar)
  ($ '("pkill waybar || true"))
  ($ '("setsid waybar"))
  ($ '("fyi \"Succesfully completed home-reconfigure on heks-linux\"")))

(define (reconfigure)
  "Complete system reconfigure."
  (fmt)
  (home-reconfigure)
  (update-flatpaks)
  (install-flatpaks)
  (update-dnfs)
  (install-dnfs)
  (install-wallpapers)
  ($ '("fastfetch || true")))

(define (test)
  "Unit tests."
  (time-machine-manifest-shell '("guile -L ./src -L ./test"
                                 "-c '((@ (veritas runner) run-tests))'")
                               #:verbose? #t))
