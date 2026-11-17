;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The laptop's parameters, as data.
;;
;; A profile is the *named bundle of parameters* a machine wears: it is read, not
;; loaded, so every key here must be in `profile-parameter-table' and every value
;; must have the shape the parameter already holds.  What a profile cannot do is
;; compute - that is what an override is for, and the two compose (profile first,
;; override second).
;;
;; `heks-profile use laptop' copies this file to
;; ~/.config/heks-linux/profile.scm, which is the one applied at render time.  The
;; copy is deliberate: a checkout can be edited, branched or thrown away without
;; changing the machine it describes.

;;; Code:

((palette . modus-vivendi)
 (sans-font . "Work Sans")
 (mono-font . "JuliaMono")
 (serif-font . "Source Serif 4")
 (keyboard-layout . "us")
 (natural-scroll? . #t)
 (blur? . #t)
 (client-side-decorations? . #t)
 ;; A laptop is read with a window over one screen; the tab bar is the row of
 ;; chrome this profile can do without.
 (tab-bar? . #f)
 ;; On battery a shorter interval is a nice thing to look at and a cheap one.
 (wallpaper-interval . "45m")
 (screenshots-dir . "Pictures/Screenshots"))
