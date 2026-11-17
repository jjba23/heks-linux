;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The front end a keybinding runs to choose one picture from the palette's set.
;;
;; Whelk owns the background: it draws it, rotates it, and remembers the picture
;; a person picked as a GUI preference - an alist under
;; @env{XDG_STATE_HOME}/whelk, written by its own picker.  What it does not
;; have is a command-line verb for "set this one", and both a compositor binding
;; and heks-toon's wall view want exactly that.  So this is that verb, and it is
;; deliberately the smallest thing that could be one: it writes the same
;; preference whelk's picker writes and asks the shell to re-read its settings.
;;
;; It is a module rather than a generated script because it is logic - which
;; candidate is next, which one is not the one on screen - and logic in a string
;; is logic nobody tests.  The launcher `wallpaper.scm' installs gives it three
;; paths through the environment; everything below is testable in a temporary
;; directory with no session and no compositor.
;;
;; The state file is written beside whelk's preference because heks-toon reads
;; it to mark the current picture in its grid.  Two records of one choice is one
;; too many, and the alternative was teaching another repository to read whelk's
;; alist; the file is one line, and it is written after the preference, so the
;; shell is always the thing that is right.
;;
;;; Code:

(define-module (heks-linux wallpaper-shim)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:export (shim-main
            shim-candidates
            shim-current
            shim-remember!
            shim-step
            shim-random
            main))

(define (shim-list-file)
  (getenv "HEKS_WALLPAPER_LIST"))

(define (shim-preferences-file)
  (getenv "HEKS_WALLPAPER_PREFERENCES"))

(define (shim-state-file)
  (getenv "HEKS_WALLPAPER_STATE"))

(define (shim-candidates)
  "Return the candidate pictures, in the order the list file names them.

A missing list is an empty collection rather than an error: the front end is
reached from a keybinding, and a keybinding that printed a backtrace at a person
would be worse than one that said there is nothing to choose."
  (let ((file (shim-list-file)))
    (if (or (not file) (not (file-exists? file)))
      '()
      (filter (lambda (line)
                (not (string=? line "")))
              (call-with-input-file file
                                    (lambda (port)
                                      (let loop ((lines '()))
                                        (let ((line (read-line port)))
                                          (if (eof-object? line)
                                            (reverse lines)
                                            (loop (cons line lines)))))))))))

(define (read-preferences)
  "Return whelk's preference alist for this settings file, or the empty list."
  (let ((file (shim-preferences-file)))
    (if (or (not file) (not (file-exists? file)))
      '()
      (catch #t
             (lambda ()
               (call-with-input-file file
                                     (lambda (port)
                                       (let ((value (read port)))
                                         (if (list? value) value '())))))
             (lambda _ '())))))

(define (shim-current)
  "Return the picture whelk is showing, or @code{#f}."
  (let ((pair (assq 'wallpaper-selected (read-preferences))))
    (and pair (cdr pair))))

(define (ensure-directory! directory)
  (unless (file-exists? directory)
    (let ((parent (dirname directory)))
      (unless (string=? parent directory)
        (ensure-directory! parent))
      (catch 'system-error
             (lambda () (mkdir directory))
             (lambda _ #t)))))

(define (write-atomically! file contents)
  "Write @var{contents} to @var{file} through a temporary file and a rename."
  (let ((directory (dirname file)))
    (ensure-directory! directory)
    (let* ((port (mkstemp! (string-append file ".XXXXXX")))
           (temporary (port-filename port)))
      (set-port-encoding! port "UTF-8")
      (display contents port)
      (close-port port)
      (chmod temporary #o600)
      (rename-file temporary file))))

(define (shim-remember! path)
  "Record @var{path} as the picture whelk should show.

The preference is replaced rather than appended, because two entries for one key
make the file's meaning depend on which one a reader happens to find first.  The
write is atomic for the same reason every other write in this tree is: the shell
watches that directory and may read the file the instant it changes."
  (let* ((file (shim-preferences-file))
         (old (read-preferences))
         (without (filter (lambda (pair)
                            (not (eq? (car pair) 'wallpaper-selected)))
                          old))
         (updated (cons (cons 'wallpaper-selected path) without)))
    (write-atomically! file
                       (with-output-to-string
                         (lambda ()
                           (write updated)
                           (newline)))))
  (let ((state (shim-state-file)))
    (when state
      (write-atomically! state (string-append path "\n"))))
  path)

(define (shim-step step)
  "Return the candidate @var{step} places after the current one, wrapping.

The walk is over the palette's own set, sorted, so `next' after the last picture
is the first one and calling it twice never lands on the picture already on
screen by accident."
  (let* ((candidates (shim-candidates))
         (count (length candidates))
         (current (shim-current)))
    (cond
      [(zero? count) #f]
      [(not current) (first candidates)]
      [else
       (let ((index (list-index (lambda (candidate)
                                  (string=? candidate current))
                                candidates)))
         (list-ref candidates
                   (modulo (+ (or index 0) step) count)))])))

