;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Renders @file{~/.config/fastfetch/config.jsonc}, the system summary printed
;; by @code{fastfetch} when a shell starts.
;;
;; The module owns two things: the ordered list of modules to display and the
;; logo.  Both are plain data, so @code{fastfetch-conf} is a pure renderer that
;; can be called from a REPL and serialized with @code{scm->json-string}
;; without touching the disk.
;;
;; A commented-out image logo sits next to the active small-text logo.  It works
;; in terminals that implement the Kitty graphics protocol; enable it by moving
;; the comment and pointing it at a PNG.

;;; Code:

(define-module (heks-linux fastfetch)
  #:declarative? #t
  #:use-module (json)
  #:use-module (ice-9 string-fun)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (fastfetch-conf install-fastfetch-config fastfetch-config-filename
                           fastfetch-config-dir))

(define s
  (scriba-auto-logger))

(define* (fastfetch-conf #:key clone-dir)
  "Return the FastFetch configuration as a Scheme association list.

Serializing the result with @code{scm->json-string} produces a valid
@file{config.jsonc}.  @var{clone-dir} is accepted for symmetry with the other
modules and is only used by the commented-out image logo.

@example
(scm->json-string (fastfetch-conf) #:pretty #t)
@end example"
  (let* ((modules `(title separator
                          ((type . os)
                           (format . "Heks GNU/Linux: {pretty-name}"))
                          host
                          kernel
                          uptime
                          packages
                          shell
                          ((type . cpu) (key . "CPU Temp")
                           (temp . #t)
                           (format . "{temperature}"))
                          gpu
                          memory
                          disk
                          wm
                          wmtheme
                          theme
                          icons
                          terminal
                          display
                          battery
                          locale
                          break
                          colors)))
    `(($schema . "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json")
      (logo (type . small))
      ;; === Use this for images in fastfetch (works well with Kitty) ===
      ;; (logo (source unquote
      ;; (string-replace-substring (format #f
      ;; "~a/resources/varesa-small-3.png"
      ;; (heks-linux-clone-dir)) "~/"
      ;; (format #f "~a/"
      ;; (getenv "HOME"))))
      ;; (width . 32)
      ;; (padding (top . 2)
      ;; (left . 2)
      ;; (right . 2)))
      (modules unquote
               (list->vector modules)))))

;; Directory receiving @file{config.jsonc}; defaults to @file{~/.config/fastfetch}
;; and is overridable per machine (or per call) like every other path parameter.
(define fastfetch-config-dir
  (make-parameter (format #f "~a/.config/fastfetch"
                          (or (getenv "HOME") "/tmp"))))

;; Name of the rendered JSON file.  FastFetch only looks for @file{config.jsonc},
;; so change this only if you know why you want to.
(define fastfetch-config-filename
  (make-parameter "config.jsonc"))

(define (install-fastfetch-config)
  "Write the FastFetch configuration to @code{fastfetch-config-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/fastfetch-settings.scm} before rendering."
  (log-info s "Installing FastFetch configuration")
  (load-local-overrides '(heks-linux fastfetch) 'fastfetch-settings)
  (install-config-file! #:name (fastfetch-config-filename)
                        #:dir (fastfetch-config-dir)
                        #:contents (scm->json-string (fastfetch-conf
                                                                     #:clone-dir
                                                                     (heks-linux-clone-dir))
                                                     #:pretty #t))
  (log-success s "Installed FastFetch configuration"))
