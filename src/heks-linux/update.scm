;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; One update, every package manager, at the same time.
;;
;; The tree has a task per manager - `maak update-zypper', `update-flatpak',
;; `update-guix', `update-nix' - and `maak update' runs them one after another.
;; That is correct and it is the worst part of the day: four managers, four
;; long waits, and none of the waiting is CPU-bound.  Zypper is downloading from
;; a mirror while Guix is building a profile and Nix is copying store paths, and
;; doing them in sequence spends three of those waits doing nothing.
;;
;; So this is the same four commands, run concurrently, with one table that says
;; what each one is doing.  It is a program rather than a task because a task
;; runner's console is line-oriented by design and this wants a table that
;; redraws; `maak update' is still the entry point, and it calls this.
;;
;; Three promises the old sequence did not make:
;;
;;   - A manager that is not installed is skipped, not failed.  A machine
;;     without Nix has nothing to upgrade, and a machine without Flatpak is a
;;     machine that should still update.
;;   - A manager that needs root asks once, before the table starts, so the
;;     password prompt is not four prompts interleaved with a progress table.
;;   - Each manager's full output goes to a log under
;;     @file{$XDG_STATE_HOME/heks-linux/update/}, because a table can only show
;;     the last line and the line that mattered is usually above it.
;;
;;; Code:

(define-module (heks-linux update)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 threads)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux validation)
  #:export (update-managers
            manager-name
            manager-label
            manager-programs
            run-manager
            update-all
            update-check
            main))

(define-record-type <manager>
  (%manager name label programs check commands root?)
  manager?
  (name manager-name)
  (label manager-label)
  (programs manager-programs)
  (check manager-check)
  (commands manager-commands)
  (root? manager-root?))

(define* (manager name #:key label programs check commands (root? #f))
  "Describe one package manager: what it runs to check, and to update.

@var{commands} is a list of argv lists run in order; the first failure stops that
manager and is reported, while the others carry on.  @var{programs} is what has to
exist on @env{PATH} for the manager to be attempted at all."
  (%manager name label programs check commands root?))

;; The four halves of this machine, as data.  The order is the order they are
;; reported in, not the order they run in: the table is read top to bottom.
(define update-managers
  (list (manager 'zypper
                 #:label "openSUSE"
                 #:programs '("zypper")
                 ;; `zypper list-updates' refreshes the metadata as it runs, so
                 ;; the answer is the one `dup' would act on.
                 #:check '(("zypper" "list-updates"))
                 #:commands '(("zypper" "--non-interactive" "refresh")
                              ("zypper" "--non-interactive" "dup"))
                 #:root? #t)
        (manager 'flatpak
                 #:label "Flatpak"
                 #:programs '("flatpak")
                 #:check '(("flatpak" "remote-ls" "--updates"
                            "--columns=application,branch,version"))
                 #:commands '(("flatpak" "update" "-y")
                              ("flatpak" "uninstall" "--unused" "-y")))
        (manager 'nix
                 #:label "Nix"
                 #:programs '("nix")
                 #:check '(("nix" "profile" "upgrade" "--all" "--dry-run"))
                 #:commands '(("nix" "profile" "upgrade" "--all")
                              ("nix" "profile" "wipe-history" "--older-than"
                               "30d")
                              ("nix-store" "--gc")))
        (manager 'guix
                 #:label "Guix"
                 #:programs '("guix")
                 ;; Guix has no dry run that leaves the profile alone, so the
                 ;; check is the channels file's own answer: `heks-pins' compares
                 ;; the pin against the branch tip, and this points at it.
                 #:check '(("heks-pins" "check" "--only" "guix"))
                 #:commands '(("guix" "pull" "--channels=channels.scm")
                              ("guix" "upgrade")
                              ("guix" "gc")))))

;;; ====== Running one manager ======

(define (manager-available? manager)
  "Return @code{#t} when every program @var{manager} needs is on @env{PATH}."
  (every (lambda (program)
           (or (string=? program "nix-store")
               (program-on-path? program)))
         (manager-programs manager)))

