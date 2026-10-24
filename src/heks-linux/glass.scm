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
;; The house style: the frosted-glass shell every Heks page is built in.
;;
;; A page here is a document that has to look like it belongs to this desktop
;; and to nothing else - the keyboard reference, the wallpaper gallery and the
;; palette chooser are the same object seen from three angles.  So the shell is
;; shared: the same mesh of palette colours behind the same translucent panels,
;; the same grain, the same hairlines, the same footer that says what this is
;; and that it is free software.
;;
;; A page builds its body as SXML - the same s-expressions the Waybar power menu
;; is written in - and hands it over; it gets the document, the layers and the
;; stylesheet around it.  The colours are not parameters of this module: they are
;; the *current* palette's, read at render time, which is why a page repainted
;; after a theme change looks like it was drawn for that theme rather than
;; tinted towards it.
;;
;; Why not @code{sxml->xml} from @code{(sxml simple)}: it writes XML, and this is
;; HTML.  It escapes the contents of @code{<style>} and @code{<script>}, which
;; HTML reads as raw text, so @code{a > b} reaches the browser as @code{a &gt;
;; b} and the rules after it stop working; and it self-closes every empty
;; element, so @code{<br />} becomes a tag the HTML parser has to be forgiving
;; about.  The tree is SXML either way - the writer below is thirty lines that
;; know about void elements and raw-text elements, and nothing else about HTML.
;;
;;; Code:

(define-module (heks-linux glass)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-13)
  #:export (html-escape
            sxml->html
            sxml->html-string
            glass-fill
            glass-tokens
            glass-common-css
            glass-layers
            glass-document
            glass-brand
            glass-credits))

