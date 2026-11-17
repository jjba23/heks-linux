;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The desktop, as one document another program can read.
;;
;; Every fact here already exists as a parameter: the palette, the three faces,
;; the shell, the editor, the clone directory, the language and the timezone.
;; The problem is that they exist *inside* a Guile process, so anything that
;; wants them - a bug report, a screenshot caption, the About window, heks-toon -
;; re-derives them from files the modules wrote, which is a second reading of the
;; same truth and a second thing to keep in step.
;;
;; So this is a projection, not a registry: it reads the parameters and prints
;; them, and it holds no value of its own.  That is what keeps the speculative
;; part bounded - an export that becomes a second source of truth is the failure
;; mode, and the defence is that nothing reads this document back.  A renderer
;; still asks `(heks-linux-palette)'; a report asks this.
;;
;; The document has a schema name rather than a version bump: a reader can say
;; what it understands (`heks-linux/desktop/1') and refuse the rest, which is the
;; whole of what a bug report needs.
;;
;;; Code:

(define-module (heks-linux describe)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 time)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (json)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux profile)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux wezterm)
  #:use-module (heks-linux surface)
  #:export (describe-desktop
            describe-json
            describe-org
            main))

(define (timestamp)
  "Return the current local time as an ISO 8601 string."
  (strftime "%Y-%m-%dT%H:%M:%S%z" (localtime (current-time))))

(define (command-output program args)
  "Return @var{program}'s stdout when it can be run, else the empty string."
  (catch #t
         (lambda ()
           (let ((port (apply open-pipe* OPEN_READ program args)))
             (let ((text (get-string-all port)))
               (close-pipe port)
               text)))
         (lambda _ "")))

