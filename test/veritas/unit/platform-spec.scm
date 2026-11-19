;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux platform).
;;
;; The point of the module is that a target is a value with a name: the XBPS
;; architecture string, the repository it reads, and the one place that refuses
;; a target this tree cannot build.

;;; Code:

(define-module (veritas unit platform-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux platform)
  #:export (spec))

(define (target-cases)
  (suite "The Build Target"
    (test "Glibc Is Spelled As The Architecture Alone"
      (assert-equal #:expect "x86_64"
        #:got (xbps-arch)
        #:name "XBPS spells a glibc system by its architecture")
      (assert-equal #:expect "https://repo-default.voidlinux.org/current"
        #:got (xbps-repository)
        #:name "And reads the glibc tree at the root of the host"))
    (test "Musl Is Spelled With A Suffix"
      (assert-equal #:expect "x86_64-musl"
        #:got (parameterize ((target-libc 'musl))
                (xbps-arch))
        #:name "The suffix is the ABI, not a second architecture")
      (assert-equal #:expect "https://repo-default.voidlinux.org/current/musl"
        #:got (parameterize ((target-libc 'musl))
                (xbps-repository))
        #:name "Its packages are a subdirectory of the same tree"))
    (test "Another Architecture Is Spelled The Same Way"
      (assert-equal #:expect "aarch64"
        #:got (parameterize ((target-arch 'aarch64))
                (xbps-arch))
        #:name "The architecture is read from the parameter, not hard-coded"))
    (test "A Target This Tree Cannot Build Is Refused With A Reason"
      (assert-true (ensure-supported-libc!)
        #:name "glibc is the supported target")
      (assert-error (lambda ()
                      (parameterize ((target-libc 'musl))
                        (ensure-supported-libc!)))
        #:name "musl stops the build in its first second, not at a login")
      (assert-error (lambda ()
                      (parameterize ((target-libc 'uclibc))
                        (ensure-supported-libc!)))
        #:name "A libc this module has never heard of is not guessed at"))))

(define (spec)
  (veritas-run (target-cases)))
