;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux palette-picker).
;;
;; The picker is a generated Bash script two programs run: heks-toon with
;; @code{ROFI_RETV=1} and the palette's name, whelk with @code{ROFI_RETV=0} to
;; draw the list.  So the tests read the script the way those two callers reach
;; it: the entry point, the palette table, and the refusal that keeps a name
;; nobody recognises out of the settings file.

;;; Code:

(define-module (veritas unit palette-picker-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux palette-picker)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (script)
  "Return the generated picker script."
  (make-theme-picker-script))

(define (script-mentions? fragment)
  (if (string-contains (script) fragment) #t #f))

(define entry-suite
  (suite "The palette picker"
    (test "It is a script a caller can run"
      (assert-true (script-mentions? "#!/usr/bin/env bash")
        #:name "The picker be a Bash script, so it can be executable")
      (assert-equal #:expect
        (format #f "whelk --menu ~a/~a"
                (theme-picker-dir)
                (theme-picker-filename))
        #:got (palette-picker-command)
        #:name
        "The bar should open the picker through the shell's own menu protocol"))

    (test "It is reached the way heks-toon reaches it"
      ;; heks-toon names this file in its own settings and runs it with
      ;; ROFI_RETV=1 and the chosen palette's name.
      (assert-equal #:expect "heks-rofi-theme-menu"
        #:got (theme-picker-filename)
        #:name
        "The installed name is the one heks-toon 0.3.6 runs")
      (assert-true (script-mentions? "case \"${ROFI_RETV:-0}\" in")
        #:name "The script should branch on the caller's return code")
      (assert-true (script-mentions? "*) apply_theme \"$1\" ;;")
        #:name
        "With ROFI_RETV=1 the chosen name should be what gets applied"))

    (test "A switch writes the settings a switch is made of"
      (assert-true (script-mentions? "set_setting heks-linux-palette")
        #:name "The palette should be written to the user's override file")
      (assert-true (script-mentions? "set_setting heks-linux-emacs-theme")
        #:name
        "The Emacs theme should be written with it, from the palette's own entry")
      (assert-true (script-mentions? "maak install-theme")
        #:name
        "The surfaces should be re-rendered by the task that owns that list")
      (assert-true (script-mentions? "\"$LOCAL_SETTINGS.bak\"")
        #:name
        "The previous override file should be kept, not overwritten blind"))

    (test "An unknown name never reaches the settings file"
      ;; A picker can be called by anything - a stale bookmark, a typed name -
      ;; and a name that is not a palette would be written into the user's
      ;; settings and then break every configuration that reads them.
      (assert-true (script-mentions? "palette_known \"$name\"")
        #:name "The name should be checked against the table first")
      (assert-true (script-mentions? "Unknown palette: $name")
        #:name "And refused with a message that says so"))

    (test "The table carries every palette"
      (for-each (lambda (palette)
                  (assert-true (script-mentions? (format #f "~a) printf" palette))
                    #:name
                    (format #f "~a should have a swatch to draw" palette)))
                (palette-names))
      (for-each (lambda (colour)
                  (assert-true (script-mentions? colour)
                    #:name
                    (format #f "A swatch should be painted in ~a" colour)))
                (palette-swatch-colors 'nord)))

    (test "A palette's Emacs theme is the registry's, not its name"
      ;; Several palettes wear a theme called something else, and the picker has
      ;; to write the one the bridge can load.
      (assert-true (script-mentions? "ef-tritanopia-dark")
        #:name "heavy-metal's Emacs theme should be in the generated table"))))

(define (spec)
  (veritas-run entry-suite))
