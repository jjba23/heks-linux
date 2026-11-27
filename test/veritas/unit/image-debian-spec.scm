;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux image debian): the live-build description, and the
;; two things it promises.
;;
;; The Debian medium is the second-class one and says so: it is a Debian live
;; system built by Debian's own live-build, carrying this tree's payload and its
;; packages, with Debian's installer rather than a wizard of this tree's.  What
;; the suite can prove is the shape of that: the configuration names the
;; distribution it builds and the installer it carries, the package list is the
;; Debian backend's plus the medium's own, the payload is where a person's shell
;; looks for it, and nothing from the Void build leaks in.
;;
;;; Code:

(define-module (veritas unit image-debian-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux image debian)
  #:use-module (heks-linux packages apt)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? haystack needle)
  "Return @code{#t} when @var{needle} occurs in @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

(define (described path)
  "Return the contents the description writes at @var{path}."
  (let ((entry (assoc path (debian-description))))
    (if entry
      (cdr entry)
      (error "the description does not hold" path))))

(define (rendered-paths)
  "Return the paths the description writes, as a list."
  (map car (debian-description)))

(define (config-cases)
  (suite "The live-build configuration"
    (test "It Builds Debian, And Says Which Debian"
      (let ((config (described (debian-config-filename))))
        (assert-true (contains? config "lb config")
          #:name "The configuration is live-build's own")
        (assert-true (contains? config (format #f "--distribution ~a"
                                               (debian-suite)))
          #:name "The suite is the one this tree names")
        (assert-true (contains? config (format #f "--architectures ~a"
                                               (debian-architecture)))
          #:name "And the architecture the platform module targets")
        (assert-true (contains? config "--binary-images iso-hybrid")
          #:name "A hybrid ISO boots from a stick and from a disk")
        (assert-true (contains? config "non-free-firmware")
          #:name "The firmware a wireless card needs is in the archive areas")))
    (test "It Carries Debian's Own Installer"
      ;; The Debian medium is second class on purpose: the Void one installs
      ;; itself with a wizard of this tree's, and this one hands the disk to
      ;; Debian's installer and stops pretending.
      (let ((config (described (debian-config-filename))))
        (assert-true (contains? config "--debian-installer live")
          #:name "The medium boots into the installer it carries")
        (assert-true (contains? config "--initsystem systemd")
          #:name "Debian's init system is the one live-build configures for")))))

(define (package-cases)
  (suite "The package list"
    (test "The Medium Carries What The Backend Installs"
      (let ((names (debian-medium-packages)))
        (for-each (lambda (name)
                    (assert-true (if (member name names) #t #f)
                      #:name (string-append name " is on the medium")))
                  '("labwc" "greetd" "tuigreet" "kitty" "sudo"))
        ;; Debian 13 carries no Niri, so live-build cannot put one on the
        ;; medium: the tiling session is built from source on the machine, and
        ;; the Debian page is where that step lives.
        (assert-true (not (member "niri" names))
          #:name "Niri is not on it: there is no Debian package to carry")))
    (test "And Is Sorted, And Names Each Package Once"
      (let ((names (debian-medium-packages)))
        (assert-equal #:expect (length names)
          #:got (length (delete-duplicates names))
          #:name "A package named twice is a package once")
        (assert-equal #:expect names
          #:got (sort names string<?)
          #:name "The list is written sorted, so a diff reads")))
    (test "The Rendered List Is The Same List"
      (assert-equal #:expect (format #f "~a\n" (string-join (debian-medium-packages) "\n"))
        #:got (described (debian-package-list-filename))
        #:name "One list, written as live-build reads it"))))

(define (payload-cases)
  (suite "The payload"
    (test "The Setup Command Is On The Medium"
      ;; heks-setup is how a machine that came from this medium gets its desktop:
      ;; the stores are not in the image, and this script installs them.
      (let ((setup (described (format #f "config/includes.chroot/usr/local/lib/heks-linux/~a"
                                      (debian-setup-filename)))))
        (assert-true (contains? setup "guix")
          #:name "The setup script installs Guix, and renders the desktop")
        (assert-true (contains? setup "systemctl")
          #:name "And it starts the two stores the way Debian starts a service")))
    (test "The Command A Person Types Is On Their PATH"
      (let ((wrapper (described "config/includes.chroot/usr/local/bin/heks-setup")))
        (assert-true (contains? wrapper "exec ")
          #:name "The wrapper hands over to the payload")
        (assert-true (contains? wrapper (debian-setup-filename))
          #:name "And names the file it hands to")))
    (test "The Quickstart Says What To Do Next"
      (let ((quickstart (described (format #f "config/includes.chroot~a/quickstart.txt"
                                           (debian-share-dir)))))
        (assert-true (contains? quickstart "heks-setup")
          #:name "The one command that finishes the job is in it")
        (assert-true (contains? quickstart "apt")
          #:name "And the package manager of the machine it is printed on")))
    (test "Nothing From The Void Medium Leaks In"
      ;; The Void payload carries a wizard that partitions a disk with xbps and a
      ;; runit service that draws it on a console.  The Debian medium has
      ;; Debian's installer and systemd, and a command that names either of the
      ;; Void ones is a command a person will try to run.
      (let ((everything (string-join (map cdr (debian-description)) "\n")))
        (assert-true (not (contains? everything "/usr/local/bin/heks-install"))
          #:name "There is no wizard of this tree's on it")
        (assert-true (not (contains? everything "xbps"))
          #:name "And nothing asks Void for a package")
        (assert-true (not (contains? everything "/etc/sv/"))
          #:name "And nothing writes a runit service")))))

(define (build-cases)
  (suite "The build script"
    (test "It Leaves One Artefact And Its Checksum"
      (let ((script (described (debian-build-filename))))
        (assert-true (contains? script "lb build")
          #:name "The build is live-build's")
        (assert-true (contains? script "sha256sum")
          #:name "The ISO is written with a checksum beside it")
        (assert-true (contains? script (debian-image-name))
          #:name "And named after this tree, not after live-build's default")))))

(define (render-cases)
  (suite "The description is written, not described"
    (test "Every File Is Written Under The Build Directory"
      (let ((dir (format #f "/tmp/heks-image-debian-spec-~a" (getpid))))
        (system* "rm" "-rf" dir)
        (install-debian-image-config #:dir dir)
        (for-each (lambda (path)
                    (assert-true (file-exists? (format #f "~a/~a" dir path))
                      #:name (string-append path " is written")))
                  (rendered-paths))
        (for-each (lambda (script)
                    (assert-true (access? (format #f "~a/~a" dir script)
                                          X_OK)
                      #:name (string-append script " is executable")))
                  (list (debian-config-filename) (debian-build-filename)))
        (assert-equal #:expect '()
          #:got (remove (lambda (path)
                          (zero? (system* "sh" "-n"
                                          (format #f "~a/~a" dir path))))
                        (filter (lambda (path)
                                  (string-suffix? ".sh" path))
                                (rendered-paths)))
          #:name "And every shell script in it parses")))))

(define (deb-cases)
  (suite "A Medium Built After The Packages Carries Them"
    (test "The Built Packages Land Where The Quickstart Reads Them"
      ;; `maak deb-build' leaves the collection's .deb files in `dist/deb', and
      ;; the renderer copies them onto the medium so a machine installed from it
      ;; has its bar without fetching three packages.  A render that reads the
      ;; directory has to find the files in it: one that cannot list it copies
      ;; nothing and ships the medium it shipped before, silently.
      (let* ((dir (format #f "/tmp/heks-image-debian-deb-spec-~a" (getpid)))
             (built (string-append dir "-built")))
        (system* "rm" "-rf" dir built)
        (mkdir built)
        (call-with-output-file (format #f "~a/whelk-1.0_amd64.deb" built)
                               (lambda (port) (display "not really a package" port)))
        (parameterize ((debian-deb-source built))
          (install-debian-image-config #:dir dir))
        (assert-true (file-exists?
                      (format #f "~a/config/includes.chroot~a/whelk-1.0_amd64.deb"
                              dir (debian-deb-dir)))
          #:name "The .deb is in the medium, in the directory the help names")))))

(define (spec)
  (veritas-run (config-cases) (package-cases) (payload-cases) (build-cases)
    (render-cases)
    (deb-cases)))
