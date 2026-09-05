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

(define-module (heks-linux rmpc)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:export (rmpc-keybinds rmpc-cava
                          rmpc-search-and-artists
                          rmpc-tabs
                          rmpc-config
                          rmpc-password
                          rmpc-theme-filename
                          rmpc-theme
                          install-rmpc-config))

(define s
  (scriba-auto-logger))

(define rmpc-password
  (make-parameter "***"))

(define rmpc-audio-stream-url
  (make-parameter "http://mpd-server.jointhefreeworld.org:6690"))

(define rmpc-mpd-url
  (make-parameter "mpd-server.jointhefreeworld.org:6600"))

;; Core connection & general settings
(define (rmpc-header)
  (format #f
   "
#![enable(implicit_some)]
#![enable(unwrap_newtypes)]
#![enable(unwrap_variant_newtypes)]
(
    address: \"~a\",
    password: \"~a\",
    theme: \"heks-rmpc\",
    cache_dir: None,
    on_song_change: [
          \"bash\", \"-c\",
          \"~/.config/rmpc/on-song-change\"
        ],
    volume_step: 5,
    max_fps: 60,
    scrolloff: 0,
    wrap_navigation: false,
    enable_mouse: true,
    scroll_amount: 1,
    enable_config_hot_reload: true,
    enable_lyrics_hot_reload: true,
    status_update_interval_ms: 1000,
    rewind_to_start_sec: None,
    keep_state_on_song_change: true,
    reflect_changes_to_playlist: false,
    select_current_song_on_change: false,
    ignore_leading_the: false,
    browser_song_sort: [Disc, Track, Artist, Title],
    directories_sort: SortFormat(group_by_type: true, reverse: false),
    auto_open_downloads: true,
    album_art: (
        method: Auto,
        max_size_px: (width: 1200, height: 1200),
        disabled_protocols: [\"http://\", \"https://\"],
        vertical_align: Center,
        horizontal_align: Center,
    ),"
   (rmpc-mpd-url)
   (rmpc-password)))

;; Keybindings configuration
(define rmpc-keybinds
  (make-parameter
   "    keybinds: (
        global: {
            \"<C-x><C-c>\":         Quit,
            \"<C-h>k\":          ShowHelp,
            \"<A-x>\":          CommandMode,
            \"<C-h>s\":          ShowCurrentSongInfo,
            \"<C-h>o\":          ShowOutputs,
            \"<C-h>c\":          ShowDecoders,
            \"<C-h>d\":          ShowDownloads,
            \"oP\":          Partition(),
            \"z\":           ToggleRepeat,
            \"x\":           ToggleRandom,
            \"c\":           ToggleConsume,
            \"v\":           ToggleSingle,
            \"p\":           TogglePause,
            \"s\":           Stop,
            \">\":           NextTrack,
            \"<\":           PreviousTrack,
            \"f\":           SeekForward,
            \"b\":           SeekBack,
            \"<Tab>\":      NextTab,
            \"gt\":          NextTab,
            \"<S-Tab>\":    PreviousTab,
            \"gT\":          PreviousTab,
            \"1\":           SwitchToTab(\"Queue\"),
            \"2\":           SwitchToTab(\"Directories\"),
            \"3\":           SwitchToTab(\"Artists\"),
            \"4\":           SwitchToTab(\"Album Artists\"),
            \"5\":           SwitchToTab(\"Albums\"),
            \"6\":           SwitchToTab(\"Playlists\"),
            \"7\":           SwitchToTab(\"Search\"),
            \"<C-u>\":      Update,
            \"<C-U>\":      Rescan,
            \"R\":           AddRandom,
        },
        navigation: {
            \"<C-c>\":      Close,
            \"<Esc>\":      Close,
            \"<CR>\":        Confirm,
            \"<C-p>\":           Up,
            \"<Up>\":        Up,
            \"<C-n>\":           Down,
            \"<Down>\":      Down,
            \"<C-b>\":           Left,
            \"<Left>\":      Left,
            \"<C-f>\":           Right,
            \"<Right>\":     Right,
            \"<C-w>k\":      PaneUp,
            \"<C-Up>\":      PaneUp,
            \"<C-w>j\":      PaneDown,
            \"<C-Down>\":    PaneDown,
            \"<C-w>h\":      PaneLeft,
            \"<C-Left>\":    PaneLeft,
            \"<C-w>l\":      PaneRight,
            \"<C-Right>\":   PaneRight,
            \"K\":           MoveUp,
            \"J\":           MoveDown,
            \"<C-u>\":      UpHalf,
            \"<C-d>\":      DownHalf,
            \"<C-b>\":      PageUp,
            \"<PageUp>\":    PageUp,
            \"<C-f>\":      PageDown,
            \"<PageDown>\": PageDown,
            \"<A-<>\":          Top,
            \"<A->>\":           Bottom,
            \"m\":    Select,
            \"<C-Space>\":  InvertSelection,
            \"/\":          EnterSearch,
            \"n\":           NextResult,
            \"N\":           PreviousResult,
            \"a\":           Add,
            \"A\":           AddAll,
            \"D\":           Delete,
            \"<C-r>\":      Rename,
            \"i\":           FocusInput,
            \"oi\":          ShowInfo,
            \"<C-z>\":      ContextMenu(),
            \"<C-s>s\":      Save(kind: Modal(all: false, duplicates_strategy: Ask)),
            \"<C-s>a\":      Save(kind: Modal(all: true, duplicates_strategy: Ask)),
            \"r\":           Rate(),
        },
        queue: {
            \"d\":           Delete,
            \"D\":           DeleteAll,
            \"<CR>\":        Play,
            \"C\":           JumpToCurrent,
            \"X\":           Shuffle,
        },
    ),"))

;; CAVA visualizer configuration
(define rmpc-cava
  (make-parameter "cava: (
    framerate: 60,
    autosens: true,
    sensitivity: 100,
    lower_cutoff_freq: 50,
    higher_cutoff_freq: 10000,
    input: (
        method: Pipewire,
        source: \"\",
        sample_rate: 44100,
        channels: 2,
        sample_bits: 16,
    ),
    smoothing: (
        noise_reduction: 77,
        monstercat: false,
        waves: true,
    ),
    eq: []
),"))

;; Search and artist view settings
(define rmpc-search-and-artists
  (make-parameter
   "    search: (
        case_sensitive: false,
        ignore_diacritics: false,
        search_button: false,
        mode: Contains,
        tags: [
            (value: \"any\",         label: \"Any Tag\"),
            (value: \"artist\",      label: \"Artist\"),
            (value: \"album\",       label: \"Album\"),
            (value: \"albumartist\", label: \"Album Artist\"),
            (value: \"title\",       label: \"Title\"),
            (value: \"filename\",    label: \"Filename\"),
            (value: \"genre\",       label: \"Genre\"),
        ],
    ),
    artists: (
        album_display_mode: SplitByDate,
        album_sort_by: Date,
        album_date_tags: [Date],
    ),"))

;; UI Layout / Tabs configuration
(define rmpc-tabs
  (make-parameter
   "    tabs: [
        (
            name: \"Queue\",
            pane: Split(
                direction: Horizontal,
                panes: [
                    (
                        size: \"35%\",
                        pane: Split(
                            direction: Vertical,
                            panes: [
                                (
                                    size: \"100%\",
                                    borders: \"LEFT | RIGHT | TOP\",
                                    border_symbols: Rounded,
                                    pane: Pane(AlbumArt)
                                ),
                                (
                                    size: \"7\",
                                    borders: \"ALL\",
                                    border_symbols: Inherited(parent: Rounded, top_left: \"├\", top_right: \"┤\",),
                                    border_title: [(kind: Text(\" Lyrics \"))],
                                    border_title_alignment: Right,
                                    pane: Pane(Lyrics)
                                ),
                            ],
                        ),
                    ),
                    (
                        size: \"65%\",
                        pane: Split(
                            direction: Vertical,
                            panes: [
                                (
                                    size: \"3\",
                                    borders: \"ALL\",
                                    border_symbols: Inherited(parent: Rounded, bottom_left: \"├\", bottom_right: \"┤\",),
                                    pane: Split(
                                        direction: Horizontal,
                                        panes: [
                                            (
                                                size: \"1\",
                                                pane: Pane(Empty())
                                            ),
                                            (
                                                size: \"100%\",
                                                pane: Pane(QueueHeader())
                                            ),
                                        ]
                                    )
                                ),
                                (
                                    size: \"100%\",
                                    borders: \"LEFT | RIGHT | BOTTOM\",
                                    border_symbols: Rounded,
                                    pane: Split(
                                        direction: Vertical,
                                        panes: [
                                            (
                                                size: \"1\",
                                                pane: Pane(Empty())
                                            ),
                                            (
                                                size: \"80%\",
                                                pane: Pane(Queue)
                                            ),
                                            (size: \"20%\", pane: Pane(Cava)),
                                        ]
                                    )
                                ),
                            ],
                        )
                    ),
                ],
            ),
        ),
        (
            name: \"Directories\",
            borders: \"ALL\",
            border_symbols: Rounded,
            pane: Split(
                size: \"100%\",
                direction: Vertical,
                panes: [(pane: Pane(Directories), size: \"100%\", borders: \"ALL\", border_symbols: Rounded)],
            )
        ),
        (
            name: \"Artists\",
            borders: \"ALL\",
            border_symbols: Rounded,
            pane: Split(
                size: \"100%\",
                direction: Vertical,
                panes: [(pane: Pane(Artists), size: \"100%\", borders: \"ALL\", border_symbols: Rounded)],
            )
        ),
        (
            name: \"Album Artists\",
            borders: \"ALL\",
            border_symbols: Rounded,
            pane: Split(
                size: \"100%\",
                direction: Vertical,
                panes: [(pane: Pane(AlbumArtists), size: \"100%\", borders: \"ALL\", border_symbols: Rounded)],
            )
        ),
        (
            name: \"Albums\",
            borders: \"ALL\",
            border_symbols: Rounded,
            pane: Split(
                size: \"100%\",
                direction: Vertical,
                panes: [(pane: Pane(Albums), size: \"100%\", borders: \"ALL\", border_symbols: Rounded)],
            )
        ),
        (
            name: \"Playlists\",
            borders: \"ALL\",
            border_symbols: Rounded,
            pane: Split(
                size: \"100%\",
                direction: Vertical,
                panes: [(pane: Pane(Playlists), size: \"100%\", borders: \"ALL\", border_symbols: Rounded)],
            )
        ),
        (
            name: \"Search\",
            borders: \"ALL\",
            border_symbols: Rounded,
            pane: Split(
                size: \"100%\",
                direction: Vertical,
                panes: [(pane: Pane(Search), size: \"100%\", borders: \"ALL\", border_symbols: Rounded)],
            )
        ),
    ],
)"))

(define (rmpc-config)
  (format #f
          "~a~%~a~%~a~%~a~%~a~%)"
          (rmpc-header)
          (rmpc-keybinds)
          (rmpc-cava)
          (rmpc-search-and-artists)
          (rmpc-tabs)))

;; ===========================

;; Pragmas and opening brace
(define (rmpc-theme-pragmas)
  (format #f "#![enable(implicit_some)]
#![enable(unwrap_newtypes)]
#![enable(unwrap_variant_newtypes)]
(
"))

;; Global application settings and colors
(define (rmpc-theme-globals)
  (format #f "    default_album_art_path: None,
    format_tag_separator: \" | \",
    browser_column_widths: [20, 38, 42],
    background_color: None,
    text_color: None,
    header_background_color: None,
    modal_background_color: None,
    modal_backdrop: false,
"))

;; Styling for UI elements, symbols, and log levels
(define (rmpc-theme-styles)
  (format #f
   "    preview_label_style: (fg: \"~a\"),
    preview_metadata_group_style: (fg: \"yellow\", modifiers: \"Bold\"),
    highlighted_item_style: (fg: \"~a\", modifiers: \"Bold\"),
    current_item_style: (fg: \"black\", bg: \"~a\", modifiers: \"Bold\"),
    borders_style: (fg: \"~a\"),
    highlight_border_style: (fg: \"~a\"),
    symbols: (
        song: \"S\",
        dir: \"D\",
        playlist: \"P\",
        marker: \"M\",
        ellipsis: \"...\",
        song_style: None,
        dir_style: None,
        playlist_style: None,
    ),
    level_styles: (
        info: (fg: \"blue\", bg: \"black\"),
        warn: (fg: \"yellow\", bg: \"black\"),
        error: (fg: \"red\", bg: \"black\"),
        debug: (fg: \"light_green\", bg: \"black\"),
        trace: (fg: \"magenta\", bg: \"black\"),
    ),
"
   (get-color (heks-linux-palette)
              'primary-l)
   (get-color (heks-linux-palette)
              'primary-l)
   (get-color (heks-linux-palette)
              'primary)
   (get-color (heks-linux-palette)
              'primary-l)
   (get-color (heks-linux-palette)
              'primary-l)))

;; Cava theme
(define (rmpc-cava-theme)
  (format #f
          "
cava: (
    //bar_symbols: ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'],
    inverted_bar_as_mask: false,
    bar_width: 3,
    bar_spacing: 1,
    orientation: Bottom,
    bar_color: Gradient({
          0: \"~a\",
         30: \"~a\",
         50: \"~a\",
        100: \"~a\",
    })
),
"
          (get-color (heks-linux-palette)
                     'primary)
          (get-color (heks-linux-palette)
                     'text-l)
          (get-color (heks-linux-palette)
                     'primary-l)
          (get-color (heks-linux-palette)
                     'primary)))

;; Core widgets setup (Progress bar, Scrollbar, Tabs, Lyrics)
(define (rmpc-theme-widgets)
  (format #f
          "    progress_bar: (
        symbols: [\"█\", \"█\", \"█\", \" \", \"█\"],
        track_style: None,
        elapsed_style: (fg: \"~a\"),
        thumb_style: (fg: \"~a\"),
        use_track_when_empty: true,
    ),
    scrollbar: (
        symbols: [\"│\", \"█\", \"▲\", \"▼\"],
        track_style: (),
        ends_style: (),
        thumb_style: (fg: \"~a\"),
    ),
    tab_bar: (
        active_style: (fg: \"black\", bg: \"~a\", modifiers: \"Bold\"),
        inactive_style: (),
    ),
    lyrics: (
        timestamp: false
    ),
"
          (get-color (heks-linux-palette)
                     'primary-l)
          (get-color (heks-linux-palette)
                     'primary-l)
          (get-color (heks-linux-palette)
                     'primary-l)
          (get-color (heks-linux-palette)
                     'primary-l)))

;; Formats for the browser and song table
(define (rmpc-theme-formats)
  (format #f
   "    browser_song_format: [
        (
            kind: Group([
                (kind: Property(Track)),
                (kind: Text(\" \")),
            ])
        ),
        (
            kind: Group([
                (kind: Property(Artist)),
                (kind: Text(\" - \")),
                (kind: Property(Title)),
            ]),
            default: (kind: Property(Filename))
        ),
    ],
    song_table_format: [
        (
            prop: (kind: Property(Artist),
                default: (kind: Text(\"Unknown\"))
            ),
            label_prop: (kind: Text(\"Artist\")),
            width: \"20%\",
        ),
        (
            prop: (kind: Property(Title),
                default: (kind: Text(\"Unknown\"))
            ),
            label_prop: (kind: Text(\"Title\")),
            width: \"35%\",
        ),
        (
            prop: (kind: Property(Album), style: (fg: \"white\"),
                default: (kind: Text(\"Unknown Album\"), style: (fg: \"white\"))
            ),
            label_prop: (kind: Text(\"Album\")),
            width: \"30%\",
        ),
        (
            prop: (kind: Property(Duration),
                default: (kind: Text(\"-\"))
            ),
            label_prop: (kind: Text(\"Duration\")),
            width: \"15%\",
            alignment: Right,
        ),
    ],
"))

;; The main layout structure
(define (rmpc-theme-layout)
  (format #f
   "    layout: Split(
        direction: Vertical,
        panes: [
            (
                size: \"4\",
                pane: Split(
                    direction: Horizontal,
                    panes: [
                        (
                            size: \"35\",
                            borders: \"LEFT | TOP | BOTTOM\",
                            border_symbols: Inherited(parent: Rounded, bottom_left: \"├\"),
                            pane: Component(\"header_left\")
                        ),
                        (
                            size: \"100%\",
                            borders: \"ALL\",
                            border_symbols: Inherited(parent: Rounded, top_left: \"┬\", top_right: \"┬\", bottom_left: \"┴\", bottom_right: \"┴\"),
                            pane: Component(\"header_center\")
                        ),
                        (
                            size: \"35\",
                            borders: \"RIGHT | TOP | BOTTOM\",
                            border_symbols: Inherited(parent: Rounded, bottom_right: \"┤\"),
                            pane: Component(\"header_right\")
                        ),
                    ]
                )
            ),
            (
                pane: Pane(Tabs),
                borders: \"RIGHT | LEFT | BOTTOM\",
                border_symbols: Rounded,
                size: \"2\",
            ),
            (
                pane: Pane(TabContent),
                size: \"100%\",
            ),
            (
                size: \"3\",
                pane: Split(
                    direction: Horizontal,
                    panes: [
                        (
                            size: \"6\",
                            borders: \"ALL\",
                            border_symbols: Inherited(parent: Rounded, top_right: \"┬\", bottom_right: \"┴\"),
                            pane: Component(\"input_mode\")
                        ),
                        (
                            size: \"100%\",
                            borders: \"TOP | BOTTOM | RIGHT\",
                            border_symbols: Rounded,
                            border_title: [(kind: Text(\" \")), (kind: Property(Status(QueueLength()))), (kind: Text(\" songs / \")), (kind: Property(Status(QueueTimeTotal()))), (kind: Text(\" total time \"))],
                            border_title_alignment: Right,
                            pane: Component(\"progress_bar\"),
                        ),
                    ]
                ),
            ),
        ],
    ),
"))

;; The components dictionary and closing brace
(define (rmpc-theme-components)
  (format #f
   "    components: {
        \"state\": Pane(Property(
            content: [
                (kind: Text(\"[\"), style: (fg: \"yellow\", modifiers: \"Bold\")),
                (kind: Property(Status(StateV2( ))), style: (fg: \"yellow\", modifiers: \"Bold\")),
                (kind: Text(\"]\"), style: (fg: \"yellow\", modifiers: \"Bold\")),
            ], align: Left,
        )),
        \"title\": Pane(Property(
            content: [
                (kind: Property(Song(Title)), style: (modifiers: \"Bold\"),
                    default: (kind: Text(\"No Song\"), style: (modifiers: \"Bold\"))),
            ], align: Center, scroll_speed: 1
        )),
        \"elapsed_and_bitrate\": Pane(Property(
            content: [
                (kind: Property(Status(Elapsed))),
                (kind: Text(\" / \")),
                (kind: Property(Status(Duration))),
                (kind: Group([
                    (kind: Text(\" (\")),
                    (kind: Property(Status(Bitrate))),
                    (kind: Text(\" kbps)\")),
                ])),
            ],
            align: Left,
        )),
        \"artist_and_album\": Pane(Property(
            content: [
                (kind: Property(Song(Artist)), style: (fg: \"yellow\", modifiers: \"Bold\"),
                    default: (kind: Text(\"Unknown\"), style: (fg: \"yellow\", modifiers: \"Bold\"))),
                (kind: Text(\" - \")),
                (kind: Property(Song(Album)), default: (kind: Text(\"Unknown Album\"))),
            ], align: Center, scroll_speed: 1
        )),
        \"states\": Split(
            direction: Horizontal,
            panes: [
                (
                    size: \"1\",
                    pane: Pane(Empty())
                ),
                (
                    size: \"100%\",
                    pane: Pane(Property(content: [(kind: Property(Status(InputBuffer())), style: (fg: \"blue\"), align: Left)]))
                ),
                (
                    size: \"6\",
                    pane: Pane(Property(content: [
                        (kind: Text(\"[\"), style: (fg: \"blue\", modifiers: \"Bold\")),
                        (kind: Property(Status(RepeatV2(
                            on_label: \"z\",
                            off_label: \"z\",
                            on_style: (fg: \"yellow\", modifiers: \"Bold\"),
                            off_style: (fg: \"blue\", modifiers: \"Dim\"),
                        )))),
                        (kind: Property(Status(RandomV2(
                            on_label: \"x\",
                            off_label: \"x\",
                            on_style: (fg: \"yellow\", modifiers: \"Bold\"),
                            off_style: (fg: \"blue\", modifiers: \"Dim\"),
                        )))),
                        (kind: Property(Status(ConsumeV2(
                            on_label: \"c\",
                            off_label: \"c\",
                            oneshot_label: \"c\",
                            on_style: (fg: \"yellow\", modifiers: \"Bold\"),
                            off_style: (fg: \"blue\", modifiers: \"Dim\"),
                            oneshot_style: (fg: \"red\", modifiers: \"Dim\"),
                        )))),
                        (kind: Property(Status(SingleV2(
                            on_label: \"v\",
                            off_label: \"v\",
                            oneshot_label: \"v\",
                            on_style: (fg: \"yellow\", modifiers: \"Bold\"),
                            off_style: (fg: \"blue\", modifiers: \"Dim\"),
                            oneshot_style: (fg: \"red\", modifiers: \"Bold\"),
                        )))),
                        (kind: Text(\"]\"), style: (fg: \"blue\", modifiers: \"Bold\")),
                        ],
                        align: Right
                    ))
                ),
            ]
        ),
        \"input_mode\": Pane(Property(
            content: [
                (kind: Transform(Replace(content: (kind: Property(Status(InputMode()))), replacements: [
                    (match: \"Normal\", replace: (kind: Text(\" ꞷ \"), style: (fg: \"black\", bg: \"~a\"))),
                    (match: \"Insert\", replace: (kind: Text(\" Δ \"), style: (fg: \"black\", bg: \"green\"))),
                ])))
            ], align: Center
        )),
        \"header_left\": Split(
            direction: Vertical,
            panes: [
                (size: \"1\", pane: Component(\"state\")),
                (size: \"1\", pane: Component(\"elapsed_and_bitrate\")),
            ]
        ),
        \"header_center\": Split(
            direction: Vertical,
            panes: [
                (size: \"1\", pane: Component(\"title\")),
                (size: \"1\", pane: Component(\"artist_and_album\")),
            ]
        ),
        \"header_right\": Split(
            direction: Vertical,
            panes: [
                (size: \"1\", pane: Component(\"states\")),
            ]
        ),
        \"progress_bar\": Split(
            direction: Horizontal,
            panes: [
                (
                    size: \"1\",
                    pane: Pane(Empty())
                ),
                (
                    size: \"100%\",
                    pane: Pane(ProgressBar)
                ),
                (
                    size: \"1\",
                    pane: Pane(Empty())
                ),
            ]
        )
    },
)
"
   (get-color (heks-linux-palette)
              'primary-l)))

;; The joined final theme
(define (rmpc-theme)
  (format #f
          "~a~a~a~a~a~a~a~a"
          (rmpc-theme-pragmas)
          (rmpc-theme-globals)
          (rmpc-cava-theme)
          (rmpc-theme-styles)
          (rmpc-theme-widgets)
          (rmpc-theme-formats)
          (rmpc-theme-layout)
          (rmpc-theme-components)))

;; ================

(define (rmpc-notify)
  (format #f "
#!/usr/bin/env bash

# Directory where to store temporary data
TMP_DIR=\"/tmp/rmpc\"

# Ensure the directory is created
mkdir -p \"$TMP_DIR\"

# Where to temporarily store the album art received from rmpc
ALBUM_ART_PATH=\"$TMP_DIR/notification_cover\"

# Path to fallback album art if no album art is found by rmpc/mpd
# Change this to your needs
DEFAULT_ALBUM_ART_PATH=\"$TMP_DIR/default_album_art.jpg\"

# Save album art of the currently playing song to a file
if ! rmpc albumart --output \"$ALBUM_ART_PATH\"; then
    # Use default album art if rmpc returns non-zero exit code
    ALBUM_ART_PATH=\"${DEFAULT_ALBUM_ART_PATH}\"
fi

# Send the notification
fyi -i \"${ALBUM_ART_PATH}\" \"Now Playing\" \"$ARTIST - $TITLE\"
"))

(define (rmpc-on-song-change)
  (format #f "
#!/usr/bin/env bash

bash ~/.config/rmpc/notify || true

pkill -x mpv || true
setsid sh -c 'mpv -v --no-video ~a > /tmp/heks-mpv.log 2>&1' &
"
          (rmpc-audio-stream-url)))

;; =====================================================================
;; Configuration Parameters
;; =====================================================================

(define rmpc-config-dir
  (make-parameter (format #f "~a/.config/rmpc"
                          (or (getenv "HOME") "/tmp"))))

(define rmpc-config-filename
  (make-parameter "config.ron"))

(define rmpc-notify-filename
  (make-parameter "notify"))

(define rmpc-on-song-change-filename
  (make-parameter "on-song-change"))

(define rmpc-theme-dir
  (make-parameter (format #f "~a/.config/rmpc/themes"
                          (or (getenv "HOME") "/tmp"))))

(define rmpc-theme-filename
  (make-parameter "heks-rmpc.ron"))

;; ============

(define (install-rmpc-config)
  "Generate and serialize the target Heks Linux system active attributes pipeline configuration directly to disk space."
  (log-info s "Installing Rmpc configuration")
  (load-local-overrides '(heks-linux rmpc)
                        'rmpc-settings)
  (install-config-file! #:name (rmpc-config-filename)
                        #:dir (rmpc-config-dir)
                        #:contents (rmpc-config))
  (install-config-file! #:name (rmpc-theme-filename)
                        #:dir (rmpc-theme-dir)
                        #:contents (rmpc-theme))
  (install-config-file! #:name (rmpc-notify-filename)
                        #:dir (rmpc-config-dir)
                        #:contents (rmpc-notify)
                        #:perms 493)
  (install-config-file! #:name (rmpc-on-song-change-filename)
                        #:dir (rmpc-config-dir)
                        #:contents (rmpc-on-song-change)
                        #:perms 493)
  (log-success s "Installed RMPC configuration"))
