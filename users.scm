;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The accounts this checkout describes.
;;
;; Every surface in this tree renders into one home: the one the renderer was
;; started with.  This file is how a machine with more than one account says so
;; once instead of copying a checkout per person.
;;
;; A user is a name, or a name and the settings that differ.  The settings are
;; the profile vocabulary - `profile' itself, plus every parameter a profile may
;; set - and they are read as data, never loaded:
;;
;; @example
;; ((joe)
;;  (alice . ((profile . laptop)
;;            (palette . windows-xp))))
;; @end example
;;
;; `joe' above wears whatever profile the machine's own file asks for, because
;; the declaration says nothing else.  `alice' wears the laptop profile and the
;; XP palette, whatever her own config directory says.  `heks-users list' shows
;; the accounts and their homes; `heks-users check' renders every home into a
;; scratch tree and reports the difference; `heks-users apply' writes, with each
;; user's ownership (run it with sudo for accounts other than your own).
;;
;;; Code:

((joe))

;;; users.scm ends here
