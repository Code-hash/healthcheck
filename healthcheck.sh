#!/usr/bin/env bash
# Check basic Linux VM health (CPU utilization, memory, and root filesystem).
set -u

usage() {
  printf 'Usage: %s [explain]\n' "${0##*/}"
  printf '  explain  Show metric details, thresholds, and an overall health summary.\n'
}

explain=false
if (( $# > 1 )); then
  usage >&2
  exit 2
fi
if (( $# == 1 )); then
  case "$1" in
    explain) explain=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
fi

for command in awk df sleep getconf; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "$command" >&2
    exit 2
  fi
done
if [[ ! -r /proc/stat || ! -r /proc/meminfo || ! -r /proc/loadavg ]]; then
  printf 'ERROR: this script requires Linux /proc information.\n' >&2
  exit 2
fi

# Return total and idle CPU ticks from the aggregate CPU line.
read_cpu_ticks() {
  awk '/^cpu / { idle=$5+$6; total=0; for (i=2; i<=NF; i++) total+=$i; printf "%.0f %.0f\n", total, idle; exit }' /proc/stat
}

read -r total_before idle_before < <(read_cpu_ticks)
sleep 1
read -r total_after idle_after < <(read_cpu_ticks)
if (( total_after <= total_before )); then
  printf 'ERROR: could not read CPU counters.\n' >&2
  exit 2
fi
cpu_percent=$(awk -v tb="$total_before" -v ta="$total_after" -v ib="$idle_before" -v ia="$idle_after" 'BEGIN { printf "%.1f", 100 * (1 - (ia-ib)/(ta-tb)) }')

memory_values=$(awk '
  /^MemTotal:/ { total=$2 }
  /^MemAvailable:/ { available=$2 }
  END {
    if (!total) exit 1
    if (!available) available=0
    printf "%.0f %.0f %.1f", total/1024, available/1024, 100*(total-available)/total
  }
' /proc/meminfo) || {
  printf 'ERROR: could not read memory information.\n' >&2
  exit 2
}
read -r memory_total_mb memory_available_mb memory_percent <<< "$memory_values"

 disk_percent=$(df -P / | awk 'NR==2 { gsub("%", "", $5); print $5 }')
if [[ ! "$disk_percent" =~ ^[0-9]+$ ]]; then
  printf 'ERROR: could not read root filesystem usage.\n' >&2
  exit 2
fi

cpu_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')
load_average=$(awk '{print $1}' /proc/loadavg)

status_for() {
  local value=$1 warning=$2 critical=$3
  awk -v value="$value" -v warning="$warning" -v critical="$critical" 'BEGIN {
    if (value >= critical) print "CRITICAL"
    else if (value >= warning) print "WARNING"
    else print "OK"
  }'
}

cpu_status=$(status_for "$cpu_percent" 75 90)
memory_status=$(status_for "$memory_percent" 80 90)
disk_status=$(status_for "$disk_percent" 80 90)
overall=OK
for status in "$cpu_status" "$memory_status" "$disk_status"; do
  if [[ "$status" == CRITICAL ]]; then overall=CRITICAL; break; fi
  if [[ "$status" == WARNING ]]; then overall=WARNING; fi
done

if [[ "$explain" == true ]]; then
  printf 'Virtual machine health report\n'
  printf '=============================\n'
  printf 'Overall: %s\n\n' "$overall"
  printf 'CPU:     %s — %s%% utilization over a 1-second sample (warning at 75%%, critical at 90%%).\n' "$cpu_status" "$cpu_percent"
  printf '         Online logical CPUs: %s; 1-minute load average: %s. Load average is reported for context and is not itself used for the CPU status.\n' "$cpu_cores" "$load_average"
  printf 'Memory:  %s — %s%% used; %s MiB available of %s MiB (warning at 80%%, critical at 90%%).\n' "$memory_status" "$memory_percent" "$memory_available_mb" "$memory_total_mb"
  printf 'Disk:    %s — root filesystem is %s%% used (warning at 80%%, critical at 90%%).\n\n' "$disk_status" "$disk_percent"
  printf 'Status meanings: OK is below the warning threshold; WARNING indicates elevated usage; CRITICAL indicates usage at or above the critical threshold.\n'
  printf 'This is a point-in-time check of CPU, memory, and the root filesystem; it does not test services, network connectivity, or other mounted filesystems.\n'
else
  printf 'VM health: %s | CPU %s%% (%s) | Memory %s%% (%s) | Root disk %s%% (%s)\n' \
    "$overall" "$cpu_percent" "$cpu_status" "$memory_percent" "$memory_status" "$disk_percent" "$disk_status"
fi

if [[ "$overall" == CRITICAL ]]; then exit 2; fi
if [[ "$overall" == WARNING ]]; then exit 1; fi
exit 0
