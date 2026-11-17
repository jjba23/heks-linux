;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; One table of the surfaces this project writes, built from the modules.
;;
;; The tree has always known what each module writes and never known the whole
;; set at once.  The keyboard reference was written in one place, the surface
;; tables in docs/ in another, and the answer to "what does the palette reach?"
;; was a `grep' that had to be right.  A surface here is the missing join: the
;; module and the procedure that renders it, the files that render produces
;; (measured, by rendering into a scratch directory), the programs that read
;; them, the package that provides each program, and the binding that reaches
;; it.
;;
;; The files are not a hand-written list.  The renderer runs the module the way
;; the installer does, with @env{HEKS_RENDER_DIR} set, and the recorded writes
;; are the answer.  That is the same machinery `heks-audit' uses to diff against
;; the live tree, which is why the docs, the doctor and the audit cannot disagree
;; about what a surface writes: there is one answer and three printers.
;;
;; The binding is found, not declared: each surface names command fragments it is
;; reached by, and the Niri and LabWC binding tables are searched for them.  A
;; surface whose key is removed from the compositor therefore loses its key in
;; every view at once.
;;
;;; Code:

(define-module (heks-linux surface)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (json)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux validation)
  #:use-module (heks-linux niri)
  #:use-module (heks-linux labwc)
  #:export (surface surface?
                     surface-name
                     surface-module
                     surface-installer
                     surface-readers
                     surface-reach
                     surfaces
                     surface-by-name
                     surface-bindings
                     surface-key
                     surface-files
                     surface-programs
                     render-surface
                     render-surface-with-status
                     make-scratch-directory
                     surface-render-problems
                     walk-files
                     generated-file?
                     source-directory
                     org-table
                     markdown-table
                     doctor-report
                     keyboard-reference-lines
                     surface-json
                     write-surfaces-doc
                     main))

(define-record-type <surface>
  (%surface name module installer readers reach)
  surface?
  (name surface-name)
  (module surface-module)
  (installer surface-installer)
  (readers surface-readers)
  (reach surface-reach))