(define (niri-outputs)
  "Return the monitors as @code{(NAME WIDTH HEIGHT SCALE)} lists, if niri answers.

The monitor layout is the one fact here that is not a parameter: it is the
machine's screen, not the configuration's opinion of it.  It is read from the
running compositor and left empty when no session is there to ask."
  (let ((text (command-output "niri" '("msg" "--json" "outputs"))))
    (catch #t
           (lambda ()
             (if (string-null? (string-trim-both text))
               '()
               (map (lambda (entry)
                      (let* ((name (car entry))
                             (output (cdr entry))
                             (mode (assoc-ref output "current_mode"))
                             (logical (assoc-ref output "logical")))
                        (list name
                              (or (and mode (assoc-ref mode "width")) 0)
                              (or (and mode (assoc-ref mode "height")) 0)
                              (or (and logical (assoc-ref logical "scale")) 1))))
                    (json->scm text))))
           (lambda _ '()))))

(define (resolved-profile)
  "Return the profile in force as an alist of strings, for the document."
  (map (lambda (row)
         (cons (symbol->string (car row))
               (let ((value (cdr row)))
                 (cond
                   [(symbol? value) (symbol->string value)]
                   [else value]))))
       (profile-current)))

(define (describe-desktop)
  "Return every fact this project knows about the session, as an alist.

The shape is data from the first key to the last, so the JSON printer and the Org
printer are two views of one value and neither can drift from the other.
@code{surfaces} is the names of the surfaces the tree writes; asking
@code{heks-audit} for their state is a second question with a second answer, on
purpose."
  `((schema . "heks-linux/desktop/1")
    (generated . ,(timestamp))
    (machine . ((hostname . ,(heks-linux-hostname))
                (user . ,(or (getenv "USER") ""))
                (home . ,(or (getenv "HOME") ""))
                (clone-dir . ,(heks-linux-clone-dir))
                (emacs-clone-dir . ,(heks-linux-emacs-clone-dir))
                (notes-roam-dir . ,(heks-linux-notes-roam-dir))
                (language . ,(heks-linux-language))
                (timezone . ,(heks-linux-timezone))
                (keyboard-layout . ,(heks-linux-keyboard-layout))))
    (desktop . ((compositor . "niri")
                (sessions . ("niri" "labwc"))
                (shell . "whelk")
                (terminal . "wezterm")
                (editor . "emacs")
                (dock . "lambdock")
                (password-command . ,(heks-linux-password-command))
                (tab-bar? . ,(wezterm-tab-bar?))
                (blur? . ,(heks-linux-blur?))
                (natural-scroll? . ,(heks-linux-natural-scroll?))
                (client-side-decorations?
                 . ,(heks-linux-client-side-decorations?))))
    (palette . ((name . ,(heks-linux-palette))
                (dark? . ,(is-dark-palette (heks-linux-palette)))
                (background . ,(get-color (heks-linux-palette) 'background))
                (background-light
                 . ,(get-color (heks-linux-palette) 'background-l))
                (text . ,(get-color (heks-linux-palette) 'text))
                (text-light . ,(get-color (heks-linux-palette) 'text-l))
                (primary . ,(get-color (heks-linux-palette) 'primary))
                ;; The accent as dconf spells it (a quoted symbol), because the
                ;; document is read by programs that write dconf keys.
                (accent . ,(get-gtk-accent-color (heks-linux-palette)))
                (icon-theme . ,(get-icon-theme (heks-linux-palette)))
                (cursor-theme . ,(get-cursor-theme (heks-linux-palette)))))
    (faces . ((sans . ,(heks-linux-sans-font))
              (mono . ,(heks-linux-mono-font))
              (serif . ,(heks-linux-serif-font))
              (emacs-theme . ,(heks-linux-emacs-theme))))
    (display . ((outputs . ,(niri-outputs))))
    (surfaces . ,(map (lambda (surface)
                        (symbol->string (surface-name surface)))
                      surfaces))
    (profile . ,(resolved-profile))))

(define* (describe-json #:key (pretty? #t))
  "Return the desktop document as JSON."
  (to-json (describe-desktop) #:pretty? pretty?))

(define (flat-value value)
  "Render one document value as Org text."
  (cond
    [(null? value) "-"]
    [(pair? value) (string-join (map flat-value value) ", ")]
    [else (format #f "~a" value)]))

(define (describe-org)
  "Return the desktop document as an Org page."
  (let* ((document (describe-desktop))
         (section (lambda (key title)
                    (let ((value (assoc-ref document key)))
                      (append (list (format #f "* ~a" title))
                              (map (lambda (row)
                                     (format #f "- ~a :: ~a"
                                             (car row)
                                             (flat-value (cdr row))))
                                   value)
                              (list ""))))))
    (string-join
     (append (list "#+title: The desktop this machine is"
                   (format #f "#+date: ~a" (assoc-ref document 'generated))
                   ""
                   "Generated by ~heks-describe~; nothing reads it back, so it cannot"
                   "become a second source of truth."
                   "")
             (section 'machine "The machine")
             (section 'desktop "The desktop")
             (section 'palette "The palette")
             (section 'faces "The faces")
             (section 'display "The display"))
     "\n")))

(define (usage port)
  (format port "heks-describe - the session, as one document

Usage: heks-describe [OPTIONS]

  --json      Print the document as JSON (the default)
  --org       Print it as an Org page
  -h, --help  This text

The document names its schema, `heks-linux/desktop/1', and carries the palette,
the faces, the monitor layout, the shell and the editor, the clone directory and
the profile in force.
"))

(define (main args)
  "Entry point for @command{heks-describe}; @var{args} is @code{(command-line)}."
  (let loop ((remaining (cdr args))
             (org? #f))
    (cond
      [(null? remaining)
       (display (if org?
                  (describe-org)
                  (describe-json)))
       (newline)
       (exit 0)]
      [(member (car remaining) '("-h" "--help"))
       (usage (current-output-port))
       (exit 0)]
      [(string=? (car remaining) "--json")
       (loop (cdr remaining) #f)]
      [(string=? (car remaining) "--org")
       (loop (cdr remaining) #t)]
      [else
       (format (current-error-port) "heks-describe: unknown option ~a~%"
               (car remaining))
       (usage (current-error-port))
       (exit 2)])))

;;; describe.scm ends here
