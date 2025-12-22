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

(define-module (heks-linux git)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:export (gitignore-global gitconfig-personal gitconfig-work gitconfig
                             install-git-config))

(define gitignore-global
  `("bloop" ".bloop"
    ".metals"
    ".stack-work"
    "target"
    "metals.sbt"
    ".direnv"
    "dist-newstyle"))

(define gitconfig-personal
  `((user (name . "Josep Bigorra")
          (email . "jjbigorra@gmail.com")
          (signingkey . "24F46738CE114AF6"))))

(define gitconfig-work
  `((user (name . "Josep Bigorra")
          (email . "josepbigorraalgaba@vandebron.nl")
          (signingkey . "3B6D20502E380697"))))

(define gitconfig
  `((core (editor . "emacsclient")
          (excludesfile . "~/.gitignore-global"))
    (commit (gpgsign . "true"))
    (format (thread . "shallow"))
    (sendemail (thread . "no"))
    (pull (rebase . "false"))
    ("includeIf \"gitdir:~/Work/\"" ("  path" . "~/.gitconfig-work.ini"))
    ("includeIf \"gitdir:~/Hacking/\""
     ("  path" . "~/.gitconfig-personal.ini"))
    ("includeIf \"gitdir:~/Fork/\"" ("  path" . "~/.gitconfig-personal.ini"))
    ("includeIf \"gitdir:~/Scratch/\""
     ("  path" . "~/.gitconfig-personal.ini"))))

(define (install-git-config)
  (with-output-to-file (format #f "~a/.gitconfig"
                               (getenv "HOME"))
    (lambda ()
      (display (mk-rec-kv-conf-lines gitconfig
                                     #:template spaced-equal-conf-pair))))
  (with-output-to-file (format #f "~a/.gitconfig-personal.ini"
                               (getenv "HOME"))
    (lambda ()
      (display (mk-rec-kv-conf-lines gitconfig-personal
                                     #:template spaced-equal-conf-pair))))
  (with-output-to-file (format #f "~a/.gitconfig-work.ini"
                               (getenv "HOME"))
    (lambda ()
      (display (mk-rec-kv-conf-lines gitconfig-work
                                     #:template spaced-equal-conf-pair))))
  (with-output-to-file (format #f "~a/.gitignore-global"
                               (getenv "HOME"))
    (lambda ()
      (display (mk-lines gitignore-global)))))

