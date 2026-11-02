;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Renders @file{~/.config/fontconfig/fonts.conf}: how text is drawn, rather
;; than which text is drawn.  The palettes, the fonts and the sizes are decided
;; elsewhere; this file decides whether a glyph is smoothed, hinted, emboldened,
;; and whether it is allowed to break into coloured fringes.
;;
;; The rules below are the ones the reference desktop's text rendering is
;; recognised by.  It smoothed glyphs in grey - never splitting a stem into red,
;; green and blue subpixels - and it hinted lightly, so shapes keep their design
;; instead of being snapped to the pixel grid.  A Linux desktop usually does the
;; opposite: full hinting and RGB subpixel rendering, which is sharper at small
;; sizes and looks nothing like the reference.
;;
;; It is a fontconfig rule rather than a GTK setting because fontconfig is the
;; one layer every surface here has in common: the bar, the launcher, the
;; notifications, the terminals, the editor and the browsers all ask fontconfig
;; how to draw a glyph.  A GTK-only setting would leave half the desktop
;; rendering differently.
;;
;; The rules assign rather than prefer.  A program that wants subpixel rendering
;; has already put its own antialiasing flags in the pattern it asks fontconfig
;; to match, so an edit in the default @code{weak} mode would be skipped as a
;; duplicate of what the program asked for; @code{assign} overrides it.
;;
;; The one exception is the family list.  A stylesheet, a GTK setting and a Rofi
;; theme each name one family and nothing else, so a machine that has not got
;; that family has no next-best - and the one place a second best can be said
;; once, for every surface at the same time, is here.  That rule is written for
;; the configured family by name and only for it;
;; @code{fontconfig-family-matches} says why.
;;
;; The other half of the same problem is the program that names no family at
;; all: a GTK stylesheet that says @code{sans-serif}, an application that leaves
;; the choice to the theme.  Those requests reach fontconfig as a generic
;; family, and the distribution answers them with whatever it calls its default -
;; measured on this machine, Arial - so the desktop is drawn in a face nobody
;; chose.  @code{fontconfig-sans-aliases} is the list of those names, and
;; @code{fontconfig-sans-alias-matches} writes the rule that answers each one
;; with @code{(heks-linux-sans-font)}.

;;; Code:

(define-module (heks-linux fontconfig)
  #:declarative? #t
  #:use-module (srfi srfi-1)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (sxml simple)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (fontconfig-config fontconfig-config-xml fontconfig-matches
                              fontconfig-family-matches fontconfig-edits
                              fontconfig-sans-aliases
                              fontconfig-sans-alias-matches
                              install-fontconfig-config
                              fontconfig-config-dir fontconfig-config-filename
                              fontconfig-antialias? fontconfig-hinting?
                              fontconfig-hint-style fontconfig-rgba-order
                              fontconfig-lcd-filter fontconfig-embolden?
                              fontconfig-embolden-threshold
                              fontconfig-sans-fallbacks))

(define s
  (scriba-auto-logger))

