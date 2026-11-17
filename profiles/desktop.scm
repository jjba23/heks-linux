;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The desktop's parameters, as data.
;;
;; Same vocabulary as `profiles/laptop.scm', different values: the two files are
;; the whole difference between the machines, and `heks-profile diff laptop
;; desktop' prints exactly the rows that differ.  Nothing here is code, so the
;; diff is a diff of facts rather than of expressions.

;;; Code:

((palette . modus-vivendi-tinted)
 (sans-font . "Work Sans")
 (mono-font . "JuliaMono")
 (serif-font . "Source Serif 4")
 (keyboard-layout . "us")
 ;; A mouse is the pointing device that is always there; natural scrolling is a
 ;; trackpad's grammar.
 (natural-scroll? . #f)
 (blur? . #t)
 (client-side-decorations? . #t)
 (tab-bar? . #f)
 (wallpaper-interval . "1h30m"))
