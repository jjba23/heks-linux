;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux whelk).
;;
;; The rendered file is a Guile program, so the tests read it back and ask the
;; tree what the shell will be told, instead of looking for a substring of a
;; template: @code{read} either returns the form whelk is going to evaluate or
;; fails, which is a stronger claim than any search through the text.

;;; Code:

(define-module (veritas unit whelk-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux whelk)
  #:use-module (ice-9 control)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define* (rendered-settings #:key (palette 'modus-vivendi-tinted))
  "Return the settings file for @var{palette}, read back as a tree."
  (read (open-input-string (whelk-config #:palette palette
                                         #:sans-font "Work Sans"))))

(define (find-form tree head)
  "Return the first sub-form of @var{tree} whose car is @var{head}."
  (cond
    [(not (pair? tree)) #f]
    [(and (symbol? (car tree))
       (eq? (car tree) head))
     tree]
    [else (or (find-form (car tree) head)
            (find-form (cdr tree) head))]))

(define* (bar-kv key #:key (palette 'modus-vivendi-tinted))
  "Return the bar's value for @var{key} in the settings file.

A value written as @code{'top} reads back as @code{(quote top)}, so the quote
is unwrapped here: the test asks what the bar will be, not how it is spelled."
  (let* ((bar (find-form (rendered-settings #:palette palette) 'bar))
         (value (let ((pair (memq key (cdr bar))))
                  (and pair (cadr pair)))))
    (unquoted value)))

(define (unquoted value)
  "Return @var{value} without the quote a literal reads back with.

A value written as @code{'((key . value))} reads back as
@code{(quote ((key . value)))}: the file is a program, so a test that asks what
the value *is* unwraps the spelling."
  (if (and (pair? value) (eq? (car value) 'quote))
    (cadr value)
    value))

(define (called-symbols tree)
  "Return every symbol that heads a form in @var{tree}, but @code{quote}.

The rendered file is a program, so a list whose head is a symbol is a call whelk
resolves, and a list whose head is a pair is not a call at all: it is the
mistake this walks for."
  (let walk ((node tree) (found '()))
    (if (pair? node)
      (walk (car node)
            (walk (cdr node)
                  (let ((head (car node)))
                    (if (and (symbol? head) (not (eq? head 'quote))
                          (not (memq head found)))
                      (cons head found)
                      found))))
      found)))

(define (evaluates? form)
  "Return @code{#t} when @var{form} runs with every procedure it calls stubbed.

whelk loads the file by evaluating it, and a syntax error in the file is not a
throw: the handler has to escape instead of returning."
  (let ((module (make-module)))
    (module-use! module (resolve-module '(guile)))
    (for-each (lambda (head)
                (module-define! module head (lambda* (#:rest args) args)))
              (called-symbols form))
    (eq? 'evaluated
         (call/ec (lambda (escape)
                    (with-exception-handler
                      (lambda (exn) (escape #f))
                      (lambda ()
                        (eval form module)
                        'evaluated)))))))

(define (mentions? text fragment)
  "Return @code{#t} when @var{text} contains @var{fragment}.

@code{string-contains} answers with the index it found the fragment at, which
@code{assert-true} reads as a number rather than as the truth it meant."
  (if (string-contains text fragment) #t #f))

(define (row-commands row)
  "Return every command @var{row} carries, whichever mouse button runs it.

A row's left click and its right click are two different commands, and the two
heks-toon views share one glyph: the question mark opens the reference on a
click and the documentation on a right click."
  (let loop
    ((keys '(#:on-click #:on-click-right #:on-click-middle)) (acc '()))
    (if (null? keys)
      (reverse acc)
      (let ((pair (memq (car keys) (cdr row))))
        (loop (cdr keys)
              (if pair
                (cons (cadr pair) acc)
                acc))))))

(define (row-clicks rows)
  "Return the commands every bar row carries, as one flat list."
  (let loop
    ((rest rows) (acc '()))
    (if (null? rest)
      (reverse acc)
      (loop (cdr rest) (append (reverse (row-commands (car rest))) acc)))))

;; --- The suites ---

(define render-suite
  (suite "Whelk settings file"
    (test "The file is one program whelk can evaluate"
      (assert-equal #:expect 'configure-shell!
        #:got (car (rendered-settings))
        #:name
        "The rendered file should read back as the call whelk evaluates")
      (assert-true (not (eq? #f (string-contains (whelk-config)
                                                 "generated by heks-linux")))
        #:name "The file should say that it is generated"))

    (test "A bar is the top edge, reserved and one thickness"
      (assert-equal #:expect 'top #:got (bar-kv #:position)
        #:name "A menu bar belongs at the top")
      (assert-equal #:expect 'top #:got (bar-kv #:layer)
        #:name
        "A top-layer bar stays put while niri's overview zooms the workspaces")
      (assert-equal #:expect #t #:got (bar-kv #:exclusive?)
        #:name
        "The bar should reserve its edge so maximised windows stop at it")
      (assert-equal #:expect (whelk-bar-height)
        #:got (bar-kv #:height)
        #:name
        "The bar's thickness should be the one value the rest of the tree reads")
      (assert-equal #:expect 40
        #:got (parameterize ((whelk-bar-height 40))
                (bar-kv #:height))
        #:name "A machine should be able to draw a thicker bar"))

    (test "The launcher starts at the geometry this tree asks for"
      (assert-equal #:expect 720 #:got (bar-kv #:launcher-width)
        #:name "The launcher should start wider than the shell's own default")
      (assert-equal #:expect 680 #:got (bar-kv #:launcher-height)
        #:name "The launcher should start tall enough for a full result list")
      (assert-equal #:expect 28 #:got (bar-kv #:launcher-icon-size)
        #:name "The icons should read at the bar's 11pt scale")
      (assert-equal #:expect 110 #:got (bar-kv #:launcher-font-scale)
        #:name "The launcher's text should be a little larger than the bar's")
      (assert-equal #:expect 800
        #:got (parameterize ((whelk-launcher-width 800))
                (bar-kv #:launcher-width))
        #:name "A machine should be able to choose a wider launcher"))

    (test "The bar is on every output, always"
      (assert-equal #:expect "all" #:got (bar-kv #:monitor)
        #:name "One bar should land on whatever output is connected")
      (assert-equal #:expect '() #:got (bar-kv #:monitors)
        #:name
        "No connector list should pin the bar to yesterday's screens")
      (assert-equal #:expect 'always #:got (bar-kv #:when)
        #:name
        "The bar should not come and go with the number of outputs"))

    (test "The material is gloss-2007's, written out"
      ;; The bar takes the theme's material as its starting point, and these are
      ;; the six numbers that theme sets.  They are in the file so a machine can
      ;; change one of them without choosing another theme for the whole bar,
      ;; which means a drift from the theme has to be an edit and not a typo.
      (for-each
       (lambda (pair)
         (assert-equal #:expect (cadr pair)
           #:got (bar-kv (car pair))
           #:name
           (format #f "~a should be the theme's own value" (car pair))))
       '((#:radius 10)
         (#:blur 18)
         (#:shine 0.38)
         (#:reflection 0.10)
         (#:flare 0.12)
         (#:opacity 1.0))))

    (test "The CSS escape hatch does not silently drop the theme"
      ;; whelk takes a bar's `#:css' *instead of* the theme's rule, so writing
      ;; the empty string would quietly turn the theme's square slab into
      ;; whatever the structural stylesheet rounds to.
      (assert-equal #:expect #f #:got (bar-kv #:css)
        #:name "An unset escape hatch should leave the theme in charge")
      (assert-equal #:expect ".whelk-bar { border-radius: 24px; }"
        #:got (parameterize ((whelk-extra-css
                              ".whelk-bar { border-radius: 24px; }"))
                (bar-kv #:css))
        #:name "A machine that writes CSS should have it used instead"))

    (test "The left half is a menu bar's"
      (let* ((bar (find-form (rendered-settings) 'bar))
             ;; The value is the `(list ...)' form the file spells, so the head
             ;; is the symbol `list' and the modules start after it.
             (left (cdr (cadr (memq #:left (cdr bar))))))
        (assert-equal #:expect '(start-module menu-module)
          #:got (map car left)
          #:name
          "The machine's own menu, then the focused application's File/Edit/View")))

    (test "Every non-empty module list is a list form"
      ;; A bare `((custom-module ...) ...)' is an application, not a list: the
      ;; first module would be called as a procedure when whelk loads the
      ;; file.  Each non-empty row has to spell `(list ...)' instead.
      (for-each
       (lambda (key)
         (let ((value (bar-kv key)))
           (assert-equal #:expect 'list
             #:got (car value)
             #:name
             (format #f "~a should be a (list ...) form" key))))
       '(#:left #:right #:overflow)))))

(define palette-suite
  (suite "Whelk follows the palette"
    (test "The bar's background is the palette's, tinted and translucent"
      (assert-equal #:expect
        (hex-to-rgba (whelk-bar-base #:palette 'modus-vivendi-tinted)
                     #:alpha
                     (get-whelk-opacity 'modus-vivendi-tinted))
        #:got (bar-kv #:background)
        #:name
        "The background should be the tinted palette colour at its own opacity")
      (assert-true (not (equal? (bar-kv #:background)
                                (bar-kv #:background
                                        #:palette 'golden-gate-light)))
        #:name
        "A light palette should get a different bar than a dark one"))

    (test "The ink is measured against the bar, not against the palette"
      (assert-equal #:expect
        (readable-ink (whelk-bar-base #:palette 'rose-pine-dawn)
                      (list (get-color 'rose-pine-dawn 'text)
                            (get-color 'rose-pine-dawn 'primary)))
        #:got (bar-kv #:foreground #:palette 'rose-pine-dawn)
        #:name
        "The bar's text should be an ink the bar's own background can carry")
      (assert-true (>= (contrast-ratio (bar-kv #:foreground
                                               #:palette 'rose-pine-dawn)
                                       (whelk-bar-base #:palette
                                                       'rose-pine-dawn))
                       4.5)
        #:name
        "The ink should clear WCAG AA on the bar it is drawn on"))

    ;; Not one palette, every palette: the bar has a colour of its own and a
    ;; palette only tints it, so a palette whose own ink is too quiet for the
    ;; tinted bar is the case this fallback exists for.
    (for-each (lambda (palette)
                (assert-true (>= (contrast-ratio
                                  (bar-kv #:foreground #:palette palette)
                                  (whelk-bar-base #:palette palette))
                                 4.5)
                  #:name
                  (format #f
                          "The bar's ink should be legible in ~a too"
                          palette)))
              (palette-names))

    (test "The accent and the hairline come from the palette"
      (assert-equal #:expect (get-color 'nord 'primary)
        #:got (bar-kv #:accent #:palette 'nord)
        #:name "The accent should be the palette's primary colour")
      (assert-equal #:expect (hex-to-rgba (get-color 'nord 'text-l)
                                          #:alpha 0.15)
        #:got (bar-kv #:border-color #:palette 'nord)
        #:name "The rim should be the quiet ink at the launcher's own alpha"))

    (test "The tint is a setting"
      (assert-equal #:expect (get-color 'nord 'background)
        #:got (parameterize ((whelk-bar-tint 0))
                (whelk-bar-base #:palette 'nord))
        #:name "A tint of zero leaves the bar the reference's neutral grey")
      (assert-true (not (equal? (whelk-bar-base #:palette 'nord)
                                (get-color 'nord 'background)))
        #:name
        "The default should move the palette's background toward that grey"))))

(define surface-suite
  (suite "Whelk covers the four programs it replaces"
    (test "The right half carries the readings and the panels"
      (let ((kinds (map car (whelk-rows))))
        (for-each (lambda (kind)
                    (assert-true (if (memq kind kinds) #t #f)
                      #:name
                      (format #f "The bar should carry a ~a" kind)))
                  '(clipboard-module dnd-module notifications-module
                                     tray-module wifi-module bluetooth-module
                                     battery-module audio-module
                                     power-profile-module memory-module
                                     keyboard-module clock-module))))

    (test "The chevron shelves what is read once in a while"
      ;; The split is whelk's own bar's: the load, the ways into the desktop's
      ;; views, the keyboard layout and the brightness are built with the bar
      ;; and kept behind the chevron, so the row that has to fit between the
      ;; menu and the clock stays the row that gets used.
      (assert-equal #:expect
        '(cpu-module custom-module wallpaper-module custom-module
                     language-module backlight-module)
        #:got (map car (whelk-overflow-rows))
        #:name
        "The shelf should hold the load, the two views, the wallpapers, the layout and the brightness")
      (assert-equal #:expect #f
        #:got (bar-kv #:overflow-expanded?)
        #:name
        "The shelf should start closed: an open shelf eats the width it saves")
      (let ((shown (map car (whelk-rows))))
        (for-each (lambda (kind)
                    (assert-true (if (memq kind shown) #f #t)
                      #:name
                      (format #f "~a belongs on the shelf, not on the row" kind)))
                  '(cpu-module language-module backlight-module))))

    (test "The bar launches heks-toon's views"
      ;; The glyphs are the bar's way into the window, and the entry point is
      ;; the program the desktop entry names: a glyph whose command drifted
      ;; would be a button that opens nothing.  The reference has no view
      ;; argument - it is the window's first view - so it is the bare program.
      ;; The wallpapers are not one of them: whelk opens its own menu for them,
      ;; so the glyphs that still leave the shell are the palette and the docs,
      ;; and the question mark.  They are on the shelf, so the clicks are asked
      ;; for across both rows.
      (let ((joined (string-join (row-clicks (append (whelk-rows)
                                                     (whelk-overflow-rows)))
                                 "\n")))
        (for-each (lambda (view)
                    (assert-true (mentions? joined (format #f "heks-toon ~a"
                                                           view))
                      #:name
                      (format #f
                              "A bar glyph should open heks-toon's ~a view"
                              view)))
                  '("palettes" "docs"))
        (assert-true (mentions? joined "heks-toon")
          #:name "The question mark should open the keyboard reference")))

    (test "The wallpapers are whelk's own, not a view in heks-toon"
      ;; A click on the wallpaper glyph opens whelk's menu of thumbnails, and a
      ;; right click shuffles it: nothing about the collection leaves the shell,
      ;; so the rendered file names whelk's own reading and no toon view.
      (let ((text (whelk-config)))
        (assert-true (mentions? text "wallpaper-module")
          #:name "The bar's wallpaper glyph should be whelk's own reading")
        (assert-true (eq? #f (string-contains text "heks-toon walls"))
          #:name "Nothing in the bar should open heks-toon's walls view")))

    (test "The launcher, the locker and the panels are whelk's own"
      (let ((text (whelk-config)))
        (for-each (lambda (retired)
                    (assert-true (eq? #f (string-contains text retired))
                      #:name
                      (format #f "The rendered file should not name ~a" retired)))
                  '("swaylock" "waybar")))
      (assert-true (mentions? (whelk-config) "whelk --launcher")
        #:name "A click on the search glyph should open whelk's launcher"))

    (test "The lock screen is whelk's, not a second laptop"
      (assert-equal #:expect "whelk --lock" #:got (whelk-lock-command)
        #:name
        "The binding that locks the session should reach the shell's own locker")
      (assert-equal #:expect "whelk --dnd" #:got (whelk-dnd-command)
        #:name
        "Do not disturb is the shell's state, not a mode in another daemon's file"))

    (test "The rendered file runs, so whelk can load it"
      ;; whelk evaluates this file, so the form printed here is the program that
      ;; draws the shell.  Reading it back as a tree cannot tell the alist a card
      ;; wants from a call to a pair, which is how a card whose options were
      ;; spliced in unquoted reached the desktop as "settings file was rejected";
      ;; running it with every procedure stubbed can.
      (assert-true (evaluates? (rendered-settings))
        #:name "Every form in the file should be one whelk can evaluate"))

    (test "The desktop shows whelk's own cards, one form each"
      ;; The card list is the settings file's, not a preset asked for by name: a
      ;; machine that starts whelk without a cards line gets a bar and an empty
      ;; desktop, so the file has to spell every card it wants.  The order is
      ;; the Golden Gate set's, which is the order whelk draws with no settings
      ;; file at all.
      (let ((widgets (cadr (memq #:widgets (cdr (rendered-settings))))))
        (assert-equal #:expect 'list
          #:got (car widgets)
          #:name "The cards should be spliced into one list form")
        (assert-equal #:expect
          '(clock calendar weather battery notes reminders world-clock stocks)
          #:got (map (lambda (card) (cadr (cadr card))) (cdr widgets))
          #:name "The list should be the Golden Gate set, in its own order")
        (assert-equal #:expect '(desktop-widget 32 64)
          #:got (list (car (cadr widgets))
                      (cadr (memq #:x (cdr (cadr widgets))))
                      (cadr (memq #:y (cdr (cadr widgets)))))
          #:name
          "A card should be a desktop-widget form with its own place on the screen")))

    (test "The weather is Amsterdam and the stocks are the Dutch names"
      ;; whelk reads these two options as text: a Scheme number for a coordinate
      ;; or a list for the symbols reaches the runtime as something that is not
      ;; text, is ignored, and leaves the card on whelk's built-in San Francisco
      ;; and AAPL/MSFT/NVDA.  The rendered shape is therefore part of the
      ;; promise, not an implementation detail.
      (let* ((widgets (cadr (memq #:widgets (cdr (rendered-settings)))))
             (card (lambda (kind)
                     (find (lambda (w)
                             (eq? (cadr (cadr w)) kind))
                           (cdr widgets))))
             (option (lambda (kind key)
                       (cdr (assq key
                                  (unquoted (cadr (memq #:options
                                                        (cdr (card kind))))))))))
        (assert-equal #:expect "Amsterdam"
          #:got (option 'weather 'location)
          #:name "The weather card names Amsterdam")
        (assert-equal #:expect "52.3676"
          #:got (option 'weather 'latitude)
          #:name "Amsterdam's latitude is written as text")
        (assert-equal #:expect "4.9041"
          #:got (option 'weather 'longitude)
          #:name "Amsterdam's longitude is written as text")
        (assert-equal #:expect 'metric
          #:got (option 'weather 'units)
          #:name "The card reads in Celsius")
        (assert-equal #:expect
          "AD.AS,ASML.AS,HEIA.AS,INGA.AS,PHIA.AS,ADYEN.AS"
          #:got (option 'stocks 'symbols)
          #:name "Ahold Delhaize and five other Euronext Amsterdam names")
        (assert-true (string? (option 'stocks 'symbols))
          #:name "The symbols are one comma-separated line, as whelk reads them")))

    (test "One idle manager decides when the screen locks"
      ;; whelk owns the logind hint, the countdown and the lock screen; a
      ;; second idle daemon would be a second policy for the same session.
      (assert-equal #:expect '(idle-settings #:lock-after 300)
        #:got (cadr (memq #:idle (cdr (rendered-settings))))
        #:name "Five idle minutes, counted by the shell"))

    (test "The clipboard keeps a bounded history and forgets it on lock"
      (let ((clipboard (cadr (memq #:clipboard (cdr (rendered-settings))))))
        (assert-equal #:expect 'clipboard-settings
          #:got (car clipboard)
          #:name "The policy should be whelk's own record")
        (assert-equal #:expect #f
          #:got (cadr (memq #:persist (cdr clipboard)))
          #:name "Nothing should be written to disk by default")
        (assert-equal #:expect #f
          #:got (cadr (memq #:persist-only-pinned? (cdr clipboard)))
          #:name "A history that does not persist has nothing to vault")
        (assert-true (eq? #t (cadr (memq #:clear-on-lock? (cdr clipboard))))
          #:name "Unpinned copies should go when the session locks")
        (assert-equal #:expect 50
          #:got (cadr (memq #:max-entries (cdr clipboard)))
          #:name "The history should stop at whelk's fifty entries")
        (assert-equal #:expect '(* 32 1024 1024)
          #:got (cadr (memq #:max-entry-bytes (cdr clipboard)))
          #:name "One entry should be capped at thirty-two megabytes")
        (assert-equal #:expect '(* 128 1024 1024)
          #:got (cadr (memq #:max-total-bytes (cdr clipboard)))
          #:name "The whole history should be capped at a hundred and twenty-eight")
        (assert-equal #:expect 3600
          #:got (cadr (memq #:ttl-seconds (cdr clipboard)))
          #:name "Unpinned copies should expire after an hour")))

    (test "The launcher's radius is one value the compositor can read"
      (assert-equal #:expect 16 #:got (whelk-window-radius)
        #:name
        "Sixteen is whelk's own floor for the launcher's corners")
      (assert-equal #:expect 20
        #:got (parameterize ((whelk-window-radius 20))
                (whelk-window-radius))
        #:name
        "The same number is what niri rounds the launcher's shadow with"))

    (test "The bar's radius is one value the compositor can read too"
      ;; The bar, the panels that drop from it and the desktop's cards all round
      ;; their corners with the bar's radius, and niri rounds the blur behind
      ;; them with the same number: a rule at another radius leaves a square
      ;; patch of blur showing past a rounded corner.
      (assert-equal #:expect 10 #:got (whelk-bar-radius)
        #:name "gloss-2007's own radius should be the bar's")
      (assert-equal #:expect 8
        #:got (parameterize ((whelk-bar-radius 8))
                (bar-kv #:radius))
        #:name "and the setting should reach the bar whelk draws"))))

(define (spec)
  (veritas-run render-suite palette-suite surface-suite))
