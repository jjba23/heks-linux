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
;; catppuccin-frappe
;; catppuccin-macchiato
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
;; rose-pine
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
;;
;; JuliaMono is the monospace face this desktop configures.  It was drawn for a
;; programming language and ended up being one of the best text faces on a
;; terminal: a humanist skeleton instead of the squared-off geometry most code
;; fonts have, a tall x-height that keeps 12 point readable at arm's length, and
;; the confusable glyphs pulled apart on purpose - a slashed zero, an l with a
;; tail, three distinct shapes for i, l and 1.  Its coverage is the reason it is
;; here at all: the box drawing, the arrows, the mathematical operators, the
;; Greek and the emoji-adjacent symbols are in the same file, so a terminal
;; stops falling back to a second font mid-line when something prints a lambda
;; or a box.  Legible, complete, and it does not look like a spreadsheet.
;;
;; It is free software - SIL Open Font License 1.1 - and openSUSE packages it
;; with TeX Live, as `texlive-juliamono-fonts', which is one line in the font list
;; of (heks-linux packages zypper).  Nothing is vendored in this checkout.
;;
;; Every surface that shows code asks for it by name: WezTerm, Emacs through the
;; bridge, GTK's monospace setting, Niri's own font.  The fontconfig module also
;; answers the generic `monospace' with it, so a browser and a GTK view that name
;; nothing get the same face.
(define heks-linux-mono-font
  (make-parameter "JuliaMono"))

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
;; - Spectral
;;
;; Source Serif 4 is the serif that goes with the other two.  It is modern in the
;; way that matters here: drawn for a screen first, at text sizes, with a low
;; stroke contrast so it does not shimmer at 11 point, short sturdy serifs, and a
;; variable optical-size axis - the same family tightens up for a heading and
;; opens up for a document instead of pretending one drawing serves both.  It sits
;; between the other two rather than fighting them: humanist like JuliaMono, calm
;; like Work Sans, and quiet enough to read a page of prose in without announcing
;; itself.
;;
;; It is free software - SIL Open Font License 1.1 - and openSUSE packages it as
;; `adobe-sourceserif4-fonts', one line in the font list of
;; (heks-linux packages zypper).
;;
;; Emacs gets it through the bridge for prose buffers, and the fontconfig module
;; answers the generic `serif' with it, so a document in a browser reads in the
;; same family as a note in Emacs instead of in the distribution's Times clone.
(define heks-linux-serif-font
  (make-parameter "Source Serif 4"))

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
