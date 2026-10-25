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
;; Unit tests for (heks-linux gallery), the wallpaper page behind the preview
;; window.
;;
;; The page is rendered by substitution, so the tests check three things: that
;; every wall it lists is a picture inside the collection, that no colour token
;; was left unpainted, and that the launcher still falls back to the Rofi wall
;; on every path where the page cannot be served.

;;; Code:

(define-module (veritas unit gallery-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux gallery)
  #:use-module (heks-linux glass)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux rofi)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux wallpaper)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:export (spec))

(define (occurs? haystack needle)
  "Whether @var{needle} appears inside @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

(define (page)
  "The gallery page rendered for the running palette."
  (gallery-html (gallery-images)))

;; A counter, so two progress samples written inside the same second do not
;; share a path and read each other's stage.
(define progress-counter 0)

(define (progress-temp-file)
  "A fresh path for a progress file."
  (set! progress-counter (1+ progress-counter))
  (format #f "/tmp/heks-progress-spec-~a-~a"
          (current-time)
          progress-counter))

(define (status-for-line line)
  "The switch status a page would see for a progress file holding @var{line}."
  (let ((file (progress-temp-file)))
    (call-with-output-file file
      (lambda (port) (display line port)))
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (parameterize ((gallery-progress-file file))
          (gallery-palette-status)))
      (lambda () (delete-file file)))))