;; Whether glyphs are smoothed at all.  Off gives the jagged text no modern
;; desktop has drawn in decades.
(define fontconfig-antialias?
  (make-parameter #t))

;; Whether glyph edges are pushed towards the pixel grid.  The reference hints
;; lightly; how lightly is @var{fontconfig-hint-style}.
(define fontconfig-hinting?
  (make-parameter #t))

;; How hard: "hintnone", "hintslight", "hintmedium" or "hintfull".
;;
;; "hintslight" is the reference's setting.  It keeps a letterform's proportions and
;; lets the smoothing do the work, where "hintfull" forces stems onto whole
;; pixels at the cost of the design - which is why Linux text at 10pt so often
;; looks like a different typeface than the same font at 20pt.
(define fontconfig-hint-style
  (make-parameter "hintslight"))

;; Which subpixel order to render for: "none", "rgb", "bgr", "vrgb" or "vbgr".
;;
;; "none" is grayscale antialiasing, and it is the whole look: no colour
;; fringes on the edge of every stem, so text stays neutral whatever the
;; wallpaper behind a translucent bar happens to be.
(define fontconfig-rgba-order
  (make-parameter "none"))

;; The filter used to calm colour fringing.  "lcdnone" leaves the glyphs alone;
;; the lcddefault and lcdlight filters exist to make subpixel text gentler, which
;; is a problem this configuration does not have.
(define fontconfig-lcd-filter
  (make-parameter "lcdnone"))

;; Whether to fake a heavier weight.  The reference's smoothing makes text look slightly
;; bolder than FreeType's does; the bar and the launcher already ask for the
;; weights they want, so this stays off unless a machine's font is visibly thin.
(define fontconfig-embolden?
  (make-parameter #f))

;; The point size @var{fontconfig-embolden?} starts at.  Faking bold is a
;; large-text trick: at 10pt it closes the counters of a letter.
(define fontconfig-embolden-threshold
  (make-parameter 12))

;; The faces to fall back to when the configured sans family is not on the
;; machine, in the order they are preferred.
;;
;; Every surface here asks for exactly one family, and that family is
;; @code{(heks-linux-sans-font)}: GTK builds a family name out of one string,
;; Rofi takes one, and the bar's stylesheet cannot name a list at all - GTK reads
;; a quoted comma list as a single family *name*, which is why the bar's icons
;; are spans of markup rather than a font list.  So a machine whose configured
;; face is missing has nothing between it and fontconfig's generic default, and
;; the desktop quietly stops looking like itself: the menu bar is drawn in
;; Arial, the launcher in Arial, the notifications in Arial.
;;
;; The list is the faces it should be drawn in, best first.  Work Sans is the
;; interface face this desktop configures; Helvetica Neue is the face the
;; reference desktop draws its own interface in, and the closest relation to
;; it; and Adwaita Sans is what a GNOME machine already has.  A machine that
;; configured another sans still gets the rest: the family in use is dropped
;; from the list when the rule is written, so the list can be written as "the
;; faces this desktop is drawn after" rather than as "the faces after whichever
;; one you picked".
;;
;; None of them has to be installed.  A family that is not on the machine is
;; simply not a candidate, and fontconfig walks on to the next.
(define fontconfig-sans-fallbacks
  (make-parameter '("Helvetica Neue" "Adwaita Sans")))

;; The names a program uses when it means "this desktop's sans" without naming
;; a family: the generic family CSS and fontconfig define, and the short spelling
;; fontconfig has accepted since before it had a generic family at all.
;;
;; @code{system-ui} is deliberately not in the list, and the reason is worth
;; writing down rather than rediscovering.  fontconfig 2.18 resolves it itself,
;; inside the library, before any file's rules see the pattern: the family has
;; already been rewritten to the system's default by the time a
;; @code{<match>} in @file{fonts.conf} could test for it, so a rule that names
;; it never fires and only looks like it works.  What a GTK 4 application means
;; by @code{system-ui} is its interface font, which is
;; @code{(heks-linux-sans-font)} already - set in the GTK settings and in the
;; dconf keys this configuration writes.
;;
;; They are a list and a parameter because it is a list of names, not a fact
;; about this desktop: a machine that also wants a browser's platform keyword to
;; land here adds that keyword to its own list.
(define fontconfig-sans-aliases
  (make-parameter '("sans-serif" "sans")))

(define fontconfig-config-dir
  (make-parameter (format #f "~a/.config/fontconfig"
                          (or (getenv "HOME") "/tmp"))))

(define fontconfig-config-filename
  (make-parameter "fonts.conf"))

(define (fontconfig-edit name value)
  "Return one fontconfig @code{edit} element assigning @var{name} to @var{value}.

@var{value} is tagged the way fontconfig wants it: booleans as @code{bool},
keywords as @code{const}.  A boolean is recognised here rather than asked for,
because @code{#t} in a Scheme parameter and @code{true} in fontconfig are the
same idea written twice."
  `(edit (@ (name ,name) (mode "assign"))
         ,(if (boolean? value)
            `(bool ,(if value "true" "false"))
            `(const ,(format #f "~a" value)))))

(define (fontconfig-edits)
  "Return the font-drawing rules as a list of fontconfig @code{edit} elements.

Every rule is optional: a machine that wants subpixel rendering sets
@var{fontconfig-rgba-order} to rgb and gets the same file without the grayscale
rule, rather than a second configuration somewhere else.

@example
(length (fontconfig-edits))
@end example"
  (append (list (fontconfig-edit "antialias" (fontconfig-antialias?))
                (fontconfig-edit "hinting" (fontconfig-hinting?))
                (fontconfig-edit "hintstyle" (fontconfig-hint-style))
                (fontconfig-edit "rgba" (fontconfig-rgba-order))
                (fontconfig-edit "lcdfilter" (fontconfig-lcd-filter)))
          (if (fontconfig-embolden?)
            (list (fontconfig-edit "embolden" #t))
            '())))

(define (fontconfig-matches)
  "Return the @code{match} rules that carry @code{fontconfig-edits}.

One rule covers every size.  A second one, only when
@var{fontconfig-embolden?} is on, gates the faking on
@var{fontconfig-embolden-threshold} - which is why the edits are returned
separately: the same rule can then be used at two sizes."
  `((match (@ (target "font"))
      ,@(fontconfig-edits))
    ,@(if (fontconfig-embolden?)
        `((match (@ (target "font"))
            (test (@ (name "size") (compare "more_eq") (qual "all"))
              (double ,(format #f "~a"
                               (fontconfig-embolden-threshold))))
            ,(fontconfig-edit "embolden" #t)))
        '())))

(define (fontconfig-family-edit family)
  "Return one fontconfig @code{edit} that appends @var{family} to a pattern.

The value is a @code{string} and not a @code{const}: a family name is text that
fontconfig compares against the names on disk, where the drawing keywords
@code{fontconfig-edit} writes are a closed set.

@var{family} is appended with @code{binding=\"same\"}, and both halves of that
were measured rather than assumed.  The default binding is @code{weak}, and a
weak family loses to the generic chain a distribution has already resolved the
pattern to - a fallback that loses to Arial is not a fallback.  @code{same}
gives the appended face the weight of the family the pattern asked for, which is
what makes it win."
  `(edit (@ (name "family") (mode "append") (binding "same"))
         (string ,family)))

(define (fontconfig-sans-alias-edit)
  "Return the edit that puts the configured sans in front of a generic request.

@code{prepend} and not the @code{append} the fallback rule uses, because by the
time this rule runs the distribution's configuration has already appended its
own idea of the default sans to the pattern: a family appended after that one
loses to it however strongly it is bound.  Only a family in front of it wins.

@code{strong} and not the @code{same} the fallback rule uses, for the same
reason read backwards: the values already in the pattern were put there by
another file, and @code{same} would copy their weight instead of outranking
it."
  `(edit (@ (name "family") (mode "prepend") (binding "strong"))
         (string ,(heks-linux-sans-font))))

(define (fontconfig-sans-alias-matches)
  "Return the rules that answer a generic sans request with the configured face.

One rule per alias, because fontconfig compares one family name per test and a
single rule would have to carry one test per spelling anyway.  Together they are
what makes @code{sans-serif} mean the configured face in a stylesheet that never
heard of it: the GTK themes, the web views and every application that leaves the
family to the system.

Each test is @code{qual=\"first\"}, and that is the part that keeps the rule
honest.  A distribution appends @code{sans-serif} to almost every pattern as a
last resort (@code{48-guessfamily.conf} does it to every family whose name
contains \"sans\"), so a rule that matched the name anywhere in the list would
answer a request for DejaVu Sans with the desktop's own sans - the desktop
deciding a font the program had already decided.  With @code{first}, the rule
fires only when the generic name is what was asked for, and a pattern that
names a family keeps it.

The aliases are written before @code{fontconfig-family-matches} and that order
matters: the fallback rule tests for @code{(heks-linux-sans-font)} anywhere in
the pattern, so this rule is what puts it there.  A generic request then gets
both the prepended face and the fallback chain behind it."
  (map (lambda (alias)
         `(match (@ (target "pattern"))
            (test (@ (name "family") (compare "eq") (qual "first"))
              (string ,alias))
            ,(fontconfig-sans-alias-edit)))
       (fontconfig-sans-aliases)))

(define (fontconfig-family-matches)
  "Return the @code{match} rule that gives a missing sans family its fallbacks.

The rule tests for the configured family by name, and that test is the whole
reason it is safe: a rule without one is a preference applied to every pattern
fontconfig ever resolves, and this desktop has no business deciding what a
document's serif should be.  With the test, a program that asks for
@code{(heks-linux-sans-font)} and does not get it walks
@code{fontconfig-sans-fallbacks} instead of walking into the distribution's
default.

The edits are written in reverse, because fontconfig tries the last appended
family first: writing the list backwards is what lets the parameter be read in
the order the faces are wanted.

No rule is written when there is nothing to fall back to, rather than an empty
@code{match} element: a machine that wants the stock fontconfig gets the stock
configuration."
  (let* ((sans (heks-linux-sans-font))
         (families (remove (lambda (family)
                             (equal? family sans))
                           (fontconfig-sans-fallbacks))))
    (if (null? families)
      '()
      `((match (@ (target "pattern"))
          (test (@ (name "family") (compare "eq"))
            (string ,sans))
          ,@(map fontconfig-family-edit (reverse families)))))))

(define* (fontconfig-config)
  "Return the fontconfig configuration as an SXML element.

Three kinds of rule, in the order fontconfig reads them: the alias rules that
answer a generic sans request (@code{fontconfig-sans-alias-matches}), the pattern
rules that give the named sans its fallbacks (@code{fontconfig-family-matches}),
and the font rules that decide how the answer is drawn
(@code{fontconfig-matches}).  The alias rules come first because the second rule
tests for the family the first one puts into the pattern.

There is no @code{xmlns} attribute on the root: fontconfig reads the file
against its own DTD and rejects a namespace declaration as an invalid attribute -
a warning on every font match, for a file that only fontconfig ever reads.

The tree is what a test asserts on - which hints are set, that the grayscale
rule is written in assign mode, and which families are preferred - while
@code{fontconfig-config-xml} is how it reaches @file{fonts.conf}.

@example
(sxml->xml (fontconfig-config))
@end example"
  `(fontconfig
    ,@(fontconfig-sans-alias-matches)
    ,@(fontconfig-family-matches)
    ,@(fontconfig-matches)))

(define* (fontconfig-config-xml)
  "Render @file{fonts.conf} as a string.

The XML declaration and the DOCTYPE are written by hand: fontconfig's own files
carry both, SXML has a node for only the first, and a file that looks like every
other fontconfig file is a file somebody can compare against
@file{/etc/fonts/fonts.conf} without wondering what produced it."
  (string-append "<?xml version=\"1.0\"?>
<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">
<!-- ====== Heks-Linux font rendering ======
     auto-generated file, DO NOT EDIT!

     How glyphs are drawn - grayscale smoothing, light hinting, no LCD filter -
     which family answers a generic sans request, and which families back up
     the one this desktop names.  Which family is asked for, and at what size,
     is decided by the modules that set them. -->
"
                 (with-output-to-string (lambda ()
                                          (sxml->xml
                                           (fontconfig-config))))
                 "\n"))

(define (install-fontconfig-config)
  "Write the font rendering rules to @code{~/.config/fontconfig/fonts.conf}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/fontconfig-settings.scm} first, so a machine
that wants subpixel rendering - or no antialiasing at all - can say so in its own
file instead of forking this one.  Fontconfig reads the file when a program
starts; already-running applications keep the rendering they started with."
  (log-info s "Installing fontconfig configuration")
  (load-local-overrides '(heks-linux fontconfig)
                        'fontconfig-settings)
  (install-config-file! #:name (fontconfig-config-filename)
                        #:dir (fontconfig-config-dir)
                        #:contents (fontconfig-config-xml))
  (log-success s "Installed fontconfig configuration"))
