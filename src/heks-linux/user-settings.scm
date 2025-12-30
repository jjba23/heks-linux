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

(define-module (heks-linux user-settings)
  #:declarative? #t
  #:export (heks-linux-palette heks-linux-language
                               heks-linux-timezone
                               heks-linux-hostname
                               heks-linux-clone-dir
                               heks-linux-mono-font
                               heks-linux-serif-font
                               heks-linux-sans-font
                               heks-linux-emacs-theme
                               heks-linux-notes-roam-dir
                               heks-linux-keyboard-layout
                               heks-linux-bash-highlight))

;; ===========================================

;; Valid palettes for the system, and for Emacs are:
;;
;; catppuccin-latte
;; catppuccin-mocha
;; dracula
;; ef-autumn
;; ef-bio
;; ef-cyprus
;; ef-dream
;; ef-melissa-light
;; everforest-dark
;; everforest-light
;; gruvbox-dark
;; gruvbox-light
;; heavy-metal
;; kaolin-dark
;; modus-vivendi
;; modus-operandi
;; solarized-light
;;
(define heks-linux-palette
  (make-parameter 'modus-operandi))

(define heks-linux-emacs-theme
  (make-parameter 'modus-operandi))

;; Common color choices for the bash highlight:
;;
;; 0: Black
;; 1: Red
;; 2: Green
;; 3: Yellow
;; 4: Blue
;; 5: Magenta 
;; 6: Cyan
;; 7: White
;;
;; See the man pages for tput for more information
(define heks-linux-bash-highlight
  (make-parameter "\"$(tput setaf 5)\""))

(define heks-linux-mono-font
  (make-parameter "IBM Plex Mono"))

(define heks-linux-sans-font
  (make-parameter "IBM Plex Sans"))

(define heks-linux-serif-font
  (make-parameter "IBM Plex Serif"))

(define heks-linux-keyboard-layout
  (make-parameter "us"))

(define heks-linux-language
  (make-parameter "nl_NL"))

(define heks-linux-timezone
  (make-parameter "Europe/Amsterdam"))

(define heks-linux-hostname
  (make-parameter "heks-linux"))

(define heks-linux-clone-dir
  (make-parameter "~/Hacking/heks-linux"))

(define heks-linux-notes-roam-dir
  (make-parameter "~/Hacking/private-notes"))

;; ===========================================
