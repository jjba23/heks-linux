;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The read-only audit: what a render would change, and what it no longer writes.
;;
;; `maak check-updates' answers the same question about packages - what has an
;; update, without installing it - and this is that shape for the files this
;; project owns.  A reconfigure writes and moves on; nothing notices that a file
;; was hand-edited three months ago, that a module's output changed shape while
;; the machine kept the old copy, or that a script the tree stopped rendering is
;; still sitting in ~/.local/bin and still on a keybinding.
;;
;; So every surface is rendered the way the installer would render it, with
;; @env{HEKS_RENDER_DIR} set, and the recorded text is compared against the live
;; tree.  Nothing is written: the render is the same code path as a real install
;; right up to the rename, and the rename is the part that is skipped.
;;
;; Three answers per file, and one per surface:
;;
;;   - `same'     the live file already holds what the tree would write;
;;   - `changed'  it holds something else, whether hand-edited or stale;
;;   - `missing'  the render produces it and the machine does not have it;
;;   - `retired'  the file carries a generated header, sits in a directory a
;;                surface writes to, and no surface produces it any more.
;;
;; The program is quiet on a clean tree, exits non-zero on any difference, and
;; takes no input: it is meant to be a pipeline step, not a conversation.
;;
;;; Code:

(define-module (heks-linux audit)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (json)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux surface)
  #:export (audit
            audit-surface
            audit-report
            audit-json
            audit-clean?
            main))

(define (read-file path)
  "Return @var{path}'s contents, or @code{#f} when it cannot be read.

A file that exists and cannot be read is reported as changed rather than as an
error: the audit's question is whether the tree matches, and an unreadable file
does not match."
  (catch #t
         (lambda ()
           (call-with-input-file path
                                 (lambda (port)
                                   (get-string-all port))))
         (lambda _ #f)))

(define (remove-tree path)
  "Delete @var{path}, and everything below it when it is a directory."
  (catch #t
         (lambda ()
           (if (eq? 'directory (stat:type (lstat path)))
             (begin
               (for-each (lambda (name)
                           (unless (member name '("." ".."))
                             (remove-tree (format #f "~a/~a" path name))))
                         (scandir path))
               (rmdir path))
             (delete-file path)))
         (lambda _ #f)))

(define* (audit-surface surface #:key (directory #f) (contents? #f))
  "Render @var{surface} and compare every write against the live tree.

Returns a list of @code{(STATE TARGET SURFACE)} triples, or one
@code{(render-failed SURFACE OUTPUT)} entry when the installer did not finish.
With @var{contents?}, a file report also carries what the render produced and
the mode it asked for, as @code{(STATE TARGET SURFACE CONTENTS PERMS)}: the user
installer needs the bytes as well as the verdict, and re-rendering to get them
would be a second render that could disagree with the first."
  (let* ((scratch (or directory (make-scratch-directory)))
         (result (render-surface-with-status surface #:directory scratch))
         (ok? (first result))
         (output (second result))
         (writes (third result)))
    (if (not ok?)
      (list (list 'render-failed (surface-name surface) output))
      (map (lambda (write)
             (let* ((target (first write))
                    (state (cond
                             [(not (file-exists? target)) 'missing]
                             [(equal? (read-file target) (third write)) 'same]
                             [else 'changed])))
               (if contents?
                 (list state target (surface-name surface)
                       (third write) (second write))
                 (list state target (surface-name surface)))))
           writes))))

(define (audit-files reports)
  "Return the reports that are about a file rather than about a render."
  (filter (lambda (report)
            (memq (first report) '(same changed missing)))
          reports))

(define (retired-files reports)
  "Return generated files in the touched directories that nothing writes now.

Only a file this project generated counts, and only inside a directory a surface
still writes to: widening the walk to the whole home would report every
`~/.config/*' this configuration never owned."
  (let* ((files (audit-files reports))
         (targets (map second files))
         (home (or (getenv "HOME") ""))
         (directories (delete-duplicates (map (lambda (target)
                                                (dirname target))
                                              targets)
                                         string=?))
         ;; The home directory itself is shared with the distribution's
         ;; skeleton: `.bashrc' and its backups live there and are none of this
         ;; walk's business.  A dedicated directory below it is.
         (ours (remove (lambda (directory) (string=? directory home))
                       directories)))
    (filter (lambda (path)
              (and (not (member path targets))
                (not (string-suffix? "~" path))
                (not (any (lambda (suffix) (string-suffix? suffix path))
                          '(".bak" ".orig" ".old" ".rej" ".swp")))
                (generated-file? path)))
            (append-map walk-files ours))))

(define* (audit #:key (contents? #f))
  "Run every surface and return the whole report, as an alist.

Three keys: @code{files} (the per-file states), @code{retired} (the paths), and
@code{failed} (the surfaces whose render did not finish).  The report is data, so
the text view and the JSON view are two printers over one answer."
  (let ((reports (append-map (lambda (surface)
                               (let ((scratch (make-scratch-directory)))
                                 (let ((result (audit-surface surface
                                                              #:directory
                                                              scratch
                                                              #:contents?
                                                              contents?)))
                                   (remove-tree scratch)
                                   result)))
                             surfaces)))
    (list (cons 'files (audit-files reports))
          (cons 'retired (retired-files reports))
          (cons 'failed (filter (lambda (report)
                                  (eq? (first report) 'render-failed))
                                reports)))))

(define (audit-clean? result)
  "Return @code{#t} when @var{result} carries no difference at all."
  (and (null? (filter (lambda (report)
                        (memq (first report) '(changed missing)))
                      (cdr (assq 'files result))))
    (null? (cdr (assq 'retired result)))
    (null? (cdr (assq 'failed result)))))

(define (state-label state)
  (string-upcase (symbol->string state)))

(define* (audit-report #:key (port (current-output-port)) (verbose? #f))
  "Print the audit and return whether the tree is clean.

A clean tree prints its summary and nothing else.  A tree with differences
prints them grouped by state, then a summary; a retired file is listed by path
because there is no surface left to group it under."
  (let* ((result (audit))
         (files (cdr (assq 'files result)))
         (retired (cdr (assq 'retired result)))
         (failed (cdr (assq 'failed result)))
         (changed (filter (lambda (report)
                            (eq? (first report) 'changed))
                          files))
         (missing (filter (lambda (report)
                            (eq? (first report) 'missing))
                          files)))
    (format port "heks-audit: ~a surfaces, ~a files~%"
            (length surfaces)
            (length files))
    (for-each (lambda (report)
                (format port "~a ~a~%" (state-label (first report))
                        (second report)))
              (append changed missing))
    (for-each (lambda (path)
                (format port "RETIRED ~a~%" path))
              retired)
    (for-each (lambda (report)
                (format port "FAILED ~a: ~a~%"
                        (second report)
                        (string-trim-right (or (third report) ""))))
              failed)
    (when verbose?
      (format port "~%unchanged: ~a~%"
              (length (filter (lambda (report)
                                (eq? (first report) 'same))
                              files))))
    (if (audit-clean? result)
      (begin
        (format port "heks-audit: the tree matches what would be written~%")
        #t)
      (begin
        (format port
                "heks-audit: ~a changed, ~a missing, ~a retired, ~a failed~%"
                (length changed)
                (length missing)
                (length retired)
                (length failed))
        (format port
                "heks-audit: nothing was written; `maak home-reconfigure' applies a change~%")
        #f))))

(define (audit-json)
  "Return the audit as a JSON string."
  (let* ((result (audit))
         (files (cdr (assq 'files result))))
    (scm->json-string
     `((version . 1)
       (clean . ,(audit-clean? result))
       (files . ,(map (lambda (report)
                        `((state . ,(symbol->string (first report)))
                          (path . ,(second report))
                          (surface . ,(symbol->string (third report)))))
                      files))
       (retired . ,(cdr (assq 'retired result)))
       (failed . ,(map (lambda (report)
                         `((surface . ,(symbol->string (second report)))
                           (output . ,(or (third report) ""))))
                       (cdr (assq 'failed result))))))))

(define (usage port)
  (format port "heks-audit - what a render would change, without changing it

Usage: heks-audit [OPTIONS]

  --json        Print the report as JSON instead of text
  --quiet       Print nothing; only the exit status speaks
  --verbose     Also count the files that already match
  -h, --help    This text

Exit status: 0 when the tree matches what would be written, 1 when it does not,
2 when an option was not understood.  Nothing is written either way.
"))

(define (main args)
  "Entry point for @command{heks-audit}; @var{args} is @code{(command-line)}."
  (let loop ((remaining (cdr args))
             (json? #f)
             (quiet? #f)
             (verbose? #f))
    (cond
      [(null? remaining)
       (cond
         [json?
           (let* ((result (audit))
                  (clean? (audit-clean? result)))
             (display (audit-json))
             (newline)
             (exit (if clean? 0 1)))]
         [quiet?
           (exit (if (audit-report #:port (%make-void-port "w")) 0 1))]
         [else
           (exit (if (audit-report #:verbose? verbose?) 0 1))])]
      [(member (car remaining) '("-h" "--help"))
       (usage (current-output-port))
       (exit 0)]
      [(string=? (car remaining) "--json")
       (loop (cdr remaining) #t quiet? verbose?)]
      [(string=? (car remaining) "--quiet")
       (loop (cdr remaining) json? #t verbose?)]
      [(string=? (car remaining) "--verbose")
       (loop (cdr remaining) json? quiet? #t)]
      [else
        (format (current-error-port) "heks-audit: unknown option ~a~%"
                (car remaining))
        (usage (current-error-port))
        (exit 2)])))

;;; audit.scm ends here
