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
                                "'((@(hekserij alacritty) install-alacritty))'")
                               #:verbose? #t))

(define (install-waybar)
  (remkdir-p "~/.config/waybar")
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(hekserij waybar) install-waybar))'")
                               #:verbose? #t))

(define (install-rofi)
  (remkdir-p "~/.config/rofi")
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(hekserij rofi) install-rofi))'")
                               #:verbose? #t))

(define (install-git)
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                     "'((@(hekserij git) install-git))'")
                               #:verbose? #t))

(define (install-flatpaks)
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(hekserij packages flatpaks) install-flatpaks))'")
                               #:verbose? #t))

(define (update-flatpaks)
  ($ '("flatpak update -y")
     #:verbose? #t))

(define (install-dnfs)
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(hekserij packages dnfs) install-dnfs))'")
                               #:verbose? #t))

(define (update-dnfs)
  ($ '("sudo dnf update -y")
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
