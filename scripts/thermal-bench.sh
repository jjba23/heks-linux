#!/usr/bin/env bash
# heks-linux
#
# SPDX-License-Identifier: MIT
# Copyright © Josep Bigorra <jjbigorra@gmail.com>
#
# Measure CPU temperature under a load that is the same load every time.
#
# Commentary:
#
# The number that says whether a repaste, a cooler or a fan curve helped is not
# the hottest reading ever seen: it is the temperature the machine settles at
# once the cooler has caught up, on the same workload, from the same starting
# point, with the same fan curve.  So each run is three fixed phases and one
# number per sensor:
#
# - idle, for a fixed number of seconds, so the run starts cold the same way
#   every time and the idle temperature is a reading of its own;
# - load, from `stress-ng --cpu N --cpu-method matrixprod' until its own timeout
#   stops it.  The method is pinned because stress-ng's default rotates through
#   its methods, and a heat load that depends on which second you sampled is not
#   a load you can compare across days;
# - the steady window, the last quarter of the load (at least a minute), which
#   is what the summary reports as mean and max.  The first part of a run is the
#   heatsink filling up, not the cooler's steady state.
#
# Every sample records the sensors hwmon exposes and the mean core clock, because
# a machine that throttles hits the same temperature at a lower clock and would
# otherwise look unchanged.
#
# What this cannot measure is room temperature, and it matters more than
# anything else on the page: a run an hour apart in a warmer room reads higher
# with nothing about the cooler changed.  Note it next to the label.
#
# Everything a run saw about itself - CPU, kernel, governor, worker count, load
# and duration - is written into the samples file, so a summary found six months
# later still says what it was measuring.

set -uo pipefail