;; Elements HTML has no closing tag for.  A writer that emits </br> is not
;; writing HTML: the parser reads that as a second <br>.
(define %html-void-elements
  '(area base br col embed hr img input link meta param source track wbr))

;; Elements whose contents are text, not markup, so they are written verbatim.
;; Escaping them is how a stylesheet turns into "a &gt; b".
(define %html-raw-elements
  '(script style))

(define (html-escape text)
  "Escape @var{text} for use as HTML text or as an attribute value.

The five characters that end a value early are the five that are replaced; a
document built as SXML should never need this, but an attribute value assembled
by hand does."
  (with-output-to-string
      (lambda ()
        (string-for-each (lambda (ch)
                           (display (case ch
                                      ((#\&) "&amp;")
                                      ((#\<) "&lt;")
                                      ((#\>) "&gt;")
                                      ((#\") "&quot;")
                                      (else (string ch)))))
                         text))))

(define (sxml-attribute-value attr)
  "Return the value of the SXML @var{attr} pair as a string.

SXML allows @code{(name value)} and @code{(name . value)}; both arrive here, and a
value that is a list has one element."
  (let ((value (cdr attr)))
    (format #f "~a"
            (if (and (pair? value) (null? (cdr value)))
                (car value)
                value))))

(define (sxml-write-attributes attrs port)
  "Write the SXML attribute list @var{attrs} to @var{port}."
  (for-each (lambda (attr)
              (format port " ~a=\"~a\""
                      (car attr)
                      (html-escape (sxml-attribute-value attr))))
            attrs))

(define (sxml-write-children body raw? port)
  "Write @var{body} - the children of one element - to @var{port}.

When @var{raw?} the text children are written as they are, which is what a
stylesheet and a script need."
  (for-each (lambda (child)
              (if (and raw? (string? child))
                  (display child port)
                  (sxml->html child port)))
            body))

(define (sxml-write-element node port)
  "Write one SXML element @var{node} to @var{port}."
  (let* ((tag (car node))
         (elements (cdr node))
         (named-attrs (and (pair? elements)
                           (pair? (car elements))
                           (eq? '@ (caar elements))
                           (cdar elements)))
         (body (if named-attrs (cdr elements) elements)))
    (case tag
      ((*TOP*)
       (for-each (lambda (child) (sxml->html child port)) elements))
      ((*RAW*)
       (display (car elements) port))
      ((*COMMENT*)
       (format port "<!--~a-->" (car elements)))
      (else
       (format port "<~a" tag)
       (sxml-write-attributes (or named-attrs '()) port)
       (display ">" port)
       (unless (memq tag %html-void-elements)
         (sxml-write-children body (memq tag %html-raw-elements) port)
         (format port "</~a>" tag))))))

(define* (sxml->html node #:optional (port (current-output-port)))
  "Write @var{node}, an SXML tree, to @var{port} as HTML.

Handles the three node kinds a page needs - elements with an attribute list,
text, and @code{(*RAW* text)} for content that must not be escaped - and treats
void and raw-text elements differently, which is the whole difference between
XML and HTML here."
  (cond
    ((or (null? node) (not node) (eq? node #t)) *unspecified*)
    ((string? node) (display (html-escape node) port))
    ((not (pair? node)) (display node port))
    ((symbol? (car node)) (sxml-write-element node port))
    (else (for-each (lambda (child) (sxml->html child port)) node))))

(define (sxml->html-string tree)
  "Return @var{tree}, an SXML document, as a string of HTML."
  (call-with-output-string
    (lambda (port)
      (sxml->html tree port))))

(define glass-common-css
;; The stylesheet every Heks page starts from.
;;
;; It carries the parts that are not about any one page: the page itself, the two
;; layers behind the glass, the glass recipe, the brand line, the keycap, and the
;; footer that carries the licence.  A page appends its own rules after this, so a
;; later rule always wins and a page never has to fight the shell.
  "* { box-sizing: border-box; }
html, body { height: 100%; }
body {
  margin: 0;
  background-color: @background@;
  color: @text@;
  font-family: '@sans@', system-ui, -apple-system, sans-serif;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
  color-scheme: @scheme@;
  overflow: hidden;
}

/* The mesh: the palette's own colours as large, soft blooms over a base wash.
   Everything glass sits on top of this, which is the whole trick - a blur with a
   flat colour behind it is invisible.  The base wash matters on a pure-black
   palette, where there is otherwise nothing for the light to fall on. */
.mesh {
  position: fixed;
  inset: -18%;
  z-index: 0;
  pointer-events: none;
  background-image:
    radial-gradient(58% 52% at 14% 2%, @mesh-primary@ 0%, transparent 66%),
    radial-gradient(46% 42% at 94% -4%, @mesh-text@ 0%, transparent 70%),
    radial-gradient(62% 58% at 80% 102%, @mesh-primary@ 0%, transparent 68%),
    radial-gradient(44% 46% at -4% 96%, @mesh-secondary@ 0%, transparent 74%),
    linear-gradient(165deg, @mesh-base-top@ 0%, @mesh-base-bottom@ 100%);
  filter: blur(26px) saturate(135%);
}
/* Grain, drawn by an inline SVG so the page stays one file with no requests. */
.grain {
  position: fixed;
  inset: 0;
  z-index: 1;
  pointer-events: none;
  opacity: 0.035;
  mix-blend-mode: overlay;
  background-image: url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='180' height='180'><filter id='g'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3' stitchTiles='stitch'/></filter><rect width='180' height='180' filter='url(%23g)'/></svg>\");
}

.app {
  position: relative;
  z-index: 2;
  display: flex;
  gap: 14px;
  height: 100vh;
  padding: 14px;
}

/* One recipe for every pane of glass on every page. */
aside, main {
  position: relative;
  border: 1px solid @hairline@;
  border-radius: 20px;
  background-color: @glass@;
  background-image: @haze@;
  -webkit-backdrop-filter: @blur@;
  backdrop-filter: @blur@;
  box-shadow: inset 0 1px 0 @inner-light@, inset 0 -1px 0 @inner-dark@,
              0 40px 90px -50px @shadow@;
  overflow: hidden;
}
aside {
  flex: 0 0 246px;
  display: flex;
  flex-direction: column;
  padding: 20px 12px 14px;
}
main { display: flex; flex: 1; flex-direction: column; min-width: 0; }

.brand {
  margin: 0 12px 2px;
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 10.5px;
  letter-spacing: 0.22em;
  text-transform: uppercase;
  color: @text-l@;
}
h1 {
  margin: 0 12px 4px;
  font-size: 19px;
  font-weight: 700;
  letter-spacing: -0.022em;
}
.stat {
  margin: 0 12px 18px;
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 11.5px;
  letter-spacing: 0.02em;
  color: @text-l@;
}
.stat b { color: @primary@; font-weight: 600; }
.sidebar-foot {
  margin-top: auto;
  padding: 14px 12px 2px;
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 10.5px;
  line-height: 1.7;
  letter-spacing: 0.03em;
  color: @text-l@;
  opacity: 0.75;
}

/* A keycap: monospace, with a lit top edge and a shadow underneath, so the row
   reads as something you could press. */
kbd {
  display: inline-flex;
  align-items: center;
  padding: 5px 10px;
  border: 1px solid @key-border@;
  border-radius: 9px;
  background-color: @key-base@;
  background-image: @key-face@;
  box-shadow: inset 0 1px 0 @key-light@, 0 1px 1px @shadow-soft@, 0 4px 10px -6px @shadow@;
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 14.5px;
  font-weight: 500;
  line-height: 1.25;
  letter-spacing: 0.015em;
  white-space: nowrap;
  color: @key-text@;
  text-shadow: 0 1px 0 @key-light@;
}

/* The sidebar's tabs and the toolbar above the content: both pages have them,
   so both pages look like each other. */
nav.tabs { display: flex; flex-direction: column; gap: 3px; margin-bottom: 4px; }
.tab {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  width: 100%;
  padding: 9px 12px;
  border: 1px solid transparent;
  border-radius: 11px;
  background: transparent;
  color: @text-l@;
  font: inherit;
  font-size: 13.5px;
  text-align: left;
  cursor: pointer;
  transition: background 0.16s ease, color 0.16s ease, box-shadow 0.16s ease;
}
.tab:hover { background: @hover@; color: @text@; }
.tab[aria-selected='true'] {
  background-image: @selected-face@;
  color: @text@;
  box-shadow: inset 0 0 0 1px @primary-edge@, 0 6px 18px -14px @shadow@;
}
.tab .count {
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 11.5px;
  font-variant-numeric: tabular-nums;
  opacity: 0.5;
}
.tab[aria-selected='true'] .count { color: @primary@; opacity: 1; }

.toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px 20px 12px;
  border-bottom: 1px solid @hairline@;
}
.search {
  flex: 1;
  padding: 10px 14px 10px 34px;
  border: 1px solid @hairline@;
  border-radius: 11px;
  background-color: @field@;
  background-image: @magnifier@;
  background-repeat: no-repeat;
  background-position: 12px center;
  background-size: 13px 13px;
  color: @text@;
  font: inherit;
  font-size: 13px;
  outline: none;
  transition: border-color 0.16s ease, box-shadow 0.16s ease;
}
.search::placeholder { color: @text-l@; opacity: 0.75; }
.search:focus { border-color: @primary@; box-shadow: 0 0 0 3px @primary-ghost@; }
.toolbar .hint {
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 11px;
  letter-spacing: 0.04em;
  color: @text-l@;
  opacity: 0.7;
  white-space: nowrap;
}

footer {
  display: flex;
  align-items: center;
  gap: 14px;
  flex-wrap: nowrap;
  padding: 10px 20px;
  border-top: 1px solid @hairline@;
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 11px;
  letter-spacing: 0.04em;
  color: @text-l@;
}
footer kbd { padding: 3px 8px; font-size: 12px; border-radius: 7px; box-shadow: none; }
/* Nothing in the footer may wrap: a hint broken across two lines turns the
   whole bar into two rows and pushes the page up. */
footer > span { flex: 0 0 auto; white-space: nowrap; }
footer .grow { flex: 1 1 auto; }
footer .credits { flex: 0 1 auto; opacity: 0.75; overflow: hidden; text-overflow: ellipsis; }
footer .credits b { color: @primary@; font-weight: 600; }

.swatches { display: flex; align-items: center; gap: 6px; }
.swatch {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 3px 7px 3px 4px;
  border: 1px solid @hairline-soft@;
  border-radius: 999px;
  background-color: @glass-strong@;
}
.swatch i {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  border: 1px solid @hairline@;
}
.swatch span { opacity: 0.8; }

::-webkit-scrollbar { width: 11px; }
::-webkit-scrollbar-thumb {
  border: 3px solid transparent;
  border-radius: 999px;
  background-clip: content-box;
  background-color: @scroll@;
}
::-webkit-scrollbar-thumb:hover { background-color: @text-l@; }
::-webkit-scrollbar-track { background: transparent; }
")

(define (glass-tokens palette)
  "Return the token alist that paints the shell from @var{palette}.

Light and dark get different glass on purpose: the haze is white at a few
percent on both, because that is what glass does, but a light palette needs a
stronger wash and a much weaker shadow to read as a pane rather than a hole."
  (let* ((dark? (is-dark-palette palette))
         (background (get-color palette 'background))
         (background-l (get-color palette 'background-l))
         (text (get-color palette 'text))
         (text-l (get-color palette 'text-l))
         (primary (get-color palette 'primary)))
    `(("@background@" . ,background)
      ("@background-l@" . ,background-l)
      ("@text@" . ,text)
      ("@text-l@" . ,text-l)
      ("@primary@" . ,primary)
      ("@on-primary@" . ,background)
      ("@sans@" . ,(heks-linux-sans-font))
      ("@mono@" . ,(heks-linux-mono-font))
      ("@scheme@" . ,(if dark? "dark" "light"))
      ("@glass@" . ,(hex-to-rgba background-l #:alpha (if dark? 0.40 0.52)))
      ("@glass-strong@" . ,(hex-to-rgba background-l #:alpha 0.72))
      ("@haze@" . ,(if dark?
                       "linear-gradient(180deg, rgba(255, 255, 255, 0.085) 0%, rgba(255, 255, 255, 0.015) 100%), radial-gradient(130% 95% at 0% 0%, rgba(255, 255, 255, 0.075) 0%, rgba(255, 255, 255, 0) 58%)"
                       "linear-gradient(180deg, rgba(255, 255, 255, 0.78) 0%, rgba(255, 255, 255, 0.42) 100%), radial-gradient(130% 95% at 0% 0%, #ffffff 0%, rgba(255, 255, 255, 0) 58%)"))
      ("@blur@" . "blur(32px) saturate(185%)")
      ("@hairline@" . ,(hex-to-rgba text #:alpha (if dark? 0.15 0.13)))
      ("@hairline-soft@" . ,(hex-to-rgba text #:alpha 0.085))
      ("@inner-light@" . ,(if dark?
                              "rgba(255, 255, 255, 0.11)"
                              "rgba(255, 255, 255, 0.90)"))
      ("@inner-dark@" . ,(if dark?
                             "rgba(0, 0, 0, 0.35)"
                             "rgba(0, 0, 0, 0.06)"))
      ("@hover@" . ,(hex-to-rgba text #:alpha (if dark? 0.07 0.05)))
      ("@selected-face@" . ,(format #f "linear-gradient(180deg, ~a 0%, ~a 100%)"
                                    (hex-to-rgba primary #:alpha (if dark? 0.22 0.28))
                                    (hex-to-rgba primary #:alpha (if dark? 0.09 0.12))))
      ("@primary-edge@" . ,(hex-to-rgba primary #:alpha 0.45))
      ("@primary-ghost@" . ,(hex-to-rgba primary #:alpha 0.22))
      ("@primary-soft@" . ,(hex-to-rgba primary #:alpha (if dark? 0.16 0.12)))
      ("@field@" . ,(if dark? "rgba(0, 0, 0, 0.26)" "rgba(255, 255, 255, 0.62)"))
      ("@shadow@" . ,(if dark? "rgba(0, 0, 0, 0.85)" "rgba(0, 0, 0, 0.28)"))
      ("@shadow-soft@" . ,(hex-to-rgba text #:alpha 0.18))
      ("@key-face@" . ,(if dark?
                           "linear-gradient(180deg, rgba(255, 255, 255, 0.20) 0%, rgba(255, 255, 255, 0.05) 100%)"
                           "linear-gradient(180deg, rgba(255, 255, 255, 0.95) 0%, rgba(255, 255, 255, 0.45) 100%)"))
      ("@key-base@" . ,(hex-to-rgba (if dark? background-l text) #:alpha 0.55))
      ("@key-border@" . ,(hex-to-rgba text #:alpha (if dark? 0.24 0.16)))
      ("@key-light@" . ,(if dark?
                            "rgba(255, 255, 255, 0.24)"
                            "rgba(255, 255, 255, 0.95)"))
      ("@key-text@" . ,text)
      ("@scroll@" . ,(hex-to-rgba text #:alpha 0.24))
      ("@mesh-primary@" . ,(hex-to-rgba primary #:alpha (if dark? 0.42 0.34)))
      ("@mesh-secondary@" . ,(hex-to-rgba primary #:alpha (if dark? 0.20 0.12)))
      ("@mesh-text@" . ,(hex-to-rgba text #:alpha (if dark? 0.13 0.09)))
      ("@mesh-base-top@" . ,(if dark?
                                (hex-to-rgba text #:alpha 0.07)
                                (hex-to-rgba background-l #:alpha 0.9)))
      ("@mesh-base-bottom@" . ,background)
      ("@magnifier@" . ,(glass-magnifier palette)))))

(define (glass-magnifier palette)
  "Return a magnifier glyph as a data URI, inked in @var{palette}'s text colour.

The search field draws its own icon so a page needs no icon font and no request:
a tiny SVG in the palette's colour, inlined into the stylesheet.  The colour goes
in with its hash escaped, because inside a url() a hash starts a fragment and the
glyph silently disappears."
  (format #f
          "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' stroke='~a' stroke-width='1.6' stroke-linecap='round'><circle cx='6.6' cy='6.6' r='4.6'/><path d='M10.2 10.2 L14 14'/></svg>\")"
          (string-replace-substring (get-color palette 'text-l)
                                    "#" "%23")))

(define* (glass-fill template #:key (palette (heks-linux-palette)))
  "Paint @var{template} with the tokens of @var{palette}."
  (fill-template template (glass-tokens palette)))

;; The two layers that sit behind the glass: the mesh and the grain.  They come
;; before the app, so the panels have something to diffuse and the page has
;; texture where nothing else is drawn.
(define glass-layers
  '((div (@ (class "mesh")))
    (div (@ (class "grain")))))

;; The brand line, with the lambda the desktop itself is labelled with.
(define glass-brand
  '(p (@ (class "brand")) "λ Heks GNU/Linux"))

(define (glass-credits)
  "Return the footer credit: what this page is, and what it is licensed under.

A page generated by a program for a machine should say so, and a desktop built
out of one should say what it is built out of.  It costs one line and it is the
only place either statement is made."
  '(span (@ (class "credits"))
         "Rendered by " (b "heks-linux") " · free software · GPL-3.0-or-later"))

(define* (glass-document title body
                         #:key (css "") (palette (heks-linux-palette))
                         (lang "en"))
  "Return @var{body} - a list of SXML nodes - as a complete page.

@var{css} is appended after the shared stylesheet, so page rules win over shell
rules without specificity games.  The stylesheet is written as raw text and the
document is written as HTML: this is a page for a browser, not an XML feed."
  (string-append
   "<!DOCTYPE html>\n"
   (sxml->html-string
    `(*TOP*
      (html (@ (lang ,lang))
            (head (meta (@ (charset "utf-8")))
                  (meta (@ (name "viewport")
                           (content "width=device-width, initial-scale=1")))
                  (title ,title)
                  (style (*RAW* ,(glass-fill (string-append glass-common-css css)
                                             #:palette palette))))
            (body ,@glass-layers
                  ,@body))))))