(define* (manager-succeeds? manager #:key (root? #f))
  "Whether @var{manager}'s programs exist and, when it needs root, we have it."
  (and (manager-available? manager)
       (or (not (manager-root? manager))
           root?
           (zero? (getuid)))))

(define (state-home)
  "Return the state directory updates log into."
  (let ((xdg (getenv "XDG_STATE_HOME")))
    (format #f "~a/heks-linux/update"
            (if (and xdg (not (string=? xdg "")))
              xdg
              (format #f "~a/.local/state" (or (getenv "HOME") "/tmp"))))))

(define (ensure-directory! path)
  (unless (file-exists? path)
    (let ((parent (dirname path)))
      (unless (string=? parent path)
        (ensure-directory! parent))
      (catch 'system-error
             (lambda () (mkdir path))
             (lambda _ #t)))))

(define (log-path manager)
  (format #f "~a/~a.log" (state-home) (manager-name manager)))

(define (run-commands manager commands on-line)
  "Run @var{commands} for @var{manager}, calling @var{on-line} with each line.

The child's stdout and stderr are the log port, which `system*' honours, and the
line callback sees what was written so the table can show the newest line without
reading the file back."
  (let ((log (open-output-file (log-path manager))))
    (set-port-encoding! log "UTF-8")
    (let loop ((remaining commands)
               (ok? #t))
      (cond
        [(or (null? remaining) (not ok?)) ok?]
        [else
         (let* ((raw (car remaining))
                (argv (if (and (manager-root? manager)
                               (not (zero? (getuid))))
                        (append (list "sudo" "-n") raw)
                        raw))
                (program (car argv))
                (args (cdr argv))
                (status (parameterize ((current-output-port log)
                                       (current-error-port log))
                          (apply system* program args))))
           (on-line manager
                    (format #f "~a ~a"
                            program
                            (if (null? args) "" (string-join args " "))))
           (loop (cdr remaining)
                 (and status (zero? status))))])))
  (close-port log))

(define (run-manager manager on-state on-line)
  "Run @var{manager}'s update commands; report state changes through @var{on-state}."
  (on-state manager 'running "starting")
  (let ((status (catch #t
                  (lambda ()
                    (run-commands manager
                                  (manager-commands manager)
                                  (lambda (manager line)
                                    (on-state manager 'running line))))
                  (lambda (key . args)
                    (on-state manager 'failed
                              (format #f "~a: ~a" key args))
                    #f))))
    (if status
      (on-state manager 'ok "up to date")
      (on-state manager 'failed "see the log"))
    status))

;;; ====== The table ======

(define* (color code text #:key (enabled? #t))
  (if enabled?
    (format #f "\x1b;[~am~a\x1b;[0m" code text)
    text))

(define (status-cell state line color?)
  (case state
    [(waiting) (color "33" "waiting" #:enabled? color?)]
    [(running) (color "36" "running" #:enabled? color?)]
    [(ok) (color "32" "done" #:enabled? color?)]
    [(failed) (color "31" "failed" #:enabled? color?)]
    [(skipped) (color "33" "skipped" #:enabled? color?)]
    [else (format #f "~a" state)]))

(define (clip text width)
  "Return @var{text} cut to @var{width} characters, with an ellipsis."
  (let ((text (string-trim-both (or text ""))))
    (if (<= (string-length text) width)
      text
      (format #f "~a..." (substring text 0 (- width 3))))))

(define (render-table statuses order color? port)
  "Print the status table once."
  (let ((width (if (isatty? port) 60 200)))
    (for-each (lambda (name)
                (let* ((entry (assq-ref statuses name))
                       (manager (assq-ref entry 'manager))
                       (state (assq-ref entry 'state))
                       (line (assq-ref entry 'line)))
                  (format port "  ~a ~a ~a~%"
                          (string-pad-right (symbol->string name) 10)
                          (string-pad-right (status-cell state line color?)
                                            (+ 8 (if color? 9 0)))
                          (clip line width))))
              order)))

(define (report-final statuses order port)
  (format port "~%heks-update: ~a~%"
          (string-join
           (map (lambda (name)
                  (format #f "~a ~a"
                          name
                          (case (assq-ref (assq-ref statuses name) 'state)
                            [(ok) "done"]
                            [(failed) "FAILED"]
                            [(skipped) "skipped"]
                            [else "?"])))
                order)
           ", ")))

(define* (update-all #:key (only #f) (port (current-output-port)))
  "Update every selected manager concurrently; return whether all succeeded.

The table redraws in place on a terminal and prints one line per state change
otherwise, so the same program works in a pipeline without a screen to move a
cursor on."
  (let* ((managers (if only
                     (filter (lambda (manager)
                               (memq (manager-name manager) only))
                             update-managers)
                     update-managers))
         (color? (and (isatty? port) (not (getenv "NO_COLOR"))))
         ;; Root is asked for once, here, rather than by four children at once.
         (root-ok? (and (any manager-root? managers)
                        (or (zero? (getuid))
                            (begin
                              (format port
                                      "heks-update: asking for root once, for zypper~%")
                              (system* "sudo" "-v")))))
         ;; Every command that needs root is run through `sudo -n': the one
         ;; prompt above is the whole conversation, and a cache that expired
         ;; mid-run fails the manager instead of hanging the table.
         (mutex (make-mutex))
         (statuses '())
         (order (map manager-name managers)))
    ;; The `sudo -v' above is only a permission check; the fork is this
    ;; program's own, so a failure to fork is simply "no root".
    (set! statuses
          (map (lambda (manager)
                 (list (cons 'name (manager-name manager))
                       (cons 'manager manager)
                       (cons 'state
                             (if (manager-succeeds? manager #:root? root-ok?)
                               'waiting
                               'skipped))
                       (cons 'line
                             (if (manager-available? manager)
                               ""
                               (if (manager-root? manager)
                                 "root was not granted"
                                 "not installed")))))
               managers))
    (let ((threads
           (filter-map (lambda (manager)
                         (and (eq? (assq-ref (assq-ref statuses
                                                       (manager-name manager))
                                             'state)
                                   'waiting)
                              (call-with-new-thread
                               (lambda ()
                                 (run-manager
                                  manager
                                  (lambda (manager state line)
                                    (with-mutex mutex
                                      (let ((entry (assq-ref statuses
                                                             (manager-name
                                                              manager))))
                                        (set-cdr! (assq 'state entry) state)
                                        (set-cdr! (assq 'line entry) line))))
                                  #f)))))
                       managers)))
      (let ((lines 0))
        (let loop ()
          (with-mutex mutex
            (when (and (isatty? port) (> lines 0))
              (format port "\x1b;[~aA" lines))
            (render-table statuses order color? port)
            (set! lines (length managers)))
          (if (any (lambda (manager)
                     (memq (assq-ref (assq-ref statuses (manager-name manager))
                                     'state)
                           '(waiting running)))
                   managers)
            (begin
              (usleep 400000)
              (loop))
            #t)))
      (for-each join-thread threads))
    (report-final statuses order port)
    (every (lambda (manager)
             (memq (assq-ref (assq-ref statuses (manager-name manager)) 'state)
                   '(ok skipped)))
           managers)))

(define (run-check-command argv)
  "Return one check command's output, or a note that it could not run.

The check commands are the managers' own read-only queries; a manager that is not
installed has no command to run, and one that fails has said something worth
printing rather than something worth hiding."
  (let* ((program (car argv))
         (args (cdr argv))
         (port (catch #t
                 (lambda () (apply open-pipe* OPEN_READ program args))
                 (lambda _ #f))))
    (if (not port)
      (format #f "could not run ~a\n" program)
      (let ((output (catch #t
                      (lambda () (get-string-all port))
                      (lambda _ ""))))
        (close-pipe port)
        output))))

(define (manager-check-text manager)
  "Return everything @var{manager}'s check commands printed, in order."
  (with-output-to-string
    (lambda ()
      (for-each (lambda (argv)
                  (display (run-check-command argv)))
                (manager-check manager)))))

(define* (update-check #:key (only #f) (port (current-output-port)))
  "Ask every manager what it would change, concurrently, and print the answers.

Nothing is installed and nothing needs root: the checks are the managers' own
read-only queries, run at the same time, then printed in a stable order so two
runs can be compared."
  (let* ((managers (if only
                     (filter (lambda (manager)
                               (memq (manager-name manager) only))
                             update-managers)
                     update-managers))
         (results (make-hash-table))
         (mutex (make-mutex))
         (threads
          (filter-map (lambda (manager)
                        (if (not (manager-available? manager))
                          (begin
                            (hash-set! results (manager-name manager)
                                       "not installed\n")
                            #f)
                          (call-with-new-thread
                           (lambda ()
                             (let ((text (manager-check-text manager)))
                               (with-mutex mutex
                                 (hash-set! results (manager-name manager)
                                            text)))))))
                      managers)))
    (for-each join-thread threads)
    (for-each (lambda (manager)
                (let ((name (manager-name manager)))
                  (format port "~%== ~a (~a) ==~%"
                          (manager-label manager)
                          name)
                  (let ((text (hash-ref results name "not installed\n")))
                    (display (if (string-null? (string-trim-both text))
                               "  nothing to do\n"
                               text)
                             port))))
              managers)
    #t))


(define (parse-only value)
  (map string->symbol (string-split value #\,)))

(define (usage port)
  (format port "heks-update - one update, every package manager

Usage: heks-update [OPTIONS]

  --check          Report what would change and change nothing
  --only NAMES     Comma-separated managers: zypper, flatpak, nix, guix
  --logs           Print the directory the full logs are written to
  -h, --help       This text

Exit status: 0 when every selected manager finished (or was skipped because it
is not installed), 1 when one failed, 2 for a usage error.
"))

(define (main args)
  "Entry point for @command{heks-update}; @var{args} is @code{(command-line)}."
  (let loop ((remaining (cdr args))
             (check? #f)
             (only #f))
    (cond
      [(null? remaining)
       (if check?
         (begin (update-check #:only only) (exit 0))
         (exit (if (update-all #:only only) 0 1)))]
      [(member (car remaining) '("-h" "--help"))
       (usage (current-output-port))
       (exit 0)]
      [(string=? (car remaining) "--check")
       (loop (cdr remaining) #t only)]
      [(string=? (car remaining) "--logs")
       (format #t "~a~%" (state-home))
       (exit 0)]
      [(string=? (car remaining) "--only")
       (if (null? (cdr remaining))
         (begin
           (format (current-error-port) "heks-update: --only needs a value~%")
           (exit 2))
         (loop (cddr remaining) check? (parse-only (cadr remaining))))]
      [else
       (format (current-error-port) "heks-update: unknown option ~a~%"
               (car remaining))
       (usage (current-error-port))
       (exit 2)])))

;;; update.scm ends here
