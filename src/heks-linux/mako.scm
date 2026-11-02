;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Renders @file{~/.config/mako/config}, the notification daemon configuration.
;;
;; The module is deliberately organised around a @emph{list of pairs}, not a
;; template string: each line is a @code{(key . value)} pair and the whole list
;; is flattened by @code{mk-kv-conf-lines}.  That is what allows the spec to
;; assert on rendered behaviour without starting mako.
;;
;; The banner is drawn the way the reference drew one - a rounded panel over the
;; wallpaper, a hairline rim instead of a frame, the title heavy and the body
;; plain, the icon at the left - with three differences that are this desktop's
;; rather than the reference's:
;;
;;   it follows the palette.  The reference's banners were smoked glass whatever the
;;   theme; here a light palette gets a pale panel with dark text and a dark one
;;   gets the smoked panel.  The hairline, the radius and the translucency are the
;;   language the menu bar and the launcher already speak, so the three surfaces
;;   read as one system rather than as three programs.
;;
;;   it drops below the menu bar.  The anchor is the top right corner, which is
;;   the corner the bar occupies, so the top margin clears the bar and the banner
;;   starts where the bar ends - the way the reference's notification came in under the
;;   menu bar rather than over it.
;;
;;   it has no shadow, and that is deliberate.  The compositor can only shadow or
;;   blur the surface a client gives it, and mako's surface is sized for the whole
;;   stack of banners rather than for the one being drawn: asking for either put a
;;   grey box behind and above the banner.  Measured, then removed - the rim is the
;;   banner's own edge, and the panel is opaque enough not to need a blur.
;;
;; A @code{do-not-disturb} mode is declared so that
;; @code{makoctl mode -t do-not-disturb} toggles it.  In that mode notifications
;; are still recorded in the history buffer, they are simply never drawn - so
;; nothing is lost when you dismiss the world for an hour.
;;
;; The DND state is also surfaced on the Waybar (see @code{waybar-mako-dnd}) and
;; bound to @kbd{Mod+Shift+N} in @code{(heks-linux niri)}.

;;; Code:

(define-module (heks-linux mako)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux prelude)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (mako-config install-mako-config mako-config-filename
                        mako-radius mako-margin opacity->hex-alpha
                        mako-config-dir))

(define s
  (scriba-auto-logger))

;; The corner radius of a banner, in pixels.  One value because two programs need
;; it: this configuration rounds the panel with it, and the compositor rounds the
;; panel's *shadow* with the same number (@code{geometry-corner-radius} in
;; @code{(heks-linux niri)}).  A shadow drawn at a different radius pokes out
;; behind the corners, which is the one way a floating panel can look broken.
;; Twelve rather than the sixteen this used to be: the reference's banners were gently
;; rounded, and at sixteen a short banner reads as a bubble.
(define mako-radius
  (make-parameter 12))

;; The banner's margin, as mako's four values - top, right, bottom, left.
;;
;; The top one is the interesting one.  The anchor is the top right corner, which
;; is where the menu bar is, so the top margin has to clear the bar: eight pixels
;; of air under a 26 pixel bar is 34.  The two are kept in step by hand, because a
;; notification does not otherwise know that a bar exists.
(define mako-margin
  (make-parameter "34,8,8,8"))

;; The banner hairline: one pixel of the palette's secondary text colour at
;; roughly 35% opacity.  That is the notification trick - a rim that reads
;; as an edge in a dark palette and as a soft shadow in a light one, without ever
;; turning into a visible frame.
;;
;; It is also the *only* edge a banner has.  A drop shadow would be the
;; compositor's, and the compositor can only shadow the surface mako gives it,
;; which is the whole stack of banners rather than the one on screen - so the
;; rim carries the separation alone, and it carries a little more of it than the
;; 15% it started at.
(define mako-border-size 1)
(define mako-border-alpha "59")

;; Accent and text colours keep their own soft alpha; only the banner background
;; follows the palette's `mako-opacity', which replaces the old hard-coded alpha.
;; The text goes nearly all the way to opaque: a banner is read at a glance, over
;; whatever wallpaper happens to be behind it, and 73% white on a translucent
;; panel is a sentence somebody has to lean in for.
(define mako-accent-alpha "bb")
(define mako-text-alpha "f2")

