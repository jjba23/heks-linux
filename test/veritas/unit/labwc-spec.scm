;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux labwc): the floating session's five files.
;;
;; Every one of them is read by a program that fails when it is wrong - an XML
;; file that is not XML is a menu that does not open, an autostart that starts
;; the bar twice draws it twice - so the tests pin the shape of each file and the
;; one policy that is this project's: floating windows by default, decorations in
;; the palette's colours.

;;; Code:

(define-module (veritas unit labwc-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux labwc)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux services)
  #:use-module (heks-linux ssh)
  #:use-module (heks-linux user-settings)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (holds? text fragment)
  "Return #t when @var{text} contains @var{fragment}."
  (if (string-contains text fragment) #t #f))

(define (rc-suite)
  (suite "rc.xml"
    (test "The Document Is XML"
      (assert-true (holds? (labwc-rc-xml) "<?xml version=")
        #:name "The file starts with an XML declaration")
      (assert-true (holds? (labwc-rc-xml) "<labwc_config>")
        #:name "The document names the program's root element")
      (assert-true (holds? (labwc-rc-xml) "</labwc_config>")
        #:name "The document is closed"))
    (test "The Tree Escapes What It Prints"
      (parameterize ((labwc-sans-font "Work & Co"))
        (assert-true (holds? (labwc-rc-xml) "<name>Work &amp; Co</name>")
          #:name "A font name is data, not markup"))
      (assert-true (holds? (labwc-rc-xml)
                           "<action name=\"Execute\"><command>kitty</command></action>")
        #:name "Execute takes its command as a child element"))
    (test "The Session States Its Policy"
      (assert-true (holds? (labwc-rc-xml) "<theme>")
        #:name "The theme is named")
      (assert-true (holds? (labwc-rc-xml) "<policy>")
        #:name "The placement policy is stated"))
    (test "The Palette Paints The Decorations"
      (assert-true (holds? (labwc-themerc)
                           (get-color (labwc-palette) 'background))
        #:name "The window background is the palette's"))
    (test "Every Binding Is Complete"
      (assert-true (if (every (lambda (binding)
                                (and (assq 'key binding)
                                  (assq 'cmd binding)
                                  (assq 'desc binding)))
                              (labwc-bindings))
                     #t #f)
        #:name "A binding is a chord, an action and a description"))
    (test "The Terminal Chord Survives The Second Session"
      (assert-true (holds? (format #f "~s" (map (lambda (binding)
                                                  (cdr (assq 'key binding)))
                                                (labwc-bindings)))
                           "W-t")
        #:name "Mod+t opens a terminal here too"))
    (test "The Session Has The Chords The Other One Has"
      ;; The two sessions are one desktop managed two ways: a person switching
      ;; between them should not lose the media keys, the restarts, the capture
      ;; or the reference the tiling session has.  What cannot follow is the
      ;; tiling verbs themselves - a stacking compositor has no columns to
      ;; consume or expel - so this is not the whole list, it is the half that
      ;; means the same in both.
      (let ((keys (map (lambda (binding) (cdr (assq 'key binding)))
                       (labwc-bindings))))
        (for-each (lambda (key)
                    (assert-true (and (member key keys) #t)
                      #:name (format #f "~a is bound here too" key)))
                  '("XF86AudioPlay" "XF86AudioPrev" "XF86AudioNext"
                    "W-C-w" "W-C-e" "W-S-d" "W-S-/" "W-S-g" "W-S-r"
                    "W-x" "W-S-x" "W-S-/"))))
    (test "Every Desktop Has A Key"
      ;; Four desktops with no chord to reach three of them is four desktops and
      ;; one, and the scroll on the desktop is not a thing anybody finds: the
      ;; numbered chords go there, and the shifted ones take the window along.
      (let ((rc (labwc-rc-xml)))
        (assert-true (holds? rc "<action name=\"GoToDesktop\" to=\"2\"")
          #:name "Super+2 goes to the second desktop")
        (assert-true (holds? rc "<action name=\"SendToDesktop\" to=\"3\"")
          #:name "Super+Shift+3 takes the window with it")
        (assert-equal #:expect 4
          #:got (length (labwc-desktops))
          #:name "And the desktops the file declares are the ones with a key")))))

(define (theme-suite)
  (suite "themerc-override"
    (test "The Accent Follows The Palette"
      (assert-true (holds? (labwc-themerc)
                           (get-color (labwc-palette) 'primary))
        #:name "The accent is the palette's primary")
      (assert-true (holds? (labwc-themerc) "window.active.title.bg.color:")
        #:name "The active title has a colour"))
    (test "Radius And Gap Are Parameters"
      (parameterize ((labwc-corner-radius 12)
                     (labwc-gap 8))
        (assert-true (holds? (labwc-rc-xml) "<cornerRadius>12</cornerRadius>")
          #:name "The radius is rendered")
        (assert-true (holds? (labwc-rc-xml) "<gap>8</gap>")
          #:name "The gap is rendered")))))

(define (session-files-suite)
  (suite "Session files"
    (test "The Menu Is XML"
      (assert-true (holds? (labwc-menu-xml) "<menu id=")
        #:name "The menu is an XML document with a root menu")
      (assert-true (holds? (labwc-menu-xml) "<item label=")
        #:name "The menu offers entries"))
    (test "Autostart Starts The Shell Once"
      (assert-true (holds? (labwc-autostart) "whelk")
        #:name "The bar is started")
      (assert-equal #:expect 1
        #:got (length (filter (lambda (line)
                                (and (not (string-prefix? "#" line))
                                  (holds? line "whelk")))
                              (string-split (labwc-autostart) #\newline)))
        #:name "A shell started twice is two bars"))
    (test "Autostart Starts The Shared Desktop"
      (assert-true (holds? (labwc-autostart) "emacs --daemon")
        #:name "The editor daemon starts with this session too")
      (assert-true (holds? (labwc-autostart) "podman system service")
        #:name "So does the container service")
      (assert-true (holds? (labwc-autostart) (heks-linux-password-command))
        #:name "So does the password manager")
      (assert-true (holds? (labwc-autostart) (ssh-agent-session-command))
        #:name "A session without a user manager starts the agent")
      (assert-equal #:expect 0
        #:got (length (filter (lambda (line)
                                (and (not (string-prefix? "#" line))
                                  (holds? line "heks-window-notify")))
                              (string-split (labwc-autostart) #\newline)))
        #:name "Niri's event watcher stays with Niri"))
    (test "The Environment Names The Session"
      (assert-true (holds? (labwc-environment) "XDG_CURRENT_DESKTOP")
        #:name "The session says which desktop it is"))
    (test "The Shell Wears The XP Taskbar"
      ;; whelk ships an `xp' preset - a Luna-blue bottom taskbar with Start at
      ;; the left, the notification area and a 24-hour clock at the right - and
      ;; WHELK_PRESET is how a session asks for it without a second settings
      ;; file: the environment file is exported before the first client starts.
      (assert-true (holds? (labwc-environment) "WHELK_PRESET=xp")
        #:name "The floating session asks the shell for the XP bar")
      (assert-true (parameterize ((labwc-whelk-preset ""))
                     (not (holds? (labwc-environment) "WHELK_PRESET")))
        #:name "And a machine that would rather not sets it to nothing"))
    (test "The Environment Carries The Session's Variables"
      (assert-true (holds? (labwc-environment)
                           (format #f "SSH_AUTH_SOCK=~a"
                                   (ssh-agent-session-socket)))
        #:name "The agent's socket is exported before the first client")
      (assert-true (parameterize ((init-system 'systemd))
                     (not (holds? (labwc-environment) "SSH_AUTH_SOCK")))
        #:name "Systemd's environment.d owns it there"))
    (test "The Entry Is The Prompt's, Not This Home's"
      ;; A prompt lists system files, and its account cannot read a person's
      ;; home: the session entry belongs to (heks-linux greeter).  What this
      ;; module writes is the compositor's five files and no entry.
      (assert-equal #:expect 0
        #:got (length (filter (lambda (text) (holds? text "[Desktop Entry]"))
                              (list (labwc-rc-xml)
                                    (labwc-themerc)
                                    (labwc-menu-xml)
                                    (labwc-environment)
                                    (labwc-autostart))))
        #:name "None of the five files is a session entry"))))

(define (spec)
  (veritas-run
    (rc-suite)
    (theme-suite)
    (session-files-suite)))
