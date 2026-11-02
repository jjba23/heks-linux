;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux mako).  The configuration is an association list
;; that is later flattened into @code{key=value} lines, so the tests inspect
;; the flattened text exactly like mako will read it.

;;; Code:

(define-module (veritas unit mako-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux mako)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:export (spec))

(define (render-mako-config-for palette)
  "Render the mako configuration for @var{palette} the way it is written to disk."
  (mk-kv-conf-lines (mako-config #:palette palette
                                 #:sans-font "Work Sans")))

(define (render-mako-config)
  "Render the mako configuration the way it is written to disk."
  (render-mako-config-for 'modus-operandi))

(define (mako-conf-occurs? fragment)
  (not (eq? #f (string-contains (render-mako-config) fragment))))

(define mako-suite
  (suite "Mako Notification Suite"
    (test "Notification behaviour is configured"
      (assert-true (mako-conf-occurs? "max-history=7")
        #:name "Notification history should be kept")
      (assert-true (mako-conf-occurs? "default-timeout=10000")
        #:name "A default timeout should be set")
      (assert-true (mako-conf-occurs? "on-button-left=dismiss")
        #:name "Left click should dismiss a notification"))

    (test "Do Not Disturb Mode Is Declared"
      (assert-true (mako-conf-occurs? "[mode=do-not-disturb]")
        #:name
        "A do-not-disturb mode section should exist so makoctl can toggle it")
      (assert-true (mako-conf-occurs? "invisible=1")
        #:name
        "While in do-not-disturb, notifications must not be drawn"))

    (test "Banner Background Follows Palette Opacity"
      ;; The expected alpha is derived from the palette, not baked in:
      ;; the whole point of these keys is that they are tunable, so a
      ;; test that hardcodes one turns a taste change into a failure.
      (assert-true (mako-conf-occurs?
                    (format #f "background-color=~a~a"
                            (string-upcase (get-color 'modus-operandi
                                                      'background))
                            (string-upcase
                             (opacity->hex-alpha (get-mako-opacity
                                                  'modus-operandi)))))
        #:name
        "The default banner should use its palette mako-opacity")
      (assert-true (not (eq? #f
                             (string-contains
                              (render-mako-config-for 'golden-gate-dark)
                              (format #f "background-color=~a~a"
                                      (string-upcase
                                       (get-color 'golden-gate-dark
                                                  'background))
                                      (string-upcase
                                       (opacity->hex-alpha
                                        (get-mako-opacity
                                         'golden-gate-dark)))))))
        #:name
        "Golden Gate should render its own, more transparent banner"))

    (test "Banners Match The Reference Look"
      (assert-true (mako-conf-occurs? "border-radius=12")
        #:name
        "Notification banners should be rounded like the reference's were")
      (assert-true (mako-conf-occurs? "border-size=1")
        #:name
        "Notification banners should carry a one-pixel hairline edge")
      (assert-true (mako-conf-occurs?
                    (format #f "border-color=~a59"
                            (get-color 'modus-operandi 'text-l)))
        #:name
        "The edge should be the secondary text colour at 35% opacity")
      ;; The radius is one number because the compositor rounds the banner's
      ;; *shadow* with it too; a shadow at another radius pokes out behind the
      ;; corners.
      (assert-equal #:expect 12
        #:got (mako-radius)
        #:name
        "The radius should be a setting the compositor can read")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((mako-radius 20))
                                   (render-mako-config))
                                 "border-radius=20")))
        #:name "A machine should be able to round its banners differently"))

    (test "The Banner Drops Below The Menu Bar"
      ;; The anchor is the top right corner, which is where the bar is: a
      ;; banner drawn from eight pixels down would sit on top of the menu bar,
      ;; which is what the old margin did.
      (assert-true (mako-conf-occurs? "anchor=top-right")
        #:name
        "Banners belong in the corner the reference keeps them in")
      (assert-true (mako-conf-occurs? "margin=34,8,8,8")
        #:name
        "The top margin should clear the menu bar and the other three should not")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((mako-margin "10"))
                                   (render-mako-config))
                                 "margin=10")))
        #:name "The margin should be a setting"))

    (test "Urgent Notifications Do Not Look Like The Others"
      ;; Mako's urgency levels are the only distinction a notification
      ;; carries, so the critical ones wear the palette's accent in their rim
      ;; and stay until dismissed.
      (assert-true (mako-conf-occurs? "[urgency=critical]")
        #:name "A critical section should exist")
      (assert-true (mako-conf-occurs? "default-timeout=0")
        #:name
        "A critical notification should stay until it is dismissed")
      (assert-true (not (eq? #f (string-contains
                                 (render-mako-config-for 'modus-operandi)
                                 (format #f "border-color=~a"
                                         (get-color 'modus-operandi
                                                    'primary)))))
        #:name
        "The rim should be the palette's accent, in every palette"))))

(define (spec)
  (veritas-run mako-suite))
