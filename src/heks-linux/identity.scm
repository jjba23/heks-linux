;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; What this system says it is, in the two files that answer the question.
;;
;; @file{/etc/os-release} is the file programs read: a desktop's system summary,
;; a status bar, anything that shows a distribution's name.  Void's base-files
;; ships it as a symlink into @file{/usr/lib}, so a package upgrade would put
;; Void's name back; the image replaces the link with a file of its own.
;;
;; @file{/etc/issue} is the file a getty prints above its login prompt, which is
;; the first line on every console the graphical prompt does not own - the
;; consoles that keep a plain login with a shell on them.  It belongs to Void's
;; base-files too, and it is one line.
;;
;; The name is spelled once here, and the surfaces that show it read it from
;; here: the image writes these two files, and the login prompt is titled with
;; it.
;;
;; The system presents itself as Heks and still says what it is built on:
;; @code{ID_LIKE} names Void, because a tool that has never heard of
;; @code{heks} should do here what it does there rather than fall into a
;; fallback nobody wrote.  That is not branding leaking; it is the one field
;; that stops the rebrand from breaking the distribution underneath.

;;; Code:

(define-module (heks-linux identity)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:export (heks-name
            heks-id
            heks-homepage
            os-release
            issue))

;; The name a person reads.  One string, because it appears on a console, in a
;; boot menu, in a login box and in a system summary, and four spellings of one
;; name is how a system starts looking like two.
(define heks-name
  "Heks GNU/Linux")

;; The identifier, as @file{/etc/os-release} spells it: lower case, one word,
;; and the one field a script may compare against.
(define heks-id
  "heks")

(define heks-homepage
  "https://codeberg.org/jjba23/heks-linux")

(define* (os-release #:optional version)
  "Return @file{/etc/os-release}, as text.

@var{version} is the release the image was built from, or @code{#f} for a tree
that is not on a tag: a rolling base has no version of its own to claim, and a
version that is wrong is worse than one that is absent."
  (format #f "NAME=\"~a\"
ID=~a
ID_LIKE=void
PRETTY_NAME=\"~a\"
~aHOME_URL=\"~a\"
BUG_REPORT_URL=\"~a/issues\"
ANSI_COLOR=\"0;38;2;71;128;97\"
"
          heks-name
          heks-id
          heks-name
          (if version
            (format #f "VERSION=\"~a\"
VERSION_ID=\"~a\"
"
                    version version)
            "")
          heks-homepage
          heks-homepage))

(define (issue)
  "Return @file{/etc/issue}, the banner a getty prints above its login prompt.

@command{agetty} expands the escapes itself - the kernel release, this machine's
name and the console it is on - so they leave here as a backslash and a letter.
It is the one line a person sees on @kbd{Ctrl+Alt+F4}, which is why it says the
system's name and nothing else."
  (format #f "~a \\r (\\n) (\\l)~%" heks-name))
