;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux prelude), the small helper layer every config
;; module is built on: list flattening, key/value rendering and the file
;; installer.

;;; Code:

(define-module (veritas unit prelude-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define scratch-dir
  (format #f "/tmp/heks-prelude-spec-~a" (getpid)))

(define (read-file path)
  (let ((port (open-input-file path)))
    (let ((contents (get-string-all port)))
      (close-port port)
      contents)))

(define (symlinked-install)
  "Install a config over a symlink and report what became of it.

Returns a list of the path's type, the contents read through the link and the
contents of the file the link points at - which is the whole question: does the
installer write through a dotfile linked into a repository, or replace the link
with a regular file?"
  (let* ((root (format #f "~a/symlinked" scratch-dir))
         (repo (format #f "~a/repo" root))
         (conf (format #f "~a/conf" root))
         (real (format #f "~a/linked.conf" repo))
         (link (format #f "~a/linked.conf" conf)))
    (ensure-directory-tree! repo)
    (ensure-directory-tree! conf)
    (call-with-output-file real
                           (lambda (port) (display "old\n" port)))
    (symlink real link)
    (install-config-file! #:name "linked.conf" #:dir conf #:contents "new\n")
    (list (stat:type (lstat link)) (read-file link) (read-file real))))

;; Computed once, at load time: the setup creates a symlink, so a second run
;; would fail on the link it made itself.
(define symlinked-install-result (symlinked-install))

(define prelude-suite
  (suite "Prelude Helper Suite"
    (test "List Flattening"
      (assert-equal #:expect '(1 2 3 4 5)
        #:got (flatten-list '(1 (2 (3 4)) 5))
        #:name "Nested lists should be flattened")
      (assert-equal #:expect '()
        #:got (flatten-list '())
        #:name "Flattening the empty list should stay empty"))

    (test "Key Value Rendering"
      (assert-equal #:expect "host=localhost\nport=80\n"
        #:got (mk-kv-conf-lines '((host . "localhost")
                                  (port . 80)))
        #:name "Pairs should render with the default template")
      (assert-equal #:expect "host = localhost\n"
        #:got (mk-kv-conf-lines '((host . "localhost"))
                                #:template
                                spaced-equal-conf-pair)
        #:name "The template should be overridable")
      (assert-equal #:expect "  color: black;\n"
        #:got (mk-kv-conf-lines '((color . "black"))
                                #:template
                                css-conf-pair)
        #:name "CSS pairs should render indented"))

    (test "Nested Structures Render As Ini Sections"
      (assert-equal #:expect "\n[settings]\nport=8080\n"
        #:got (mk-rec-kv-conf-lines '((settings
                                       (port . 8080)))
                                    #:template "~a=~a\n")
        #:name
        "A nested list should become an INI section header"))

    (test "Directory Trees Are Created Recursively"
      (ensure-directory-tree! (format #f "~a/a/b/c" scratch-dir))
      (assert-true (file-exists? (format #f "~a/a/b/c" scratch-dir))
        #:name
        "Missing parents should be created, not just the leaf")
      (assert-true (eqv? 'directory
                         (stat:type (stat (format #f "~a/a/b/c"
                                                  scratch-dir))))
        #:name "The created leaf should really be a directory"))

    (let ((target-dir (format #f "~a/installed/nested" scratch-dir)))
      (install-config-file! #:name "deep.conf"
                            #:dir target-dir
                            #:contents "hello\n")
      (test "Config Files Install Into Missing Directories"
        (assert-true (file-exists? (format #f "~a/deep.conf"
                                           target-dir))
          #:name
          "The installer should create its directory tree")
        (assert-equal #:expect "hello\n"
          #:got (read-file (format #f "~a/deep.conf"
                                   target-dir))
          #:name "The installer should write the contents")
        (assert-equal #:expect 420
          #:got (stat:perms (stat (format #f "~a/deep.conf"
                                          target-dir)))
          #:name
          "The default permissions should be #o644")))

    (test "Config Files Are Written Through Symlinks"
      (assert-equal #:expect 'symlink
        #:got (list-ref symlinked-install-result 0)
        #:name
        "A dotfile linked into a repository should stay linked")
      (assert-equal #:expect "new\n"
        #:got (list-ref symlinked-install-result 1)
        #:name
        "Reading through the link should give the new contents")
      (assert-equal #:expect "new\n"
        #:got (list-ref symlinked-install-result 2)
        #:name
        "The file the link points at should be the one rewritten"))

    (test "Executable Config Files Get Executable Permissions"
      (let ((target-dir (format #f "~a/bin" scratch-dir)))
        (install-config-file! #:name "script.sh"
                              #:dir target-dir
                              #:contents "#!/usr/bin/env bash\n"
                              #:perms 493)
        (assert-equal #:expect 493
          #:got (stat:perms (stat (format #f "~a/script.sh"
                                          target-dir)))
          #:name
          "Passing #o755 should make the file executable")))

    (test "A Render Never Reuses A Temporary Name"
      ;; The temporary file is created exclusively, so a second render of one
      ;; file cannot be handed a name that is already taken.  That is the
      ;; property the installer relies on: a parallel reconfigure renders one
      ;; file twice, and the suites render it from more than one fiber.  The
      ;; names are checked while every one of the files is still open, which a
      ;; scheme that invented its suffix could not promise.
      (let ((target (format #f "~a/exclusive.config" scratch-dir)))
        (ensure-directory-tree! (dirname target))
        (let* ((ports (map (lambda (i) (create-temp-file target))
                           (iota 16)))
               (names (map port-filename ports)))
          (assert-equal #:expect 16
            #:got (length (delete-duplicates names))
            #:name "Sixteen renders should get sixteen names")
          (assert-true (every file-exists? names)
            #:name
            "Every one of them should be a file while the others are open")
          (for-each close-port ports)
          (for-each delete-file names))))

    (test "A Render Leaves Nothing Behind"
      (let ((target-dir (format #f "~a/repeated" scratch-dir)))
        (for-each (lambda (i)
                    (install-config-file! #:name "same.conf"
                                          #:dir target-dir
                                          #:contents "racy\n"))
                  (iota 16))
        (assert-equal #:expect "racy\n"
          #:got (read-file (format #f "~a/same.conf" target-dir))
          #:name "The last render should be the one on disk")
        (assert-equal #:expect '("same.conf")
          #:got (scandir target-dir
                         (lambda (name)
                           (not (member name '("." "..")))))
          #:name "No temporary file should be left beside it")))

    (test "A Message With No Catalogue Is Its Own Translation"
      ;; gettext answers with the msgid when no catalogue is installed, which
      ;; is what lets the prose be written in English and translated later.
      (assert-equal #:expect "no catalogue has this message"
        #:got (G_ "no catalogue has this message")
        #:name "An untranslated message should come back unchanged"))

    (test "The Catalogue Binds One Project Domain"
      (assert-equal #:expect "heks-linux"
        #:got text-domain
        #:name "The text domain should be the project's name")
      (let ((previous (getenv "XDG_DATA_HOME"))
            (data (format #f "~a/xdg-data" scratch-dir)))
        (setenv "XDG_DATA_HOME" data)
        (let ((answer (locale-directory)))
          (if previous
            (setenv "XDG_DATA_HOME" previous)
            (unsetenv "XDG_DATA_HOME"))
          (assert-equal #:expect (format #f "~a/locale" data)
            #:got answer
            #:name "The catalogue should live under the XDG data directory"))))

    (test "The Catalogue Compiles Where gettext Looks"
      (let ((target (format #f "~a/catalogue" scratch-dir)))
        (install-locale-catalogue #:target-dir target)
        (assert-true (file-exists? (format #f "~a/nl/LC_MESSAGES/~a.mo"
                                           target text-domain))
          #:name "po/nl.po should compile into the domain's catalogue")))))

(define (spec)
  (veritas-run prelude-suite))
