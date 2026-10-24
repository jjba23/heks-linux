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

         (test "The Launcher Falls Back To The Rofi Wall"
               (assert-true (string-prefix? "#!/usr/bin/env bash"
                                            (default-launcher))
                            #:name "The launcher should be a Bash script")
               (assert-true (occurs? (default-launcher)
                                     (wallpaper-chooser-filename))
                            #:name
                            "The fallback should be the Rofi wall that is installed beside it")
               (assert-true (occurs? (default-launcher)
                                     "command -v guix")
                            #:name
                            "The page is rendered by the project modules, so the launcher needs Guix")
               (assert-true (occurs? (default-launcher)
                                     "guix shell -m manifest.scm")
                            #:name
                            "The server should run inside the manifest shell")
               (assert-true (occurs? (default-launcher) "--app=")
                            #:name
                            "The gallery should open as an app window, not a tab"))

         (test "The Launcher Serves One Port"
               (assert-true (occurs? (default-launcher)
                                     (format #f "PORT=~a" (gallery-port)))
                            #:name "The port should be baked into the script")
               (assert-true (occurs? (default-launcher) "/dev/tcp/127.0.0.1")
                            #:name
                            "A second launch should reuse the running server instead of starting another"))))

(define (spec)
  (veritas-run gallery-suite))
