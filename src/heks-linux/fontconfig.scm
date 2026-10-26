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

;;; Commentary:
;;
;; Renders @file{~/.config/fontconfig/fonts.conf}: how text is drawn, rather
;; than which text is drawn.  The palettes, the fonts and the sizes are decided
;; elsewhere; this file decides whether a glyph is smoothed, hinted, emboldened,
;; and whether it is allowed to break into coloured fringes.
;;
;; The rules below are the ones a Mac's text rendering is recognised by.  macOS
;; has always smoothed glyphs in grey - it never split a stem into red, green and
;; blue subpixels - and it hinted lightly, so shapes keep their design instead of
;; being snapped to the pixel grid.  A Linux desktop usually does the opposite:
;; full hinting and RGB subpixel rendering, which is sharper at small sizes and
;; looks nothing like a Mac.
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

;;; Code:

(define-module (heks-linux fontconfig)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (sxml simple)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (fontconfig-config fontconfig-config-xml fontconfig-matches
                              fontconfig-edits install-fontconfig-config
                              fontconfig-config-dir fontconfig-config-filename
                              fontconfig-antialias? fontconfig-hinting?
                              fontconfig-hint-style fontconfig-rgba-order
                              fontconfig-lcd-filter fontconfig-embolden?
                              fontconfig-embolden-threshold))

(define s
  (scriba-auto-logger))

;; Whether glyphs are smoothed at all.  Off gives the jagged text a Mac has not
;; had since Mac OS 9.
(define fontconfig-antialias?
  (make-parameter #t))

;; Whether glyph edges are pushed towards the pixel grid.  macOS hints lightly;
;; how lightly is @var{fontconfig-hint-style}.
(define fontconfig-hinting?
  (make-parameter #t))

;; How hard: "hintnone", "hintslight", "hintmedium" or "hintfull".
;;
;; "hintslight" is the Mac's setting.  It keeps a letterform's proportions and
;; lets the smoothing do the work, where "hintfull" forces stems onto whole
;; pixels at the cost of the design - which is why Linux text at 10pt so often
;; looks like a different typeface than the same font at 20pt.
(define fontconfig-hint-style
  (make-parameter "hintslight"))

;; Which subpixel order to render for: "none", "rgb", "bgr", "vrgb" or "vbgr".
;;
;; "none" is grayscale antialiasing, and it is the whole Mac look: no colour
;; fringes on the edge of every stem, so text stays neutral whatever the
;; wallpaper behind a translucent bar happens to be.
(define fontconfig-rgba-order
  (make-parameter "none"))

;; The filter used to calm colour fringing.  "lcdnone" leaves the glyphs alone;
;; the lcddefault and lcdlight filters exist to make subpixel text gentler, which
;; is a problem this configuration does not have.
(define fontconfig-lcd-filter
  (make-parameter "lcdnone"))

;; Whether to fake a heavier weight.  macOS' smoothing makes text look slightly
;; bolder than FreeType's does; the bar and the launcher already ask for the
;; weights they want, so this stays off unless a machine's font is visibly thin.
(define fontconfig-embolden?
  (make-parameter #f))

;; The point size @var{fontconfig-embolden?} starts at.  Faking bold is a
;; large-text trick: at 10pt it closes the counters of a letter.
(define fontconfig-embolden-threshold
  (make-parameter 12))

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

(define* (fontconfig-config)
  "Return the fontconfig configuration as an SXML element.

There is no @code{xmlns} attribute on the root: fontconfig reads the file
against its own DTD and rejects a namespace declaration as an invalid attribute -
a warning on every font match, for a file that only fontconfig ever reads.

The tree is what a test asserts on - which hints are set, and that the grayscale
rule is written in assign mode - while @code{fontconfig-config-xml} is how it
reaches @file{fonts.conf}.

@example
(sxml->xml (fontconfig-config))
@end example"
  `(fontconfig
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

     How glyphs are drawn: grayscale smoothing, light hinting, no LCD filter.
     Which font is drawn, and at what size, is decided by the modules that set
     them. -->
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
