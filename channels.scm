;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The channel list this repository pins: `maak guix-pull' runs
;; `guix pull --channels=channels.scm', and every task that needs a
;; reproducible shell uses `guix time-machine --channels=channels.scm'.
;;
;; Guix itself is pinned to a commit, and so is the jointhefreeworld channel:
;; a pin says which release of the collection this configuration was tested
;; against, and `maak guix-pull' only has to fetch that one.  The channel
;; carries the collection this configuration is built from - maak, veritas,
;; scriba, kracht, hygguile, ggg, lambdock, heks-toon, the Emacs packages and
;; the rest - and it comes after guix in the list, so its packages take
;; precedence over the copies Guix carries, which is the point: the system gets
;; the newest release instead of whatever the last Guix import happened to pick
;; up.
;;
;; Bumping the jointhefreeworld pin is one line: take the trunk commit that
;; released what you want (`git ls-remote` at the channel's URL, or `git log` in
;; a checkout) and write it here.  The Nix side of the same collection is pinned
;; to the same release at `nix-jointhefreeworld-revision' in maak.scm.
;;
;; The introduction is the channel's first signed commit and the key in its
;; .guix-authorizations; `guix git authenticate' in the channel checkout
;; verifies the whole history against it.
;;
;;; Code:

(list (channel
       (name 'guix)
       (url "https://codeberg.org/guix/guix.git")
       (branch "master")
       (commit "b7c99ce1297f19da01ba26828464b5e6d9d74572")
       (introduction
        (make-channel-introduction "9edb3f66fd807b096b48283debdcddccfea34bad"
                                   (openpgp-fingerprint
                                    "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
      (channel
       (name 'jointhefreeworld)
       (url "https://github.com/jjba23/guix-jointhefreeworld")
       (branch "trunk")
       ;; The release this configuration is built against: lambdock 0.21.1,
       ;; heks-toon 0.3.2, maak 0.14.0, veritas 0.9.0, scriba 0.4.5, sift
       ;; 1.8.0, and the rest of the collection, at the same revision.  The
       ;; sift bump is the release its own `maak release' cut: it reads
       ;; imports and reports the ones nothing keeps (SIFT060) and the ones no
       ;; file of the project declares (SIFT061), binds names inside
       ;; `define-syntax', `let-syntax' and `letrec-syntax', and gives the
       ;; language server a file filter, a cached lazy index, ranked
       ;; completion, signature help and `source.organizeImports'.
       (commit "267addd914bd1d20301f77ec496cc266793b2bb9")
       (introduction
        (make-channel-introduction
         "b0ac3f05075d7959860fc9e1db5871acddea3986"
         (openpgp-fingerprint
          "83BC 6E1C 8726 B8C2 97F8  D16E 24F4 6738 CE11 4AF6")))))
