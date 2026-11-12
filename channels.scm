;;; heks-linux
;;;
;;; SPDX-License-Identifier: MIT
;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;;
;;; The channel list this repository pins: `maak guix-pull' runs
;;; `guix pull --channels=channels.scm', and every task that needs a
;;; reproducible shell uses `guix time-machine --channels=channels.scm'.
;;;
;;; Guix itself is pinned to a commit, and so is the jointhefreeworld channel:
;;; a pin says which release of the collection this configuration was tested
;;; against, and `maak guix-pull' only has to fetch that one.  The channel
;;; carries the collection this configuration is built from - maak, veritas,
;;; scriba, kracht, hygguile, ggg, lambdock, heks-toon, the Emacs packages and
;;; the rest - and it comes after guix in the list, so its packages take
;;; precedence over the copies Guix carries, which is the point: the system gets
;;; the newest release instead of whatever the last Guix import happened to pick
;;; up.
;;;
;;; Bumping the jointhefreeworld pin is one line: take the trunk commit that
;;; released what you want (`git ls-remote` at the channel's URL, or `git log` in
;;; a checkout) and write it here.  The Nix side of the same collection is pinned
;;; by the `nix-jointhefreeworld` input in flake.lock - `nix flake update
;;; nix-jointhefreeworld` moves it - and the two are kept at the same release, so
;;; the Nix-installed half of the collection is not ahead of the Guix-installed
;;; one.
;;;
;;; The introduction is the channel's first signed commit and the key in its
;;; .guix-authorizations; `guix git authenticate' in the channel checkout
;;; verifies the whole history against it.
;;;
;;; Code:

(list (channel
       (name 'guix)
       (url "https://codeberg.org/guix/guix.git")
       (branch "master")
       (commit "3b4e87350015c5e5223bcfd5043837e63fd6d635")
       (introduction
        (make-channel-introduction "9edb3f66fd807b096b48283debdcddccfea34bad"
                                   (openpgp-fingerprint
                                    "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
      (channel
       (name 'jointhefreeworld)
       (url "https://github.com/jjba23/guix-jointhefreeworld")
       (branch "trunk")
       (commit "872c1e2ee0cee99e49472bfbfaf3a7e5975b1c2d")
       (introduction
        (make-channel-introduction
         "b0ac3f05075d7959860fc9e1db5871acddea3986"
         (openpgp-fingerprint
          "83BC 6E1C 8726 B8C2 97F8  D16E 24F4 6738 CE11 4AF6")))))
