;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux waybar).

;; IMPORTANT contributor note:
;;
;; `assert-true' and friends are *pure constructors*: they return a closure
;; that the veritas runner later applies to a context.  When such a call sits
;; in a non-final position of a body (typically inside a `let'), its return
;; value is unused and Guile's optimizer deletes the call entirely, so the
;; assertion silently never runs.  Always pass assertions as direct arguments
;; to `test', as this file does.

;;; Code:

(define-module (veritas unit waybar-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux waybar)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (menu-rows)
  "Return the rows of the system menu that can be picked.

A row is a @code{(label icon command)} list; the rule between two groups of rows
is a plain string, because a rule nobody can select must not look like a row
somebody can."
  (filter list? (waybar-system-menu-entries)))

(define (row-labelled label)
  "Return the system menu row whose label is @var{label}, or @code{#f}."
  (find (lambda (row)
          (equal? (car row) label)) (menu-rows)))

(define (module-option module key)
  "Return @var{key}'s value from the option list of @var{module}, or @code{#f}.

A custom item is a list whose first element names it and whose rest is an alist
of options, so this is how a test asks what the bar will tell waybar about it."
  (assoc-ref (cdr module) key))

(define (css-rule-for id)
  "Return the declaration list of the CSS rule that selects @var{id}, or @code{#f}.

The bar's stylesheet groups modules that share a role into one rule - the
appearance buttons, the readouts, the quiet states - so the selector a given id
appears in changes whenever the grouping does.  Looking the id up inside the
selectors, rather than restating the whole selector here, keeps these tests
about what the bar does and not about how the rules happen to be spelled."
  (let loop ((rules (waybar-css)))
    (cond ((null? rules) #f)
          ((and (pair? (car rules))
                (string? (car (car rules)))
                (string-contains (car (car rules)) id))
           (cdr (car rules)))
          (else (loop (cdr rules))))))

(define (css-values key)
  "Return every value the stylesheet declares under @var{key}.

A menu bar is read as one row, so what matters about its ink is a property of
the whole row: \"every item is painted in the palette's text colour\" is a claim
about this list, not about any one rule."
  (filter-map (lambda (rule)
                (and (pair? rule)
                     (list? (cdr rule))
                     (let ((entry (assoc key (cdr rule))))
                       (and entry (cdr entry)))))
              (waybar-css)))

(define (bar-ink)
  "Return the ink the bar paints its items in.

It is the colour the stylesheet declares on @code{module}, which every item
inherits: taking it from the stylesheet rather than from the palette keeps the
test about one ink rather than about which palette happens to be in use."
  (assoc-ref (assoc-ref (waybar-css)
                        'module)
             'color))

(define waybar-suite
  (suite "Waybar Configuration Suite"
         (test "System Menu At The Far Left"
               ;; A Mac menu bar carries the apple at the far left; this bar
               ;; carries the desktop's own mark there, and the session that
               ;; used to hang off the right edge of the row hangs off that mark
               ;; instead.
               (assert-equal #:expect 'custom/heks-system-menu
                             #:got
                             (vector-ref (assoc-ref (waybar-conf)
                                                    'modules-left)
                                         0)
                             #:name
                             "The system menu should be the first thing on the bar")
               (assert-equal #:expect #f
                             #:got
                             (member 'custom/power
                                     (vector->list (assoc-ref (waybar-conf)
                                                              'modules-right)))
                             #:name
                             "The power glyph at the end of the row should be gone")
               (assert-equal #:expect #f
                             #:got (css-rule-for "#custom-power")
                             #:name
                             "Its stylesheet rule should be gone with it")
               (assert-equal #:expect "Heks"
                             #:got
                             (assoc-ref (waybar-system-menu-button)
                                        'format)
                             #:name
                             "The first item should say the machine's name, not a glyph")
               (assert-equal #:expect "🐧"
                             #:got
                             (parameterize ((waybar-system-menu-label "🐧"))
                               (assoc-ref (waybar-system-menu-button)
                                          'format))
                             #:name
                             "A machine should be able to wear a penguin instead")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-system-menu-button)
                                                     'on-click)
                                          "heks-system-menu")))
                            #:name "A click should open the system menu")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-system-menu-button)
                                                     'on-click-right)
                                          "rofi -show power")))
                            #:name
                            "The right button should still reach the session in one click")
               (assert-true (not (eq? #f (css-rule-for
                                          "#custom-heks-system-menu")))
                            #:name
                            "The logo should be styled as the bar's one bold item"))

         (test "System Menu Rows"
               ;; The Apple menu's shape: what this machine is, the ways into
               ;; it, then the ways out of the session.  The session rows are
               ;; the power menu's own, so the two menus cannot drift apart.
               (assert-true (not (eq? #f (row-labelled "About This Heks")))
                            #:name
                            "The menu should answer what this machine is")
               (assert-equal #:expect "heks-about"
                             #:got
                             (caddr (row-labelled "About This Heks"))
                             #:name
                             "About should open the generated About window")
               (assert-true (not (eq? #f (row-labelled "Search")))
                            #:name
                            "Spotlight should be reachable from the menu too")
               (assert-true (not (eq? #f (string-contains
                                          (caddr (row-labelled "Search"))
                                          "rofi -show drun")))
                            #:name "Search should open the Rofi launcher")
               (assert-true (not (eq? #f (string-contains
                                          (caddr (row-labelled "Search"))
                                          "sleep")))
                            #:name
                            "The second Rofi should wait for the menu to close")
               (assert-equal #:expect "systemctl poweroff"
                             #:got
                             (caddr (row-labelled "Shut Down"))
                             #:name
                             "The session rows are the power menu's own, not a second copy")
               (assert-true (not (eq? #f (row-labelled "Lock")))
                            #:name "Locking the session should be one row away")
               (assert-true (not (eq? #f (row-labelled "Log Out")))
                            #:name "So should logging out")
               (assert-true (not (eq? #f (any string?
                                              (waybar-system-menu-entries))))
                            #:name
                            "The groups should be separated by rules nobody can pick")
               (assert-true (not (eq? #f (string-contains (waybar-system-menu)
                                                          "nonselectable")))
                            #:name
                            "A rule should be printed as a row Rofi cannot select")
               (assert-true (not (eq? #f (string-contains (waybar-system-menu)
                                                          "ROFI_RETV")))
                            #:name "The menu should be a Rofi script-mode menu")
               (assert-true (not (eq? #f (string-contains (waybar-system-menu)
                                                          "-modi")))
                            #:name
                            "The script should hand itself to Rofi as the mode it opens")
               (assert-true (not (eq? #f (string-contains (waybar-system-menu)
                                                          "location: north west")))
                            #:name
                            "The menu should drop from the top left, under the logo")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-system-menu)
                                          (format #f "lines: ~a"
                                                  (length (waybar-system-menu-entries))))))
                            #:name
                            "The window should be exactly as tall as its rows")
               (assert-true (not (eq? #f (string-contains (waybar-system-menu)
                                                          "setsid")))
                            #:name
                            "Every action should be detached from the menu's stdout"))

         (test "About This Heks"
               ;; The first row of the system menu answers what a Mac answers
               ;; with About This Mac: what the machine says it is, and not what
               ;; this configuration guesses.
               (assert-true (not (eq? #f (string-contains (waybar-about)
                                                          "/etc/os-release")))
                            #:name
                            "The window should read what the machine says it runs")
               (assert-true (not (eq? #f (string-contains (waybar-about)
                                                          (format #f "~a"
                                                                  (heks-linux-palette)))))
                            #:name
                            "It should name the palette the desktop is wearing")
               (assert-true (not (eq? #f (string-contains (waybar-about)
                                                          "/proc/uptime")))
                            #:name
                            "The uptime should not depend on a flag uptime may not have")
               (assert-true (not (eq? #f (string-contains (waybar-about)
                                                          "zenity")))
                            #:name
                            "It should open a window rather than a second Rofi menu")
               (assert-true (not (eq? #f (string-contains (waybar-about)
                                                          "fyi")))
                            #:name
                            "A machine with no GTK dialog should still say something"))

         (test "Spotlight Glyph"
               ;; Rofi used to hide behind the bar's own label.  Now that the
               ;; leftmost item is the system menu, the launcher keeps a glyph of
               ;; its own so it is no further away than it was.
               (assert-true (not (eq? #f (member 'custom/heks-spotlight
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-left)))))
                            #:name
                            "The launcher should keep a place on the bar")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-spotlight)
                                                     'format)
                                          "\uf58d")))
                            #:name
                            "It should be the app grid, a glyph no text font claims")
               (assert-equal #:expect (waybar-icon "\uf58d")
                             #:got
                             (assoc-ref (waybar-spotlight)
                                        'format)
                             #:name
                             "It should name the solid face instead of trusting fallback")
               (assert-true (not (eq? #f (assoc-ref (assoc-ref (waybar-css)
                                                               "*")
                                                    'font-family)))
                            #:name
                            "The family belongs on the rule waybar's labels carry")
               (assert-equal #:expect #f
                             #:got
                             (assoc-ref (assoc-ref (waybar-css)
                                                   'module)
                                        'font-family)
                             #:name
                             "A family on the module never reaches the labels")
               (assert-equal #:expect #f
                             #:got
                             (string-contains
                              (assoc-ref (assoc-ref (waybar-css)
                                                    "*")
                                         'font-family)
                              "Font Awesome")
                             #:name
                             "A quoted comma list is one family name, so icons are left to fallback")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-spotlight)
                                                     'on-click)
                                          "rofi -show drun")))
                            #:name "A click should open the launcher")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-spotlight)
                                                     'on-click)
                                          "pkill rofi")))
                            #:name
                            "An open launcher should be replaced, not left to refuse the click")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-spotlight)
                                                     'on-click-right)
                                          "rofi -show window")))
                            #:name
                            "The right button should be the window switcher")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((waybar-spotlight-command
                                                          "fuzzel"))
                                            (assoc-ref (waybar-spotlight)
                                                       'on-click))
                                          "fuzzel")))
                            #:name
                            "The launcher should be pointable at another one from the settings file")
               (assert-equal #:got (css-rule-for "#custom-heks-spotlight")
                             #:expect (css-rule-for "#custom-media")
                             #:name
                             "The app grid should wear the actions' style"))

         (test "Every Item Explains Itself On Hover"
               ;; On a custom module `tooltip' is a bool and the text lives in
               ;; `tooltip-format' - a string in `tooltip' is silently ignored.
               ;; Most of this bar carried its hover text there, which is exactly
               ;; why most of it had nothing to say.
               (assert-equal #:expect #f
                             #:got (module-option (waybar-keybindings)
                                                  'tooltip)
                             #:name
                             "A string in tooltip is a bool waybar ignores")
               (assert-true (not (eq? #f (module-option (waybar-keybindings)
                                                        'tooltip-format)))
                            #:name
                            "The reference says what its two buttons do")
               (assert-true (not (eq? #f (module-option (waybar-clipboard)
                                                        'tooltip-format)))
                            #:name "So does the clipboard")
               (assert-true (not (eq? #f (module-option (waybar-system-menu-button)
                                                        'tooltip-format)))
                            #:name "So does the system menu's logo")
               (assert-true (not (eq? #f (module-option (waybar-spotlight)
                                                        'tooltip-format)))
                            #:name "So does the launcher")
               (assert-true (not (eq? #f (module-option (waybar-wallpaper)
                                                        'tooltip-format)))
                            #:name "So does the wall chooser")
               (assert-true (not (eq? #f (module-option (waybar-docs)
                                                        'tooltip-format)))
                            #:name "So does the documentation")
               ;; The readouts that waybar does not document a tooltip for.
               (assert-equal #:expect '()
                             #:got
                             (filter (lambda (option)
                                       (eq? #f (module-option option
                                                              'tooltip-format)))
                                     (list (waybar-backlight)
                                           (waybar-battery)
                                           (waybar-audio-icon)
                                           (waybar-power-profiles)
                                           (waybar-clock))))
               ;; The wheel and the spare buttons: a menu bar item that cannot
               ;; be adjusted without opening something is a label, not a control.
               (assert-true (not (eq? #f (module-option (waybar-audio-icon)
                                                        'on-scroll-up)))
                            #:name "The volume follows the wheel")
               (assert-true (not (eq? #f (module-option (waybar-backlight)
                                                        'on-scroll-up)))
                            #:name "So does the brightness")
               (assert-true (not (eq? #f (module-option (waybar-media)
                                                        'on-click-right)))
                            #:name "The music glyph can play and pause without a menu")
               (assert-true (not (eq? #f (module-option (waybar-battery)
                                                        'on-click)))
                            #:name "The battery reaches the session menu"))

         (test "Main Configuration (JSON Source)"
               (assert-true (list? (waybar-conf))
                            #:name
                            "Waybar config should be a list (convertible to JSON)")
               (assert-equal #:expect 'top
                              #:got (assoc-ref (waybar-conf) 'position)
                              #:name "Waybar position should be top by default")
               (assert-true (vector? (assoc-ref (waybar-conf)
                                                'modules-left))
                            #:name
                            "Modules should be represented as vectors for JSON arrays")
               (assert-true (not (eq? #f (member 'custom/mako-dnd
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The do-not-disturb indicator should sit on the bar"))

         (test "Keybinding Reference Button"
               (assert-true (not (eq? #f (member 'custom/heks-keys
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The question-mark button should sit on the bar")
               (assert-true (eq? #f (member 'custom/heks-info
                                            (vector->list
                                             (assoc-ref (waybar-conf)
                                                        'modules-right))))
                            #:name
                            "The bar should carry only the new question mark")
               (assert-equal #:expect (waybar-icon "\uf059")
                             #:got (assoc-ref (waybar-keybindings)
                                              'format)
                             #:name
                             "The button should be a circled question mark glyph, in the solid face")
               ;; The bar asks the compositor to spawn the window: a client
               ;; that spawns it itself has no activation token, and an open
               ;; window cannot be raised without one.
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-keybindings)
                                                     'on-click)
                                          "niri msg action spawn")))
                            #:name
                            "Clicking it should ask the compositor to activate it")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-keybindings)
                                                     'on-click)
                                          "heks-toon")))
                            #:name
                            "Clicking it should open the keyboard reference")
               (assert-true (not (eq? #f (css-rule-for "#custom-heks-keys")))
                            #:name
                            "The button should be styled like the rest of the bar")

               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-keybindings)
                                                     'on-click-right)
                                          "codeberg.org/jjba23/heks-linux")))
                            #:name
                            "A right click should still reach the project page"))

         (test "Wallpaper Button"
               (assert-true (not (eq? #f (member 'custom/heks-wallpaper
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The wallpaper button should sit beside the palette")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-wallpaper) 'on-click)
                                          "heks-toon walls")))
                            #:name
                            "Clicking it should open the wall chooser")
               (assert-true (string? (assoc-ref (waybar-wallpaper) 'format))
                            #:name "The button is a glyph, not a label")
               (assert-equal #:expect (waybar-icon "\uf03e")
                             #:got (assoc-ref (waybar-wallpaper) 'format)
                             #:name
                             "The glyph should be the picture icon, named in the solid face")
               (assert-true (not (eq? #f (css-rule-for "#custom-heks-palette")))
                            #:name
                            "The appearance buttons should share one rule")
               (assert-equal #:got (css-rule-for "#custom-heks-palette")
                             #:expect (css-rule-for "#custom-heks-wallpaper")
                             #:name
                             "The palette and the wall chooser should wear one style"))

         (test "Documentation Button"
               ;; The docs button is the same question as the palette and the
               ;; wall chooser - what is this desktop - answered from the
               ;; projects' own READMEs instead of a browser tab.
               (assert-true (not (eq? #f (member 'custom/heks-docs
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The documentation button should sit on the bar")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-docs) 'on-click)
                                          "heks-toon docs")))
                            #:name
                            "Clicking it should open the documentation view")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-docs) 'on-click)
                                          "niri msg action spawn")))
                            #:name
                            "It should ask the compositor for the activation a bar click cannot prove")
               (assert-equal #:expect (waybar-icon "\uf518")
                             #:got (assoc-ref (waybar-docs) 'format)
                             #:name
                             "The glyph should be the book, in the solid face that has it")
               (assert-true (not (eq? #f (module-option (waybar-docs)
                                                        'tooltip-format)))
                            #:name
                            "The tooltip should say what the book opens"))

         (test "Clipboard Button"
               ;; The clipboard glyph is the bar's way into the history the
               ;; compositor keeps: the same picker the keybinding opens.
               (assert-true (not (eq? #f (member 'custom/heks-clipboard
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The clipboard button should sit on the bar")
               (assert-equal #:expect 'custom/heks-clipboard
                             #:got (car (waybar-clipboard))
                             #:name
                             "The button should be the bar's own custom item")
               (assert-equal #:expect (waybar-icon "\uf328")
                             #:got (assoc-ref (waybar-clipboard) 'format)
                             #:name
                             "The glyph should be the clipboard, named in the solid face")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-clipboard) 'on-click)
                                          "clipman pick --tool=rofi")))
                            #:name
                            "Clicking it should browse the clipboard history")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-clipboard) 'on-click)
                                          "pkill rofi")))
                            #:name
                            "An open rofi should be replaced, not left to refuse the click")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((waybar-clipboard-command
                                                          "wl-paste | fzf"))
                                            (assoc-ref (waybar-clipboard)
                                                       'on-click))
                                          "wl-paste | fzf")))
                            #:name
                            "The picker should be pointable at another one from the settings file")
               (assert-equal #:got (css-rule-for "#custom-heks-clipboard")
                             #:expect (css-rule-for "#custom-media")
                             #:name
                             "The clipboard glyph should wear the actions' style"))

         (test "Password Manager Button"
               ;; macOS keeps its passwords in a window nobody puts on the menu
               ;; bar; this desktop keeps them one glyph away, and the glyph
               ;; opens the machine's own password manager rather than one the
               ;; bar hard-codes.
               (assert-true (not (eq? #f (member 'custom/heks-password
                                                 (vector->list
                                                  (assoc-ref (waybar-conf)
                                                             'modules-right)))))
                            #:name
                            "The password manager should have a glyph on the bar")
               (assert-equal #:expect 'custom/heks-password
                             #:got (car (waybar-password))
                             #:name
                             "The button should be the bar's own custom item")
               (assert-equal #:expect (waybar-icon "\uf084")
                             #:got (assoc-ref (waybar-password) 'format)
                             #:name
                             "The glyph should be the key, in the solid face that has it")
               ;; The default is the machine's setting, which is also what the
               ;; session starts: one command, two places that cannot drift.
               (assert-equal #:expect (heks-linux-password-command)
                             #:got (waybar-password-program)
                             #:name
                             "The bar should open the machine's password manager")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-password)
                                                     'on-click)
                                          (heks-linux-password-command))))
                            #:name "Clicking it should open that manager")
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-password)
                                                     'on-click)
                                          "pkill rofi")))
                            #:name
                            "An open launcher should be replaced, not left to swallow the click")
               ;; The manager starts at login with --silent, so the window is
               ;; already there and has to be raised: only the compositor can
               ;; hand out the activation token that takes.
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-password)
                                                     'on-click)
                                          "niri msg action spawn")))
                            #:name
                            "It should ask the compositor to raise the window it opens")
               (assert-equal #:expect "keepassxc"
                             #:got
                             (parameterize ((waybar-password-command "keepassxc"))
                               (waybar-password-program))
                             #:name
                             "The bar should be able to choose its own manager")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((heks-linux-password-command
                                                          "flatpak run com.onepassword.OnePassword"))
                                            (assoc-ref (waybar-password)
                                                       'on-click))
                                          "flatpak run com.onepassword.OnePassword")))
                            #:name
                            "A Flatpak install should come through the same setting")
               (assert-equal #:expect (waybar-icon "\uf023")
                             #:got
                             (parameterize ((waybar-password-icon "\uf023"))
                               (assoc-ref (waybar-password) 'format))
                             #:name
                             "The glyph itself should be a setting too")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((waybar-password-label
                                                          "KeePassXC"))
                                            (assoc-ref (waybar-password)
                                                       'tooltip-format))
                                          "KeePassXC")))
                            #:name
                            "The tooltip should name whichever manager the glyph opens")
               (assert-true (not (eq? #f (module-option (waybar-password)
                                                        'tooltip-format)))
                            #:name
                            "The key should say what it opens")
               (assert-equal #:got (css-rule-for "#custom-heks-password")
                             #:expect (css-rule-for "#custom-media")
                             #:name
                             "The key should wear the actions' style")
               (assert-equal #:got (css-rule-for "#custom-heks-password:hover")
                             #:expect (css-rule-for "#custom-media:hover")
                             #:name
                             "So should its hover"))

         (test "The Bar Wears The Mac Menu Bar"
               ;; Mavericks' menu bar: a sheen of light, a lit top edge, a
               ;; hairline at the foot, and text with a shadow so it survives
               ;; the wallpaper.
               (assert-true (not (eq? #f (assoc-ref (assoc-ref (waybar-css)
                                                               "window#waybar")
                                                    'background-image)))
                            #:name "The bar should carry a sheen, not a flat fill")
               (assert-true (not (eq? #f (assoc-ref (assoc-ref (waybar-css)
                                                               "window#waybar")
                                                    'border-top)))
                            #:name "The top edge should be lit")
               (assert-true (not (eq? #f (assoc-ref (assoc-ref (waybar-css)
                                                               "window#waybar")
                                                    'border-bottom)))
                            #:name "The foot of the bar should be drawn")
               (assert-true (not (eq? #f (string-contains
                                          (format #f "~a"
                                                  (assoc-ref (assoc-ref (waybar-css)
                                                                        'module)
                                                             'text-shadow))
                                          "rgba")))
                            #:name
                            "The items should carry the menu bar's text shadow")
               (assert-equal #:expect "0px 8px"
                             #:got (assoc-ref (css-rule-for "#cpu") 'padding)
                             #:name
                             "Items should keep the menu bar's tight spacing"))

         (test "The Bar Is A Material, Not A White Slab"
               ;; The bar is the blurred, saturated wallpaper under a tinted
               ;; veil.  These are the numbers that make it one - and the ones
               ;; that stop it from being a milky strip with a grey band under
               ;; it, which is what a strong gloss over a palette background
               ;; drew.
               (assert-equal #:expect "rgba(242, 243, 245, 0.48)"
                             #:got
                             (parameterize ((heks-linux-palette 'golden-gate-light)
                                            (waybar-bar-tint 0))
                               (assoc-ref (waybar-bar-bg) 'background))
                             #:name
                             "A tint of zero should leave the Mac's neutral material")
               (assert-equal #:expect "rgba(245, 245, 247, 0.48)"
                             #:got
                             (parameterize ((heks-linux-palette 'golden-gate-light)
                                            (waybar-bar-tint 1))
                               (assoc-ref (waybar-bar-bg) 'background))
                             #:name
                             "A tint of one should leave the palette's own background")
               (assert-equal #:expect "rgba(242, 243, 245, 0.8)"
                             #:got
                             (parameterize ((heks-linux-palette 'golden-gate-light)
                                            (waybar-bar-tint 0)
                                            (waybar-bar-opacity 0.8))
                               (assoc-ref (waybar-bar-bg) 'background))
                             #:name
                             "The bar's own opacity should override the palette's")
               (assert-equal #:expect #f
                             #:got
                             (parameterize ((heks-linux-palette 'golden-gate-light))
                               (string-contains
                                (assoc-ref (waybar-bar-bg) 'background-image)
                                "rgba(0, 0, 0,"))
                             #:name
                             "The light bar should not darken toward its foot")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((heks-linux-palette
                                                          'catppuccin-mocha))
                                            (assoc-ref (waybar-bar-bg)
                                                       'background-image))
                                          "rgba(0, 0, 0,")))
                            #:name
                            "The smoked bar should keep a shade at its foot")
               ;; A warm palette still gives a light menu bar, not a beige one:
               ;; that is what the tint toward the neutral material is for.
               (assert-equal #:expect "rgba(238, 231, 212, 0.68)"
                             #:got
                             (parameterize ((heks-linux-palette 'gruvbox-light)
                                            (waybar-bar-tint 0.5))
                               (assoc-ref (waybar-bar-bg) 'background))
                             #:name
                             "A beige palette should give a warm-white bar")
               ;; Every number in that material is a setting, not a literal:
               ;; the two neutral greys, the strength of the sheen, and the
               ;; hover veil are the bar's whole look.
               (assert-equal #:expect "rgba(10, 20, 30, 0.48)"
                             #:got
                             (parameterize ((heks-linux-palette 'golden-gate-light)
                                            (waybar-bar-tint 0)
                                            (waybar-bar-neutral-light "#0a141e"))
                               (assoc-ref (waybar-bar-bg) 'background))
                             #:name
                             "The light material's grey should be a setting")
               (assert-equal #:expect "rgba(40, 50, 60, 0.68)"
                             #:got
                             (parameterize ((heks-linux-palette 'catppuccin-mocha)
                                            (waybar-bar-tint 0)
                                            (waybar-bar-neutral-dark "#28323c"))
                               (assoc-ref (waybar-bar-bg) 'background))
                             #:name
                             "So should the smoked material's")
               (assert-equal #:expect "linear-gradient(180deg, rgba(255, 255, 255, 0.000) 0%, rgba(255, 255, 255, 0.000) 50%, rgba(255, 255, 255, 0.000) 100%)"
                             #:got
                             (parameterize ((heks-linux-palette 'golden-gate-light)
                                            (waybar-bar-sheen 0))
                               (assoc-ref (waybar-bar-bg) 'background-image))
                             #:name
                             "A sheen of zero should leave a flat strip")
               (assert-equal #:expect "rgba(56, 58, 66, 0.3)"
                             #:got
                             (parameterize ((heks-linux-palette 'doom-one-light)
                                            (waybar-hover-opacity 0.3))
                               (assoc-ref (css-rule-for "#cpu:hover")
                                          'background))
                             #:name
                             "The hover veil's strength should be a setting")
               (assert-equal #:expect "3px"
                             #:got
                             (parameterize ((waybar-hover-radius "3px"))
                               (assoc-ref (css-rule-for "#cpu:hover")
                                          'border-radius))
                             #:name
                             "So should its corner radius")
               ;; The escape hatch: CSS nobody wrote a parameter for still has
               ;; a way into the generated file, and it comes last.
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((waybar-extra-css
                                                          "#clock { letter-spacing: 1px; }"))
                                            (waybar-style))
                                          "#clock { letter-spacing: 1px; }")))
                            #:name
                            "Extra CSS should be appended to the stylesheet")
               (assert-true (string-suffix? "#clock { letter-spacing: 1px; }"
                                            (parameterize ((waybar-extra-css
                                                            "#clock { letter-spacing: 1px; }"))
                                              (waybar-style)))
                            #:name
                            "The machine's CSS should be the stylesheet's last word"))

         (test "Every Control Lights Up Under The Pointer"
               ;; A Mac's menu bar does not tint the item it is about to open,
               ;; it darkens the material under the pointer.  Every item that
               ;; answers a click (or a wheel) should answer the pointer the
               ;; same way, and the ones that answer nothing should not.
               (assert-true (not (eq? #f (css-rule-for "#cpu:hover")))
                            #:name "A readout that opens a menu should light up")
               (assert-equal #:got (css-rule-for "#cpu:hover")
                             #:expect (css-rule-for "#clock:hover")
                             #:name "The clock should wear the same highlight")
               (assert-equal #:got (css-rule-for "#custom-heks-password:hover")
                             #:expect (css-rule-for "#custom-media:hover")
                             #:name
                             "An action should wear the same highlight as its neighbours")
               (assert-equal #:got (css-rule-for "#custom-heks-system-menu:hover")
                             #:expect (css-rule-for "#custom-media:hover")
                             #:name "The wordmark included")
               (assert-equal #:expect #f
                             #:got (css-rule-for "#tray:hover")
                             #:name
                             "The tray belongs to other programs, so the bar leaves it alone"))

         (test "Do Not Disturb Indicator"
               (assert-true (not (eq? #f (string-contains
                                          (assoc-ref (waybar-mako-dnd)
                                                     'on-click)
                                          "makoctl mode -t do-not-disturb")))
                            #:name
                            "Clicking the indicator should toggle the mako DND mode"))

         (test "One Ink, No Accent"
               ;; Mavericks' menu bar has no accent colour in it at all: the
               ;; brightest thing there is the frontmost application's name, and
               ;; it is bright because it is bold.  The bar follows that, so the
               ;; palette's accent appears nowhere and every item is painted in
               ;; the same ink - the two battery alarms excepted, which are not
               ;; decoration but the same red OS X turns its battery to.
               (assert-equal #:expect #f
                             #:got (string-contains (format #f "~s"
                                                            (waybar-css))
                                                    "primary")
                             #:name
                             "The palette's accent should appear nowhere in the bar")
               (assert-equal #:expect #f
                             #:got (string-contains (format #f "~s"
                                                            (waybar-css))
                                                    "text-l")
                             #:name
                             "The bar should not keep a second, dimmer ink")
               (assert-equal #:expect '()
                             #:got (remove (lambda (value)
                                             (member value
                                                     (list (bar-ink)
                                                           "#ff9e3b"
                                                           "#e82424")))
                                           (css-values 'color))
                             #:name
                             "Every item should be painted in the palette's one ink")
               (assert-true (not (eq? #f (assoc 'color (css-rule-for "#battery.warning"))))
                            #:name
                            "The low battery should still be the one exception")
               ;; Hovers are a veil of the bar's own ink, never a colour of their
               ;; own: the power button used to flash red at the cursor.
               (assert-equal #:expect '()
                             #:got (remove (lambda (value)
                                             (let ((text (format #f "~a" value)))
                                               (or (string=? text "transparent")
                                                   (string-contains text "rgba("))))
                                           (css-values 'background))
                             #:name
                             "Every background should be the strip or a veil of the ink"))

         (test "Keyboard Layout Item"
               ;; A menu bar names a layout in two letters.  Waybar's own
               ;; niri/language module only knows the full name, which is why
               ;; this is a custom item with a label script and a menu behind it.
               (assert-equal #:expect 'custom/heks-language
                             #:got (car (waybar-language))
                             #:name "The layout should be the bar's own custom item")
               (assert-equal #:expect 8
                             #:got (assoc-ref (waybar-language) 'signal)
                             #:name
                             "The label should repaint on the bar's layout signal")
               (assert-equal #:expect "once"
                             #:got (assoc-ref (waybar-language) 'interval)
                             #:name
                             "The label is not a poll: the menu pokes it")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-label)
                                          "niri msg keyboard-layouts")))
                            #:name "The label reads the layouts from the compositor")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-label)
                                          "CODES=(\"us\")")))
                            #:name
                            "The label bakes in the configured layouts, in the compositor's order")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-menu)
                                          "switch-layout")))
                            #:name
                            "The menu switches the layout through the compositor")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-menu)
                                          "RTMIN+8")))
                            #:name
                            "The menu pokes the bar so the label repaints at once")
               (assert-true (not (eq? #f (string-contains
                                          (waybar-language-menu)
                                          "lines: $lines")))
                            #:name
                            "The menu is only as tall as the layouts it lists"))

         (test "Rounded Bar Styling"
               (assert-equal #:expect "0px"
                             #:got
                             (assoc-ref (assoc-ref (waybar-css)
                                                   "window#waybar")
                                        'border-radius)
                             #:name
                             "The floating bar should carry the configured corner radius")
               (assert-equal #:expect "0px"
                             #:got
                             (parameterize ((waybar-border-radius "0px"))
                               (assoc-ref (assoc-ref (waybar-css)
                                                     "window#waybar")
                                          'border-radius))
                             #:name
                             "The bar corner radius should be overridable"))

         (test "CSS Rules Generation"
               (assert-true (not (null? (waybar-css)))
                            #:name "CSS list should not be empty")
               (assert-true (not (eq? #f (assoc-ref (waybar-css)
                                                    "window#waybar")))
                            #:name "CSS should contain a rule for the waybar window")
               (assert-equal #:expect 'transparent
                             #:got (assoc-ref (assoc-ref (waybar-css)
                                                         'module)
                                              'background)
                             #:name
                             "Module background should be transparent in CSS"))))

(define (spec)
  (veritas-run waybar-suite))
