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

(define-module (heks-linux prelude)
  #:declarative? #f
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 textual-ports)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (G_ setup-i18n
               syscall
               flatten-list
               spaced-conf-pair
               mk-lines
               mk-kv-conf-lines
               serialize-rec-conf-item
               mk-rec-kv-conf-lines
               spaced-equal-conf-pair
               equal-conf-pair
               equal-conf-quote-value-pair
               load-local-overrides
               css-conf-pair
               ensure-directory-tree!
               install-config-file!
               nix-profile-install
               fill-template
               template-leftovers
               mk-css-conf-lines))

(define s
  (scriba-auto-logger))

(define (G_ msg)
  "Translate @var{msg} using the current text domain.

@example
(G_ \"Hello\")
@end example"
  (gettext msg))

(define (setup-i18n)
  "Initialize internationalization (i18n) locales and text domains for the application.
Safely catches and logs errors if initialization fails."
  (catch #t
         (lambda ()
           (setlocale LC_MESSAGES "")
           (bindtextdomain "sss" "./resources/locale")
           (textdomain "sss"))
         (lambda (key . args)
           (format #t "error setting i18n up: ~a: ~a" key args))))

(define* (syscall cmd
                  #:key (silent? #f))
  "Execute the system command @var{cmd} via an input pipe and return its stdout.
If @var{silent?} is true, the output is also printed to the current output port.

@example
(syscall \"echo 'hello'\")
@result{} \"hello
\"
@end example"
  (let* ((process (open-input-pipe cmd))
         (process-output (get-string-all process)))
    (close-pipe process)
    (unless silent?
      (display process-output)) process-output))

(define (mk-lines items)
  "Join a list of @var{items} into a single string, appending a newline to each item.

@example
(mk-lines '(\"foo\" \"bar\"))
@result{} \"foo
bar
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (format #t "~a\n" x)) items))))

(define (fill-template template substitutions)
  "Replace every @code{@@token@@} in @var{template} from @var{substitutions}.

@var{substitutions} is a list of @code{(token . value)} pairs; a token with no
value is left in place.  Pages and stylesheets that carry a dozen palette
colours are written this way rather than as positional @code{format} arguments,
where a missing value silently shifts every colour after it."
  (fold (lambda (pair text)
          (string-replace-substring text (car pair) (cdr pair)))
        template
        substitutions))

(define (template-leftovers document)
  "Return the @code{@@token@@}s left in @var{document}.

A leftover means a value was never supplied and the browser would show the
placeholder, so a renderer's spec can assert the document is complete instead of
trusting the argument list."
  (let loop ((index 0) (found '()))
    (let ((open (and (< index (string-length document))
                     (string-index document #\@ index))))
      (if (not open)
          (reverse found)
          (let ((close (and (< (1+ open) (string-length document))
                            (string-index document #\@ (1+ open)))))
            (if (not close)
                (reverse found)
                (loop (1+ close)
                      (cons (substring document open (1+ close)) found))))))))

(define* (mk-css-conf-lines pairs)
  "Format an association list of @var{pairs} into a CSS ruleset string.

@example
(mk-css-conf-lines '((body (color . \"black\") (margin . 0))))
@result{} \"body {
  color: black;
  margin: 0;
}
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (format #t "~a {\n"
                                               (car x))
                                       (display (mk-kv-conf-lines (cdr x)
                                                 #:template css-conf-pair))
                                       (display "}\n\n")) pairs))))

(define* (mk-kv-conf-lines pairs
                           #:key (template "~a=~a\n"))
  "Format an association list of @var{pairs} into configuration lines using @var{template}.

@example
(mk-kv-conf-lines '((host . \"localhost\") (port . 80)))
@result{} \"host=localhost
port=80
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (cond
                                         ((pair? x)
                                          (format #t template
                                                  (car x)
                                                  (cdr x)))
                                         (else (format #t "~a" x)))) pairs))))

(define (serialize-rec-conf-item template item)
  "Serialize a single configuration @var{item} using @var{template} to the current output port.
If the item's value is a list, it formats the key as an INI-style section header.

@example
(with-output-to-string
  (lambda () (serialize-rec-conf-item \"~a=~a
\" '(port . 80))))
@result{} \"port=80
\"
@end example"
  (cond
    ((list? (cdr item))
     (cond
       ((string? (car item))
        (display (string-append "\n["
                                (car item) "]\n")))
       (else (display (string-append "\n["
                                     (symbol->string (car item)) "]\n"))))
     (display (mk-rec-kv-conf-lines (cdr item)
                                    #:template template)))
    (else (format #t template
                  (car item)
                  (cdr item)))))

(define* (mk-rec-kv-conf-lines pairs
                               #:key (template equal-conf-pair))
  "Recursively format nested configuration @var{pairs} into a string using @var{template}.
This handles both top-level key-values and nested blocks as INI-style sections.

@example
(mk-rec-kv-conf-lines '((settings (port . 8080))) #:template \"~a=~a
\")
@result{} \"
[settings]
port=8080
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (item)
                                       (serialize-rec-conf-item template item))
                                     pairs))))

(define spaced-equal-conf-pair
  "~a = ~a\n")

(define equal-conf-pair
  "~a=~a\n")

(define equal-conf-quote-value-pair
  "~a=\"~a\"\n")

(define spaced-conf-pair
  "~a ~a\n")

(define css-conf-pair
  "  ~a: ~a;\n")

(define (nix-profile-install x)
  "Install the Nix package specified by the attribute path @var{x} via system call.

@example
(nix-profile-install \"nixpkgs.tmux\")
@end example"
  (syscall (format #f "nix-env -iA ~a" x)))

(define (flatten-list xs)
  "Recursively flatten a nested list structure @var{xs} into a single flat list.

@example
(flatten-list '(1 (2 (3 4)) 5))
@result{} (1 2 3 4 5)
@end example"
  (cond
    ((null? xs)
     '())
    ((pair? xs)
     (append (flatten-list (car xs))
             (flatten-list (cdr xs))))
    (else (list xs))))

(define (ensure-directory-tree! dir)
  "Create @var{dir} and every missing parent directory leading to it.

Unlike a bare @code{mkdir}, this also works for nested targets such as
@file{~/.config/systemd/user} on a machine where @file{~/.config/systemd}
does not exist yet.

@example
(ensure-directory-tree! \"~/.config/systemd/user\")
@end example"
  (unless (file-exists? dir)
    (let ((parent (dirname dir)))
      (unless (string=? parent dir)
        (ensure-directory-tree! parent))
      (log-info s "Creating directory: ~a" dir)
      (catch 'system-error
             (lambda ()
               (mkdir dir))
             (lambda (key . args)
               ;; Tolerate a concurrent creator; anything else is real.
               (unless (file-exists? dir)
                 (apply throw key args)))))))

(define (symlink? path)
  "Whether @var{path} is a symbolic link, dangling or not."
  (catch 'system-error
    (lambda () (eq? 'symlink (stat:type (lstat path))))
    (lambda _ #f)))

(define (install-target path)
  "Return where a config file at @var{path} really lives.

A dotfile that is a symlink into a repository stays one: the write goes to what
it points at, which is what writing through a symlink always did, and the rename
that makes the write atomic happens there rather than here.  Chained links are
followed; after eight hops the file is treated as a link that points at itself.
The target has to be resolved before the temp file is named, because a rename is
only atomic inside one directory."
  (let loop ((path path) (hops 0))
    (if (or (>= hops 8) (not (symlink? path)))
        path
        (let ((link (readlink path)))
          (loop (if (eqv? #\/ (string-ref link 0))
                    link
                    (format #f "~a/~a" (dirname path) link))
                (1+ hops))))))

(define* (install-config-file! #:key name dir contents
                               (perms 420))
  "Write @var{contents} to a file named @var{name} inside directory @var{dir}.
If @var{dir} (or any of its parents) does not exist, it is created
automatically.  @var{perms} is applied to the written file with
@code{chmod}; the default @code{#o644} is readable by everyone, while
executable scripts pass @code{#o755} (493).

The file is written beside the target and renamed into place, so it is either
the old file or the new one and never half of one.  That matters for the
generated scripts: re-rendering one of them from inside itself - which is what
a palette switch does - must not pull the file out from under a running
interpreter.  A path that is a symlink is written through, so a dotfile linked
into a repository stays linked.

@example
(install-config-file! #:name \"config.toml\"
                      #:dir \"/etc/myapp\"
                      #:contents \"[settings]
port = 8080\")
@end example"
  (ensure-directory-tree! dir)
  (let* ((path-to-file (format #f "~a/~a" dir name))
         ;; A symlinked dotfile is written through, not replaced, so the target
         ;; is what gets the temporary file and the rename.
         (target (install-target path-to-file))
         ;; Written beside the target and renamed over it, because a rename is
         ;; atomic: every reader sees either the old file or the new one, never
         ;; half of one.  One of those readers is the palette picker itself -
         ;; re-rendering that script from inside the script is exactly what a
         ;; palette switch does - and truncating it in place makes Bash carry on
         ;; reading from an offset that no longer means what it did.
         (temp-file (format #f "~a.~a.tmp" target (getpid))))
    (log-info s "Writing config to file: ~a" path-to-file)
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (let ((file-port (open-output-file temp-file)))
          (set-port-encoding! file-port "UTF-8")
          (display contents file-port)
          (close-output-port file-port)
          ;; The permissions go on before the rename, so the file never exists
          ;; under its own name with the wrong ones.
          (chmod temp-file perms)
          (rename-file temp-file target)))
      (lambda ()
        (when (file-exists? temp-file)
          (delete-file temp-file))))))

(define (get-config-dir xdg-config)
  "Return the configuration directory used for local override files.
@var{xdg-config} is the value of @code{$XDG_CONFIG_HOME}.  When it is unset or
empty this falls back to @file{~/.config}, the XDG default, so overrides keep
working in minimal sessions and inside systemd units or cron jobs where the
variable is absent."
  (if (and xdg-config
           (not (string=? xdg-config "")))
      (begin
        (log-info s "load-local-overrides: Using $XDG_CONFIG_HOME: ~a"
                  xdg-config) xdg-config)
      (let ((home (getenv "HOME")))
        (if home
            (begin
              (log-info s
               "load-local-overrides: $XDG_CONFIG_HOME empty/unset, falling back to $HOME/.config")
              (format #f "~a/.config" home))

            (begin
              (log-info s
               "load-local-overrides: Warning - Neither $XDG_CONFIG_HOME nor $HOME is defined.")
              #f)))))

(define (load-local-overrides module-name profile-name)
  "Dynamically load a machine-specific configuration file within a target module.

Look for an optional configuration file at the path
@file{$XDG_CONFIG_HOME/heks-linux/@var{profile-name}.scm}, defaulting to
@file{~/.config/heks-linux/@var{profile-name}.scm} if @env{XDG_CONFIG_HOME} is
not set or empty.  If the file exists, temporarily switch the active module
context to @var{module-name} using @code{save-module-excursion} before
executing @code{load}.

This ensures that the localized configuration script evaluates within the
namespace where the module's parameters and internal definitions are bound,
preventing unbound variable errors.

@example
(load-local-overrides '(heks-linux waybar) 'waybar-settings)
@end example"
  (log-info s
   "load-local-overrides: Attempting override resolution for module ~a with profile '~a'"
   module-name profile-name)
  (let* ((xdg-config (getenv "XDG_CONFIG_HOME"))
         (config-dir (get-config-dir xdg-config)))
    (if config-dir
        (let ((local-file (format #f "~a/heks-linux/~a.scm" config-dir
                                  profile-name)))
          (log-info s
                    "load-local-overrides: Checking for override file at: ~a"
                    local-file)
          (if (file-exists? local-file)
              (begin
                (log-info s
                 "load-local-overrides: Override file found (~a). Entering module excursion into ~a..."
                 local-file module-name)
                (save-module-excursion (lambda ()
                                         (set-current-module (resolve-module
                                                              module-name))
                                         (log-info s

                                          "load-local-overrides: Loading ~a into ~a scope..."
                                          local-file module-name)
                                         (load local-file)
                                         (log-info s
                                          "load-local-overrides: Successfully loaded ~a"
                                          local-file))))
              (log-info s
               "load-local-overrides: No override file found at ~a. Skipping."
               local-file)))
        (log-info s
         "load-local-overrides: Could not resolve a config directory. Skipping."))))
