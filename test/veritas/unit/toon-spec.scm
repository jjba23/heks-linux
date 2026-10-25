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

;;; Commentary:
;;
;; Unit tests for (heks-linux toon): the three command lines the bar and the
;; compositor build, the application id the window rule matches on, and the
;; retirement of the HTML pages heks-toon replaces.
;;
;; The program itself is not run - heks-toon is a package of its own, and what
;; this module owns is the little the desktop has to say to it.  What is checked
;; is that the words are the same on both sides: a view name or an application
;; id that drifted would be a bar button that opens nothing.
;;
;; Cases that have to set something up return their assertions as a list, as
;; veritas reads a body for the assertions built while it runs and a `let' whose
;; assertions are not its last form would have them optimized away.  See the
;; note at the top of waybar-spec.scm.

;;; Code:

(define-module (veritas unit toon-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux toon)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux niri)
  #:use-module (heks-linux waybar)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (scratch-dir name)
  "Return a path under /tmp for a test that has to touch the filesystem."
  (format #f "/tmp/heks-toon-spec-~a/~a" (getpid) name))

(define (touch-file! path contents)
  "Write CONTENTS to PATH, making the directory above it first."
  (ensure-directory-tree! (dirname path))
  (call-with-output-file path
    (lambda (port)
      (display contents port))))

(define (remove-tree! path)
  "Remove PATH and whatever is below it, so a run leaves nothing behind."
  (when (file-exists? path)
    (if (eq? 'directory (stat:type (stat path)))
        (begin
          (for-each (lambda (entry)
                      (remove-tree! (format #f "~a/~a" path entry)))
                    (cddr (scandir path)))
          (rmdir path))
        (delete-file path))))

(define (toon-conf-occurs? needle)
  "Whether the rendered Niri configuration contains NEEDLE."
  (not (eq? #f (string-contains (string-join (serialize-kdl (niri-config))
                                             "\n")
                                needle))))

(define* (override-cases #:key (command "/tmp/heks-toon"))
  "Return the cases for a command the configuration overrides.
The views are the program's arguments, so they have to follow the command
rather than a literal written once."
  (parameterize ((toon-command command))
    (list (assert-equal #:expect (format #f "~a palettes" command)
                        #:got (toon-palettes-command)
                        #:name "An overridden command keeps its view")
          (assert-equal #:expect command
                        #:got (toon-keys-command)
                        #:name "An overridden command needs no argument"))))

(define (retire-cases)
  "Create the launchers and the page the old pages left, retire them, and
return the cases."
  (let* ((launcher-dir (scratch-dir "bin"))
         (config-dir (scratch-dir "config"))
         (stale (map (lambda (name)
                       (format #f "~a/~a" launcher-dir name))
                     toon-retired-launchers))
         (page (format #f "~a/heks-linux/keybindings/index.html" config-dir))
         (kept (format #f "~a/heks-wallpaper" launcher-dir)))
    (for-each (lambda (path)
                (touch-file! path "#!/usr/bin/env bash\n"))
              (append stale
                      (list kept)))
    (touch-file! page "<!DOCTYPE html>\n")
    (parameterize ((toon-launcher-dir launcher-dir)
                   (toon-config-dir (format #f "~a/heks-linux" config-dir)))
      (install-toon-config))
    (let ((cases (list (assert-true (every (lambda (path)
                                             (not (file-exists? path)))
                                           stale)
                                    #:name
                                    "Every launcher the pages installed should be gone")
                       (assert-true (not (file-exists? page))
                                    #:name
                                    "The generated keyboard reference should be gone")
                       (assert-true (file-exists? kept)
                                    #:name
                                    "A launcher this configuration still owns should stay")
                       (assert-true (not (file-exists?
                                          (format #f "~a/heks-toon" launcher-dir)))
                                    #:name
                                    "The window is a program, not a generated launcher"))))
      (remove-tree! (dirname launcher-dir))
      (remove-tree! (dirname config-dir))
      cases)))

(define (spawn-cases)
  "Return the cases for the wrapper the bar runs the window through.
A client cannot raise a window it did not just create, so the bar goes through
the compositor's own spawn - which carries an activation token - and keeps the
direct call as the fallback for a machine where niri is not the compositor."
  (let ((spawned (toon-spawn-command "heks-toon palettes")))
    (list (assert-true
           (not (eq? #f (string-contains
                         spawned
                         "niri msg action spawn -- heks-toon palettes")))
           #:name "The command should go through niri's spawn first")
          (assert-true
           (not (eq? #f (string-contains spawned "|| heks-toon palettes")))
           #:name "It should fall back to running the program"))))

(define (second-run-cases)
  "Retire the same launcher twice and return the cases.
Running `maak home-reconfigure' twice is the normal case, so a retired launcher
that is already gone has to be the quiet case, not an error."
  (let* ((launcher-dir (scratch-dir "again"))
         (config-dir (scratch-dir "again-config"))
         (stale (format #f "~a/heks-keybindings" launcher-dir)))
    (touch-file! stale "#!/usr/bin/env bash\n")
    (parameterize ((toon-launcher-dir launcher-dir)
                   (toon-config-dir (format #f "~a/heks-linux" config-dir)))
      (install-toon-config)
      (install-toon-config))
    (let ((cases (list (assert-true (not (file-exists? stale))
                                    #:name
                                    "The launcher should be gone after both runs"))))
      (remove-tree! (dirname launcher-dir))
      cases)))

(define toon-suite
  (suite "heks-toon Suite"
         (test "The Views Are One Program"
               ;; The view names are the program's own words: a bar button that
               ;; spelled them differently would open the default view at best.
               (assert-equal #:expect "heks-toon"
                             #:got (toon-keys-command)
                             #:name
                             "The keyboard reference is the default view")
               (assert-equal #:expect "heks-toon walls"
                             #:got (toon-walls-command)
                             #:name "The wall chooser names its view")
               (assert-equal #:expect "heks-toon palettes"
                             #:got (toon-palettes-command)
                             #:name "The palette chooser names its view")
               (assert-equal #:expect "heks-toon docs"
                             #:got (toon-docs-command)
                             #:name "The documentation view names its view"))

         (test "The Command Is A Parameter"
               (override-cases))

         (test "The Bar Asks The Compositor To Spawn The Window"
               (spawn-cases))

         (test "The Window Rule Matches The Program"
               (assert-equal #:expect "org.jointhefreeworld.heks-toon"
                             #:got toon-app-id
                             #:name "The application id is the program's own")
               (assert-true (toon-conf-occurs?
                             "match app-id=\"^org.jointhefreeworld.heks-toon$\"")
                            #:name "Niri should match the window by that id")
               (assert-true (toon-conf-occurs? "open-focused true")
                            #:name
                            "The window should be focused the moment it opens")
               (assert-true (toon-conf-occurs? "blur true")
                            #:name
                            "The compositor should blur what is behind the glass")
               (assert-true (not (toon-conf-occurs? "#<"))
                            #:name
                            "Every block should serialize as KDL, not as a record")
               (assert-true (not (toon-conf-occurs? "chrome-"))
                            #:name
                            "The browser window rule the pages needed should be gone"))

         (test "The Bar Launches The Views"
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-keybindings)
                                                     'on-click)
                                          "heks-toon")))
                            #:name "The question mark opens the reference")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-palette)
                                                     'on-click)
                                          "heks-toon palettes")))
                            #:name
                            "The palette glyph opens the palette chooser")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-wallpaper)
                                                     'on-click)
                                          "heks-toon walls")))
                            #:name
                            "The picture glyph opens the wall chooser"))

         (test "The Pages Are Retired"
               (retire-cases))

         (test "Retiring A Second Time Is Harmless"
               (second-run-cases))))

(define (spec)
  (veritas-run toon-suite))