(define (shim-random)
  "Return a candidate other than the one on screen.

The entropy comes from @code{/dev/urandom} and falls back to the clock: a
shuffle that repeats the current picture is a key that looks broken."
  (let* ((candidates (shim-candidates))
         (count (length candidates)))
    (cond
      [(zero? count) #f]
      [else
       (let* ((seed (catch #t
                      (lambda ()
                        (call-with-input-file "/dev/urandom"
                                              (lambda (port)
                                                (let ((bytes (get-bytevector-n port 4)))
                                                  (+ (* 256 (bytevector-u8-ref bytes 0))
                                                     (bytevector-u8-ref bytes 1))))))
                      (lambda _ (car (cdr (current-time))))))
              (first-pick (list-ref candidates (modulo seed count)))
              (current (shim-current)))
         (if (and (> count 1) (string=? first-pick current))
           (list-ref candidates (modulo (1+ seed) count))
           first-pick))])))

(define (reload-shell!)
  "Ask whelk to re-read its settings, when a session exists to ask."
  (when (getenv "WAYLAND_DISPLAY")
    (catch #t
           (lambda ()
             (system* "whelk" "--reload"))
           (lambda (key . args)
             (format (current-error-port)
                     "heks-wallpaper: could not ask whelk to reload: ~a~%"
                     key)))))

(define (shim-main args)
  "Run one wallpaper command; return an exit status.

The vocabulary is the previous engine's - @code{random}, @code{next},
@code{prev}, @code{restore}, @code{set PATH}, @code{current}, @code{list} - so
a keybinding or a program that called it keeps working after the port."
  (let ((command (if (null? args) "random" (car args))))
    (cond
      [(member command '("-h" "--help" "help"))
       (format #t "heks-wallpaper [random|next|prev|restore|set PATH|current|list]\n")
       0]
      [(string=? command "current")
       (let ((current (shim-current)))
         (format #t "~a~%" (or current ""))
         (if current 0 1))]
      [(string=? command "list")
       (for-each (lambda (candidate)
                   (format #t "~a~%" candidate))
                 (shim-candidates))
       0]
      [(string=? command "restore")
       (reload-shell!)
       0]
      [(string=? command "set")
       (cond
         [(null? (cdr args))
          (format (current-error-port) "heks-wallpaper: set needs a path~%")
          2]
         [(not (file-exists? (cadr args)))
          (format (current-error-port)
                  "heks-wallpaper: no such wallpaper: ~a~%" (cadr args))
          1]
         [else
          (shim-remember! (cadr args))
          (format #t "wallpaper: ~a~%" (cadr args))
          (reload-shell!)
          0])]
      [else
       (let ((choice (cond
                       [(string=? command "random") (shim-random)]
                       [(string=? command "next") (shim-step 1)]
                       [(string=? command "prev") (shim-step -1)]
                       [else #f])))
         (cond
           [(not choice)
            (format (current-error-port) "heks-wallpaper: unknown command: ~a~%"
                    command)
            2]
           [else
            (shim-remember! choice)
            (format #t "wallpaper: ~a~%" choice)
            (reload-shell!)
            0]))])))

(define (main args)
  "Entry point for @command{heks-wallpaper}; @var{args} is @code{(command-line)}."
  (exit (shim-main (cdr args))))

;;; wallpaper-shim.scm ends here
