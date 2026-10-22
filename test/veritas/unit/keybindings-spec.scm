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
;; Unit tests for (heks-linux keybindings), the HTML reference behind the
;; question mark on the Waybar.
;;
;; The reference curates its own wording, so the tests do two jobs: they check
;; the shape the renderer expects, and they pin the Niri page to the chords
;; @code{(niri-bindings)} actually writes.  Add a binding in @code{niri.scm}
;; without adding it here and this suite fails.

;;; Code:

(define-module (veritas unit keybindings-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux keybindings)
  #:use-module (heks-linux niri)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (niri-chords)
  "The chord of every binding Niri writes, in rendered form."
  (map keybindings-niri-chord (niri-bindings)))

(define (page-chords page)
  "Every chord listed on @var{page}."
  (map car (append-map cdr (list-ref page 3))))

(define (row-shaped? row)
  "Whether @var{row} is a @code{(chord label [note])} the renderer accepts."
  (and (>= (length row) 2)
       (<= (length row) 3)
       (every string? row)
       (not (string-null? (car row)))
       (not (string-null? (cadr row)))))

(define (page-shaped? page)
  "Whether @var{page} has an id, title, tagline and non-empty sections."
  (and (= (length page) 4)
       (string? (list-ref page 0))
       (string? (list-ref page 1))
       (string? (list-ref page 2))
       (not (null? (list-ref page 3)))
       (every (lambda (section)
                (and (string? (car section))
                     (not (null? (cdr section)))
                     (every row-shaped? (cdr section))))
              (list-ref page 3))))

(define (html)
  "The reference rendered for a known palette."
  (parameterize ((heks-linux-palette 'golden-gate-dark))
    (keybindings-html)))

(define keybindings-suite
  (suite "Keybinding Reference Suite"
         (test "Every Page Is Shaped For The Renderer"
               (assert-true (> (length (keybindings-pages)) 1)
                            #:name "The reference should cover several apps")
               (assert-true (every page-shaped? (keybindings-pages))
                            #:name
                            "Each page needs an id, a title, a tagline and typed rows"))

         (test "The Niri Page Covers Every Configured Binding"
               (assert-equal #:expect (length (niri-bindings))
                             #:got (length (page-chords
                                            (car (keybindings-pages))))
                             #:name
                             "The Niri page should list every binding exactly once")
               (assert-true (lset= string=?
                                   (niri-chords)
                                   (page-chords (car (keybindings-pages))))
                            #:name
                            "Every chord Niri writes should appear on its page"))

         (test "The Document Is Self Contained And Palette Painted"
               (assert-true (string-prefix? "<!DOCTYPE html>" (html))
                            #:name "The reference should be a complete document")
               (assert-true (not (eq? #f (string-contains (html) "<style>")))
                            #:name "The stylesheet should be embedded")
               (assert-true (not (eq? #f (string-contains (html) "</script>")))
                            #:name "The script should be embedded")
               (assert-true (not (eq? #f (string-contains (html) "#0a84ff")))
                            #:name
                            "The document should be painted from the selected palette")
               (assert-true (not (eq? #f (string-contains (html)
                                                          "<kbd>s-t</kbd>")))
                            #:name
                            "Chords should render as single Emacs-style keycaps")
               (assert-true (eq? #f (string-contains (html) "Super+"))
                            #:name
                            "The reference should not fall back to Super+ notation")
               (assert-true (eq? #f (string-contains (html) "Alt+"))
                            #:name
                            "Alt should be written as M throughout")
               (assert-true (not (eq? #f (string-contains (html)
                                                          "id=\"search\"")))
                            #:name "The search field should be wired in")
               (assert-true (every (lambda (page)
                                     (not (eq? #f
                                               (string-contains (html)
                                                                (format #f
                                                                        "id=\"page-~a\""
                                                                        (list-ref page
                                                                                  0))))))
                                   (keybindings-pages))
                            #:name "Every page should exist in the document"))

         (test "The Launcher Opens The Rendered File"
               (assert-true (string-prefix? "#!/usr/bin/env bash"
                                            (keybindings-launcher-script))
                            #:name "The launcher should be a Bash script")
               (assert-true (not (eq? #f (string-contains
                                          (keybindings-launcher-script)
                                          "google-chrome --app=")))
                            #:name
                            "Chrome should host the reference as an app window")
               (assert-true (not (eq? #f (string-contains
                                          (keybindings-launcher-script)
                                          "xdg-open")))
                            #:name "There should be a browser fallback")
               (assert-true (not (eq? #f (string-contains
                                          (keybindings-launcher-script)
                                          (format #f "~a/~a"
                                                  (keybindings-dir)
                                                  (keybindings-filename)))))
                            #:name
                            "The launcher should point at the installed document"))))

(define (spec)
  (veritas-run keybindings-suite))
