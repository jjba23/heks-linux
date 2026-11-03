; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux rmpc).  The module writes two RON documents whose
;; value is entirely in what they say: a keymap that must not bind one key twice
;; and a theme that must take its chrome from the palette.  Both are checked as
;; text, because that is exactly what rmpc reads.

;;; Code:

(define-module (veritas unit rmpc-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux rmpc)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (scope-keys text scope)
  "Return the key strings bound inside SCOPE of the rendered keybinds TEXT.

The keymap is written one binding per line and one scope per block, so the
scope is found by its opening line and closed by the first line that ends it."
  (let loop ((lines (string-split text #\newline)) (inside? #f) (keys '()))
    (cond
      [(null? lines) (reverse keys)]
      [(string-contains (car lines) (string-append scope ": {"))
       (loop (cdr lines) #t keys)]
      [(and inside? (string-contains (car lines) "},"))
       (loop (cdr lines) #f keys)]
      [inside?
        (let* ((line (car lines))
               (open (string-contains line "\"")))
          (if open
            (let* ((rest (substring line (+ open 1)))
                   (end (string-contains rest "\"")))
              (loop (cdr lines) #t
                    (if end
                      (cons (substring rest 0 end) keys)
                      keys)))
            (loop (cdr lines) #t keys)))]
      [else (loop (cdr lines) #f keys)])))

(define (has? text fragment)
  "Whether FRAGMENT appears in TEXT, as a boolean.

`string-contains' answers with an index, which an assertion reads as a
number, so every check goes through this."
  (if (string-contains text fragment) #t #f))

(define (binds? keys key)
  "Whether KEYS holds KEY."
  (if (member key keys) #t #f))

(define (keymap-suite)
  (suite "Keymap"
    (test "No Scope Binds A Key Twice"
      (let ((text (rmpc-keybinds)))
        (for-each
         (lambda (scope)
           (let ((keys (scope-keys text scope)))
             (assert-equal #:expect (length (delete-duplicates keys))
               #:got (length keys)
               #:name (format #f "~a binds every key once" scope))))
         '("global" "navigation" "queue"))))
    (test "The Emacs Movement Keys Are Bound"
      (let ((keys (scope-keys (rmpc-keybinds) "navigation")))
        (for-each
         (lambda (key)
           (assert-true (binds? keys key)
             #:name (format #f "~a is bound" key)))
         '("<C-n>" "<C-p>" "<C-f>" "<C-b>" "<C-v>" "<A-v>"
           "<C-a>" "<C-e>" "<C-Space>" "<C-k>" "<C-s>" "<C-g>"))))
    (test "The Cursor And Page Keys Do Not Fight"
      (let ((text (rmpc-keybinds)))
        (assert-true (has? text "\"<C-f>\": Right")
          #:name "C-f is forward-char, not a page")
        (assert-true (has? text "\"<C-b>\": Left")
          #:name "C-b is backward-char, not a page")
        (assert-true (has? text "\"<C-v>\": PageDown")
          #:name "C-v pages forward, as in Emacs")
        (assert-true (has? text "\"<A-v>\": PageUp")
          #:name "M-v pages back, as in Emacs")))
    (test "The Emacs Session And File Keys Are Bound"
      (let ((global (scope-keys (rmpc-keybinds) "global"))
            (navigation (scope-keys (rmpc-keybinds) "navigation"))
            (queue (scope-keys (rmpc-keybinds) "queue")))
        (for-each
         (lambda (key)
           (assert-true (binds? global key)
             #:name (format #f "~a is bound globally" key)))
         '("<C-x><C-c>" "<C-x>o" "<A-x>" "<C-h>k"))
        ;; rmpc 0.11 accepts Save and Close only in `navigation', and
        ;; JumpToCurrent only in `queue', so each lives in that scope.
        (assert-true (binds? navigation "<C-x><C-s>")
          #:name "C-x C-s saves from the lists")
        (assert-true (binds? navigation "<C-x><C-w>")
          #:name "C-x C-w saves everything")
        (assert-true (binds? navigation "<C-x>k")
          #:name "C-x k closes the view")
        (assert-true (binds? queue "<C-l>")
          #:name "C-l reveals the playing song")))))

(define (theme-suite)
  (suite "Theme"
    (test "The Chrome Comes From The Palette"
      (let ((theme (rmpc-theme))
            (accent (get-color (heks-linux-palette) 'primary)))
        (assert-true (has? theme accent)
          #:name "the accent is the palette's primary")
        (assert-true (not (has? theme "borders_style: (fg: \"yellow\")"))
          #:name "no border colour is hardcoded")
        (assert-true (has? theme "\"volume\"")
          #:name "the header carries the volume slider")))
    (test "The Player Settings Are Polished"
      (let ((config (rmpc-config)))
        (assert-true (has? config "wrap_navigation: true")
          #:name "the lists wrap")
        (assert-true (has? config "scrolloff: 3")
          #:name "the selection keeps its context")
        (assert-true (has? config "select_current_song_on_change: true")
          #:name "a new song is scrolled into view")
        (assert-true (has? config "\"~/.config/rmpc/on-song-change\"")
          #:name "the hook path is a literal tilde, not a format escape")))))

(define (spec)
  (veritas-run (keymap-suite)
    (theme-suite)))
