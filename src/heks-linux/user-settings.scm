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
  #:declarative? #f
  #:use-module (heks-linux prelude)
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
                               heks-linux-keyboard-options
                               heks-linux-bash-highlight
                               heks-linux-client-side-decorations?
                               heks-linux-blur?
                               heks-linux-caps-to-ctrl?
                               heks-linux-natural-scroll?))

;; ===========================================

;; Valid palettes for the system, and for Emacs are:
;;
;; catppuccin-latte
;; catppuccin-mocha
;; dracula
;; ef-autumn
;; ef-bio
;; ef-cyprus
;; ef-day
;; ef-dream
;; ef-melissa-light
;; ef-kassio
;; everforest-dark
;; everforest-light
;; gruvbox-dark
;; gruvbox-light
;; heavy-metal
;; kaolin-dark
;; modus-vivendi
;; modus-vivendi-tinted
;; modus-vivendi-deuteranopia
;; modus-vivendi-tritanopia
;; modus-operandi
;; modus-operandi-tinted
;; modus-operandi-deuteranopia
;; modus-operandi-tritanopia
;; solarized-light
;; solarized-dark
;; doom-tomorrow-night
;; doom-molokai
;; doom-one
;; doom-one-light
;; nord
;; tokyo-night
;; rose-pine-moon
;; rose-pine-dawn
;; kanagawa
;; ayu-dark
;; ayu-mirage
;; ayu-light
;; golden-gate-light
;; golden-gate-dark
;;
(define heks-linux-palette
  (make-parameter 'modus-vivendi-tinted))

(define heks-linux-emacs-theme
  (make-parameter 'modus-vivendi-tinted))

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

;;
;; --- Fonts ---
;;

;; In most systems ~/.fonts is supported
;; for some situations and flatpak, ~/.local/share/fonts
;;
;; If you like, ensure your custom font packages are installed,
;; like Iosevka
;; https://github.com/be5invis/Iosevka/releases
;;
;; Then you can customize the heks-linux fonts

;; Honorable mentions are:
;; -  (builtin) Noto Mono
;; - Iosevka Term
;; - IBM Plex Mono
;; - Intel One Mono
(define heks-linux-mono-font
  (make-parameter "Intel One Mono"))

;; Honorable mentions are:
;; - (built-in) Adwaita Sans
;; - Plus Jakarta Sans
;; - Lucida Sans
;; - Iosevka Aile
;; - IBM Plex Sans
(define heks-linux-sans-font
  (make-parameter "Lucida Sans"))

;; Honorable mentions are:
;; - (built-in) DejaVu Serif
;; - Iosevka Slab
;; - IBM Plex Serif
(define heks-linux-serif-font
  (make-parameter "DejaVu Serif"))

;; -- Other settings --

(define heks-linux-keyboard-layout
  (make-parameter "us"))

;; Additional XKB options for the keyboard, given as a list of option strings.
;; Use this to enable extra input levels or overlays on top of the layout.
;; The `ctrl:nocaps' option is composed in automatically while
;; `heks-linux-caps-to-ctrl?' is enabled.
(define heks-linux-keyboard-options
  (make-parameter '()))

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

(define heks-linux-caps-to-ctrl?
  (make-parameter #t))

;; Whether to show window title bars and close/minimize buttons
(define heks-linux-client-side-decorations?
  (make-parameter #t))

;; Whether to use blur effects
(define heks-linux-blur?
  (make-parameter #t))

;; "natural" scrolling: content follows the fingers on a
;; touchpad and the wheel direction is inverted for mice.
(define heks-linux-natural-scroll?
  (make-parameter #f))

(load-local-overrides '(heks-linux user-settings)
                      'local-settings)
