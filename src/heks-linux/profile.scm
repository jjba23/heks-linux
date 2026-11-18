;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; A profile is a named bundle of parameters, written as data.
;;
;; The tree already has one way to make a machine its own: an override file that
;; is *code*, evaluated inside a module's own namespace, which can redefine a
;; procedure, add a keybinding or replace a list.  That is the right tool for the
;; machine that wants to differ, and the wrong one for the two machines that
;; differ only in palette, faces and which session they start.
;;
;; So this is the other half, and the difference is deliberate:
;;
;;   - An override is Scheme, loaded with `load', and can do anything a module
;;     can.  A profile is an alist, read with `read' and never evaluated.
;;   - An override is named after the module it bends; a profile is named after
;;     the machine it describes, and covers every module at once.
;;   - A key a profile does not know is an error, not a binding.  That is what
;;     lets `heks-profile check' mean something: a typo in a profile is caught
;;     before a render, where a typo in an override is caught by the renderer
;;     failing halfway through a session.
;;
;; The contract is bounded on purpose: a profile sets parameters and nothing
;; else.  A machine that needs a different *shape* - another bar, a second rule -
;; writes an override, and the two do not overlap.  A profile is applied first,
;; so an override still wins.
;;
;; The file lives at @file{$XDG_CONFIG_HOME/heks-linux/profile.scm}.  Its content
;; is the profile itself, so a machine's description is one file a `cp' can
;; replace and a `diff' can explain:
;;
;; @example
;; ((palette . nord)
;;  (sans-font . \"Work Sans\")
;;  (blur? . #f)
;;  (modules . (niri whelk kitty)))
;; @end example
;;
;;; Code:

(define-module (heks-linux profile)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (profile-parameter-table
            profile-keys
            profile-parameter
            profile-validate
            profile-read
            profile-current
            profile-file
            profile-directory
            profile-candidates
            apply-profile!
            apply-active-profile!))

;; The whole vocabulary: what a profile may say, and where the parameter lives.
;; A pair is (KEY MODULE VARIABLE), and the value is applied by calling the
;; parameter - which is a procedure - with it.  The table is the contract: it is
;; what makes "a profile that is only parameters" a decidable claim rather than a
;; slogan, and adding a parameter to a profile is adding one row here.
(define profile-parameter-table
  '((palette (heks-linux user-settings) heks-linux-palette)
    (emacs-theme (heks-linux user-settings) heks-linux-emacs-theme)
    (bash-highlight (heks-linux user-settings) heks-linux-bash-highlight)
    (mono-font (heks-linux user-settings) heks-linux-mono-font)
    (sans-font (heks-linux user-settings) heks-linux-sans-font)
    (serif-font (heks-linux user-settings) heks-linux-serif-font)
    (keyboard-layout (heks-linux user-settings) heks-linux-keyboard-layout)
    (keyboard-options (heks-linux user-settings) heks-linux-keyboard-options)
    (language (heks-linux user-settings) heks-linux-language)
    (timezone (heks-linux user-settings) heks-linux-timezone)
    (hostname (heks-linux user-settings) heks-linux-hostname)
    (screenshots-dir (heks-linux user-settings) heks-linux-screenshots-dir)
    (password-command (heks-linux user-settings) heks-linux-password-command)
    (password-startup-args (heks-linux user-settings) heks-linux-password-startup-args)
    (clone-dir (heks-linux user-settings) heks-linux-clone-dir)
    (emacs-clone-dir (heks-linux user-settings) heks-linux-emacs-clone-dir)
    (notes-roam-dir (heks-linux user-settings) heks-linux-notes-roam-dir)
    (caps-to-ctrl? (heks-linux user-settings) heks-linux-caps-to-ctrl?)
    (client-side-decorations? (heks-linux user-settings) heks-linux-client-side-decorations?)
    (blur? (heks-linux user-settings) heks-linux-blur?)
    (natural-scroll? (heks-linux user-settings) heks-linux-natural-scroll?)
    (tab-bar? (heks-linux kitty) kitty-tab-bar?)
    (wallpaper-interval (heks-linux wallpaper) wallpaper-rotation-interval)))

(define (profile-keys)
  "Return every key a profile may carry, sorted."
  (sort (map car profile-parameter-table)
        (lambda (a b)
          (string<? (symbol->string a) (symbol->string b)))))

(define (profile-parameter key)
  "Return the @code{(MODULE VARIABLE)} @var{key} names, or @code{#f}."
  (let ((row (assq key profile-parameter-table)))
    (and row (cdr row))))

(define (value-kind value)
  "Return the shape of @var{value}, as a profile error names it."
  (cond
    [(symbol? value) 'symbol]
    [(string? value) 'string]
    [(boolean? value) 'boolean]
    [(number? value) 'number]
    [(list? value) 'list]
    [else 'unknown]))

(define (profile-validate dataset)
  "Return the problems in @var{dataset}, as a list of strings.

@var{dataset} is what @code{read} returned: an alist of @code{(KEY . VALUE)}
pairs.  Two questions are asked of every row - is the key part of the
vocabulary, and does the value have the shape the parameter already holds - and
nothing is applied when either answer is no.  The shape check is not a type
system: a profile that sets @code{blur?} to a string is caught, one that sets a
font to a face this machine does not have is not, and only the render can know
that."
  (cond
    [(not (list? dataset))
     (list "a profile is a list of (key . value) pairs")]
    [else
     (append-map (lambda (row)
                   (cond
                     [(not (pair? row))
                      (list (format #f "~s is not a (key . value) pair"
                                    row))]
                     [(not (profile-parameter (car row)))
                      (list (format #f "unknown profile key: ~a (known keys: ~a)"
                                    (car row)
                                    (string-join (map symbol->string
                                                      (profile-keys))
                                                 ", ")))]
                     [else
                      (let* ((parameter (profile-parameter (car row)))
                             (module (resolve-module (car parameter)))
                             (variable (module-ref module (cadr parameter)))
                             (expected (value-kind (variable))))
                        (if (eq? expected (value-kind (cdr row)))
                          '()
                          (list (format #f
                                        "~a takes a ~a, not a ~a"
                                        (car row)
                                        expected
                                        (value-kind (cdr row))))))]))
                 dataset)]))

(define (profile-read path)
  "Read the profile at @var{path} as data; return @code{(values DATA PROBLEM)}.

The file is read, never loaded: a profile cannot define a procedure, call one,
or reach the file system, which is exactly the promise that separates it from an
override.  A missing file answers an empty profile rather than an error, because
most machines do not have one."
  (if (not (file-exists? path))
    (values '() '())
    (catch #t
           (lambda ()
             (call-with-input-file path
                                   (lambda (port)
                                     (let ((data (read port)))
                                       (values data '())))))
           (lambda (key . args)
             (values #f (list (format #f "~a is not readable: ~a" path key)))))))

;; The active profile is memoized: every module's installer asks for it, and the
;; file is applied once per process.  `#f' means "not asked yet", `'none' means
;; "asked, and this machine has no profile".
(define active-profile 'unset)

(define* (profile-directory #:key (config-dir #f))
  "Return the directory profiles live in.

It is @file{profiles/} beside the active profile, under the same
@env{XDG_CONFIG_HOME} the overrides use, so one directory holds the machine's
described selves and one of them is the one in force."
  (format #f "~a/heks-linux/profiles" (or config-dir (config-home))))

(define (config-home)
  "Return the project's configuration directory, XDG first."
  (let ((xdg (getenv "XDG_CONFIG_HOME")))
    (if (and xdg (not (string=? xdg "")))
      xdg
      (format #f "~a/.config" (or (getenv "HOME") "/tmp")))))

(define* (profile-file #:key (config-dir #f))
  "Return the path of the profile in force."
  (format #f "~a/heks-linux/profile.scm"
          (or config-dir (config-home))))

(define* (profile-current #:key (config-dir #f))
  "Return the profile in force as an alist, or the empty list."
  (call-with-values (lambda ()
                      (profile-read (profile-file #:config-dir config-dir)))
                    (lambda (data problem)
                      (cond
                        [(pair? problem)
                         (format (current-error-port) "profile: ~a~%" problem)
                         '()]
                        [(or (not data) (null? data)) '()]
                        [else
                         (let ((problems (profile-validate data)))
                           (when (pair? problems)
                             (for-each (lambda (problem)
                                         (format (current-error-port)
                                                 "profile: ~a~%"
                                                 problem))
                                       problems))
                           (if (null? problems) data '()))]))))

(define (default-repo-dir)
  "Return the checkout whose @file{profiles/} this machine can wear.

The launcher exports @env{HEKS_LINUX_CLONE} because a keybinding runs from
wherever it was pressed; a shell run inside the checkout answers with the
directory it was started in, which is the same tree."
  (let ((clone (getenv "HEKS_LINUX_CLONE")))
    (if (and clone (not (string=? clone ""))) clone (getcwd))))

(define* (profile-candidates #:key (config-dir #f)
                                  (repo-dir (default-repo-dir)))
  "Return every profile this machine can choose, as @code{(NAME PATH)} pairs.

Two places are searched: the user's @file{profiles/} directory, which is the one
`heks-profile use' writes to, and the checkout's own @file{profiles/}, which is
where a named profile is published.  The user's copy wins on a name, so a
machine can take a published profile and keep its own version of it."
  (let* ((user (profile-directory #:config-dir config-dir))
         (repo (and repo-dir (format #f "~a/profiles" repo-dir)))
         (entries (lambda (directory)
                    (if (and directory (file-exists? directory))
                      (map (lambda (name)
                             (cons (string-drop-right name 4)
                                   (format #f "~a/~a" directory name)))
                           (filter (lambda (name)
                                     (string-suffix? ".scm" name))
                                   (scandir directory)))
                      '()))))
    (let loop ((remaining (append (entries user) (entries repo)))
               (seen '())
               (kept '()))
      (cond
        [(null? remaining) (reverse kept)]
        [(member (caar remaining) seen)
         (loop (cdr remaining) seen kept)]
        [else
         (loop (cdr remaining)
               (cons (caar remaining) seen)
               (cons (car remaining) kept))]))))

(define* (apply-profile! data #:key (config-dir #f))
  "Apply @var{data} to the parameters it names; return the problems, if any.

Every row is checked before any is applied, so a profile with one typo changes
nothing rather than half of the machine.  A parameter is called, not assigned:
they are procedures by design, and calling one is the only way to set it that
works for every module without knowing which file it lives in."
  (let ((problems (profile-validate data)))
    (if (pair? problems)
      problems
      (begin
        (for-each (lambda (row)
                    (let* ((parameter (profile-parameter (car row)))
                           (module (resolve-module (car parameter)))
                           (variable (module-ref module (cadr parameter))))
                      (variable (cdr row))))
                  data)
        '()))))

(define (requested-profile-name)
  "Return the profile a caller named for this render, or @code{#f}.

`heks-users' applies another account's declared profile by exporting
@env{HEKS_PROFILE}; the name is resolved against the checkout's @file{profiles/}
before that account's own config, because the declaration is the source and the
account may not have a session to have written one."
  (let ((name (getenv "HEKS_PROFILE")))
    (and name (not (string=? name "")) (string->symbol name))))

(define (requested-user-settings)
  "Return the extra @code{(KEY . VALUE)} rows a caller handed to this render.

@env{HEKS_USER_SETTINGS} carries them as text, and they are read, never
evaluated, exactly like a profile file: a declaration may set parameters, it may
not run code."
  (let ((text (getenv "HEKS_USER_SETTINGS")))
    (if (and text (not (string=? text "")))
      (catch #t
        (lambda ()
          (let ((data (read (open-input-string text))))
            (and (list? data) data)))
        (lambda _ #f))
      #f)))

(define* (apply-active-profile! #:key (config-dir #f))
  "Apply the profile in force once per process, before any override code.

Called from `load-local-overrides' rather than from a module of its own: an
override is loaded at install time, when the module's parameters exist, and a
profile is applied in the same breath and one step earlier.  That is what keeps
the precedence honest - profile first, override second - without a second
loading order nobody can see.

A profile named in @env{HEKS_PROFILE} replaces the one the account's file asks
for, and @env{HEKS_USER_SETTINGS} is applied after it, so a declared user's
parameters win over the profile they came from without a second file to edit."
  (when (eq? active-profile 'unset)
    (let* ((requested (requested-profile-name))
           (extra (requested-user-settings))
           (path (and requested
                      (assoc-ref (profile-candidates #:config-dir config-dir)
                                 (symbol->string requested))))
           (declared (and path
                          (call-with-values
                            (lambda () (profile-read path))
                            list))))
      (when (and requested (not path))
        (format (current-error-port) "profile: no profile named ~a~%"
                requested))
      (let ((data (cond
                    [(and declared (null? (cadr declared))) (car declared)]
                    [requested '()]
                    [else (profile-current #:config-dir config-dir)])))
        (when (and declared (pair? (cadr declared)))
          (for-each (lambda (problem)
                      (format (current-error-port) "profile: ~a~%" problem))
                    (cadr declared)))
        (let* ((merged (append data (or extra '())))
               (problems (apply-profile! merged #:config-dir config-dir)))
          (when (pair? problems)
            (for-each (lambda (problem)
                        (format (current-error-port)
                                "profile: ~a~%"
                                problem))
                      problems))
          (set! active-profile (if (null? merged) 'none merged))))))
  active-profile)

;;; profile.scm ends here
