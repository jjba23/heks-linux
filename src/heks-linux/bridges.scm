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

(define-module (heks-linux bridges)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (heks-linux-to-emacs-bridge
            install-heks-linux-to-emacs-bridge-config
            heks-linux-to-bash-bridge
            install-heks-linux-to-bash-bridge-config
            bash-bridge-filename
            bash-bridge-dir
            emacs-bridge-filename
            emacs-bridge-dir))

(define s
  (scriba-auto-logger))

(define* (heks-linux-to-emacs-bridge)
  (let* ((elisp `(progn (setopt heks-emacs-font-mono
                                ,(heks-linux-mono-font))
                        (setopt heks-emacs-font-sans
                                ,(heks-linux-sans-font))
                        (setopt heks-emacs-font-serif
                                ,(heks-linux-serif-font))
                        (setopt heks-emacs-theme
                                (intern ,(format #f "~a"
                                                 (heks-linux-emacs-theme))))
                        (setopt heks-emacs-clone-dir
                                ,(heks-linux-clone-dir))
                        (setopt heks-emacs-notes-roam-dir
                                ,(heks-linux-notes-roam-dir))
                        (setopt heks-emacs-ews-music-directory ""))))
    elisp))

(define (heks-linux-to-bash-bridge)
  (let* ((vars `((HEKS_BASH_HIGHLIGHT_TEXT unquote
                                           (heks-linux-bash-highlight))))
         (vars-str (string-join (map (lambda (v)
                                       (format #f "~a=~a"
                                               (car v)
                                               (cdr v))) vars) "\n")))
    (format #f "#!/usr/bin/env bash\n~a" vars-str)))

(define emacs-bridge-dir
  (make-parameter (format #f "~a/.emacs.d"
                          (or (getenv "HOME") "/tmp"))))

(define emacs-bridge-filename
  (make-parameter "heks-linux-bridge.el"))

(define bash-bridge-dir
  (make-parameter (format #f "~a"
                          (or (getenv "HOME") "/tmp"))))

(define bash-bridge-filename
  (make-parameter ".bash-heks-linux-bridge.bash"))

(define (install-heks-linux-to-emacs-bridge-config)
  (log-info s "Installing Heks Linux to Emacs bridge configuration")
  (install-config-file! #:name (emacs-bridge-filename)
                        #:dir (emacs-bridge-dir)
                        #:contents (object->string (heks-linux-to-emacs-bridge)))
  (log-success s "Installed Heks Linux to Emacs bridge configuration"))

(define (install-heks-linux-to-bash-bridge-config)
  (log-info s "Installing Heks Linux to Bash bridge configuration")
  (install-config-file! #:name (bash-bridge-filename)
                        #:dir (bash-bridge-dir)
                        #:contents (heks-linux-to-bash-bridge))
  (log-success s "Installed Heks Linux to Bash bridge configuration"))
