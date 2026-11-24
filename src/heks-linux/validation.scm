;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The check a generated file passes before it reaches its target.
;;
;; A desktop whose failure mode is a black screen is a desktop where the file
;; writing is the cheap half.  Niri already knows how to read its own KDL, whelk
;; already knows how to read its own settings, and both are on the machine that
;; is about to be written to: asking them is a subprocess, and not asking them
;; is a session that does not come back after the next login.
;;
;; So this is a table, not a parser.  Each entry says which file it claims, which
;; program validates it, and how that program is called with a candidate path.
;; A file with no entry is written as before - the check is insurance, not a
;; gate that every new surface has to satisfy before it can exist - and a
;; validator that is not installed is skipped rather than treated as a failure,
;; because a machine without whelk can still render a Kitty file.
;;
;; The one check that is not a subprocess is Scheme: every generated `.scm' is
;; read with `read', which catches the mistake that actually happens - a render
;; that ended a list early - without needing the program that will later load it.
;;
;;; Code:

(define-module (heks-linux validation)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (json)
  #:export (validate-config-contents
            validator-for
            program-on-path?))

(define (program-on-path? program)
  "Return @code{#t} when @var{program} can be executed from @env{PATH}."
  (let ((path (or (getenv "PATH") "")))
    (any (lambda (directory)
           (let ((candidate (format #f "~a/~a"
                                    (if (string=? directory "")
                                      "."
                                      directory)
                                    program)))
             (and (file-exists? candidate)
               (not (eq? 'directory (stat:type (stat candidate)))))))
         (string-split path #\:))))

(define (which program)
  "Return @var{program} when it is on @env{PATH}, otherwise @code{#f}.

The empty string is kept as the program rather than the absolute path: the
validators are invoked through @code{open-pipe*}, which searches @env{PATH}
itself, and naming the program is what keeps the diagnostic readable."
  (and (program-on-path? program) program))

(define (run-validator program args contents)
  "Run @var{program} against @var{contents} written to a scratch file.

The validators take a path, not a standard input stream - `niri validate --config'
and `xmllint --noout' both want a file - so the candidate is written beside the
run and removed afterwards.  What the program says is what gets reported: a
validator's own message names the line, which is the only part worth printing
beside a file that was not written."
  (let* ((path (format #f "/tmp/heks-validate-~a-~a"
                       (getpid) (random 1000000)))
         (errors (open-output-string)))
    (call-with-output-file path
                           (lambda (port) (display contents port)))
    (let ((status
           (catch #t
                  (lambda ()
                    (with-error-to-port errors
                                        (lambda ()
                                          (apply system* program
                                                 (append args (list path))))))
                  (lambda (key . details)
                    (format (current-error-port)
                            "validation: could not run ~a: ~a ~a~%"
                            program key details)
                    #f))))
      (catch #t (lambda () (delete-file path)) (lambda _ #f))
      (and status
        (not (zero? status))
        (or (first-line (get-output-string errors))
          (format #f "rejected by ~a" (basename program)))))))

(define (first-line text)
  "Return the first non-empty line of @var{text}, trimmed, or #f."
  (let ((lines (filter (lambda (line) (not (string-null? (string-trim-both line))))
                       (string-split text #\newline))))
    (and (pair? lines) (string-trim-both (car lines)))))

(define (scheme-syntax-problem contents)
  "Return a reason when @var{contents} is not readable as Scheme, else #f.

Reading every form is the read half of what a Guile process does with a dotfile -
settings and bridges - and it is the one check that needs nothing installed."
  (catch #t
         (lambda ()
           (call-with-input-string contents
             (lambda (port)
               (let loop ()
                 (let ((form (read port)))
                   (unless (eof-object? form)
                     (loop))))))
           #f)
         (lambda (key . args)
           (format #f "not readable as Scheme (~a)" key))))

(define (json-syntax-problem contents)
  "Return a reason when @var{contents} is not JSON, else #f."
  (catch #t
         (lambda ()
           (json-string->scm contents)
           #f)
         (lambda (key . args)
           (format #f "not readable as JSON (~a)" key))))

(define (whelk-settings? name directory)
  "Return @code{#t} when @var{name} in @var{directory} is whelk's settings file."
  (and (string=? name "settings.scm")
    (string? directory)
    (string-suffix? "/whelk" directory)))

(define (validator-for name directory)
  "Return the validator @var{name} in @var{directory} is checked with, or #f.

A validator is @code{(KIND PROGRAM . ARGS)}: @code{scheme} and @code{json} are
in-process, and every other kind names a program that is handed the candidate
file.  The directory is part of the question because whelk's file is called
@file{settings.scm} like a dozen others, and only the one inside @file{whelk/}
is whelk's to read."
  (cond
    [(whelk-settings? name directory)
     (list 'program "whelk" "--config")]
    [(string-suffix? ".kdl" name)
     (list 'program "niri" "validate" "--config")]
    [(string-suffix? ".scm" name)
     (list 'scheme)]
    [(string-suffix? ".json" name)
     (list 'json)]
    [(string-suffix? ".xml" name)
     (list 'program "xmllint" "--noout")]
    [(string-suffix? ".sh" name)
     (list 'program "bash" "-n")]
    [else #f]))

(define (validate-config-contents name directory contents)
  "Return @code{#f} when @var{contents} may be written as @var{name}, else a reason.

@var{directory} is where the file is going, and is only consulted to tell whelk's
@file{settings.scm} from every other one.  A validator that is not installed
answers @code{#f}: the check is skipped, not failed, so a machine with only part
of the stack still renders the rest."
  (let ((validator (validator-for name directory)))
    (and validator
      (case (car validator)
        [(scheme) (scheme-syntax-problem contents)]
        [(json) (json-syntax-problem contents)]
        [(program)
         (let ((program (which (cadr validator))))
           (and program
             (run-validator program (cddr validator) contents)))]
        [else #f]))))

;;; validation.scm ends here
