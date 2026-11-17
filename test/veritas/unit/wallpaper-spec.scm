;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux wallpaper) after the port to whelk.
;;
;; The module no longer draws anything: whelk owns the layer surface, the
;; transition, the rotation and the picker.  What is left here is the half whelk
;; cannot know - which pictures go with which palette - and the one command a
;; keybinding runs, so the tests are about that half: the curated sets, the
;; interval written the way a person says it, the fit words kept from the old
;; engine, and the preference file the front end writes where whelk reads it.

;;; Code:

(define-module (veritas unit wallpaper-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux wallpaper)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux palette)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:export (spec))

(define (palette-list)
  "Return every palette name the project ships."
  (palette-names))

(define (wallpaper-set palette)
  "Return the pictures @var{palette} curates."
  (parameterize ((heks-linux-palette palette))
    (wallpapers)))

(define (every-palette-has-pictures?)
  "Return #t when no palette answers with an empty set."
  (every (lambda (palette)
           (not (null? (wallpaper-set palette))))
         (palette-list)))

(define (pictures-are-usable-paths?)
  "Return #t when every picture is absolute and names an image file."
  (every (lambda (palette)
           (every (lambda (path)
                    (and (string-prefix? "/" path)
                         (or (string-suffix? ".png" path)
                             (string-suffix? ".jpg" path)
                             (string-suffix? ".jpeg" path))))
                  (wallpaper-set palette)))
         (palette-list)))


(define (interval-suite)
  (suite "Rotation interval"
    (test "A Person's Spelling Is Read As Seconds"
      (parameterize ((wallpaper-rotation-interval "1h30m"))
        (assert-equal #:expect 5400
                      #:got (wallpaper-interval-seconds)
                      #:name "1h30m is ninety minutes")))
    (test "Minutes Are Minutes"
      (parameterize ((wallpaper-rotation-interval "45m"))
        (assert-equal #:expect 2700
                      #:got (wallpaper-interval-seconds)
                      #:name "45m is forty-five minutes")))
    (test "A Bare Number Is Seconds"
      (parameterize ((wallpaper-rotation-interval "90"))
        (assert-equal #:expect 90
                      #:got (wallpaper-interval-seconds)
                      #:name "90 is ninety seconds")))
    (test "An Empty Value Falls Back"
      (parameterize ((wallpaper-rotation-interval ""))
        (assert-equal #:expect 5400
                      #:got (wallpaper-interval-seconds)
                      #:name "An empty value is the default interval")))))

(define (fit-suite)
  (suite "Fit policy"
    (test "fill Crops"
      (parameterize ((wallpaper-scaling "fill"))
        (assert-equal #:expect 'cover
                      #:got (wallpaper-fit)
                      #:name "fill is whelk's cover")))
    (test "fit Letterboxes"
      (parameterize ((wallpaper-scaling "fit"))
        (assert-equal #:expect 'contain
                      #:got (wallpaper-fit)
                      #:name "fit is whelk's contain")))
    (test "stretch Distorts"
      (parameterize ((wallpaper-scaling "stretch"))
        (assert-equal #:expect 'fill
                      #:got (wallpaper-fit)
                      #:name "stretch is whelk's fill")))))

(define (whelk-form-suite)
  (suite "Whelk settings"
    (test "The Form Carries The Palette's Pictures"
      (parameterize ((heks-linux-palette 'kanagawa))
        (let ((form (wallpaper-whelk-form)))
          (assert-true (if (memv #:paths form) #t #f)
                       #:name "The form hands whelk a path list")
          (assert-true (not (eq? #f (string-contains (format #f "~s" form)
                                                     "wallpapers/kanagawa.jpg")))
                       #:name "kanagawa's picture is the one in the catalog")
          (assert-equal #:expect (length (wallpapers))
                        #:got (- (length (cadr (memv #:paths form))) 1)
                        #:name "Every picture of the palette is handed over"))))
    (test "The Interval Is In Seconds"
      (parameterize ((wallpaper-rotation-interval "1h30m"))
        (assert-equal #:expect 5400
                      #:got (cadr (memv #:interval (wallpaper-whelk-form)))
                      #:name "1h30m is handed over as 5400")))
    (test "The Form Starts Nothing"
      (assert-true (not (eq? #f (string-contains
                                 (format #f "~s" (wallpaper-whelk-form))
                                 "#:paths")))
                   #:name "The form is settings, not a unit"))))

(define (front-end-suite)
  (suite "Front end"
    (test "The Command Names The Installed Launcher"
      (parameterize ((wallpaper-script-dir "/tmp/heks-bin")
                     (wallpaper-script-filename "heks-wallpaper"))
        (assert-equal #:expect "/tmp/heks-bin/heks-wallpaper"
          #:got (wallpaper-script-command)
          #:name "The command is absolute")))
    (test "The Candidate List Is One Absolute Path Per Line"
      (let ((lines (string-split (wallpaper-candidates-file) #\newline))
            (pictures (wallpaper-candidates)))
        (assert-equal #:expect (length pictures)
          #:got (length lines)
          #:name "One line per picture")
        (assert-true (every (lambda (line) (string-prefix? "/" line)) lines)
          #:name "Every line is absolute")
        (assert-equal #:expect pictures
          #:got (sort lines string<?)
          #:name "The list is the sorted set")))
    (test "The Launcher Gives The Shim Its Paths"
      (let ((script (wallpaper-shim-script)))
        (assert-true (string-contains script "DO NOT EDIT")
          #:name "The launcher says it is generated")
        (assert-true (string-contains script "HEKS_WALLPAPER_LIST=")
          #:name "The candidate list is exported")
        (assert-true (string-contains script "HEKS_WALLPAPER_PREFERENCES=")
          #:name "The preference file is exported")
        (assert-true (string-contains script "(heks-linux wallpaper-shim)")
          #:name "The Scheme half is what runs"))))
    (test "Whelk's Preference File Is Where Whelk Reads It"
      (assert-true (string-suffix? "whelk/preferences-settings.scm"
                                   (wallpaper-preferences-file))
        #:name "The path ends in whelk's settings file")))

(define (catalogue-suite)
  (suite "Palette catalogue"
    (test "Every Palette Curates Something"
      (assert-true (every-palette-has-pictures?)
        #:name "No palette is left without a background"))
    (test "Every Picture Is An Absolute Image Path"
      (assert-true (pictures-are-usable-paths?)
        #:name "A relative path or a non-image is a broken background"))
    (test "The Same Palette Curates The Same Set Twice"
      (assert-equal #:expect (wallpaper-set 'rose-pine)
        #:got (wallpaper-set 'rose-pine)
        #:name "Selection is a function of the palette"))
    (test "Two Palettes Do Not Share One Set"
      (assert-true (not (equal? (wallpaper-set 'kanagawa)
                                (wallpaper-set 'catppuccin-mocha)))
        #:name "The mapping is per palette, not global"))))

(define (spec)
  (veritas-run
   (interval-suite)
   (fit-suite)
   (whelk-form-suite)
   (front-end-suite)
   (catalogue-suite)))