(define (stage-line stage seconds-ago)
  "A picker progress line for @var{stage}, started @var{seconds-ago}s ago."
  (format #f "~a ~a golden-gate~%" stage (- (current-time) seconds-ago)))

(define (default-launcher)
  "The launcher rendered with its default settings."
  (mk-gallery-launcher-cmd))

(define gallery-suite
  (suite "Wallpaper Gallery Suite"
         (test "Every Wallpaper In The Collection Is A Picture"
               (assert-true (every (lambda (entry)
                                     (let ((path (assoc-ref entry 'path)))
                                       (and (string-prefix? (wallpaper-catalog-dir)
                                                            path)
                                            (or (occurs? path ".jpg")
                                                (occurs? path ".jpeg")
                                                (occurs? path ".png")
                                                (occurs? path ".webp")
                                                (occurs? path ".gif")
                                                (occurs? path ".jxl")))))
                                   (gallery-images))
                            #:name
                            "The walk must not pick up the repository objects"))

         (test "The Palette Set Comes First And Is Marked"
               (assert-true (not (null? (gallery-images)))
                            #:name "The collection should not be empty")
               (assert-true (every (lambda (entry)
                                     (assoc-ref entry 'palette?))
                                   (take (gallery-images)
                                         (length (parameterize ((heks-linux-palette
                                                                 (heks-linux-palette)))
                                                  (wallpapers)))))
                            #:name
                            "The wallpapers curated for the palette should lead the wall")
               (assert-true (not (eq? #f (assoc-ref (car (gallery-images))
                                                    'path)))
                            #:name "An entry should carry the path it stands for"))

         (test "The Page Paints Every Token"
               (assert-true (null? (gallery-unresolved-tokens (page)))
                            #:name
                            "A leftover @token@ means a colour was never supplied")
               (assert-true (string-prefix? "<!DOCTYPE html>" (page))
                            #:name "The gallery should be a complete document")
               (assert-true (occurs? (page) "<style>")
                            #:name "The stylesheet should be embedded")
               (assert-true (occurs? (page) "</script>")
                            #:name "The script should be embedded")
               (assert-true (occurs? (page) "/preview?path=")
                            #:name "The page should ask for a large preview")
               (assert-true (occurs? (page) "/thumb?w=")
                            #:name "The wall should be built from thumbnails"))

         (test "The Page Is Painted From The Palette"
               (assert-true (occurs? (page)
                                     (get-color (heks-linux-palette) 'primary))
                            #:name "The accent should be the palette's own")
               (assert-true (occurs? (page)
                                     (get-color (heks-linux-palette) 'background))
                            #:name "The page background should be the palette's"))

         (test "Cells Stay Inside The Wall"
               ;; Renderers return SXML; the writer is what turns a node into
               ;; markup, so the assertion goes through it like the page does.
               (assert-true (occurs?
                             (sxml->html-string
                              (gallery-cell '((path . "/x/a.jpg")
                                              (name . "a.jpg")
                                              (folder . "/x")
                                              (palette? . #f)
                                              (current? . #f))))
                             "data-path=\"/x/a.jpg\"")
                            #:name "A cell should carry the path it applies")
               (assert-true (not (occurs?
                                  (sxml->html-string
                                   (gallery-cell '((path . "/x/<a>.jpg")
                                                   (name . "<a>.jpg")
                                                   (folder . "/x")
                                                   (palette? . #f)
                                                   (current? . #f))))
                                   "<a>.jpg"))
                            #:name
                            "A file name should not be able to inject markup"))

         (test "The Page Can Watch A Palette Switch"
               ;; The stage the picker wrote is the stage the page shows, with
               ;; the palette's name alongside it.
               (assert-equal #:expect "rendering"
                             #:got (assoc-ref
                                    (status-for-line (stage-line "rendering" 1))
                                    "stage")
                             #:name
                             "The page should show the stage the picker is in")
               (assert-equal #:expect "golden-gate"
                             #:got (assoc-ref
                                    (status-for-line (stage-line "rendering" 1))
                                    "palette")
                             #:name
                             "The page should say which palette is being applied")
               (assert-equal #:expect "true"
                             #:got (assoc-ref
                                    (status-for-line (stage-line "rendering" 1))
                                    "running")
                             #:name
                             "A switch a second old should be reported as moving")
               (assert-equal #:expect "done"
                             #:got (assoc-ref
                                    (status-for-line (stage-line "done" 1))
                                    "stage")
                             #:name
                             "A finished switch should report that it finished")
               (assert-equal #:expect "failed"
                             #:got (assoc-ref
                                    (status-for-line (stage-line "failed" 1))
                                    "stage")
                             #:name
                             "A switch that failed should report the failure")

               ;; A file left behind by a picker killed mid-render must not be
               ;; reported as a switch that never ends.
               (assert-equal #:expect "idle"
                             #:got (assoc-ref
                                    (status-for-line (stage-line "rendering" 600))
                                    "stage")
                             #:name
                             "A stale stage should not be reported as a switch")
               (assert-equal #:expect "idle"
                             #:got (assoc-ref
                                    (parameterize ((gallery-progress-file
                                                    (progress-temp-file)))
                                      (gallery-palette-status))
                                    "stage")
                             #:name
                             "A page opened with no switch running should say nothing")

               ;; The picker writes the file; the page reads it.  Two programs,
               ;; one path, and the path is the contract between them.
               (assert-true (occurs? (make-rofi-theme-menu-script)
                                     "heks-theme-progress")
                            #:name
                            "The picker and the page should agree on one progress file"))

         (test "The Page Says What A Switch Is Doing"
               (assert-true (occurs? (page) "id=\"switch\"")
                            #:name
                            "The palette tab should have somewhere to show a switch")
               (assert-true (every (lambda (stage)
                                     (occurs? (page)
                                              (format #f "~a:" stage)))
                                   (list "starting" "settings" "rendering"
                                         "wallpaper" "emacs" "done"))
                            #:name
                            "Every stage the picker writes should have a label")
               (assert-true (occurs? (page) "/palette-status")
                            #:name
                            "The page should ask how the switch is getting on")
               (assert-true (occurs? (page) "is-busy")
                            #:name
                            "The card being applied should show that it is busy"))

         (test "The Preview Zooms And Double-Click Applies"
               ;; The picture is what you look at before deciding, so it can be
               ;; zoomed, dragged, and double-clicked to put it on the screen.
               (assert-true (every (lambda (control)
                                     (occurs? (page) control))
                                   (list "zoom-in" "zoom-out" "zoom-fit"))
                            #:name
                            "The preview should offer zoom in, zoom out and fit")
               (assert-true (occurs? (page) "image.addEventListener('dblclick'")
                            #:name
                            "Double-clicking the picture should set it as the wallpaper")
               (assert-true (occurs? (page) "cell.addEventListener('dblclick'")
                            #:name
                            "Double-clicking a wallpaper on the wall should set it too")
               (assert-true (occurs? (page) "addEventListener('wheel'")
                            #:name "The wheel should zoom the preview")
               (assert-true (occurs? (page) "pointermove")
                            #:name "A zoomed picture should be draggable")
               (assert-true (occurs? (page) "event.key === '0'")
                            #:name
                            "A key should bring the whole wallpaper back")

               ;; Zooming to inspect a detail is pointless if the picture was
               ;; served at thumbnail width, so the preview is asked for wide.
               (assert-true (>= (gallery-preview-width) 2000)
                            #:name
                            "The preview should be served large enough to zoom into"))

         (test "The Launcher Says Why It Could Not Open"
               (assert-true (string-prefix? "#!/usr/bin/env bash"
                                            (default-launcher))
                            #:name "The launcher should be a Bash script")
               ;; There is no Rofi wall to fall back to any more, and a click
               ;; that opens nothing is indistinguishable from a broken button.
               (assert-true (not (occurs? (default-launcher)
                                          "heks-wallpaper-chooser"))
                            #:name
                            "The retired Rofi wall should not be a fallback")
               (assert-true (occurs? (default-launcher) "give_up")
                            #:name
                            "A launcher with no fallback should announce the failure")
               (assert-true (occurs? (default-launcher) "fyi")
                            #:name "The failure should be a notification")
               (assert-true (occurs? (default-launcher) "SERVER_ENV")
                            #:name
                            "The server should start from the profile captured at install time")
               (assert-true (occurs? (default-launcher)
                                     "guix shell -m manifest.scm")
                            #:name
                            "When that profile is gone the launcher should still try Guix")
               (assert-true (occurs? (default-launcher) "--app=")
                            #:name
                            "The gallery should open as an app window, not a tab")
               ;; The palette page keeps a fallback - the Rofi picker, which is a
               ;; script mode the Rofi config already declares.
               (assert-true (occurs?
                             (mk-gallery-launcher-cmd
                              #:anchor "#palettes"
                              #:fallback "rofi -show theme")
                             "rofi -show theme")
                            #:name
                            "A launcher given a fallback should still use it"))

         (test "The Launcher Serves One Port"
               (assert-true (occurs? (default-launcher)
                                     (format #f "PORT=~a" (gallery-port)))
                            #:name "The port should be baked into the script")
               ;; The launcher is a bash script, but not necessarily a bash built
               ;; with /dev/tcp: the first bash on the bar's PATH is Guix's
               ;; bash-minimal, which has no net redirections, and a probe that
               ;; needs them fails while the server is up.
               (assert-true (not (occurs? (default-launcher) "exec 3<>"))
                            #:name
                            "The readiness check must not open the socket with a bash redirection")
               (assert-true (occurs? (default-launcher) "heks-linux-gallery")
                            #:name
                            "A second launch should reuse the running server")
               (assert-true (occurs? (default-launcher) "kill -0")
                            #:name
                            "The running server should be checked by the pid it wrote")
               (assert-true (occurs? (default-launcher) "ss -ltnH")
                            #:name
                            "A server started elsewhere should be found through the kernel")

               ;; The launcher and the server have to agree on that file, the way
               ;; they agree on the progress file: two programs, one path.
               (assert-true (occurs? (gallery-ready-file) "heks-linux-gallery")
                            #:name
                            "The server should write the pid file the launcher reads"))))

(define (spec)
  (veritas-run gallery-suite))
