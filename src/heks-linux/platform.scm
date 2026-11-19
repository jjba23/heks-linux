;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The machine an artefact is built for: its architecture and its libc.
;;
;; Void publishes two binary trees, one built against glibc and one against
;; musl, and they are told apart by the XBPS architecture string -
;; @code{x86_64} and @code{x86_64-musl} - and by the repository path.
;;
;; This tree targets glibc only, for a reason that is not taste: whelk and
;; lambdock are installed from a Nix flake built against glibc, and Flatpak is
;; glibc-only, so a musl artefact would boot to a desktop whose shell and dock
;; cannot be installed.  The libc is a parameter rather than a constant so that
;; an artefact can be built for musl on the day those two problems are solved,
;; and @code{ensure-supported-libc!} is the one place that says when: the
;; answer is "not yet", with the reason, instead of a build that fails halfway.
;;
;; What is *not* here: the packages.  A libc is not a package list, and a musl
;; build needs its own list rather than this one renamed - which is why the
;; image's list is a value it reads, not something this module rewrites.
;;
;;; Code:

(define-module (heks-linux platform)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:export (target-libc
            target-arch
            xbps-arch
            xbps-repository
            ensure-supported-libc!))

;; The libc the artefact is built against.  @code{glibc} is the only supported
;; value today; see the commentary above.
(define target-libc
  (make-parameter 'glibc))

;; The CPU architecture.  x86_64 and aarch64 are the two Void publishes live
;; images for, and x86_64 is the only one this tree has been tested on.
(define target-arch
  (make-parameter 'x86_64))

(define (xbps-arch)
  "Return the XBPS architecture string for the target.

XBPS spells a musl system by suffixing the architecture - @code{x86_64-musl} -
and a glibc system by the architecture alone, so this is the one place the two
conventions meet."
  (let ((arch (symbol->string (target-arch)))
        (libc (target-libc)))
    (case libc
      [(glibc) arch]
      [(musl) (string-append arch "-musl")]
      [else (error "xbps-arch: unknown libc:" libc)])))

(define (xbps-repository)
  "Return the Void repository URL for the target.

The musl tree is a subdirectory of the same host, which is why the two URLs
differ by one path segment rather than by a host name."
  (case (target-libc)
    [(glibc) "https://repo-default.voidlinux.org/current"]
    [(musl) "https://repo-default.voidlinux.org/current/musl"]
    [else (error "xbps-repository: unknown libc:" (target-libc))]))

(define (ensure-supported-libc!)
  "Refuse a target this tree cannot build, and name what is missing.

A build that stops here stops in the first second.  The alternative is an
artefact that installs and then cannot start the shell, which is a failure
somebody debugs at a login prompt."
  (case (target-libc)
    [(glibc) #t]
    [(musl)
     (error (string-append
             "musl is not a supported target yet: whelk and lambdock come "
             "from a glibc Nix flake and Flatpak is glibc-only, so the "
             "desktop would boot to a session it cannot install. Build with "
             "(target-libc 'glibc), or extend this module and the image's "
             "package list together."))]
    [else (error "ensure-supported-libc!: unknown libc:" (target-libc))]))
