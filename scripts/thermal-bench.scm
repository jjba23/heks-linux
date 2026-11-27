#!/usr/bin/env -S guile --no-auto-compile -s
!#
;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>
;;
;; Measure CPU temperature under a load that is the same load every time.
;;
;; Commentary:
;;
;; The number that says whether a repaste, a cooler or a fan curve helped is not
;; the hottest reading ever seen: it is the temperature the machine settles at
;; once the cooler has caught up, on the same workload, from the same starting
;; point, with the same fan curve.  So each run is three fixed phases and one
;; number per sensor:
;;
;; - idle, for a fixed number of seconds, so the run starts cold the same way
;;   every time and the idle temperature is a reading of its own;
;; - load, from `stress-ng --cpu N --cpu-method matrixprod' until its own timeout
;;   stops it.  The method is pinned because stress-ng's default rotates through
;;   its methods, and a heat load that depends on which second you sampled is not
;;   a load you can compare across days;
;; - the steady window, the last quarter of the load (at least a minute), which
;;   is what the summary reports as mean and max.  The first part of a run is the
;;   heatsink filling up, not the cooler's steady state.
;;
;; Every sample records the sensors hwmon exposes and the mean core clock, because
;; a machine that throttles hits the same temperature at a lower clock and would
;; otherwise look unchanged.
;;
;; What this cannot measure is room temperature, and it matters more than
;; anything else on the page: a run an hour apart in a warmer room reads higher
;; with nothing about the cooler changed.  Note it next to the label.
;;
;; Everything a run saw about itself - CPU, kernel, governor, worker count, load
;; and duration - is written into the samples file, so a summary found six months
;; later still says what it was measuring.

(use-modules (ice-9 format)
             (ice-9 ftw)
             (ice-9 rdelim)
             (srfi srfi-1))

(define program "thermal-bench")

;; Load duration in minutes, as the person typed it; fractions are accepted
;; (0.5 is thirty seconds).
(define minutes "10")
;; Seconds of idle sampling before the load starts.
(define idle-seconds 60)
;; Seconds between samples.
(define interval 1)
;; One worker per CPU unless told otherwise: the load is the machine's, and the
;; count is recorded so a run on another machine cannot be mistaken for this one.
(define workers 1)
;; The fixed load.  See the commentary for why the method is not stress-ng's
;; default.
(define method "matrixprod")
(define label "")
(define out-dir
  (let ((data-home (getenv "XDG_DATA_HOME")))
    (format #f "~a/heks-linux/thermal"
            (if (and data-home (not (string=? data-home "")))
              data-home
              (format #f "~a/.local/share" (or (getenv "HOME") "/tmp"))))))

(define (say text)
  (format (current-error-port) "~a: ~a~%" program text))

(define (die text)
  (say text)
  (exit 1))

(define (usage)
  (format #t "~a - measure temperature under a fixed, repeatable load~%~%" program)
  (format #t "  ~a [run] [OPTIONS]~%" program)
  (format #t "      Idle, then a full CPU load, sampling every hwmon sensor.  Writes~%")
  (format #t "      samples.csv and summary.txt under --out.~%~%")
  (format #t "      --minutes N     load duration in minutes (default ~a; 0.5 = 30 s)~%" minutes)
  (format #t "      --idle N        seconds of idle sampling first (default ~a)~%" idle-seconds)
  (format #t "      --interval N    seconds between samples (default ~a)~%" interval)
  (format #t "      --workers N     stress-ng workers (default one per CPU)~%")
  (format #t "      --label NAME    run name, also the directory name (default a timestamp)~%")
  (format #t "      --out DIR       where runs are kept (default ~a)~%~%" out-dir)
  (format #t "  ~a summarise CSV~%" program)
  (format #t "      Print the summary of an existing samples.csv.~%~%")
  (format #t "  ~a compare A B~%" program)
  (format #t "      Per-sensor idle and steady-state difference between two runs, given as~%")
  (format #t "      run directories or summary files.  Warns when the two runs were not the~%")
  (format #t "      same setup.~%~%")
  (format #t "  ~a self-test~%" program)
  (format #t "      Check the summary arithmetic and the comparison on synthetic samples.~%~%")
  (format #t "A run cannot see the room temperature, and a repaste judged an hour apart in a~%")
  (format #t "warmer room reads worse than it is: keep the room, the fan curve and the session~%")
  (format #t "the same, and write the ambient next to the label.~%"))

;; ===========================================
;; Reading the machine
;; ===========================================

(define (file-first-line path)
  "Return PATH's first line, or #f when it cannot be read."
  (catch #t
         (lambda ()
           (call-with-input-file path
                                 (lambda (port)
                                   (let ((line (read-line port)))
                                     (and (not (eof-object? line)) line)))))
         (lambda _ #f)))

(define (read-lines path)
  "Return every line of PATH, without its terminator."
  (call-with-input-file path
                        (lambda (port)
                          (let loop ((lines '()))
                            (let ((line (read-line port)))
                              (if (eof-object? line)
                                (reverse lines)
                                (loop (cons line lines))))))))

(define (make-directories path)
  "Create PATH and every missing directory above it."
  (unless (or (string=? path "") (string=? path "/") (file-exists? path))
    (let ((slash (string-rindex path #\/)))
      (when (and slash (> slash 0))
        (make-directories (substring path 0 slash))))
    (catch 'system-error (lambda () (mkdir path)) (lambda _ #t))))

(define (program-exists? name)
  (let ((path (getenv "PATH")))
    (and path
      (any (lambda (dir)
             (let ((candidate (format #f "~a/~a" dir name)))
               (and (file-exists? candidate)
                 (not (file-is-directory? candidate)))))
           (string-split path #\:)))))

;; A machine reports its CPUs in /proc/cpuinfo on every kernel this runs on, and
;; reading it costs one file rather than a process per run.
(define (cpu-count)
  (let ((path "/proc/cpuinfo"))
    (if (file-exists? path)
      (max 1
           (length (filter (lambda (line)
                             (string-prefix? "processor" line))
                           (read-lines path))))
      1)))

(define (cpu-model)
  (let loop ((lines (if (file-exists? "/proc/cpuinfo")
                      (read-lines "/proc/cpuinfo")
                      '())))
    (cond
      [(null? lines) (utsname:machine (uname))]
      [(string-prefix? "model name" (car lines))
       (let ((colon (string-index (car lines) #\:)))
         (if colon
           (string-trim-both (substring (car lines) (1+ colon))
                             #\space)
           (utsname:machine (uname))))]
      [else (loop (cdr lines))])))

(define (cpu-frequency-files)
  (let ((dir "/sys/devices/system/cpu"))
    (if (file-is-directory? dir)
      (filter-map (lambda (entry)
                    (let ((path (format #f "~a/~a/cpufreq/scaling_cur_freq"
                                        dir entry)))
                      (and (file-exists? path) path)))
                  (scandir dir
                           (lambda (entry)
                             (string-prefix? "cpu" entry))))
      '())))

(define (governors)
  (delete-duplicates
   (filter-map (lambda (file)
                 (let ((line (file-first-line
                              (string-append
                               (string-drop-right file
                                                  (string-length
                                                   "cpufreq/scaling_cur_freq"))
                               "cpufreq/scaling_governor"))))
                   (and line (not (string=? line "")) line)))
               (cpu-frequency-files))
   string=?))

;; ===========================================
;; The sensors
;; ===========================================

;; hwmon's own names and labels, with everything a CSV or a shell would trip over
;; turned into an underscore: `cros_ec' calls one of its inputs
;; `cpu_f75303@4d', and a column full of @ in a file somebody greps is a column
;; somebody quotes wrong.
(define (sanitise text)
  (let loop ((chars (string->list text))
             (out '())
             (last-underscore? #f))
    (if (null? chars)
      (list->string
       (reverse
        (let drop-trailing ((reversed out))
          (if (and (pair? reversed) (char=? (car reversed) #\_))
            (drop-trailing (cdr reversed))
            reversed))))
      (let ((char (if (or (char-alphabetic? (car chars))
                        (char-numeric? (car chars)))
                    (car chars)
                    #\_)))
        (if (and (char=? char #\_) last-underscore?)
          (loop (cdr chars) out #t)
          (loop (cdr chars) (cons char out) (char=? char #\_)))))))

;; Two devices of the same kind report the same name - a pair of spd5118 sticks,
;; or two NVMe drives - so a repeated column gains a suffix instead of a second
;; column nobody can tell apart.
(define column-counts (make-hash-table))

(define (next-column base)
  (let* ((count (1+ (or (hash-ref column-counts base) 0))))
    (hash-set! column-counts base count)
    (if (= count 1) base (format #f "~a_~a" base count))))

(define sensor-columns '())
(define sensor-paths '())

(define (temp-input-files dir)
  (if (file-is-directory? dir)
    (filter (lambda (name)
              (and (string-prefix? "temp" name)
                (string-suffix? "_input" name)))
            (scandir dir))
    '()))

(define (discover-sensors)
  (let ((root "/sys/class/hwmon"))
    (when (file-is-directory? root)
      (for-each
       (lambda (dir)
         (let* ((path (format #f "~a/~a" root dir))
                (name (file-first-line (format #f "~a/name" path))))
           (when (and name (not (string=? name "")))
             (for-each
              (lambda (file)
                (let* ((input (format #f "~a/~a" path file))
                       (base (string-drop-right input (string-length "_input")))
                       (tag (file-first-line (format #f "~a_label" base)))
                       (column
                        (next-column
                         (sanitise
                          (if (and tag (not (string=? tag "")))
                            (format #f "~a_~a" name tag)
                            name)))))
                  (set! sensor-columns (append sensor-columns (list column)))
                  (set! sensor-paths (append sensor-paths (list input)))))
              (temp-input-files path)))))
       (scandir root (lambda (entry) (string-prefix? "hwmon" entry)))))))

;; hwmon reports millidegrees.  One decimal is the precision a comparison needs,
;; and the arithmetic is done here rather than by a program per value: a ten
;; minute run is six hundred samples of a dozen sensors.
(define (temperature path)
  (let ((raw (file-first-line path)))
    (if (and raw
          (let ((number (string->number raw)))
            (and number (integer? number))))
      (let* ((value (string->number raw))
             (magnitude (abs value)))
        (format #f "~a~d.~d"
                (if (< value 0) "-" "")
                (quotient magnitude 1000)
                (quotient (remainder magnitude 1000) 100)))
      "")))

;; The mean core clock is the other half of a temperature reading: a machine that
;; throttles settles at the same degrees while doing less work.
(define (cpu-mhz)
  (let ((frequencies (filter-map (lambda (file)
                                   (let ((line (file-first-line file)))
                                     (and line (string->number line))))
                                 (cpu-frequency-files))))
    (if (null? frequencies)
      ""
      (number->string (quotient (quotient (apply + frequencies)
                                          (length frequencies))
                                1000)))))

(define (csv-join values)
  (string-join values ","))

;; ===========================================
;; The load
;; ===========================================

(define csv-port #f)
(define bench-dir "")
(define bench-csv "")
(define load-pid #f)
(define load-samples? #f)

(define (write-row phase elapsed)
  (format csv-port "~a,~a,~a~%" phase elapsed
          (csv-join (append (map temperature sensor-paths)
                            (list (cpu-mhz)))))
  (when (string=? phase "load")
    (set! load-samples? #t)))

(define (stop-load)
  (when load-pid
    (catch #t (lambda () (kill load-pid SIGTERM)) (lambda _ #t))
    (catch #t (lambda () (waitpid load-pid 0)) (lambda _ #t))
    (set! load-pid #f)))

;; A run that was interrupted still has samples worth keeping, and a summary of a
;; shortened load says so through its own load_seconds.
(define (finish)
  (unless load-samples?
    (die (format #f "the load produced no samples; the run is in ~a" bench-dir)))
  (when csv-port (force-output csv-port))
  (let ((summary (summarise bench-csv)))
    (catch #t
           (lambda ()
             (call-with-output-file (format #f "~a/summary.txt" bench-dir)
                                    (lambda (port) (display summary port))))
           (lambda _
             (die (format #f "cannot write ~a/summary.txt" bench-dir))))
    (display summary)
    (say (format #f "run written to ~a" bench-dir))))

(define (spawn-load load-seconds)
  (let ((pid (primitive-fork)))
    (if (zero? pid)
      (begin
        (catch #t
               (lambda ()
                 (execlp "stress-ng" "stress-ng"
                         "--cpu" (number->string workers)
                         "--cpu-method" method
                         "--timeout" (format #f "~as" load-seconds)
                         "--quiet"))
               (lambda _ (primitive-exit 127)))
        (primitive-exit 127))
      pid)))

(define (child-status->exit status)
  (or (status:exit-val status)
    (+ 128 (or (status:term-sig status) 0))))

(define (load-phase load-seconds)
  (say (format #f "loading ~a workers for ~as" workers load-seconds))
  (set! load-pid (spawn-load load-seconds))
  (let ((load-start (current-time)))
    (let loop ()
      (write-row "load" (- (current-time) load-start))
      (let ((status (waitpid load-pid WNOHANG)))
        (if (zero? (car status))
          (begin
            (sleep interval)
            (loop))
          (let ((exit (child-status->exit (cdr status))))
            (set! load-pid #f)
            (unless (zero? exit)
              (die (format #f "stress-ng failed with status ~a" exit)))))))))

(define (idle-phase)
  (say (format #f "idle for ~as" idle-seconds))
  (let ((start (current-time)))
    (let loop ()
      ;; Sampled before the clock is judged, not after: a run that starts on a
      ;; second boundary would otherwise decide the idle phase was over before it
      ;; took a single sample, and a summary with no idle row cannot say where the
      ;; run started from.
      (let ((elapsed (- (current-time) start)))
        (write-row "idle" elapsed)
        (unless (>= elapsed idle-seconds)
          (sleep interval)
          (loop))))))

(define (run-benchmark)
  (unless (program-exists? "stress-ng")
    (die "stress-ng is not installed; install it (Void: sudo xbps-install -S stress-ng)"))
  (let ((load-seconds (let ((number (string->number minutes)))
                        (and number (> number 0)
                          (inexact->exact (truncate (* number 60)))))))
    (unless (and load-seconds (> load-seconds 0))
      (die "--minutes must be more than zero"))
    (unless (and (integer? idle-seconds) (>= idle-seconds 0))
      (die "--idle takes whole seconds"))
    (unless (and (integer? interval) (>= interval 1))
      (die "--interval takes whole seconds, at least one"))
    (unless (and (integer? workers) (>= workers 1))
      (die "--workers takes a whole number, at least one"))

    (discover-sensors)
    (when (null? sensor-paths)
      (die "no temperature sensor under /sys/class/hwmon; nothing to measure"))

    (when (string=? label "")
      (set! label (format #f "run-~a"
                          (strftime "%Y%m%dT%H%M%SZ" (gmtime (current-time))))))
    (set! bench-dir (format #f "~a/~a" out-dir label))
    (set! bench-csv (format #f "~a/samples.csv" bench-dir))
    (when (file-exists? bench-dir)
      (die (format #f "~a already exists; give this run another --label" bench-dir)))
    (make-directories bench-dir)

    (catch #t
           (lambda ()
             (set! csv-port (open-output-file bench-csv)))
           (lambda _
             (die (format #f "cannot write ~a" bench-csv))))

    (format csv-port "# label: ~a~%" label)
    (format csv-port "# started: ~a~%"
            (strftime "%Y-%m-%dT%H:%M:%SZ" (gmtime (current-time))))
    (format csv-port "# cpu: ~a~%" (cpu-model))
    (format csv-port "# kernel: ~a~%" (utsname:release (uname)))
    (format csv-port "# governor: ~a~%" (string-join (governors) ","))
    (format csv-port "# workers: ~a~%" workers)
    (format csv-port "# method: ~a~%" method)
    (format csv-port "# load_minutes: ~a~%" minutes)
    (format csv-port "# idle_seconds: ~a~%" idle-seconds)
    (format csv-port "# interval_seconds: ~a~%" interval)
    (format csv-port "phase,elapsed_s,~a,cpu_mhz~%"
            (csv-join sensor-columns))
    (force-output csv-port)

    (sigaction SIGINT (lambda _ (stop-load) (finish) (exit 130)))
    (sigaction SIGTERM (lambda _ (stop-load) (finish) (exit 130)))

    (idle-phase)
    (load-phase load-seconds)
    (finish)))

;; ===========================================
;; The record of a run
;; ===========================================

(define (read-samples path)
  "Return the comments, the column names and the rows of a samples file.

Each row is (PHASE ELAPSED VALUES), where an unreadable value is #f."
  (let loop ((lines (read-lines path))
             (comments '())
             (columns #f)
             (rows '()))
    (cond
      [(null? lines)
       (values (reverse comments) columns (reverse rows))]
      [(string-prefix? "#" (car lines))
       (loop (cdr lines) (cons (car lines) comments) columns rows)]
      [(not columns)
       (loop (cdr lines) comments
             (drop (string-split (car lines) #\,) 2)
             rows)]
      [else
        (let ((fields (string-split (car lines) #\,)))
          (loop (cdr lines) comments columns
                (cons (list (car fields)
                            (or (string->number (cadr fields)) 0)
                            (map (lambda (field)
                                   (and (not (string=? field ""))
                                     (string->number field)))
                                 (drop fields 2)))
                      rows)))])))

(define (phase-lines name columns sums counts peaks)
  (let loop ((index 0) (columns columns) (lines '()))
    (if (null? columns)
      (apply string-append (reverse lines))
      (let ((count (vector-ref counts index)))
        (loop (1+ index) (cdr columns)
              (cons (if (zero? count)
                      (format #f "~a\t~a\t-\t-\t0~%" (car columns) name)
                      (format #f "~a\t~a\t~,1f\t~,1f\t~a~%" (car columns) name
                              (/ (vector-ref sums index) count)
                              (vector-ref peaks index)
                              count))
                    lines))))))

;; The summary answers one question per sensor: what did the machine settle at,
;; and what did it touch on the way.  The steady window is the last quarter of
;; the load, or the last minute when the load was shorter than four.
(define (summarise path)
  (unless (file-exists? path)
    (die (format #f "cannot read ~a" path)))
  (call-with-values
    (lambda ()
      (catch #t
             (lambda () (read-samples path))
             (lambda _ (die (format #f "cannot read ~a" path)))))
    (lambda (comments columns rows)
      (when (null? rows)
        (format (current-error-port) "no samples in the file~%")
        (exit 1))
      (let* ((load-seconds
              (fold (lambda (row highest)
                      (if (and (string=? (car row) "load")
                            (> (cadr row) highest))
                        (cadr row)
                        highest))
                    0 rows))
             (window (min load-seconds (max 60 (quotient load-seconds 4))))
             (steady-from (- load-seconds window))
             (columns (or columns '()))
             (size (length columns))
             (idle-sums (make-vector size 0))
             (idle-counts (make-vector size 0))
             (idle-peaks (make-vector size 0))
             (steady-sums (make-vector size 0))
             (steady-counts (make-vector size 0))
             (steady-peaks (make-vector size 0)))
        (for-each
         (lambda (row)
           (let* ((phase (car row))
                  (elapsed (cadr row))
                  (name (cond
                          [(string=? phase "idle") 'idle]
                          [(and (string=? phase "load")
                             (>= elapsed steady-from)) 'steady]
                          [else #f])))
             (when name
               (for-each (lambda (index value)
                           (when value
                             (let* ((sums (if (eq? name 'idle) idle-sums steady-sums))
                                    (counts (if (eq? name 'idle)
                                              idle-counts
                                              steady-counts))
                                    (peaks (if (eq? name 'idle) idle-peaks steady-peaks))
                                    (count (vector-ref counts index)))
                               (vector-set! sums index
                                            (+ (vector-ref sums index) value))
                               (vector-set! counts index (1+ count))
                               (when (or (zero? count)
                                       (> value (vector-ref peaks index)))
                                 (vector-set! peaks index value)))))
                         (iota size)
                         (caddr row)))))
         rows)
        (with-output-to-string
         (lambda ()
           (for-each (lambda (comment) (display comment) (newline)) comments)
           (format #t "# load_seconds: ~a~%" load-seconds)
           (format #t "# steady_window_seconds: ~a~%" window)
           (format #t "sensor\tphase\tmean\tmax\tsamples~%")
           (display (phase-lines "idle" columns idle-sums idle-counts idle-peaks))
           (display (phase-lines "steady" columns steady-sums steady-counts
                                 steady-peaks))))))))

;; ===========================================
;; Comparing runs
;; ===========================================

(define (meta path key)
  (let ((prefix (format #f "# ~a: " key)))
    (let loop ((lines (read-lines path)))
      (cond
        [(null? lines) ""]
        [(string-prefix? prefix (car lines))
         (substring (car lines) (string-length prefix))]
        [else (loop (cdr lines))]))))

(define (summary-path run)
  (let ((path (if (file-exists? run) run (format #f "~a/~a" out-dir run))))
    (if (file-is-directory? path)
      (format #f "~a/summary.txt" path)
      path)))

(define (summary-rows path)
  (filter-map (lambda (line)
                (let ((fields (string-split line #\tab)))
                  (and (not (string-prefix? "#" line))
                    (= (length fields) 5)
                    (not (string=? (car fields) "sensor"))
                    fields)))
              (read-lines path)))

;; Two runs are only comparable when the machine was under the same load at the
;; same clocks: a governor that changed between them explains a difference that
;; the cooler did not.
(define (compare-runs a b)
  (let* ((a (summary-path a))
         (b (summary-path b)))
    (unless (file-exists? a) (die (format #f "cannot read ~a" a)))
    (unless (file-exists? b) (die (format #f "cannot read ~a" b)))
    (for-each (lambda (key)
                (let ((left (meta a key))
                      (right (meta b key)))
                  (unless (string=? left right)
                    (say (format #f "~a differs: '~a' vs '~a'" key left right)))))
              '(cpu kernel governor workers method load_minutes))
    (let ((first (summary-rows a)))
      (format #t "sensor\tphase\t~a\t~a\tchange~%"
              (meta a "label") (meta b "label"))
      (for-each
       (lambda (fields)
         (let ((sensor (car fields))
               (phase (cadr fields))
               (mean (caddr fields)))
           (let ((other (find (lambda (row)
                                (and (string=? (car row) sensor)
                                  (string=? (cadr row) phase)))
                              first)))
             (when (and other
                     (string->number mean)
                     (string->number (caddr other)))
               (let ((change (- (string->number mean)
                                (string->number (caddr other)))))
                 (format #t "~a\t~a\t~a\t~a\t~a~,1f~%"
                         sensor phase (caddr other) mean
                         (if (>= change 0) "+" "")
                         change))))))
       (summary-rows b)))))

;; ===========================================
;; Self-test
;; ===========================================

;; The arithmetic a summary rests on is easy to get subtly wrong - an off-by-one
;; on the steady window, a mean over the wrong phase - and wrong in a way that
;; reads like a plausible temperature.  This builds samples whose answer is known
;; by hand: 11 idle samples at 30.0, and a 100 s load whose sensor `zeta` rises one
;; degree per second from 10.0, so the last 60 s of it average 80.0 and peak at
;; 110.0.
(define (write-synthetic path tag offset)
  (call-with-output-file path
                         (lambda (port)
                           (format port "# label: ~a~%" tag)
                           (format port "# workers: 1~%")
                           (format port "phase,elapsed_s,zeta,alpha_mid,cpu_mhz~%")
                           (do ((t 0 (1+ t))) ((> t 10))
                             (format port "idle,~a,~a.0,~a.0,1000~%"
                                     t (+ offset 30) (+ offset 40)))
                           (do ((t 0 (1+ t))) ((> t 100))
                             (format port "load,~a,~a.0,~a.0,3000~%"
                                     t (+ offset 10 t) (+ offset 20 t))))))

(define (assert-line text want)
  (unless (member want (string-split text #\newline))
    (die (format #f "summary is missing '~a'" want))))

(define (self-test)
  (let ((work (format #f "~a/heks-thermal-~a"
                      (or (getenv "TMPDIR") "/tmp")
                      (getpid))))
    (dynamic-wind
      (lambda () (make-directories work))
      (lambda ()
        (write-synthetic (format #f "~a/samples.csv" work) "synthetic-a" 0)
        (let ((summary (summarise (format #f "~a/samples.csv" work))))
          (call-with-output-file (format #f "~a/summary.txt" work)
                                 (lambda (port) (display summary port)))
          (assert-line summary "zeta\tidle\t30.0\t30.0\t11")
          (assert-line summary "zeta\tsteady\t80.0\t110.0\t61")
          (assert-line summary "cpu_mhz\tsteady\t3000.0\t3000.0\t61")

          ;; The same load five degrees hotter: the comparison has to say +5.0 and
          ;; nothing else.
          (write-synthetic (format #f "~a/hotter.csv" work) "synthetic-b" 5)
          (let ((hotter (summarise (format #f "~a/hotter.csv" work))))
            (call-with-output-file (format #f "~a/hotter.txt" work)
                                   (lambda (port) (display hotter port)))
            (let ((comparison
                   (with-output-to-string
                    (lambda ()
                      (compare-runs (format #f "~a/summary.txt" work)
                                    (format #f "~a/hotter.txt" work))))))
              (assert-line comparison "zeta\tsteady\t80.0\t85.0\t+5.0")

              ;; A label is how a run is asked for: compare looks a bare name up
              ;; among the runs under --out before it gives up on it.
              (make-directories (format #f "~a/synthetic-a" work))
              (make-directories (format #f "~a/synthetic-b" work))
              (call-with-output-file (format #f "~a/synthetic-a/summary.txt" work)
                                     (lambda (port) (display summary port)))
              (call-with-output-file (format #f "~a/synthetic-b/summary.txt" work)
                                     (lambda (port) (display hotter port)))
              (let ((saved out-dir))
                (set! out-dir work)
                (let ((by-label
                       (with-output-to-string
                        (lambda ()
                          (compare-runs "synthetic-a" "synthetic-b")))))
                  (set! out-dir saved)
                  (assert-line by-label "zeta\tsteady\t80.0\t85.0\t+5.0"))))))
        (say "self-test passed"))
      (lambda ()
        (catch #t (lambda () (system* "rm" "-rf" work)) (lambda _ #t))))))

;; ===========================================
;; Command line
;; ===========================================

(define (option-value args option)
  (if (null? args)
    (die (format #f "~a needs a value" option))
    (car args)))

(define (parse-run-options args)
  (let loop ((args args))
    (unless (null? args)
      (let ((option (car args)))
        (case (string->symbol option)
          [(--minutes)
           (set! minutes (option-value (cdr args) option))
           (loop (cddr args))]
          [(--idle)
           (let ((value (option-value (cdr args) option)))
             (set! idle-seconds (or (string->number value)
                                  (die "--idle takes whole seconds")))
             (loop (cddr args)))]
          [(--interval)
           (let ((value (option-value (cdr args) option)))
             (set! interval (or (string->number value)
                              (die "--interval takes whole seconds, at least one")))
             (loop (cddr args)))]
          [(--workers)
           (let ((value (option-value (cdr args) option)))
             (set! workers (or (string->number value)
                             (die "--workers takes a whole number, at least one")))
             (loop (cddr args)))]
          [(--label)
           (set! label (option-value (cdr args) option))
           (loop (cddr args))]
          [(--out)
           (set! out-dir (option-value (cdr args) option))
           (loop (cddr args))]
          [(-h --help help)
           (usage)
           (exit 0)]
          [(--)
           (loop (cdr args))]
          [else
            (if (string-prefix? "-" option)
              (begin
                (say (format #f "unknown option: ~a" option))
                (usage)
                (exit 2))
              ;; A positional argument ends the options, as it does for the
              ;; shell version this replaces.
              #t)])))))

(define (main args)
  (set! workers (cpu-count))
  (let* ((named (and (pair? args)
                  (member (car args)
                          '("run" "summarise" "compare" "self-test"
                            "help" "-h" "--help"))))
         (command (if named (car args) "run"))
         (rest (if named (cdr args) args)))
    (cond
      [(string=? command "summarise")
       (display (summarise (or (and (pair? rest) (car rest))
                             (die "summarise needs a samples.csv"))))]
      [(string=? command "compare")
       (compare-runs (or (and (pair? rest) (car rest))
                       (die "compare needs two runs"))
                     (or (and (pair? rest) (pair? (cdr rest)) (cadr rest))
                       (die "compare needs two runs")))]
      [(string=? command "self-test")
       (self-test)]
      [(member command '("help" "-h" "--help"))
       (usage)]
      [else
        (parse-run-options rest)
        (run-benchmark)]))
  (exit 0))

(main (cdr (command-line)))