(define* (surface name #:key module installer readers (reach '()))
  "Describe one surface: @var{name}, its @var{module} and @var{installer}.

@var{readers} is a list of @code{(PROGRAM . PACKAGE)} pairs naming what reads the
files and the package that provides it; @var{reach} is a list of command
fragments a keybinding can be recognised by.  Both are declarations, because
neither can be measured: no render tells you which program opens a file, and a
binding is a fact about the compositor's table rather than about the file."
  (%surface name module installer readers reach))

;; The same pairs `maak home-reconfigure' renders, plus the second session.  The
;; order is the order a reconfigure writes them, which is the order a diff reads
;; best in.
(define surfaces
  (list (surface 'gtk3
                 #:module 'gtk
                 #:installer 'install-gtk3-config
                 #:readers '(("gtk4" . "gtk4") ("gtk3" . "gtk3")))
        (surface 'gtk4
                 #:module 'gtk
                 #:installer 'install-gtk4-config
                 #:readers '(("gtk4" . "gtk4")))
        (surface 'gtk-dconf
                 #:module 'gtk
                 #:installer 'install-gtk-dconf-config
                 #:readers '(("dconf" . "dconf")))
        (surface 'dconf
                 #:module 'dconf
                 #:installer 'install-dconf-config
                 #:readers '(("dconf" . "dconf")))
        (surface 'niri
                 #:module 'niri
                 #:installer 'install-niri-config
                 #:readers '(("niri" . "niri"))
                 #:reach '("niri msg"))
        (surface 'whelk
                 #:module 'whelk
                 #:installer 'install-whelk-config
                 #:readers '(("whelk" . "whelk"))
                 #:reach '("whelk --launcher" "whelk --lock" "whelk --clipboard"))
        (surface 'palette-picker
                 #:module 'palette-picker
                 #:installer 'install-palette-picker-config
                 #:readers '(("heks-toon" . "heks-toon"))
                 #:reach '("heks-toon palettes"))
        (surface 'wezterm
                 #:module 'wezterm
                 #:installer 'install-wezterm-config
                 #:readers '(("wezterm" . "wezterm"))
                 #:reach '("wezterm"))
        (surface 'zen
                 #:module 'zen
                 #:installer 'install-zen-config
                 #:readers '(("zen" . "zen-browser")))
        (surface 'btop
                 #:module 'btop
                 #:installer 'install-btop-config
                 #:readers '(("btop" . "btop"))
                 #:reach '("btop"))
        (surface 'lambdock
                 #:module 'lambdock
                 #:installer 'install-lambdock-config
                 #:readers '(("lambdock" . "lambdock")))
        (surface 'wallpaper
                 #:module 'wallpaper
                 #:installer 'install-wallpaper-config
                 #:readers '(("whelk" . "whelk"))
                 #:reach '("heks-wallpaper" "heks-toon walls"))
        (surface 'bridges-emacs
                 #:module 'bridges
                 #:installer 'install-heks-linux-to-emacs-bridge-config
                 #:readers '(("emacs" . "emacs"))
                 #:reach '("emacsclient"))
        (surface 'bridges-bash
                 #:module 'bridges
                 #:installer 'install-heks-linux-to-bash-bridge-config
                 #:readers '(("bash" . "bash")))
        (surface 'capture
                 #:module 'capture
                 #:installer 'install-capture-config
                 #:readers '(("bash" . "bash") ("grim" . "grim"))
                 #:reach '("heks-capture"))
        (surface 'eca
                 #:module 'eca
                 #:installer 'install-eca-config
                 #:readers '(("eca" . "eca")))
        (surface 'git
                 #:module 'git
                 #:installer 'install-git-config
                 #:readers '(("git" . "git")))
        (surface 'ssh
                 #:module 'ssh
                 #:installer 'install-ssh-config
                 #:readers '(("ssh" . "openssh")))
        (surface 'fastfetch
                 #:module 'fastfetch
                 #:installer 'install-fastfetch-config
                 #:readers '(("fastfetch" . "fastfetch")))
        (surface 'fontconfig
                 #:module 'fontconfig
                 #:installer 'install-fontconfig-config
                 #:readers '(("fontconfig" . "fontconfig")))
        (surface 'rmpc
                 #:module 'rmpc
                 #:installer 'install-rmpc-config
                 #:readers '(("rmpc" . "rmpc"))
                 #:reach '("rmpc"))
        (surface 'toon
                 #:module 'toon
                 #:installer 'install-toon-config
                 #:readers '(("heks-toon" . "heks-toon"))
                 #:reach '("heks-toon"))
        (surface 'containers-registries
                 #:module 'containers
                 #:installer 'install-containers-registries-config
                 #:readers '(("podman" . "podman")))
        (surface 'containers-policy
                 #:module 'containers
                 #:installer 'install-containers-policy-config
                 #:readers '(("podman" . "podman")))
        (surface 'distrobox
                 #:module 'distrobox
                 #:installer 'install-distrobox-config
                 #:readers '(("distrobox" . "distrobox"))
                 #:reach '("heks-deb"))
        (surface 'labwc
                 #:module 'labwc
                 #:installer 'install-labwc-config
                 #:readers '(("labwc" . "labwc"))
                 #:reach '("labwc"))))

(define (surface-by-name name)
  "Return the surface called @var{name}, or @code{#f}."
  (find (lambda (surface)
          (eq? (surface-name surface) name))
        surfaces))

;;; ====== Rendering one surface ======

(define (source-directory)
  "Return this project's @file{src} directory.

The directory is derived from the file this module was loaded from rather than
from a parameter: a render spawns a child that has to be given the same tree, and
a machine whose override points the clone somewhere else must still audit the
code that is running.  @env{HEKS_LINUX_SRC} wins, for a tree that was copied
somewhere without its parent."
  (or (let ((env (getenv "HEKS_LINUX_SRC")))
        (and env (not (string=? env "")) env))
      (let ((file (module-filename (resolve-module '(heks-linux surface)))))
        (and file
             (let ((directory (dirname (dirname file))))
               (and (file-exists? (format #f "~a/heks-linux" directory))
                    directory))))
      (format #f "~a/src" (or (getenv "PWD") "."))))

(define (render-command surface directory)
  "Return the Scheme expression that renders @var{surface} into @var{directory}."
  (format #f
          "(begin (setenv \"HEKS_RENDER_DIR\" ~s) ((@ (heks-linux ~a) ~a)))"
          directory
          (surface-module surface)
          (surface-installer surface)))

(define (run-render surface directory)
  "Run @var{surface}'s installer with rendering on; return @code{(ok . output)}."
  (let* ((port (catch #t
                 (lambda ()
                   (open-pipe* OPEN_READ
                               "guile"
                               "--no-auto-compile"
                               "-L"
                               (source-directory)
                               "-c"
                               (render-command surface directory)))
                 (lambda (key . args)
                   (cons #f (format #f "could not start guile: ~a" key))))))
    (if (pair? port)
      port
      (let ((output (catch #t
                      (lambda () (get-string-all port))
                      (lambda _ ""))))
        (let ((status (catch #t
                        (lambda () (close-pipe port))
                        (lambda _ 1))))
          (cons (and status (zero? status)) output))))))

(define (read-manifest directory)
  "Return the recorded writes in @var{directory}, as @code{(PATH PERMS FILE)}.

The manifest is read as text rather than as Scheme: it is written by another
process, one line per write, with three tab-separated fields.  A malformed line
is skipped, because a render that died mid-write is already reported by its exit
status and a half-line is not worth a second error."
  (let ((path (format #f "~a/manifest.tsv" directory)))
    (if (not (file-exists? path))
      '()
      (let loop ((lines (call-with-input-file path
                                             (lambda (port)
                                               (let collect ((acc '()))
                                                 (let ((line (read-line port)))
                                                   (if (eof-object? line)
                                                     (reverse acc)
                                                     (collect (cons line acc))))))))
                 (acc '()))
        (if (null? lines)
          (reverse acc)
          (let ((fields (string-split (car lines) #\tab)))
            (loop (cdr lines)
                  (if (= (length fields) 3)
                    (cons (list (third fields)
                                (string->number (second fields))
                                (format #f "~a/files/~a" directory (first fields)))
                          acc)
                    acc))))))))

(define (make-scratch-directory)
  "Return a directory only this process knows about.

The name comes from @code{mkstemp!}, so two renders in one process cannot share
one, and the caller owns removing it."
  (let* ((template (format #f "~a/heks-surface-XXXXXX"
                           (or (getenv "TMPDIR") "/tmp")))
         (port (mkstemp! template)))
    (close-port port)
    (delete-file template)
    (mkdir template)
    template))

(define* (render-surface-with-status surface #:key (directory #f))
  "Render @var{surface} and return @code{(OK? OUTPUT WRITES)}.

@code{WRITES} is a list of @code{(TARGET PERMS CONTENTS)}.  The status is kept
beside the writes because a surface can legitimately write nothing - @code{toon}
retires files - and a render that failed must be told apart from one that had
nothing to say."
  (let* ((scratch (or directory (make-scratch-directory)))
         (result (run-render surface scratch)))
    (list (car result)
          (cdr result)
          (if (car result)
            (map (lambda (entry)
                   (list (first entry)
                         (second entry)
                         (call-with-input-file (third entry)
                                               (lambda (port)
                                                 (get-string-all port)))))
                 (read-manifest scratch))
            '()))))

(define* (render-surface surface #:key (directory #f))
  "Render @var{surface} into a scratch directory and return its writes.

Each write is @code{(TARGET PERMS CONTENTS)}.  The directory is created when the
caller does not name one, so two renders in one process cannot share files, and
the caller owns removing it."
  (third (render-surface-with-status surface #:directory directory)))

(define (surface-render-problems surface directory)
  "Render @var{surface} into @var{directory}; return the child's complaints.

An installer that exits non-zero is a surface the audit cannot answer for, and
saying so is better than reporting every one of its files as missing."
  (cdr (run-render surface directory)))

(define (surface-files surface)
  "Return the files @var{surface} writes, as @code{(TARGET PERMS)} pairs."
  (map (lambda (write)
         (list (first write) (second write)))
       (render-surface surface)))

(define (surface-programs surface)
  "Return the programs that read @var{surface}'s files."
  (map car (surface-readers surface)))

;;; ====== The binding that reaches a surface ======

(define (binding-cmd binding)
  "Return @var{binding}'s command as a string, whichever compositor wrote it."
  (let ((pair (assq 'cmd binding)))
    (and pair
         (let ((value (cdr pair)))
           (cond
             [(string? value) value]
             [(symbol? value) (symbol->string value)]
             [else #f])))))

(define (binding-key binding)
  "Return @var{binding}'s key as a string, or @code{#f}."
  (let ((mod (assq 'mod binding))
        (bind (assq 'bind binding)))
    (cond
      [(and mod bind (cdr bind))
       (format #f "Mod+~a" (cdr bind))]
      [(and mod bind (not (cdr bind)))
       (format #f "~a" (cdr mod))]
      ;; LabWC writes one string, `W-S-t'.
      [(assq 'key binding) (cdr (assq 'key binding))]
      [else #f])))

(define (surface-bindings)
  "Return every binding the two sessions declare, as flat alists."
  (append (map (lambda (binding)
                 (list (cons 'key (binding-key binding))
                       (cons 'cmd (binding-cmd binding))
                       (cons 'desc (cdr (assq 'desc binding)))))
               (niri-bindings))
          (labwc-bindings)))

(define* (surface-key surface #:key (bindings (surface-bindings)))
  "Return the first binding whose command reaches @var{surface}, or @code{#f}."
  (let ((fragments (surface-reach surface)))
    (find (lambda (binding)
            (let ((cmd (cdr (assq 'cmd binding))))
              (and cmd
                   (any (lambda (fragment)
                          (string-contains cmd fragment))
                        fragments))))
          bindings)))

;;; ====== The views ======

(define (join-names items separator)
  (string-join items separator))

(define (program-cell surface)
  "Return @var{surface}'s readers as one cell: program (package), comma-joined."
  (join-names (map (lambda (reader)
                     (format #f "~a (~a)" (car reader) (cdr reader)))
                   (surface-readers surface))
              ", "))

(define (home-relative path)
  "Return @var{path} with a leading home directory written as a tilde.

The table is documentation as well as a report, and a page that spells one
machine's home directory out in full is a page that diffs on every machine that
reads it."
  (let ((home (or (getenv "HOME") "")))
    (if (and (not (string=? home "")) (string-prefix? home path))
      (string-append "~" (substring path (string-length home)))
      path)))

(define (file-cell writes)
  (join-names (map (lambda (write) (home-relative (first write))) writes) " "))

(define (surface-rows)
  "Return one row per surface: name, files, readers, program, key.

The files come from a render, so this is the one call that is not free: it runs a
child process per surface.  Everything that prints this table prints the same
rows, which is what makes the docs, the doctor and the audit agree."
  (map (lambda (surface)
         (let ((writes (surface-files surface))
               (key (surface-key surface)))
           (list surface
                 writes
                 (program-cell surface)
                 (if key (cdr (assq 'key key)) "-")
                 (if key (cdr (assq 'desc key)) "-"))))
       surfaces))

(define (org-table)
  "Return the surface table as an Org table."
  (let ((rows (surface-rows)))
    (string-join
     (append (list "| Surface | Files it writes | Read by (package) | Key |"
                   "|---------+-----------------+-------------------+-----|")
             (map (lambda (row)
                    (format #f "| ~a | ~a | ~a | ~a |"
                            (surface-name (first row))
                            (file-cell (second row))
                            (third row)
                            (fourth row)))
                  rows))
     "\n")))

(define (markdown-table)
  "Return the surface table as a Markdown table."
  (let ((rows (surface-rows)))
    (string-join
     (append (list "| Surface | Files it writes | Read by (package) | Key |"
                   "| --- | --- | --- | --- |")
             (map (lambda (row)
                    (format #f "| ~a | ~a | ~a | ~a |"
                            (surface-name (first row))
                            (file-cell (second row))
                            (third row)
                            (fourth row)))
                  rows))
     "\n")))

(define (doctor-report)
  "Return a line per missing program a surface depends on.

The capture module's doctor asks the same question for the tools it drives; this
asks it for every surface at once, and names the task that provides the missing
piece.  A program that is not on @env{PATH} is reported, not fatal: this desktop
can run without Zen."
  (append-map (lambda (surface)
                (append
                 (filter-map (lambda (reader)
                               (and (not (program-on-path? (car reader)))
                                    (format #f "~a: ~a is missing (~a)"
                                            (surface-name surface)
                                            (car reader)
                                            (cdr reader))))
                             (surface-readers surface))
                 (if (surface-key surface)
                   '()
                   (list (format #f "~a: no keybinding reaches it"
                                 (surface-name surface))))))
              surfaces))

(define (keyboard-reference-lines)
  "Return the keyboard reference as @code{(KEY ACTION SURFACE)} triples.

The reference used to be a hand-written page beside a hand-written table beside a
hand-written binding list.  It is a projection of the same two binding tables the
compositors are rendered from, plus the surface each command reaches, so a chord
that is added to Niri appears here without anyone remembering to add it."
  (let ((bindings (surface-bindings)))
    (map (lambda (binding)
           (let* ((cmd (or (cdr (assq 'cmd binding)) ""))
                  (owner (find (lambda (surface)
                                 (any (lambda (fragment)
                                        (string-contains cmd fragment))
                                      (surface-reach surface)))
                               surfaces)))
             (list (or (cdr (assq 'key binding)) "?")
                   (or (cdr (assq 'desc binding)) "")
                   (if owner
                     (symbol->string (surface-name owner))
                     ""))))
         bindings)))

;;; ====== Files a module no longer writes ======

(define (generated-file? path)
  "Return @code{#t} when @var{path} carries this project's generated header.

The check reads the first lines only.  Every renderer writes a banner - a comment
naming the module, or the auto-generated marker - and a file that has one and is
no longer produced by any surface is a file the tree has stopped writing rather
than a file somebody keeps by hand."

  (define (banner? port)
    (let loop ((remaining 8))
      (if (zero? remaining)
        #f
        (let ((line (read-line port)))
          (if (eof-object? line)
            #f
            (let ((lower (string-downcase line)))
              (if (and (or (string-contains lower "generated")
                           (string-contains lower "do not edit"))
                       (or (string-contains lower "heks")
                           (string-contains lower "auto-")))
                #t
                (loop (1- remaining)))))))))

  (and (file-exists? path)
       (catch #t
              (lambda () (eq? 'regular (stat:type (stat path))))
              (lambda _ #f))
       (catch #t
              (lambda () (call-with-input-file path banner?))
              (lambda _ #f))))


(define* (walk-files directory #:key (depth 1))
  "Return the regular files below @var{directory}, recursing @var{depth} levels.

Directory symlinks are not followed: a dotfile linked into a checkout must not
make the walk leave the directory it was asked about.  A directory that changes
while it is being read - a browser profile, a build tree - is left alone rather
than reported, because the audit is about what this project writes, not about
what other programs are doing."
  (define (entry-type path)
    (catch #t
      (lambda () (stat:type (lstat path)))
      (lambda _ #f)))
  (if (not (file-exists? directory))
    '()
    (let loop ((entries (catch #t
                          (lambda () (scandir directory))
                          (lambda _ '())))
               (acc '()))
      (if (null? entries)
        (reverse acc)
        (let* ((name (car entries))
               (path (format #f "~a/~a" directory name)))
          (loop (cdr entries)
                (cond
                  [(member name '("." "..")) acc]
                  [(and (> depth 0)
                        (eq? 'directory (entry-type path))
                        (not (symlink? path)))
                   (append (walk-files path #:depth (- depth 1)) acc)]
                  [(eq? 'regular (entry-type path))
                   (cons path acc)]
                  [else acc])))))))


;;; ====== The page ======

(define* (write-surfaces-doc #:key (path "docs/surfaces.org"))
  "Write the surface manifest to @var{path} as an Org page; return @var{path}.

The page is a view of the same table the command prints: prose that names where
it came from, then the measured manifest.  Regenerating it is `maak
docs-surfaces', and a page edited by hand would be a fourth list to maintain."
  (call-with-output-file path
    (lambda (port)
      (display "#+title: The surface manifest\n#+options: toc:nil\n\n" port)
      (display "[[file:../README.org][<- Back to the README]]\n\n" port)
      (display (string-join
                (list "Generated by `maak docs-surfaces' from the modules; do"
                      "not edit by hand.  `heks-surfaces --org' prints the same"
                      "table, `--json' the same data, and `--doctor' the same"
                      "manifest against this machine.")
                " ")
               port)
      (display "\n\n" port)
      (display (org-table) port)))
  path)

;;; ====== The command ======

(define (surface-json)
  "Return the manifest as a JSON-ready alist: one entry per surface.

The table the documentation prints is a view of this, and so is the doctor
report: a surface's files, the programs that read them, the package that
provides each program and the key that reaches it are one answer with several
printers."
  (map (lambda (surface)
         (let ((bindings (surface-bindings)))
           `((surface . ,(symbol->string (surface-name surface)))
             (module . ,(symbol->string (surface-module surface)))
             (installer . ,(symbol->string (surface-installer surface)))
             (files . ,(map car (surface-files surface)))
             (readers . ,(map (lambda (reader)
                                `((program . ,(car reader))
                                  (package . ,(cdr reader))))
                              (surface-readers surface)))
             (reach . ,(surface-reach surface))
             (keys . ,(let ((key (surface-key surface #:bindings bindings)))
                        (if key
                          (list (cdr (assq 'key key)))
                          '()))))))
       surfaces))

(define (usage port)
  "Print the command's options to @var{port}."
  (format port "heks-surfaces [--org|--markdown|--json|--doctor|--keys]\n"))

(define (main args)
  "Entry point for @command{heks-surfaces}; @var{args} is @code{(command-line)}."
  (let ((arguments (cdr args)))
    (cond
      [(member "--help" arguments)
       (usage (current-output-port))
       0]
      [(member "--json" arguments)
       (display (to-json (surface-json)))
       (newline)
       0]
      [(member "--doctor" arguments)
       (for-each (lambda (finding) (format #t "~a~%" finding))
                 (doctor-report))
       0]
      [(member "--keys" arguments)
       (for-each (lambda (line)
                   (format #t "~a\t~a\t~a~%" (first line) (second line)
                           (third line)))
                 (keyboard-reference-lines))
       0]
      [(member "--markdown" arguments)
       (display (markdown-table))
       0]
      [else
       (display (org-table))
       0])))

;;; surface.scm ends here
