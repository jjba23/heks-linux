;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux distrobox): the assemble manifest that creates the
;; .deb box, and the heks-deb program that drives it.
;;
;; What matters here is that the box keeps everything distrobox shares by
;; default - the host home, its Wayland socket and its PipeWire socket - and
;; that the manifest names the packages a .deb program needs before that sharing
;; reaches it: the client libraries for PipeWire and for the Mesa drivers.  The
;; manifest and the program are both generated text, so the checks read the text.
;;
;; Cases that have to set something up return their assertions as a list, as
;; veritas reads a body for the assertions built while it runs and a `let' whose
;; assertions are not its last form would have them optimized away.  See the
;; note at the top of waybar-spec.scm.

;;; Code:

(define-module (veritas unit distrobox-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux distrobox)
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (occurs? text needle)
  "Whether TEXT contains NEEDLE."
  (not (eq? #f (string-contains text needle))))

(define (scratch-dir name)
  "Return a path under /tmp for a test that has to touch the filesystem."
  (format #f "/tmp/heks-distrobox-spec-~a/~a" (getpid) name))

(define (remove-tree! path)
  "Remove PATH and whatever is below it, so a run leaves nothing behind."
  (when (file-exists? path)
    (if (eq? 'directory (stat:type (stat path)))
      (begin
        (for-each (lambda (entry)
                    (remove-tree! (format #f "~a/~a" path entry)))
                  (cddr (scandir path)))
        (rmdir path))
      (delete-file path))))

(define (nvidia-cases)
  "Return the cases for the proprietary driver flag, both ways."
  (list (parameterize ((distrobox-nvidia? #t))
          (assert-true (occurs? (distrobox-manifest) "nvidia=true")
            #:name "An NVIDIA machine integrates its drivers"))
        (parameterize ((distrobox-nvidia? #f))
          (assert-true (occurs? (distrobox-manifest) "nvidia=false")
            #:name "Every other machine leaves the drivers alone"))))

(define (script-cases)
  "Return the cases for the program, rendered for a scratch pair of directories."
  (let ((dir (scratch-dir "bin"))
        (config (scratch-dir "config")))
    (parameterize ((distrobox-script-dir dir)
                   (distrobox-config-dir config))
      (let ((script (distrobox-script)))
        (list
         (assert-true (string-prefix? "#!/usr/bin/env bash" script)
           #:name "The program is a bash script")
         (assert-true (occurs? script "distrobox assemble create --file")
           #:name "Creating the box reads the generated manifest")
         (assert-true (occurs? script
                               (format #f "~a/~a"
                                       config
                                       (distrobox-manifest-filename)))
           #:name
           "The program reads the manifest this configuration writes") (assert-true (occurs? script "apt-get install")
                                                                         #:name "A .deb file is installed by apt inside the box") (assert-true (occurs? script "dpkg --add-architecture i386")
                                                                                                                                    #:name
                                                                                                                                    "The program can enable the 32-bit libraries a .deb asks for")
         (assert-true (occurs? script "heks-deb put FILE DEST")
           #:name "The program copies a file into the box") (assert-true (occurs? script "distrobox enter --name \"$BOX\" -- cp --")
                                                              #:name
                                                              "A destination you own is copied without sudo")
         (assert-true (occurs? script "sudo cp --")
           #:name
           "A destination the box's root owns is written through sudo")
         (assert-true (occurs? script
                               (format #f "BOX=\"~a\""
                                       (distrobox-container-name)))
           #:name "The program names the box the manifest creates"))))))

(define (install-cases)
  "Install into a scratch home and return the cases about what was written."
  (let ((bin (scratch-dir "bin"))
        (config (scratch-dir "config")))
    (parameterize ((distrobox-script-dir bin)
                   (distrobox-config-dir config))
      (install-distrobox-config))
    (let* ((script (format #f "~a/~a" bin (distrobox-script-filename)))
           (manifest (format #f "~a/~a" config (distrobox-manifest-filename)))
           (cases (list
                   (assert-true (file-exists? script)
                     #:name "Installing writes the program")
                   (assert-true (file-exists? manifest)
                     #:name "Installing writes the manifest")
                   (assert-true (not (zero?
                                      (logand (stat:mode (stat script)) #o111)))
                     #:name "The program is executable")
                   (assert-equal #:expect (distrobox-manifest)
                     #:got (call-with-input-file manifest
                                                 get-string-all)
                     #:name
                     "The manifest on disk is the rendered one"))))
      (remove-tree! (dirname bin))
      (remove-tree! (dirname config))
      cases)))

(define distrobox-suite
  (suite "distrobox Suite"
    (test "The Manifest Describes The Box"
      (assert-true (occurs? (distrobox-manifest)
                            (format #f "[~a]" (distrobox-container-name)))
        #:name "The manifest names the box")
      (assert-true (occurs? (distrobox-manifest)
                            (format #f "image=~a" (distrobox-image)))
        #:name "The manifest names the image to run it from")
      (assert-true (occurs? (distrobox-manifest) "replace=false")
        #:name "Assembling an existing box must not wipe it"))

    (test "The Box Gets Audio And A GPU"
      (assert-true (occurs? (distrobox-manifest)
                            "pipewire-audio-client-libraries")
        #:name "The box carries the PipeWire client libraries")
      (assert-true (occurs? (distrobox-manifest) "libasound2-plugins")
        #:name "ALSA applications are routed to PipeWire")
      (assert-true (occurs? (distrobox-manifest) "libpulse0")
        #:name "PulseAudio applications are routed to PipeWire")
      (assert-true (occurs? (distrobox-manifest) "mesa-vulkan-drivers")
        #:name "The box carries the Mesa drivers for this GPU"))

    (test "The NVIDIA Flag Follows The Machine"
      (nvidia-cases))

    (test "The Program Drives The Manifest"
      (script-cases))

    (test "Installing Writes Both Files"
      (install-cases))))

(define (spec)
  (veritas-run distrobox-suite))
