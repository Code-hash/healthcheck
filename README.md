# VM Health Check

`healthcheck.sh` is a Bash script that performs a point-in-time health check of a Linux virtual machine. It checks CPU utilization, memory usage, and usage of the root filesystem, then reports an overall `OK`, `WARNING`, or `CRITICAL` status.

## Requirements

- Linux with readable `/proc/stat`, `/proc/meminfo`, and `/proc/loadavg`
- Bash, `awk`, `df`, `sleep`, and `getconf`

## Usage

Run a compact status line:

```bash
bash healthcheck.sh
```

Show a detailed report with metric values, thresholds, and notes about what is checked:

```bash
bash healthcheck.sh explain
```

You can also make the script executable and run it directly:

```bash
chmod +x healthcheck.sh
./healthcheck.sh
./healthcheck.sh explain
```

## Checks and thresholds

| Metric | What is measured | Warning | Critical |
| --- | --- | ---: | ---: |
| CPU | Utilization sampled over one second | 75% | 90% |
| Memory | Used memory, calculated using `MemAvailable` when provided by Linux | 80% | 90% |
| Disk | Usage of the root (`/`) filesystem | 80% | 90% |

The detailed report also includes the number of online logical CPUs and the one-minute load average for context. Load average is not used to determine CPU status.

Overall status is `CRITICAL` if any checked metric is critical; otherwise it is `WARNING` if any metric is at warning level; otherwise it is `OK`.

## Exit codes

- `0` — all checked metrics are OK
- `1` — at least one metric is at warning level
- `2` — at least one metric is critical, or the script could not run the check

## Scope

This script checks CPU, memory, and the root filesystem only. It does not check services, network connectivity, or other mounted filesystems. Results represent the system state at the time of the check.