me=${0##*/}

# Load duration in minutes; fractions are accepted (0.5 is thirty seconds).
minutes=10
# Seconds of idle sampling before the load starts.
idle_seconds=60
# Seconds between samples.
interval=1
# One worker per CPU unless told otherwise: the load is the machine's, and the
# count is recorded so a run on another machine cannot be mistaken for this one.
workers=$(nproc 2>/dev/null || printf '1')
# The fixed load.  See the commentary for why the method is not stress-ng's
# default.
method=matrixprod
label=""
out_dir=${XDG_DATA_HOME:-$HOME/.local/share}/heks-linux/thermal

die() {
    printf '%s: %s\n' "$me" "$*" >&2
    exit 1
}

say() {
    printf '%s: %s\n' "$me" "$*" >&2
}

usage() {
    cat <<EOF
$me - measure temperature under a fixed, repeatable load

  $me [run] [OPTIONS]
      Idle, then a full CPU load, sampling every hwmon sensor.  Writes
      samples.csv and summary.txt under --out.

      --minutes N     load duration in minutes (default $minutes; 0.5 = 30 s)
      --idle N        seconds of idle sampling first (default $idle_seconds)
      --interval N    seconds between samples (default $interval)
      --workers N     stress-ng workers (default one per CPU)
      --label NAME    run name, also the directory name (default a timestamp)
      --out DIR       where runs are kept (default $out_dir)

  $me summarise CSV
      Print the summary of an existing samples.csv.

  $me compare A B
      Per-sensor idle and steady-state difference between two runs, given as
      run directories or summary files.  Warns when the two runs were not the
      same setup.

  $me self-test
      Check the summary arithmetic and the comparison on synthetic samples.

A run cannot see the room temperature, and a repaste judged an hour apart in a
warmer room reads worse than it is: keep the room, the fan curve and the session
the same, and write the ambient next to the label.
EOF
}

# ===========================================
# The sensors
# ===========================================

# hwmon's own names and labels, with everything a CSV or a shell would trip over
# turned into an underscore: `cros_ec' calls one of its inputs
# `cpu_f75303@4d', and a column full of @ in a file somebody greps is a column
# somebody quotes wrong.
sanitise() {
    local text=$1
    text=${text//[![:alnum:]]/_}
    while [[ $text == *__* ]]; do
        text=${text//__/_}
    done
    printf '%s' "${text#_}" | sed 's/_$//'
}

# Two devices of the same kind report the same name - a pair of spd5118 sticks,
# or two NVMe drives - so a repeated column gains a suffix instead of a second
# column nobody can tell apart.  The count lives in an array, so the caller gets
# the name through a variable: a command substitution would run in a subshell
# and forget every count it made.
declare -A column_seen=()
next_column() {
    local base=$1
    local count=$(( ${column_seen[$base]:-0} + 1 ))
    column_seen[$base]=$count
    if [ "$count" -eq 1 ]; then
        column=$base
    else
        column="${base}_$count"
    fi
}

sensor_columns=()
sensor_paths=()
# Set by `next_column'; see the comment there for why it is not returned.
column=""

discover_sensors() {
    local dir name file base tag
    for dir in /sys/class/hwmon/hwmon*; do
        [ -d "$dir" ] || continue
        name=$(cat "$dir/name" 2>/dev/null) || continue
        [ -n "$name" ] || continue
        for file in "$dir"/temp*_input; do
            [ -r "$file" ] || continue
            base=${file%_input}
            tag=""
            [ -r "${base}_label" ] && tag=$(cat "${base}_label" 2>/dev/null)
            next_column "$(sanitise "${name}${tag:+_$tag}")"
            sensor_columns+=("$column")
            sensor_paths+=("$file")
        done
    done
}

# hwmon reports millidegrees.  One decimal is the precision a comparison needs,
# and the arithmetic is done here rather than by a program per value: a ten
# minute run is six hundred samples of a dozen sensors.
temperature() {
    local raw sign="" whole frac
    raw=$(cat "$1" 2>/dev/null) || return 0
    [[ $raw =~ ^-?[0-9]+$ ]] || return 0
    if [ "$raw" -lt 0 ]; then
        sign=-
        raw=$(( -raw ))
    fi
    whole=$(( raw / 1000 ))
    frac=$(( (raw % 1000) / 100 ))
    printf '%s%d.%d' "$sign" "$whole" "$frac"
}

# The mean core clock is the other half of a temperature reading: a machine that
# throttles settles at the same degrees while doing less work.
cpu_mhz() {
    local file sum=0 count=0
    for file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        [ -r "$file" ] || continue
        sum=$(( sum + $(cat "$file" 2>/dev/null || printf '0') ))
        count=$(( count + 1 ))
    done
    [ "$count" -gt 0 ] || return 0
    printf '%d' $(( sum / count / 1000 ))
}

csv_join() {
    local IFS=,
    printf '%s' "$*"
}

sample_row() {
    local phase=$1 elapsed=$2 path values=()
    for path in "${sensor_paths[@]}"; do
        values+=("$(temperature "$path")")
    done
    values+=("$(cpu_mhz)")
    printf '%s,%s,%s\n' "$phase" "$elapsed" "$(csv_join "${values[@]}")"
}

# ===========================================
# The load
# ===========================================

cpu_model() {
    local model
    model=$(awk -F: '/^model name/ { sub(/^ +/, "", $2); print $2; exit }' /proc/cpuinfo)
    printf '%s' "${model:-$(uname -m)}"
}

governors() {
    local file
    for file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -r "$file" ] || continue
        cat "$file" 2>/dev/null
    done | awk 'NF && !seen[$0]++ { printf "%s%s", sep, $0; sep = "," }'
}

load_pid=""
bench_csv=""
bench_dir=""

stop_load() {
    [ -n "$load_pid" ] || return 0
    kill "$load_pid" 2>/dev/null
    wait "$load_pid" 2>/dev/null
    load_pid=""
}

# A run that was interrupted still has samples worth keeping, and a summary of a
# shortened load says so through its own load_seconds.
finish() {
    if ! awk -F, '$1 == "load" { found = 1 } END { exit found ? 0 : 1 }' "$bench_csv"; then
        die "the load produced no samples; the run is in $bench_dir"
    fi
    summarise "$bench_csv" > "$bench_dir/summary.txt" ||
        die "cannot write $bench_dir/summary.txt"
    cat "$bench_dir/summary.txt"
    say "run written to $bench_dir"
}

run_benchmark() {
    local load_length start elapsed load_start status

    command -v stress-ng > /dev/null ||
        die "stress-ng is not installed; on Slowroll: sudo zypper install stress-ng"
    load_length=$(awk -v m="$minutes" 'BEGIN { if (m <= 0) exit 1; printf "%d", m * 60 }') ||
        die "--minutes must be more than zero"
    [[ $idle_seconds =~ ^[0-9]+$ ]] || die "--idle takes whole seconds"
    [[ $interval =~ ^[1-9][0-9]*$ ]] || die "--interval takes whole seconds, at least one"
    [[ $workers =~ ^[1-9][0-9]*$ ]] || die "--workers takes a whole number, at least one"

    discover_sensors
    [ "${#sensor_paths[@]}" -gt 0 ] ||
        die "no temperature sensor under /sys/class/hwmon; nothing to measure"

    [ -n "$label" ] || label="run-$(date -u +%Y%m%dT%H%M%SZ)"
    bench_dir="$out_dir/$label"
    bench_csv="$bench_dir/samples.csv"
    [ -e "$bench_dir" ] &&
        die "$bench_dir already exists; give this run another --label"
    mkdir -p "$bench_dir" || die "cannot create $bench_dir"

    {
        printf '# label: %s\n' "$label"
        printf '# started: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '# cpu: %s\n' "$(cpu_model)"
        printf '# kernel: %s\n' "$(uname -r)"
        printf '# governor: %s\n' "$(governors)"
        printf '# workers: %s\n' "$workers"
        printf '# method: %s\n' "$method"
        printf '# load_minutes: %s\n' "$minutes"
        printf '# idle_seconds: %s\n' "$idle_seconds"
        printf '# interval_seconds: %s\n' "$interval"
        printf 'phase,elapsed_s,%s,cpu_mhz\n' "$(csv_join "${sensor_columns[@]}")"
    } > "$bench_csv" || die "cannot write $bench_csv"

    trap 'stop_load; finish; exit 130' INT TERM

    say "idle for ${idle_seconds}s"
    start=$(date +%s)
    # Sampled before the clock is judged, not after: a run that starts on a
    # second boundary would otherwise decide the idle phase was over before it
    # took a single sample, and a summary with no idle row cannot say where the
    # run started from.
    while :; do
        elapsed=$(( $(date +%s) - start ))
        sample_row idle "$elapsed" >> "$bench_csv"
        [ "$elapsed" -ge "$idle_seconds" ] && break
        sleep "$interval"
    done

    say "loading ${workers} workers for ${load_length}s"
    stress-ng --cpu "$workers" --cpu-method "$method" --timeout "${load_length}s" --quiet &
    load_pid=$!
    load_start=$(date +%s)
    while kill -0 "$load_pid" 2>/dev/null; do
        sample_row load $(( $(date +%s) - load_start )) >> "$bench_csv"
        sleep "$interval"
    done
    wait "$load_pid" 2>/dev/null
    status=$?
    load_pid=""
    trap - INT TERM

    [ "$status" -eq 0 ] || die "stress-ng failed with status $status"
    finish
}

# ===========================================
# The record of a run
# ===========================================

# The summary answers one question per sensor: what did the machine settle at,
# and what did it touch on the way.  The steady window is the last quarter of
# the load, or the last minute when the load was shorter than four.
summarise() {
    local csv=${1:?summarise needs a samples.csv}
    [ -r "$csv" ] || die "cannot read $csv"
    awk -F, '
        /^#/ { print; next }
        !header_seen {
            header_seen = 1
            columns = NF
            for (i = 3; i <= NF; i++) column[i] = $i
            next
        }
        {
            rows++
            phase[rows] = $1
            at[rows] = $2 + 0
            for (i = 3; i <= NF; i++) {
                if ($i == "") continue
                value[rows, i] = $i + 0
                read[rows, i] = 1
            }
            if ($1 == "load" && $2 + 0 > load_seconds) load_seconds = $2 + 0
        }
        END {
            if (rows == 0) {
                print "no samples in the file" > "/dev/stderr"
                exit 1
            }
            window = load_seconds / 4
            if (window < 60) window = 60
            if (window > load_seconds) window = load_seconds
            steady_from = load_seconds - window
            for (r = 1; r <= rows; r++) {
                if (phase[r] == "idle") p = "idle"
                else if (phase[r] == "load" && at[r] >= steady_from) p = "steady"
                else continue
                for (i = 3; i <= columns; i++) {
                    if (!read[r, i]) continue
                    sum[p, i] += value[r, i]
                    if (count[p, i]++ == 0 || value[r, i] > peak[p, i])
                        peak[p, i] = value[r, i]
                }
            }
            printf "# load_seconds: %d\n", load_seconds
            printf "# steady_window_seconds: %d\n", window
            print "sensor\tphase\tmean\tmax\tsamples"
            for (k = 1; k <= 2; k++) {
                p = (k == 1) ? "idle" : "steady"
                for (i = 3; i <= columns; i++) {
                    if (count[p, i] == 0) {
                        printf "%s\t%s\t-\t-\t0\n", column[i], p
                        continue
                    }
                    printf "%s\t%s\t%.1f\t%.1f\t%d\n", column[i], p,
                           sum[p, i] / count[p, i], peak[p, i], count[p, i]
                }
            }
        }
    ' "$csv"
}

# ===========================================
# Comparing runs
# ===========================================

meta() {
    awk -v prefix="# $2: " 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' "$1"
}

# Two runs are only comparable when the machine was under the same load at the
# same clocks: a governor that changed between them explains a difference that
# the cooler did not.
compare() {
    local a=${1:?compare needs two runs}
    local b=${2:?compare needs two runs}
    # A run is named by its label as often as by its path - `compare before
    # after' is how it is actually typed - and the labels live under --out.
    [ -e "$a" ] || a="$out_dir/$a"
    [ -e "$b" ] || b="$out_dir/$b"
    [ -d "$a" ] && a=$a/summary.txt
    [ -d "$b" ] && b=$b/summary.txt
    [ -r "$a" ] || die "cannot read $a"
    [ -r "$b" ] || die "cannot read $b"

    local key left right
    for key in cpu kernel governor workers method load_minutes; do
        left=$(meta "$a" "$key")
        right=$(meta "$b" "$key")
        [ "$left" = "$right" ] ||
            say "$key differs: '$left' vs '$right'"
    done

    printf 'sensor\tphase\t%s\t%s\tchange\n' "$(meta "$a" label)" "$(meta "$b" label)"
    awk -F'\t' '
        FNR == NR {
            if ($0 !~ /^#/ && NF == 5 && $1 != "sensor") first[$1, $2] = $3
            next
        }
        $0 !~ /^#/ && NF == 5 && $1 != "sensor" && (($1, $2) in first) {
            printf "%s\t%s\t%s\t%s\t%+.1f\n", $1, $2, first[$1, $2], $3, $3 - first[$1, $2]
        }
    ' "$a" "$b"
}

# ===========================================
# Self-test
# ===========================================

# The arithmetic a summary rests on is easy to get subtly wrong - an off-by-one
# on the steady window, a mean over the wrong phase - and wrong in a way that
# reads like a plausible temperature.  This builds samples whose answer is known
# by hand: 11 idle samples at 30.0, and a 100 s load whose sensor `zeta` rises one
# degree per second from 10.0, so the last 60 s of it average 80.0 and peak at
# 110.0.
self_test() {
    local tmp
    tmp=$(mktemp -d) || die "cannot create a temporary directory"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT

    awk 'BEGIN {
        print "# label: synthetic-a"
        print "# workers: 1"
        print "phase,elapsed_s,zeta,alpha_mid,cpu_mhz"
        for (t = 0; t <= 10; t++)  print "idle," t ",30.0,40.0,1000"
        for (t = 0; t <= 100; t++) print "load," t "," (10 + t) ".0," (20 + t) ".0,3000"
    }' > "$tmp/samples.csv"

    summarise "$tmp/samples.csv" > "$tmp/summary.txt" || die "summarise failed"
    assert_summary "$tmp/summary.txt" \
                   $'zeta\tidle\t30.0\t30.0\t11' \
                   $'zeta\tsteady\t80.0\t110.0\t61' \
                   $'cpu_mhz\tsteady\t3000.0\t3000.0\t61'

    # The same load five degrees hotter: the comparison has to say +5.0 and
    # nothing else.
    awk 'BEGIN {
        print "# label: synthetic-b"
        print "# workers: 1"
        print "phase,elapsed_s,zeta,alpha_mid,cpu_mhz"
        for (t = 0; t <= 10; t++)  print "idle," t ",35.0,45.0,1000"
        for (t = 0; t <= 100; t++) print "load," t "," (15 + t) ".0," (25 + t) ".0,3000"
    }' > "$tmp/hotter.csv"
    summarise "$tmp/hotter.csv" > "$tmp/hotter.txt" || die "summarise failed"

    compare "$tmp/summary.txt" "$tmp/hotter.txt" > "$tmp/compare.txt" 2> /dev/null ||
        die "compare failed"
    grep -qx $'zeta\tsteady\t80.0\t85.0\t+5.0' "$tmp/compare.txt" ||
        die "compare did not report a +5.0 steady-state rise:$(printf '\n%s' "$(cat "$tmp/compare.txt")")"

    # A label is how a run is asked for: compare looks a bare name up among the
    # runs under --out before it gives up on it.
    mkdir -p "$tmp/synthetic-a" "$tmp/synthetic-b"
    cp "$tmp/summary.txt" "$tmp/synthetic-a/summary.txt"
    cp "$tmp/hotter.txt" "$tmp/synthetic-b/summary.txt"
    ( out_dir=$tmp; compare synthetic-a synthetic-b ) > "$tmp/by-label.txt" 2> /dev/null ||
        die "compare did not find runs by label"
    grep -qx $'zeta\tsteady\t80.0\t85.0\t+5.0' "$tmp/by-label.txt" ||
        die "compare by label printed something else"

    say "self-test passed"
}

