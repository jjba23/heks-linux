;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

(define-module (heks-linux user-settings)
  #:declarative? #f
  #:use-module (heks-linux prelude)
  #:export (heks-linux-palette heks-linux-language
                               heks-linux-timezone
                               heks-linux-hostname
                               heks-linux-screenshots-dir
                               heks-linux-password-command
                               heks-linux-password-startup-args
                               heks-linux-clone-dir
                               heks-linux-mono-font
                               heks-linux-serif-font
                               heks-linux-sans-font
                               heks-linux-emacs-theme
                               heks-linux-emacs-clone-dir
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
;; - Iosevka Aile
;; - IBM Plex Sans
;;
;; Work Sans is a grotesque drawn for screens: a wide lowercase, open counters,
;; a real bold rather than a synthesised one, and an italic that was drawn rather
;; than slanted.  That is what a menu bar's row of 11 point words needs, for the
;; same reason the reference's own row was set in a face with those proportions.
;;
;; It is free software - SIL Open Font License 1.1 - and packaged: openSUSE calls
;; it `google-worksans-fonts' and it is one line in (heks-linux packages zypper)'s
;; font list, so `maak install-zypper' is what puts it on a machine.  Nothing is
;; vendored in this checkout, which carries no font files at all.
;;
;; A machine that has not installed it falls back through (heks-linux fontconfig)'s
;; `fontconfig-sans-fallbacks' to Helvetica Neue - the face the reference desktop
;; draws its own interface in - and then to Adwaita Sans, rather than to whatever the
;; distribution calls the default.
;;
;; Nothing here is asked for by name alone: the fontconfig module also points
;; the generic families at this one, so a stylesheet that says `sans-serif'
;; draws in it too.
(define heks-linux-sans-font
  (make-parameter "Work Sans"))

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

;; Where a screenshot goes, as a directory.  One setting because two surfaces
;; need it: niri builds its strftime pattern from it, and the dock's Screenshots
;; stack reads it.  Two places that have to agree on where a screenshot lands is
;; one place too many - the stack would quietly show an empty folder while every
;; screenshot went somewhere else.
(define heks-linux-screenshots-dir
  (make-parameter "~/Afbeeldingen/Schermafdrukken"))

;; The password manager, as a command line.  One setting because two surfaces
;; need it, the way the screenshots directory is one setting: the session starts
;; it at login and the bar's key glyph opens it, and a machine that changed one
;; and not the other would start a vault it cannot click.
;;
;; The default is the distribution package's `1password' - the 1Password RPM
;; installs exactly that at /usr/bin/1password.  A machine that installed the
;; Flatpak instead points this at `flatpak run com.onepassword.OnePassword', and
;; one that keeps its passwords somewhere else points it at that program.
(define heks-linux-password-command
  (make-parameter "1password"))

;; The arguments that start it with the session instead of in front of you:
;; 1Password's own `--silent' keeps the app in the tray until it is asked for.
;; A manager that has no such flag sets this to the empty string, and the
;; session starts it the way a click would.
(define heks-linux-password-startup-args
  (make-parameter "--silent"))

(define heks-linux-clone-dir
  (make-parameter "~/Hacking/heks-linux"))

;; Where the heks-emacs configuration lives, if it is checked out at all.
;; A separate project with its own release cycle: the keyboard reference reads
;; the file it publishes and never depends on it being there.
(define heks-linux-emacs-clone-dir
  (make-parameter "~/Hacking/heks-emacs"))

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