(define (opacity->hex-alpha opacity)
  "Render a 0-1 @var{opacity} as the two-digit hexadecimal alpha suffix Mako
expects in a @code{#RRGGBBAA} colour."
  (format #f "~2,'0x"
          (inexact->exact (round (* 255 opacity)))))

(define* (mako-border-color palette)
  "Return the 8-digit hex colour of the banner hairline for @var{palette}.
Mako accepts @code{#RRGGBBAA}, so the alpha is appended to the palette's
@code{text-l} colour rather than blended here."
  (string-append (get-color palette 'text-l) mako-border-alpha))

(define* (mako-config #:key palette sans-font)
  "Return the mako configuration as a list ready for @code{mk-kv-conf-lines}.

@var{palette} supplies the background, accent and text colours; @var{sans-font}
is rendered as @code{<family> <size in points>}.  The returned list mixes
@code{(key . value)} pairs with raw strings, because the trailing
@code{[mode=do-not-disturb]} section is not a key/value pair.

@example
(mk-kv-conf-lines (mako-config #:palette 'nord))
@end example"
  (let* ((format-color (lambda (key alpha)
                         (string-upcase (format #f "~a~a"
                                                (get-color palette key)
                                                alpha))))
         (bg-color (format-color 'background
                                 (opacity->hex-alpha
                                  (get-mako-opacity palette))))
         (primary-color (format-color 'primary mako-accent-alpha))
         (text-color (format-color 'text mako-text-alpha)))
    (append `((sort . "-time") (max-history . 7)
              (max-visible . 5)

              ;; Geometry & Layout.  The top margin clears the menu bar; see
              ;; `mako-margin'.
              (anchor . "top-right")
              (width . 380)
              (margin unquote (mako-margin))
              (padding . "16")
              (layer . "top")

              ;; Visual Styling
              ;; soft, subtly edged, rounded banners - the reference's panel, in this
              ;; palette's own ink.  The radius is `mako-radius' because the
              ;; compositor rounds the shadow with the same number.
              (background-color unquote bg-color)
              (border-color unquote (mako-border-color palette))
              (border-size unquote mako-border-size)
              (border-radius unquote (mako-radius))
              (progress-color unquote primary-color)

              ;; Typography & Content Formatting
              (text-color unquote text-color)
              (font unquote
                    (format #f "~a 11" sans-font))
              (text-alignment . "left")
              (markup . 1)
              (format . "<b>%s</b>\\n%b")

              ;; Icons.  A banner carried its application's icon at the
              ;; left, a little smaller than the two lines of text beside it; 48
              ;; was taller than the text block, which made the icon the loudest
              ;; thing in a notification.
              (icons . 1)
              (max-icon-size . 40)
              (icon-border-radius . 8)

              ;; Actions & Timeouts
              (on-button-left . dismiss)
              (on-button-right . invoke-default-action)
              (default-timeout . 10000)
              (ignore-timeout . 1))
            ;; A notification that says something is wrong should not look like
            ;; the one that says a screenshot was saved.  Mako's urgency levels
            ;; are the only distinction a notification carries, so the critical
            ;; ones wear the palette's accent in their rim and stay until they are
            ;; dismissed - which is what the reference did with the alerts it wanted an
            ;; answer to.
            (list (format #f "\n[urgency=critical]\nborder-color=~a~a\nborder-size=2\ndefault-timeout=0\n"
                          (get-color palette 'primary)
                          mako-accent-alpha))
            ;; Do-not-disturb mode. Toggled from the session with
            ;; `makoctl mode -t do-not-disturb`; while active, notifications are
            ;; still kept in the history buffer but never drawn on screen.
            (list "\n[mode=do-not-disturb]\ninvisible=1\n"))))

;; mako has no file extension convention: the file is plainly @file{config}.
(define mako-config-filename
  (make-parameter "config"))

;; Directory receiving the rendered configuration; defaults to
;; @file{~/.config/mako}.
(define mako-config-dir
  (make-parameter (format #f "~a/.config/mako"
                          (or (getenv "HOME") "/tmp"))))

(define* (install-mako-config)
  "Write the mako configuration to @code{mako-config-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/mako-settings.scm} first.  Restart mako (or
run @code{makoctl reload}) afterwards for the change to take effect."
  (log-info s "Installing Mako configuration")
  (load-local-overrides '(heks-linux mako)
                        'mako-settings)
  (install-config-file! #:name (mako-config-filename)
                        #:dir (mako-config-dir)
                        #:contents (mk-kv-conf-lines (mako-config #:palette (heks-linux-palette)
                                                                  #:sans-font (heks-linux-sans-font))))
  (log-success s "Installed Mako configuration"))