assert_summary() {
    local file=$1
    shift
    local want
    for want in "$@"; do
        grep -qx -- "$want" "$file" ||
            die "summary is missing '${want//$'\t'/ | }'"
    done
}

# ===========================================
# Command line
# ===========================================

main() {
    local command=run
    case ${1:-} in
        run | summarise | compare | self-test | help | -h | --help)
            command=$1
            shift
            ;;
    esac

    case $command in
        summarise) summarise "${1:?summarise needs a samples.csv}" ;;
        compare) compare "${1:?compare needs two runs}" "${2:?compare needs two runs}" ;;
        self-test) self_test ;;
        help | -h | --help) usage ;;
        run)
            while [ $# -gt 0 ]; do
                case $1 in
                    --minutes)
                        minutes=${2:?--minutes needs a value}
                        shift 2
                        ;;
                    --idle)
                        idle_seconds=${2:?--idle needs a value}
                        shift 2
                        ;;
                    --interval)
                        interval=${2:?--interval needs a value}
                        shift 2
                        ;;
                    --workers)
                        workers=${2:?--workers needs a value}
                        shift 2
                        ;;
                    --label)
                        label=${2:?--label needs a value}
                        shift 2
                        ;;
                    --out)
                        out_dir=${2:?--out needs a value}
                        shift 2
                        ;;
                    -h | --help | help)
                        usage
                        return 0
                        ;;
                    --)
                        shift
                        ;;
                    -*)
                        say "unknown option: $1"
                        usage >&2
                        return 2
                        ;;
                    *) break ;;
                esac
            done
            run_benchmark
            ;;
    esac
}

main "$@"
