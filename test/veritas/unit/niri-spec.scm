;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux niri).  The compositor configuration is a tree of
;; records that gets serialized to KDL, so these tests render the whole file to
;; a string and assert on the resulting text - exactly what niri parses.

;;; Code:

(define-module (veritas unit niri-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux niri)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux services)
  #:use-module (heks-linux ssh)
  #:use-module (heks-linux whelk)
  #:use-module (heks-linux user-settings)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (render-niri-config)
  "Serialize the full niri configuration to KDL text."
  (string-join (serialize-kdl (niri-config)) "\n"))

(define (niri-conf-occurs? fragment)
  (not (eq? #f (string-contains (render-niri-config) fragment))))

;; `niri validate' reads a backslash as the start of an escape, so the only ones
;; a generated file may hold are the ones KDL defines.  A command written through
;; with its own quoting - the shell's `'\''`, a `printf`'s `\n` - leaves an
;; escape KDL rejects, and the file it is in does not parse at all.
(define (invalid-kdl-escape? text)
  (let loop ((chars (string->list text)))
    (cond [(null? chars) #f]
          [(char=? #\\ (car chars))
           (if (memv (and (pair? (cdr chars)) (cadr chars))
                     (list #\" #\\ #\n #\r #\t #\b #\f #\u))
             (loop (cddr chars))
             #t)]
          [else (loop (cdr chars))])))

;; A fragment is only telling when it belongs to the rule it is read in: `blur
;; true' and `xray false' appear in several layer rules, so this looks just past
;; the namespace the rule opens with instead of anywhere in the file.
(define (niri-rule-occurs? namespace fragment)
  (let* ((conf (render-niri-config))
         (start (string-contains conf
                                 (format #f "match namespace=\"^~a$\""
                                         namespace))))
    (if (not start)
      #f
      (let ((end (min (string-length conf) (+ start 300))))
        (not (eq? #f (string-contains (substring conf start end)
                                      fragment)))))))

;; The same question about a window rule: `open-fullscreen true' is written
;; once per application, so a fragment only tells when it belongs to the rule
;; that names the application.
(define (niri-app-rule-occurs? app-id fragment)
  (let* ((conf (render-niri-config))
         (start (string-contains conf
                                 (format #f "match app-id=\"^~a$\"" app-id))))
    (if (not start)
      #f
      (let ((end (min (string-length conf) (+ start 200))))
        (not (eq? #f (string-contains (substring conf start end)
                                      fragment)))))))

;; --- running the focus watcher ------------------------------------------
;;
;; The notification half of the focus policy is a shell program, so it is
;; tested the way `heks-capture' is: rendered into a scratch directory, run
;; against a stub `niri' that replays a recorded event stream, and judged by
;; what the stub `fyi' was told.  An assertion on the script's text would pass
;; with the program broken; this one fails when the event it reads, the field it
;; tests or the window it skips changes.

(define (block . lines)
  "Return LINES as one text, one per line, ending in a newline."
  (string-append (string-join lines "\n") "\n"))

(define (find-bash)
  "Return the bash this environment can actually run.

`/usr/bin/env' is not where the hermetic container keeps it, so the rendered
program is started by naming an interpreter rather than through its shebang."
  (let loop ((dirs (string-split (or (getenv "PATH") "") #\:)))
    (cond [(null? dirs) "bash"]
          [(file-exists? (string-append (car dirs) "/bash"))
           (string-append (car dirs) "/bash")]
          [else (loop (cdr dirs))])))

(define (write-file! path text)
  (ensure-directory-tree! (dirname path))
  (call-with-output-file path
                         (lambda (port)
                           (display text port))))

(define (read-file path)
  "Return PATH's text, or the empty string when it is not there."
  (if (file-exists? path)
    (call-with-input-file path
                          (lambda (port)
                            (let loop ((chars '()))
                              (let ((c (read-char port)))
                                (if (eof-object? c)
                                  (list->string (reverse chars))
                                  (loop (cons c chars)))))))
    ""))

(define (contains? text fragment)
  "Whether FRAGMENT appears in TEXT, as a boolean."
  (if (string-contains text fragment) #t #f))

(define (count-lines text fragment)
  "How many lines of TEXT contain FRAGMENT."
  (let loop ((lines (string-split text #\newline))
             (n 0))
    (cond [(null? lines) n]
          [(contains? (car lines) fragment) (loop (cdr lines) (1+ n))]
          [else (loop (cdr lines) n)])))

(define (stub! root name text)
  "Write an executable stub called NAME into ROOT/bin and return its path."
  (let ((path (format #f "~a/bin/~a" root name)))
    (write-file! path text)
    (system* "chmod" "755" path)
    path))

(define (opened-event id title app-id focused?)
  "Return the event stream line niri emits when window ID opens with TITLE.

The window object is the one `niri msg --json event-stream' carries, trimmed to
the fields the watcher reads - including `is_focused', which is the whole
question: a window that maps focused was asked for, one that maps unfocused
turned up."
  (format #f
          "{\"WindowOpenedOrChanged\":{\"window\":{\"id\":~a,\"title\":\"~a\",\"app_id\":\"~a\",\"pid\":7,\"workspace_id\":1,\"is_focused\":~a,\"is_floating\":false,\"is_urgent\":false}}}\n"
          id title app-id focused?))

(define (untitled-event id app-id)
  "Return the event for a window that maps before its toolkit has named it.

The same line, spaced the way a pretty printer writes JSON: how niri spaces its
output is not part of what it promises to keep stable, and the watcher must not
be the thing that depends on it."
  (format #f
          "{\"WindowOpenedOrChanged\": {\"window\": {\"id\": ~a, \"title\": null, \"app_id\": \"~a\", \"pid\": 7, \"workspace_id\": 1, \"is_focused\": false, \"is_floating\": false, \"is_urgent\": false}}}\n"
          id app-id))

(define (run-focus-watcher events)
  "Run the rendered watcher over EVENTS and answer what `fyi' was told."
  (let* ((root (format #f "/tmp/heks-niri-spec-~a/watcher" (getpid)))
         (script (format #f "~a/bin/heks-window-notify" root))
         (log (format #f "~a/calls.log" root))
         (stream (format #f "~a/events.jsonl" root)))
    (write-file! script (niri-window-notify-script))
    (write-file! stream events)
    ;; The log is read, not appended: a second run answers about itself.
    (when (file-exists? log)
      (delete-file log))
    (stub! root "fyi"
           (block (format #f "#!~a" (find-bash))
                  "echo \"fyi $*\" >> \"$LOG\""
                  "exit 0"))
    ;; The compositor answers the one request the watcher makes, and nothing
    ;; else: the stream ends when the recording does, which is what ends the run.
    (stub! root "niri"
           (block (format #f "#!~a" (find-bash))
                  "echo \"niri $*\" >> \"$LOG\""
                  "case \"$*\" in *event-stream*) cat \"$EVENTS\" ;; esac"
                  "exit 0"))
    (system* "env"
             (format #f "PATH=~a/bin:~a" root (or (getenv "PATH") ""))
             (format #f "LOG=~a" log)
             (format #f "EVENTS=~a" stream)
             (find-bash)
             script)
    (read-file log)))

(define niri-suite
  (suite "Niri Configuration Suite"
    (test "Configuration Serializes To KDL"
      (assert-true (string-prefix? "// ====== Heks-Linux Niri configuration ======"
                                   (render-niri-config))
        #:name "The generated config should start with the Heks header")
      (assert-true (niri-conf-occurs? "input {")
        #:name "An input block should be emitted")
      (assert-true (niri-conf-occurs? "binds {")
        #:name "A binds block should be emitted"))

    (test "Reference And Omarchy Parity Bindings"
      (assert-true (niri-conf-occurs?
                    "Mod+space hotkey-overlay-title=\"Open the application launcher\"")
        #:name "Super+Space should open the launcher")
      (assert-true (niri-conf-occurs? "Mod+Shift+space")
        #:name "Toggling floating mode should move to Super+Shift+Space")
      (assert-true (niri-conf-occurs? "Mod+Return")
        #:name "Super+Return should open a terminal, as in Omarchy")
      (assert-true (niri-conf-occurs? "Mod+Q")
        #:name "Super+Q should close the focused window")
      (assert-true (niri-conf-occurs? "Mod+V")
        #:name "Super+V should browse the clipboard history")
      (assert-true (niri-conf-occurs? "heks-toon palettes")
        #:name
        "The palette chooser should be reachable from a binding, on its own view")
      (assert-true (niri-conf-occurs? "whelk --dnd")
        #:name "Do-not-disturb should be reachable from a binding"))

    (test "The Reference Window Opens Focused And Blurred"
      ;; heks-toon maps its window without asking for activation, so
      ;; without this rule it opens behind whatever is focused and a
      ;; click on the bar looks like it did nothing.
      (assert-true (niri-conf-occurs?
                    "match app-id=\"^org.jointhefreeworld.heks-toon$\"")
        #:name "The window should be matched by its application id")
      (assert-true (niri-conf-occurs? "open-focused true")
        #:name "The window should be focused the moment it opens")
      (assert-true (niri-conf-occurs? "blur true")
        #:name "The compositor should blur what is behind the glass"))

    (test "The Wide Applications Open At The Full Width, Bar And All"
      ;; Niri lays a new window into a column two-thirds wide, which is the
      ;; wrong shape for a browser page or a video editor.  The answer is
      ;; `maximized', not `fullscreen': the window takes every column of
      ;; pixels the layout has, and the bar is still drawn above it, so the
      ;; desktop it launches the next thing from is still there.
      (assert-true (niri-app-rule-occurs? "google-chrome"
                                          "open-maximized true")
        #:name "Chrome should open at the full width")
      (assert-true (niri-app-rule-occurs? "firefox" "open-maximized true")
        #:name "Firefox should open at the full width")
      (assert-true (niri-app-rule-occurs? "org.mozilla.firefox"
                                          "open-maximized true")
        #:name "So should the Flatpak, which announces its sandbox id")
      (assert-true (niri-app-rule-occurs? "org.kde.kdenlive"
                                          "open-maximized true")
        #:name "The video editor should open at the full width")
      (assert-true (niri-app-rule-occurs? "com.obsproject.Studio"
                                          "open-maximized true")
        #:name "The live mixer should open at the full width")
      (assert-true (niri-app-rule-occurs? "mpv" "open-maximized true")
        #:name "So should the video players")
      (assert-true (niri-app-rule-occurs? "org.gnome.Nautilus"
                                          "open-maximized true")
        #:name "A file manager should take the width and keep the bar")
      ;; Fullscreen is the other answer, and it is not this one: it covers
      ;; the layer surfaces too, so nothing this desktop installs opens in
      ;; it unless a machine asks for it by id.
      (assert-true (eq? #f (string-contains (render-niri-config)
                                            "open-fullscreen"))
        #:name "Nothing should open fullscreen by default")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-fullscreen-apps
                                                 '("my-app")))
                                   (render-niri-config))
                                 "open-fullscreen true")))
        #:name "But a machine should still be able to ask for it")
      ;; A dialog is not a column, and the vault is nobody else's business.
      (assert-true (niri-app-rule-occurs? "pavucontrol" "open-floating true")
        #:name "A mixer should float over the work it is changing")
      (assert-true (niri-app-rule-occurs? "1password"
                                          "block-out-from \"screen-capture\"")
        #:name "The vault should stay out of screenshots and screencasts")
      ;; An id is a pattern to Niri, so it is anchored: `obs' must not
      ;; claim a window that merely starts with the same letters.
      (assert-equal #:expect "\"^obs$\"" #:got (niri-app-id-pattern "obs")
        #:name "Application ids should be matched whole")
      ;; Every group is a setting, read when the file is rendered.
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-maximized-apps
                                                 '("my-app")))
                                   (render-niri-config))
                                 "match app-id=\"^my-app$\"")))
        #:name "The maximized list should be a setting")
      (assert-true (eq? #f
                        (string-contains
                         (parameterize ((niri-maximized-apps '())
                                        (niri-floating-apps '())
                                        (niri-private-apps '()))
                           (render-niri-config))
                         "open-maximized"))
        #:name
        "Emptying the lists should leave no rule that matches nothing")
      (assert-true (eq? #f
                        (string-contains
                         (parameterize ((niri-private-apps '()))
                           (render-niri-config))
                         "block-out-from"))
        #:name "A machine that wants its vault in screenshots should say so"))

    (test "Kitty Is The Main Terminal"
      (assert-true (niri-conf-occurs?
                    "Mod+T hotkey-overlay-title=\"Launch the Kitty terminal\"")
        #:name "Super+T should launch Kitty")
      (assert-true (niri-conf-occurs? "spawn-sh \"kitty\"")
        #:name "The terminal binding should spawn kitty")
      (assert-true (not (niri-conf-occurs? "alacritty"))
        #:name "Alacritty must no longer be referenced")
      (assert-true (not (niri-conf-occurs? "wezterm"))
        #:name "WezTerm must no longer be referenced"))

    (test "The Lock Screen Is The Shell's Own"
      ;; The lock screen used to be swaylock, handed a background image and a
      ;; palette-derived command line from here.  The shell owns it now: on a
      ;; compositor with ext-session-lock-v1 the compositor holds the lock, and
      ;; whelk asks PAM for the password.  What Niri says is one command with no
      ;; arguments, and no second locker in the session.
      (assert-true (niri-conf-occurs? "spawn-sh \"whelk --lock\"")
        #:name "The lock binding should ask the shell to lock")
      (assert-true (not (niri-conf-occurs? "swaylock"))
        #:name "swaylock must no longer be referenced"))

    (test "The Clipboard Is The Shell's Own"
      ;; The history is whelk's: the shell runs wl-paste --watch itself, holds
      ;; the list, and puts an entry back from its own picker.  A clipman daemon
      ;; in the startup list would be a second history nobody reads.
      (assert-true (niri-conf-occurs? "spawn-sh-at-startup \"whelk\"")
        #:name "The shell should be started with the session")
      (assert-true (not (niri-conf-occurs? "clipman"))
        #:name "no clipman daemon and no clipman picker should be left"))

    (test "Startup Scripts Exist Under ~/.local/bin"
      (assert-true (niri-conf-occurs? "write-heks-linux-dconf-settings")
        #:name
        "The startup entry must name the script that the dconf module installs")
      (assert-true (not (niri-conf-occurs? "write-heks-dconf-settings"))
        #:name
        "The stale, non-existent startup script name must be gone"))

    (test "Springy Reference Style Motion"
      (assert-true (niri-conf-occurs? "window-open {")
        #:name "Window opening should be animated")
      (assert-true (niri-conf-occurs? "damping-ratio")
        #:name "Animations should be spring driven")
      (assert-true (niri-conf-occurs? "workspace-switch")
        #:name "Workspace switches should be animated"))

    (test "Rounded Windows And Soft Shadows"
      (assert-true (niri-conf-occurs? "geometry-corner-radius 12")
        #:name "Windows should get a rounded corner radius")
      (assert-true (niri-conf-occurs? "shadow {")
        #:name "Windows should cast a drop shadow"))

    (test "The Menu Bar Casts No Shadow And Sips The Wallpaper"
      ;; A layer surface is clipped to its own rectangle, so a bar's own
      ;; box-shadow is thrown away; the compositor has to draw one.  It does not,
      ;; by default: a menu bar is the top of the screen and not a panel floating
      ;; over it, and what separates it from what is under it is the hairline its
      ;; own stylesheet draws.  A shadow there is measurably what breaks that
      ;; illusion - on a light palette it darkened the first fourteen pixels of
      ;; every window by up to 23%.  What the compositor does draw for the bar is
      ;; the vibrancy: the backdrop is saturated under the bar's thin veil.
      (assert-true (niri-conf-occurs? "match namespace=\"^whelk-rust$\"")
        #:name "The bar should be matched by its layer namespace")
      (assert-true (niri-rule-occurs? "whelk-rust" "geometry-corner-radius 10")
        #:name
        "The blur behind the bar should stop at the bar's own corners")
      (assert-true (parameterize ((whelk-bar-radius 8))
                     (niri-rule-occurs? "whelk-rust" "geometry-corner-radius 8"))
        #:name "The corner the compositor rounds should be a setting")
      (assert-true (not (niri-conf-occurs? "softness 10"))
        #:name "The bar should cast no shadow by default")
      (assert-true (parameterize ((niri-bar-shadow? #t))
                     (niri-conf-occurs? "softness 10"))
        #:name
        "A machine that wants the shadow back should get it, short and soft")
      (assert-true (niri-conf-occurs? "saturation 1.6")
        #:name "The backdrop should be saturated under the bar's veil")
      ;; The menus that drop from the bar are the same kind of surface,
      ;; and float the same way - with a longer shadow, and corners
      ;; that match the launcher's own so the shadow does not poke out
      ;; behind a rounded panel.
      (assert-true (niri-conf-occurs? "match namespace=\"^whelk-rust-launcher$\"")
        #:name "The menus should be matched by their layer namespace")
      (assert-true (niri-conf-occurs? "geometry-corner-radius 16")
        #:name "The menus' shadow should follow the panel's own corners")
      (assert-true (niri-conf-occurs? "xray false")
        #:name "A menu's glass should show the window it drops over")
      ;; The shadow is not a blur effect: a machine that turns blur off
      ;; still has a menu bar with the material it asked for, and says so
      ;; explicitly.
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((heks-linux-blur? #f)
                                                (niri-bar-shadow? #t))
                                   (render-niri-config))
                                 "softness 10")))
        #:name "The bar should keep its shadow on a machine without blur")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((heks-linux-blur? #f))
                                   (render-niri-config))
                                 "blur false")))
        #:name "Turning blur off should tell the compositor, not just omit the rule")
      ;; Every number in that material is a setting too: the two
      ;; shadows, the vibrancy, and the corner the menus' shadow has to
      ;; share with the panel it belongs to.
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-bar-shadow? #t)
                                                (niri-bar-shadow-softness 4)
                                                (niri-menu-shadow-softness 6))
                                   (render-niri-config))
                                 "softness 4")))
        #:name "The bar's shadow softness should be a setting")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-menu-shadow-softness 6))
                                   (render-niri-config))
                                 "softness 6")))
        #:name "So should the menus'")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-bar-shadow? #t)
                                                (niri-bar-shadow-color
                                                 "#000000aa"))
                                   (render-niri-config))
                                 "#000000aa")))
        #:name "So should its colour")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-bar-shadow? #t)
                                                (niri-bar-shadow-offset-y 5))
                                   (render-niri-config))
                                 "offset x=0 y=5")))
        #:name "So should where it falls")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-layer-saturation 1.2))
                                   (render-niri-config))
                                 "saturation 1.2")))
        #:name "The vibrancy should be a setting")
      ;; One radius, two programs: the launcher rounds its corners with
      ;; it, so the compositor rounds the shadow with the same number.
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((whelk-window-radius 10))
                                   (render-niri-config))
                                 "geometry-corner-radius 10")))
        #:name
        "The menus' shadow should follow the panel's own radius setting"))

    (test "The Shell's Panes Frost What They Cover"
      ;; A Wayland client cannot blur what is behind its own surface, so the
      ;; glass the shell paints on its toasts, its notification centre, its
      ;; network panel, its on-screen display and the desktop's cards needs the
      ;; compositor's blur behind it - asked for by the namespace whelk gives
      ;; each surface, one at a time.  They all drop over a window, so they are
      ;; matched the way the menus are: `xray' off, because the window under
      ;; them is what their glass should show.
      (let ((panes "(whelk-rust-(notifications|toasts|network|osd)|whelk-widget)"))
        (assert-true (niri-conf-occurs?
                      (format #f "match namespace=\"^~a$\"" panes))
          #:name "Every floating panel and card should be matched by its namespace")
        (assert-true (niri-rule-occurs? panes "blur true")
          #:name "The compositor should blur the desktop behind each pane")
        (assert-true (niri-rule-occurs? panes "xray false")
          #:name "A pane's glass should show the window it drops over")
        (assert-true (niri-rule-occurs? panes "shadow {")
          #:name
          "A layer surface is clipped to its rectangle, so the compositor draws the shadow")
        (assert-true (niri-rule-occurs? panes "geometry-corner-radius 10")
          #:name "and rounds the blur behind the corners the pane paints")
        (assert-true (parameterize ((heks-linux-blur? #f))
                       (niri-rule-occurs? panes "blur false"))
          #:name
          "Turning blur off should tell the compositor, not just omit the rule"))
      ;; The wallpaper surface is a whelk layer too, and it is the one that must
      ;; never be blurred: the glass would have nothing left to show.
      (assert-equal #:expect #f
        #:got (niri-conf-occurs? "whelk-rust-wallpaper")
        #:name "No layer rule should match the wallpaper surface"))

    (test "The Dock's Launchpad Frosts What It Covers"
      ;; The launchpad is the dock's full screen overlay and its
      ;; backdrop is translucent, but a Wayland client cannot blur what
      ;; is behind its own surface: the frost is the compositor's,
      ;; asked for by the namespace lambdock gives the overlay.
      (assert-true (niri-conf-occurs?
                    "match namespace=\"^lambdock-launchpad$\"")
        #:name "The launchpad should be matched by its layer namespace")
      (assert-true (niri-rule-occurs? "lambdock-launchpad" "blur true")
        #:name "The compositor should frost the launchpad's backdrop")
      ;; Like the menus, and unlike the bar: the launchpad drops over
      ;; windows, so its glass shows the desktop it is covering.
      (assert-true (niri-rule-occurs? "lambdock-launchpad" "xray false")
        #:name "The launchpad's glass should show what it covers")
      ;; One switch, two halves of the look: the dock only leaves its
      ;; backdrop translucent when this desktop frosts its surfaces.
      (assert-true (parameterize ((heks-linux-blur? #f))
                     (niri-rule-occurs? "lambdock-launchpad"
                                        "blur false"))
        #:name
        "Turning blur off should tell the compositor, not just omit the rule"))

    (test "The Dock Is Started Once Per Session"
      ;; Niri re-runs the whole startup list on every config reload, and
      ;; lambdock draws a layer surface per instance, so an unguarded
      ;; entry stacked a second dock on the first each time the config
      ;; file was rewritten.  The launch holds a lock in the session's
      ;; runtime directory for as long as the dock lives instead.
      (assert-true (niri-conf-occurs?
                    "spawn-sh-at-startup \"flock -n ${XDG_RUNTIME_DIR:-/tmp/heks-linux-$USER}/lambdock-session.lock lambdock")
        #:name "The dock should start under a lock held for its lifetime")
      (assert-true (not (niri-conf-occurs? "spawn-sh-at-startup \"lambdock"))
        #:name "The dock should never be started under its bare name")
      ;; A restart is not an exception: the dock the keybinding just
      ;; killed is still holding the lock while it dies, so the
      ;; replacement queues for it rather than failing inside that
      ;; window and leaving no dock at all.
      (assert-true (niri-conf-occurs?
                    "pkill lambdock || true; flock -w 2 ${XDG_RUNTIME_DIR:-/tmp/heks-linux-$USER}/lambdock-session.lock lambdock")
        #:name "Restarting the dock should queue for the same lock"))

    (test "The Session Is The Agent's Manager Under Runit"
      ;; Void has no per-user supervisor, so the session starts the agent and
      ;; names its socket for every program it starts.  Under systemd the user
      ;; manager owns both, and the session must not start a second agent.
      (assert-true (niri-conf-occurs?
                    (format #f "SSH_AUTH_SOCK \"~a\""
                            (ssh-agent-session-socket)))
        #:name "The session should export the agent's own socket")
      (assert-true (niri-conf-occurs? "exec ssh-agent -D -a")
        #:name "The agent should be started by the session, under its lock")
      (assert-true (niri-conf-occurs?
                    (format #f "flock -n '~a.lock' sh -c"
                            (ssh-agent-session-socket)))
        #:name
        "Under the lock that keeps a config reload from starting a second one")
      (assert-true (parameterize ((init-system 'systemd))
                     (not (niri-conf-occurs? "SSH_AUTH_SOCK")))
        #:name "Systemd's user manager exports the socket, so Niri should not")
      (assert-true (parameterize ((init-system 'systemd))
                     (not (niri-conf-occurs? "ssh-agent -D -a")))
        #:name "And it starts the agent, so the session should not"))

    (test "A Command's Backslash Survives Into The KDL String"
      ;; `niri validate' rejects `\'` and reads `\n` as a newline, while the
      ;; session's own commands quote with shell syntax: the agent's
      ;; lock-and-start line is full of `'\''`.  Written through unescaped, one
      ;; of those made the whole file unparseable, so the validator refused to
      ;; install it and a reconfigure (`hr`) failed on a config it had not been
      ;; asked to change.
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((niri-extra-startups
                                                 (list "printf '%s\\n' '\\''a'\\''")))
                                   (render-niri-config))
                                 "spawn-sh-at-startup \"printf '%s\\\\n' '\\\\''a'\\\\''\"")))
        #:name "A backslash and a quote should be escaped for the KDL string")
      (assert-true (not (invalid-kdl-escape? (render-niri-config)))
        #:name "No command should reach the file with an escape KDL rejects"))

    (test "The Shell And The Editor Daemon Restart From A Binding"
      ;; Both programs are what a reconfigure changes, and both are started by
      ;; the session, so the bindings name what the session starts.  The Emacs
      ;; one used to point at ~/.local/bin/user-script-restart-emacs.bash, a
      ;; file no task in this tree writes any more: the key did nothing at all.
      (assert-true (niri-conf-occurs? "Mod+Ctrl+W")
        #:name "Restarting the shell should have a binding of its own")
      (assert-true (niri-conf-occurs? "whelk --quit")
        #:name "It should ask the running shell to stop, not kill it")
      (assert-true (niri-conf-occurs? "pgrep -x whelk")
        #:name "It should wait for that process to go before starting another")
      (assert-true (niri-conf-occurs? "Mod+Ctrl+E")
        #:name "Restarting the editor daemon should keep its binding")
      (assert-true (niri-conf-occurs? "kill-emacs")
        #:name "It should ask the running daemon to shut down")
      (assert-true (niri-conf-occurs? "emacs --daemon")
        #:name "And start the daemon the session starts")
      (assert-true (not (niri-conf-occurs? "user-script-restart-emacs.bash"))
        #:name "Not a script nothing in this tree writes"))

    (test "The Session Starts The Machine's Password Manager"
      ;; The login line and the bar's key glyph are one setting: a
      ;; machine that changed one and not the other would start a vault
      ;; it cannot click.
      (assert-true (niri-conf-occurs?
                    (format #f "spawn-sh-at-startup \"~a ~a\""
                            (heks-linux-password-command)
                            (heks-linux-password-startup-args)))
        #:name
        "The session should start the password manager quietly")
      (assert-true (not (eq? #f (string-contains
                                 (parameterize ((heks-linux-password-command
                                                 "keepassxc")
                                                (heks-linux-password-startup-args
                                                 "--minimized"))
                                   (render-niri-config))
                                 "spawn-sh-at-startup \"keepassxc --minimized\"")))
        #:name "Another manager and its own quiet flag should come through")
      (assert-true (not (eq? #f (string-contains (render-niri-config)
                                                 "spawn-sh-at-startup \"1password --silent\"")))
        #:name
        "The default should be the distribution's 1password, not the Flatpak"))

    (test "Natural Scrolling Follows Its Setting"
      (assert-true (not (niri-conf-occurs? "natural-scroll"))
        #:name
        "Natural scrolling should stay off while the setting is disabled")
      (assert-true
        (not (eq? #f (string-contains
                      (parameterize ((niri-natural-scroll? #t))
                        (render-niri-config))
                      "natural-scroll")))
        #:name
        "Enabling the setting should emit natural-scroll into the config"))

    (test "Extra Keyboard Options Are Composed With Caps To Ctrl"
      (assert-true (not (eq? #f
                             (string-contains (parameterize ((niri-keyboard-options '("lv3:ralt_switch"
                                                                                      "esperanto:qwerty")))
                                                (render-niri-config))
                                              "options \"esperanto:qwerty,lv3:ralt_switch,ctrl:nocaps\"")))
        #:name
        "Extra XKB options should be comma-joined with ctrl:nocaps")
      (assert-true (not (eq? #f
                             (string-contains (parameterize ((niri-keyboard-options '("esperanto:qwerty")))
                                                (render-niri-config))
                                              "options \"esperanto:qwerty,ctrl:nocaps\"")))
        #:name
        "A single extra option should still compose with ctrl:nocaps")
      (assert-true (not (eq? #f
                             (string-contains (parameterize ((niri-caps-to-ctrl?
                                                              #f)
                                                             (niri-keyboard-options '("esperanto:qwerty")))
                                                (render-niri-config))
                                              "options \"esperanto:qwerty\"")))
        #:name "Without ctrl:nocaps the extra options stand alone")
      (assert-true (not (eq? #f
                             (string-contains (parameterize ((niri-keyboard-options '("ctrl:nocaps")))
                                                (render-niri-config))
                                              "options \"ctrl:nocaps\"")))
        #:name "Repeated configuration does not generate redundancies"))

    (test "New Windows Take The Focus"
      ;; A window that opens takes the keyboard.  That is niri's own heuristic
      ;; auto-focus and this desktop's default: the config says nothing about
      ;; the policy, and nothing watches for a window that opened behind you,
      ;; because there is none to announce.
      (assert-true (eq? #f
                        (string-contains (render-niri-config)
                                         "strict-new-window-focus-policy"))
        #:name "Niri's heuristic auto-focus should be left alone")
      (assert-true (eq? #f
                        (string-contains (render-niri-config)
                                         "heks-window-notify"))
        #:name "A window that takes the focus has nothing to announce")
      ;; The reference window comes from a click on the bar and exists to be
      ;; read on arrival, so its rule says so itself.
      (assert-true (niri-conf-occurs? "open-focused true")
        #:name "The reference window should open focused")
      ;; A machine that would rather not be interrupted turns the policy on:
      ;; `strict-new-window-focus-policy' leaves the focus to windows that
      ;; activate themselves with a valid xdg-activation token - what a window
      ;; launched from a keybinding or the launcher does - and the watcher names
      ;; the rest.
      (let ((quiet (parameterize ((niri-steal-focus? #f))
                     (render-niri-config))))
        (assert-true (not (eq? #f
                               (string-contains quiet
                                                "strict-new-window-focus-policy")))
          #:name "The policy should be stated in a debug block when it is on")
        (assert-true
          (not (eq? #f
                    (string-contains
                     quiet
                     "spawn-sh-at-startup \"flock -n ${XDG_RUNTIME_DIR:-/tmp/heks-linux-$USER}/heks-window-notify.lock")))
          #:name
          "The watcher should start under a session lock, so a reload starts no second one")))

    (test "A Window That Opens Behind You Is Announced"
      ;; The watcher reads niri's event stream: a window that maps unfocused is
      ;; announced, one that maps focused was asked for and is not.  A window's
      ;; title changing fires the same event, so an id is announced once - and a
      ;; window that maps before its toolkit names it is announced without one.
      (let ((log (run-focus-watcher
                  (string-append (opened-event 42 "Updater" "org.gnome.Software" "false")
                                 (opened-event 43 "term" "kitty" "true")
                                 (opened-event 42 "Updater - installing" "org.gnome.Software" "false")
                                 (untitled-event 44 "org.gnome.Nautilus")
                                 "{\"WindowClosed\":{\"id\":43}}\n"))))
        (assert-true (contains? log
                                "fyi -i applications-other-symbolic -a org.gnome.Software Updater")
          #:name "A window that opened behind the focused one should be named")
        (assert-true (contains? log
                                "fyi -i applications-other-symbolic -a org.gnome.Nautilus A window opened")
          #:name
          "A window with no title yet should still be announced, and spaced JSON read")
        (assert-equal #:expect 2
          #:got (count-lines log "fyi ")
          #:name "Two windows opened behind you, so two announcements")
        (assert-true (not (contains? log "kitty"))
          #:name "A window that opened focused should not be announced")
        (assert-true (not (contains? log "installing"))
          #:name "A title change should not be announced as a new window")))))

(define (spec)
  ;; Niri's startup list follows the init system; the suite pins the target's.
  (parameterize ((init-system 'runit))
    (veritas-run niri-suite)))
