;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Configuring the users of a machine, not only the person running the command.
;;
;; Every module in this tree renders into @code{$HOME}: that is what makes one
;; checkout describe one desktop.  A machine with more than one account needs the
;; same description twice, once per home, and hand-editing the second copy is how
;; the two drift apart.
;;
;; So a user is declared, not copied.  @file{users.scm} at the root of the
;; checkout names each account and, optionally, the profile it wears and the
;; parameters that differ - the same vocabulary a profile speaks, because a
;; second user's differences are not a second language.  The file is read, never
;; loaded:
;;
;; @example
;; ((joe)
;;  (alice . ((profile . laptop)
;;            (palette . windows-xp))))
;; @end example
;;
;; Applying it renders every surface exactly the way `maak home-reconfigure'
;; does, with that user's @code{HOME} in place of this one, and writes the
;; results with that user's ownership.  The render is the audit's render - no
;; module learns about a second user, and no surface needs a second installer -
;; and a home that already matches is written not at all.
;;
;; Two limits are deliberate.  Nothing is deleted: a file the tree stopped
;; writing is reported as retired and left for the owner to remove.  And no
;; session command runs for another account: there is no bus to reload, no
;; terminal to repaint, and starting one as root on someone else's behalf is a
;; privilege this command does not need.  Files land; their session reads them
;; when it next starts.
;;
;;; Code:

(define-module (heks-linux users)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux audit)
  #:use-module (heks-linux profile)
  #:use-module (heks-linux validation)
  #:export (users-filename
            users-path
            read-users
            validate-users
            passwd-entry
            current-user-name
            home-of
            target-environment
            write-target-file!
            apply-target-user!
            main))

;; The declaration lives beside the profiles it names, so a checkout is a
;; description of the machine and not only of one account on it.
(define users-filename
  (make-parameter "users.scm"))

(define (clone-directory)
  "Return the checkout this process is rendering from.

The launcher exports @env{HEKS_LINUX_CLONE}; a shell inside the checkout answers
with the directory it was started in, which is the same tree."
  (let ((clone (getenv "HEKS_LINUX_CLONE")))
    (if (and clone (not (string=? clone ""))) clone (getcwd))))

(define* (users-path #:key (clone (clone-directory)))
  "Return the absolute path of the user declaration in @var{clone}."
  (format #f "~a/~a" clone (users-filename)))

;; --- The declaration -------------------------------------------------------

(define (normalise-entry entry)
  "Return @code{(NAME SETTINGS)} for one declaration, or @code{#f}.

A user with nothing to say is a bare symbol; one with a profile or parameters
is @code{(NAME (KEY . VALUE) ...)}.  The two spellings are one data shape once
read, so the rest of the module never asks which was written."
  (cond
    [(symbol? entry) (cons entry '())]
    [(and (pair? entry)
       (symbol? (car entry))
       (list? (cdr entry)))
     (cons (car entry) (cdr entry))]
    [else #f]))

(define (setting-key-known? key)
  "Whether @var{key} is part of the profile vocabulary users may set."
  (or (eq? key 'profile) (memq key (profile-keys))))

(define (validate-settings name settings counter)
  "Return the problems in one user's @var{settings}.

@var{counter} is the row number, so a problem names the line a reader can find
rather than only the account."
  (let loop ((rows settings) (seen '()) (problems '()))
    (if (null? rows)
      (reverse problems)
      (let* ((row (car rows))
             (key (and (pair? row) (car row))))
        (cond
          [(not (and (pair? row) (symbol? key)))
           (loop (cdr rows) seen
                 (cons (format #f "~a: setting ~a is not a (key . value) pair"
                               name counter)
                       problems))]
          [(not (setting-key-known? key))
           (loop (cdr rows) seen
                 (cons (format #f "~a: unknown setting ~a" name key)
                       problems))]
          [(memq key seen)
           (loop (cdr rows) seen
                 (cons (format #f "~a: setting ~a appears twice" name key)
                       problems))]
          [(and (eq? key 'profile) (not (symbol? (cdr row))))
           (loop (cdr rows) (cons key seen)
                 (cons (format #f "~a: profile must be a name, not ~a"
                               name (cdr row))
                       problems))]
          [else (loop (cdr rows) (cons key seen) problems)])))))

(define (validate-users dataset)
  "Check @var{dataset} as a user declaration; return @code{(values RECORDS PROBLEMS)}.

@var{records} is a list of @code{(NAME . SETTINGS)}, in declaration order.  Every
problem is collected before anything is returned, because a file with two typos
should report both.
  A declaration is data: it may name a profile and the parameters that profile
leaves open, and nothing else.  Whether the account exists is asked later, by
the command that would write to it, so a declaration can be reviewed on a
machine other than the one it describes."
  (if (not (list? dataset))
    (values '() (list "users.scm is a list of names"))
    (let loop ((entries dataset) (seen '()) (records '()) (problems '()))
      (if (null? entries)
        (values (reverse records) (reverse problems))
        (let* ((entry (normalise-entry (car entries))))
          (cond
            [(not entry)
             (loop (cdr entries) seen records
                   (cons (format #f "~a is not a user name"
                                 (car entries))
                         problems))]
            [(memq (car entry) seen)
             (loop (cdr entries) seen records
                   (cons (format #f "~a is declared twice" (car entry))
                         problems))]
            [else
              (loop (cdr entries)
                    (cons (car entry) seen)
                    (cons entry records)
                    (append (reverse (validate-settings (car entry)
                                                        (cdr entry)
                                                        (length records)))
                            problems))]))))))

(define* (read-users #:key (path (users-path)))
  "Read the declaration at @var{path} as data; return @code{(values RECORDS PROBLEMS)}.

The file is read, never loaded, for the same reason a profile is: a declaration
cannot define a procedure, call one, or reach the file system.  A missing file
is an empty declaration, because most machines have one account."
  (if (not (file-exists? path))
    (values '() '())
    (catch #t
           (lambda ()
             (call-with-input-file path
                                   (lambda (port)
                                     (validate-users (read port)))))
           (lambda (key . args)
             (values '()
                     (list (format #f "~a: cannot be read as data" path)))))))

;; --- Accounts --------------------------------------------------------------

(define (passwd-fields line)
  "Return the seven fields of one password line, or @code{#f}.

A line with fewer fields is not an account this module can write for; refusing
it here keeps the rest of the module from carrying half an entry."
  (let ((fields (string-split line #\:)))
    (and (>= (length fields) 7)
      (list (cons 'name (list-ref fields 0))
            (cons 'uid (string->number (list-ref fields 2)))
            (cons 'gid (string->number (list-ref fields 3)))
            (cons 'home (list-ref fields 5))
            (cons 'shell (list-ref fields 6))))))

(define (passwd-line-from-database name)
  "Ask @command{getent} for @var{name}'s line; @code{#f} when it cannot answer.

@command{getent} is the same database the login program consults, so a directory
service answers exactly as it would for a login.  It is called with its argument
in a list, never through a shell string."
  (catch #t
         (lambda ()
           (let ((port (open-pipe* OPEN_READ "getent" "passwd" name)))
             (let ((line (read-line port)))
               (close-pipe port)
               (and line (not (string=? line "")) line))))
         (lambda _ #f)))

(define (passwd-line-from-file name)
  "Return @var{name}'s line from @file{/etc/passwd}, for a machine without getent."
  (and (file-exists? "/etc/passwd")
    (call-with-input-file "/etc/passwd"
                          (lambda (port)
                            (let loop ((line (read-line port)))
                              (cond
                                [(eof-object? line) #f]
                                [(string-prefix? (string-append name ":") line) line]
                                [else (loop (read-line port))]))))))

(define (passwd-entry name)
  "Return the password entry for @var{name}, or @code{#f} when there is none.

@var{name} is a string.  The answer is looked for in the name service first and
in @file{/etc/passwd} second, so a minimal container without @command{getent}
still describes its own account."
  (let ((line (or (passwd-line-from-database name)
                (passwd-line-from-file name))))
    (and line (passwd-fields line))))

(define (current-user-name)
  "Return the name of the account running this process, or @code{#f}."
  (or (getenv "USER")
    (getenv "LOGNAME")))

(define (home-of entry)
  "Return the home directory in @var{entry}, checking that it is a home.

A password entry with a relative or empty home would make the renderer write
somewhere this command cannot name, so it is refused rather than guessed."
  (let ((home (assoc-ref entry 'home)))
    (and (string? home)
      (string-prefix? "/" home)
      (not (string=? home "/"))
      home)))

;; --- Rendering one user ----------------------------------------------------

(define (target-environment name entry settings mode report users-file)
  "Return the environment a child needs to render @var{name}'s home.

The child is where the target @code{HOME} lives: every module in this tree
resolves its destination from the environment at load time, and a second user's
render is that same render with one variable changed.  The declaration itself is
handed over as a path, and the parameters as data, never as code."
  (let* ((text (symbol->string name))
         (overrides (filter (lambda (row) (not (eq? (car row) 'profile)))
                            settings))
         (profile (assoc-ref settings 'profile)))
    (append
     (list (cons "HOME" (home-of entry))
           (cons "XDG_CONFIG_HOME"
                 (format #f "~a/.config" (home-of entry)))
           (cons "USER" text)
           (cons "LOGNAME" text)
           (cons "HEKS_TARGET_USER" text)
           (cons "HEKS_TARGET_UID" (number->string (assoc-ref entry 'uid)))
           (cons "HEKS_TARGET_GID" (number->string (assoc-ref entry 'gid)))
           (cons "HEKS_TARGET_MODE" mode)
           (cons "HEKS_USERS_REPORT" report)
           (cons "HEKS_USERS_FILE" users-file))
     (if profile
       (list (cons "HEKS_PROFILE" (symbol->string profile)))
       '())
     (if (pair? overrides)
       (list (cons "HEKS_USER_SETTINGS" (format #f "~s" overrides)))
       '()))))

(define (call-with-environment bindings thunk)
  "Call @var{thunk} with @var{bindings} exported, restoring the old values after.

Restoring matters: the parent loops over users in one process, and a @code{HOME}
left pointing at the last account would make the next report describe the wrong
machine."
  (let ((saved (map (lambda (binding)
                      (cons (car binding) (getenv (car binding))))
                    bindings)))
    (dynamic-wind
      (lambda ()
        (for-each (lambda (binding)
                    (setenv (car binding) (cdr binding)))
                  bindings))
      thunk
      (lambda ()
        (for-each (lambda (old)
                    (if (cdr old)
                      (setenv (car old) (cdr old))
                      (unsetenv (car old))))
                  saved)))))

(define (read-report path)
  "Return the summary a user child wrote to @var{path}, or @code{#f}."
  (catch #t
         (lambda ()
           (call-with-input-file path
                                 (lambda (port)
                                   (let ((report (read port)))
                                     (and (list? report) report)))))
         (lambda _ #f)))

(define* (render-user record #:key (mode "check") (users-file (users-path)))
  "Render @var{record} into its own home in a child; return a report alist.

The child runs the audit's render, so a user is configured by the code path that
already knows how to describe a desktop and how to tell whether a home matches
it.  Writing is the only difference between @code{check} and @code{apply}, and it
is the child's decision because the child is the process that holds the bytes."
  (let* ((name (car record))
         (entry (passwd-entry (symbol->string name))))
    (cond
      [(not entry)
       (list (cons 'user name) (cons 'status 'unknown))]
      [(and (assoc-ref (cdr record) 'profile)
         (not (assoc-ref (profile-candidates)
                         (assoc-ref (cdr record) 'profile))))
       (list (cons 'user name) (cons 'status 'unknown-profile))]
      [else
        (let ((report (format #f "~a/heks-users-~a-~a.report"
                              (or (getenv "TMPDIR") "/tmp")
                              name (getpid))))
          (call-with-environment
           (target-environment name entry (cdr record) mode report
                               users-file)
           (lambda ()
             (system* "sh" "-c"
                      (string-join
                       (list "exec guile --no-auto-compile"
                             "-L \"$1/src\" -c"
                             "\"(use-modules (heks-linux users)) (apply-target-user!)\""
                             ">\"$2\" 2>&1")
                       " ")
                      "heks-users"
                      (clone-directory)
                      report)))
          (let ((summary (read-report report)))
            (when (file-exists? report) (delete-file report))
            (append (list (cons 'user name))
                    (if summary
                      (list (cons 'status (if (string=? mode "apply") 'applied 'checked))
                            (cons 'changed (list-ref summary 0))
                            (cons 'missing (list-ref summary 1))
                            (cons 'retired (list-ref summary 2))
                            (cons 'invalid (list-ref summary 3))
                            (cons 'failed (list-ref summary 4)))
                      (list (cons 'status 'failed))))))])))

;; --- Writing one user's files ----------------------------------------------

(define (chown-as! path uid gid)
  "Give @var{path} to @var{uid}:@var{gid}, when this process may.

A render run by the account itself cannot chown, and does not need to: the file
is already theirs.  Root writing into someone else's home is the case this
exists for."
  (when (and (zero? (getuid)) uid gid)
    (catch 'system-error
           (lambda () (chown path uid gid))
           (lambda (key . args)
             (format (current-error-port) "heks-users: cannot chown ~a: ~a~%"
                     path (cadr args))))))

(define (own-directory-chain! dir home uid gid)
  "Give @var{dir} and the directories between it and @var{home} to @var{uid}:@var{gid}.

Only the chain a write needed is touched: a user's home can hold directories
this configuration has no business rewriting, and a blanket @command{chown -R}
would be a different, larger operation than \"write this file\"."
  (define (inside? path)
    (or (string=? path home)
      (string-prefix? (string-append home "/") path)))
  (let loop ((path dir))
    (when (inside? path)
      (chown-as! path uid gid)
      (let ((parent (dirname path)))
        (unless (or (string=? parent path) (string=? parent home))
          (loop parent))))))

(define* (write-target-file! target perms contents uid gid #:key (home #f))
  "Write @var{contents} to @var{target} atomically, with @var{perms} and owner.

Returns @code{(ok . #f)} or @code{(invalid . REASON)}.  The file's own reader is
asked before anything is written, exactly as for the current user: a file that
fails its validator is reported and the old one is left alone.  @var{home} is
the directory the ownership chain stops at."
  (let* ((dir (dirname target))
         (name (basename target))
         (problem (validate-config-contents name dir contents)))
    (if problem
      (cons 'invalid problem)
      (begin
        (ensure-directory-tree! dir)
        (own-directory-chain! dir (or home dir) uid gid)
        (let* ((port (create-temp-file target))
               (temp (port-filename port)))
          (catch #t
                 (lambda ()
                   (set-port-encoding! port "UTF-8")
                   (display contents port)
                   (close-output-port port)
                   (chmod temp perms)
                   (chown-as! temp uid gid)
                   (rename-file temp target))
                 (lambda (key . args)
                   (catch #t
                          (lambda () (close-port port))
                          (lambda _ #t))
                   (when (file-exists? temp)
                     (delete-file temp))
                   (apply throw key args))))
        (cons 'ok #f)))))

;; --- The child -------------------------------------------------------------

(define (apply-target-user!)
  "Render and, in @code{apply} mode, write the user named in the environment.

This is the child @code{render-user} starts.  It answers with a summary line the
parent reads: changed, missing, retired, invalid, failed.  The environment was
set before Guile started, so every module the render spawns inherits the target
home and the declared profile without knowing either exists."
  (let* ((mode (or (getenv "HEKS_TARGET_MODE") "check"))
         (report (getenv "HEKS_USERS_REPORT"))
         (home (getenv "HOME"))
         (uid (and (getenv "HEKS_TARGET_UID")
                (string->number (getenv "HEKS_TARGET_UID"))))
         (gid (and (getenv "HEKS_TARGET_GID")
                (string->number (getenv "HEKS_TARGET_GID"))))
         (result (audit #:contents? #t))
         (files (cdr (assq 'files result)))
         (retired (cdr (assq 'retired result)))
         (failed (cdr (assq 'failed result)))
         (changed (filter (lambda (report)
                            (eq? (first report) 'changed))
                          files))
         (missing (filter (lambda (report)
                            (eq? (first report) 'missing))
                          files))
         (invalid '()))
    (when (string=? mode "apply")
      (for-each (lambda (report)
                  (let* ((target (second report))
                         (contents (list-ref report 3))
                         (perms (list-ref report 4))
                         (result (write-target-file! target perms contents
                                                     uid gid
                                                     #:home home)))
                    (when (eq? (car result) 'invalid)
                      (set! invalid (cons (cons target (cdr result)) invalid)))))
                (append changed missing)))
    (when report
      (call-with-output-file report
                             (lambda (port)
                               (write (list (length changed)
                                            (length missing)
                                            (length retired)
                                            (length invalid)
                                            (length failed))
                                      port))))
    (exit (if (pair? invalid) 3 0))))

;; --- The command -----------------------------------------------------------

(define (toggle-option remaining)
  "Drop a bare @code{--} an installed launcher may hand over."
  (remove (lambda (argument) (string=? argument "--")) remaining))

(define (usage port)
  (format port "heks-users — the declared users of this machine

Usage: heks-users [list] [--json]
       heks-users check [--json]
       heks-users apply

  list    the declaration and the account behind each name
  check   render every declared home and report what would change (default)
  apply   render and write, with that user's ownership

The declaration is users.scm beside the checkout.  A user is a name, or a name
with a profile and the parameters that profile leaves open; the parameters are
the ones a profile may set.  Applying another account's home needs root: run
heks-users with sudo, or apply the account you are logged in as.

Nothing is deleted, and no session command is run for another account: files
land, and that session reads them when it next starts.~%"))

(define (user-row record)
  "Return one row of the list view for @var{record}."
  (let* ((name (car record))
         (settings (cdr record))
         (entry (passwd-entry (symbol->string name)))
         (profile (or (assoc-ref settings 'profile) '-))
         (rest (filter (lambda (row) (not (eq? (car row) 'profile))) settings)))
    (list (symbol->string name)
          (if (and entry (home-of entry)) (home-of entry) "-")
          (if (eq? profile '-) "-" (symbol->string profile))
          (if (null? rest) "-"
            (string-join (map (lambda (row)
                                (format #f "~a=~s" (car row) (cdr row)))
                              rest)
                         " "))
          (cond [(not entry) "unknown"]
                [(not (home-of entry)) "no home"]
                [else "ok"]))))

(define (print-list records port)
  "Print the declaration table to @var{port}."
  (let ((rows (map user-row records))
        (head '("USER" "HOME" "PROFILE" "SETTINGS" "STATUS")))
    (for-each (lambda (row)
                (format port "~a~%" (string-join row "  ")))
              (cons head rows))))

(define (json-list records)
  "Return the declaration as JSON."
  (to-json
   (map (lambda (row)
          (list (cons 'user (list-ref row 0))
                (cons 'home (list-ref row 1))
                (cons 'profile (list-ref row 2))
                (cons 'settings (list-ref row 3))
                (cons 'status (list-ref row 4))))
        (map user-row records))))

(define (may-write? record)
  "Whether this process can write @var{record}'s home.

Root can write any home; anyone else can write only their own.  Asking per user
rather than once is what lets a declaration list the account running the
command beside an account it will not touch without sudo."
  (let ((entry (passwd-entry (symbol->string (car record)))))
    (or (zero? (getuid))
      (and entry (= (assoc-ref entry 'uid) (getuid))))))

(define (print-user-report report port)
  "Print one user's result to @var{port}."
  (let ((name (assoc-ref report 'user)))
    (cond
      [(eq? (assoc-ref report 'status) 'unknown)
       (format port "~a: no such account~%" name)]
      [(eq? (assoc-ref report 'status) 'unknown-profile)
       (format port "~a: no such profile~%" name)]
      [(eq? (assoc-ref report 'status) 'failed)
       (format port "~a: the render did not finish~%" name)]
      [else
        (format port "~a: ~a changed, ~a missing, ~a retired, ~a invalid, ~a failed~%"
                name
                (assoc-ref report 'changed)
                (assoc-ref report 'missing)
                (assoc-ref report 'retired)
                (assoc-ref report 'invalid)
                (assoc-ref report 'failed))])))

(define (report-clean? report)
  "Whether a user report carries no change worth writing."
  (and (memq (assoc-ref report 'status) '(checked applied))
    (zero? (assoc-ref report 'changed))
    (zero? (assoc-ref report 'missing))
    (zero? (assoc-ref report 'invalid))
    (zero? (assoc-ref report 'failed))))

(define (main args)
  "Entry point for @command{heks-users}; @var{args} is @code{(command-line)}."
  (let loop ((remaining (toggle-option (cdr args)))
             (command "check")
             (json? #f))
    (cond
      [(null? remaining)
       (let* ((records (call-with-values (lambda () (read-users)) list))
              (declared (car records))
              (problems (cadr records)))
         (when (pair? problems)
           (for-each (lambda (problem)
                       (format (current-error-port) "heks-users: ~a~%" problem))
                     problems)
           (exit 2))
         (cond
           [(string=? command "list")
            (if json?
              (begin (display (json-list declared)) (newline))
              (print-list declared (current-output-port)))
            (exit 0)]
           [(string=? command "check")
            (let ((reports (map (lambda (record)
                                  (render-user record #:mode "check"))
                                declared)))
              (if json?
                (begin (display (to-json (map (lambda (report)
                                                (map (lambda (pair)
                                                       (cons (car pair)
                                                             (cdr pair)))
                                                     report))
                                              reports)))
                  (newline))
                (for-each (lambda (report)
                            (print-user-report report (current-output-port)))
                          reports))
              (exit (if (every report-clean? reports) 0 1)))]
           [(string=? command "apply")
            (let* ((reports (map (lambda (record)
                                   (render-user record
                                                #:mode
                                                (if (may-write? record)
                                                  "apply"
                                                  "check")))
                                 declared))
                   (blocked (remove may-write? declared)))
              (for-each (lambda (report)
                          (print-user-report report (current-output-port)))
                        reports)
              (unless (null? blocked)
                (format (current-error-port)
                        "heks-users: run with sudo to write ~a's home~%"
                        (string-join (map (lambda (record)
                                            (symbol->string (car record)))
                                          blocked)
                                     ", ")))
              (exit (if (every report-clean? reports) 0 1)))]
           [else
             (format (current-error-port) "heks-users: unknown command ~a~%" command)
             (usage (current-error-port))
             (exit 2)]))]
      [(member (car remaining) '("-h" "--help"))
       (usage (current-output-port))
       (exit 0)]
      [(string=? (car remaining) "--json")
       (loop (cdr remaining) command #t)]
      [(member (car remaining) '("list" "check" "apply"))
       (loop (cdr remaining) (car remaining) json?)]
      [else
        (format (current-error-port) "heks-users: unknown option ~a~%"
                (car remaining))
        (usage (current-error-port))
        (exit 2)])))

;;; users.scm ends here
