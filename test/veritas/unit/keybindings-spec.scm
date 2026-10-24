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

(define (synth-heks-emacs)
  "Write a small heks-emacs checkout and return its directory.

The reference reads heks-emacs only through the file that project publishes, so
a synthetic one is a real test of the coupling: no checkout, no rows; a checkout,
its rows.
"
  (let* ((root (format #f "/tmp/heks-emacs-spec-~a" (getpid)))
         (docs (format #f "~a/docs" root))
         (file (format #f "~a/keybindings.org" docs)))
    (unless (file-exists? docs)
      (mkdir root)
      (mkdir docs))
    (call-with-output-file file
      (lambda (port)
        (display "#+title: The keybindings\n\n" port)
        (display "* The alphabet\n\n| ~a~ | apply |\n\n" port)
        (display "* The keys, by topic\n\n" port)
        (display "** ~C-c !~ diagnostics: Flymake\n\n" port)
        (display "| Key | Command | What it does | In |\n" port)
        (display "|---+---+---+---|\n" port)
        (display "| ~C-c ! N~ | ~flymake-goto-prev-error~ | the previous diagnostic | emacs-core.el |\n" port)
        (display "| ~C-c ! n~ | ~flymake-goto-next-error~ | the next diagnostic | emacs-core.el |\n" port)
        (display "\n** ~C-c z~ the thing at point\n\n" port)
        (display "| ~C-c z o~ | ~symbol-overlay-put~ | the symbol, lit up | notes.el |\n" port)))
    root))

(define (occurs? haystack needle)
  "Whether @var{needle} appears inside @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

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

         (test "heks-emacs Is Read If It Is There"
               ;; No checkout: the page is the curated one it always was.
               (assert-true (null? (parameterize ((heks-linux-emacs-clone-dir
                                                   "/tmp/not-a-checkout"))
                                     (heks-emacs-key-sections)))
                            #:name
                            "A missing checkout adds nothing")
               (let ((root (synth-heks-emacs)))
                 ;; A checkout: its topics arrive as sections, with the command
                 ;; as the note.
                 (assert-equal #:expect 2
                               #:got (length (parameterize ((heks-linux-emacs-clone-dir
                                                            root))
                                               (heks-emacs-key-sections)))
                               #:name
                               "Each topic in the published reference becomes a section")
                 (assert-equal #:expect '("C-c ! N" "the previous diagnostic"
                                          "flymake-goto-prev-error")
                               #:got (cadr (parameterize ((heks-linux-emacs-clone-dir
                                                          root))
                                             (car (heks-emacs-key-sections))))
                               #:name
                               "A row carries the key, the configuration's words and the command")
                 (assert-true (parameterize ((heks-linux-emacs-clone-dir root))
                                (not (null? (heks-emacs-key-sections))))
                              #:name
                              "The parser must not depend on anything but the file")))

         (test "The Notation Is Explained And The Page Has No Title"
               ;; A cheat sheet written in a notation it never explains is only
               ;; useful to its author.
               (assert-true (occurs? (html) "class=\"legend\"")
                            #:name "The page should carry the notation legend")
               (assert-true (occurs? (html) "<kbd>s</kbd>")
                            #:name "The legend should spell out the Command key")
               (assert-true (occurs? (html) "Super / Command")
                            #:name "s should be named, not just shown")
               (assert-true (occurs? (html) "Alt / Option")
                            #:name "M should be named too")
               (assert-true (not (occurs? (html) "<h1"))
                            #:name
                            "The page should not repeat the window's title inside itself")
               (assert-true (occurs? (html) "<title>Heks Linux</title>")
                            #:name
                            "Every Heks page names its window the same way"))

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
