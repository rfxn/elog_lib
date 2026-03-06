# elog_lib — Structured Event Logging for Bash

[![CI](https://github.com/rfxn/elog_lib/actions/workflows/ci.yml/badge.svg)](https://github.com/rfxn/elog_lib/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/rfxn/elog_lib)
[![Bash](https://img.shields.io/badge/bash-4.1%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-GPL%20v2-orange.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A shared Bash library for structured event logging with a dual log model
(application + audit), output module registry, event taxonomy, and classic/JSON
output formats. Source it into your script, set environment variables, and call
`elog` to log — no dependencies, no subprocesses.

Consumed by [BFD](https://github.com/rfxn/linux-brute-force-detection),
[LMD](https://github.com/rfxn/linux-malware-detect), and
[APF](https://github.com/rfxn/linux-firewall) via source inclusion.

```bash
source /opt/myapp/lib/elog_lib.sh
elog_init
elog info "application started"
elog_event "config_loaded" "info" "configuration validated" "file=/etc/myapp.conf"
```

## Features

- **Dual log model** — application log (human-readable) + audit log (always JSONL)
- **Classic and JSON output formats** — syslog-style or structured JSON per line
- **5 severity levels** with configurable minimum threshold filtering
- **Structured event envelope** — `elog_event()` with JSONL dispatch to audit log
- **23-type event taxonomy** across 7 categories with default severity mapping
- **Output module registry** — parallel indexed arrays with source filtering
- **Tag extraction** from `{tag}` message prefix for structured context
- **Log truncation** via `ELOG_LOG_MAX_LINES` (inode-preserving tail+cat)
- **Logrotate config generation** via `elog_logrotate_snippet()`
- **Legacy log path symlinks** for backward-compatible log locations
- **Pre-init auto-enable fallback** — works without calling `elog_init()` first
- **Zero project-specific references** — all context via environment variables

## Platform Support

elog_lib targets deep legacy through current production distributions:

| Distribution | Versions | Bash | Notes |
|---|---|---|---|
| CentOS | 6, 7 | 4.1, 4.2 | Bash 4.1 floor target |
| Rocky Linux | 8, 9, 10 | 4.4, 5.1, 5.2 | Primary RHEL-family targets |
| Debian | 12 | 5.2 | Primary test target |
| Ubuntu | 12.04, 14.04, 20.04, 24.04 | 4.2–5.2 | Deep legacy through current LTS |
| Slackware, Gentoo, FreeBSD | Various | 4.1+ | Functional where Bash is available |

**Minimum requirement: Bash 4.1** (ships with CentOS 6, released 2011). No
Bash 4.2+ features are used — no `${var,,}`, `mapfile -d`, `declare -n`, or
`$EPOCHSECONDS`. No external dependencies beyond coreutils.

## Quick Start

### With elog_init (recommended)

```bash
source /opt/myapp/lib/elog_lib.sh
ELOG_APP="myapp"
ELOG_LOG_DIR="/var/log/myapp"
elog_init

elog info "application started"
elog warn "{auth} failed login attempt"
elog_event "scan_started" "info" "starting security scan" "target=/var/www"
```

`elog_init()` creates the log directory, touches log files with correct
permissions, enables output modules, and optionally creates a legacy symlink.

### Without elog_init (backward compat)

```bash
source /opt/myapp/lib/elog_lib.sh
ELOG_APP="myapp"
ELOG_LOG_FILE="/var/log/myapp.log"

elog info "works without init"
```

When `elog_init()` is not called, the library auto-enables output modules on
first use. This supports BFD's drop-in pattern where `ELOG_LOG_FILE` is set
and changed dynamically between calls.

## Architecture

### Dual Log Model

Each consuming project gets two log files:

1. **Application log** (`<project>.log`) — human-readable, classic syslog-style
   or JSON. Written by `elog()`. Subject to truncation.
2. **Audit log** (`audit.log`) — machine-readable, always JSONL. Written by
   `elog_event()` only. Never truncated.

Standard paths: `/var/log/<project>/<project>.log` + `/var/log/<project>/audit.log`

### Output Module Registry

Four built-in output modules are registered at source time but start disabled
(enabled by `elog_init()` or auto-enable fallback):

| Module | Handler | Format | Source | Description |
|--------|---------|--------|--------|-------------|
| `file` | `_elog_out_file` | classic | `elog` | Append to `ELOG_LOG_FILE` |
| `audit_file` | `_elog_out_audit` | json | `event` | Append JSONL to `ELOG_AUDIT_FILE` |
| `syslog_file` | `_elog_out_syslog_file` | classic | `elog` | Append to `ELOG_SYSLOG_FILE` |
| `stdout` | `_elog_out_stdout` | classic | `all` | Terminal output with prefix modes |

**Source filtering** prevents cross-contamination: `elog()` dispatches with
`api_source="elog"` (reaches `file`, `syslog_file`, `stdout`), while
`elog_event()` dispatches with `api_source="event"` (reaches `audit_file`,
`stdout`). Modules with `source="all"` receive both.

Custom modules can be registered with `elog_output_register` for additional
output targets (e.g., CEF, remote syslog).

### Dispatch Flow

```
elog("info", "message")
  → severity filter (ELOG_LEVEL)
  → _elog_auto_enable (if no init)
  → build classic + JSON lines
  → _elog_dispatch("elog", ...) → file, syslog_file, stdout

elog_event("block_added", "warn", "blocked host", "ip=1.2.3.4")
  → severity filter (ELOG_LEVEL)
  → _elog_auto_enable (if no init)
  → build JSON envelope + classic line
  → _elog_dispatch("event", ...) → audit_file, stdout
```

## API Reference

### Public Functions

#### elog_init()

Initialize log environment. Creates log directory, touches log files, sets
permissions, creates legacy symlinks, auto-enables output modules.

Call once at consumer startup after setting `ELOG_APP`.

**Returns:** 0 on success, 1 on failure (directory creation failed).

```bash
ELOG_APP="myapp"
ELOG_LOG_DIR="/var/log/myapp"
elog_init
```

#### elog(level, message [, stdout_flag])

Primary logging function. Backward compatible with BFD v1.0.0 API.

**Arguments:**
- `level` — `debug`, `info`, `warn`, `error`, `critical`
- `message` — log message text (may include `{tag}` prefix)
- `stdout_flag` — when `ELOG_STDOUT=flag`, non-empty enables stdout output

**Behavior:**
- `debug`: stdout only (bare text), gated by `ELOG_VERBOSE=1`, never writes files
- `info`+: formatted output routed through dispatch to enabled modules
- Empty message: no output (returns 0)

**Returns:** 0 always (logging must never cause caller failure).

```bash
elog info "application started"
elog warn "{sshd} brute force detected"
elog error "failed to write state file"
elog debug "verbose detail here"
```

#### elog_debug/info/warn/error/critical(message [, stdout_flag])

Convenience wrappers that call `elog` with the corresponding level.

```bash
elog_info "application started"
elog_warn "disk usage high"
elog_error "write failed"
elog_critical "system unrecoverable"
```

#### elog_event(event_type, severity, message [, key=val ...])

Structured event logging. Dispatches via `api_source="event"` to `audit_file`
and any custom modules registered with `source="event"` or `source="all"`.

**Arguments:**
- `event_type` — event type name (see taxonomy below)
- `severity` — `debug`, `info`, `warn`, `error`, `critical`
- `message` — event description (may include `{tag}` prefix)
- `key=val` — zero or more key=value pairs added to JSON envelope

**Returns:** 0 on success, 1 on empty type.

```bash
elog_event "block_added" "warn" "{sshd} blocked host" "ip=198.51.100.5" "count=15"
elog_event "scan_completed" "info" "scan finished" "files=1234" "hits=0"
```

JSON output:
```json
{"ts":"2026-03-06T12:00:00-0500","host":"srv1","app":"bfd","pid":1234,"type":"block_added","level":"warn","tag":"sshd","msg":"blocked host","ip":"198.51.100.5","count":"15"}
```

#### elog_output_register(name, handler_fn, format, source)

Register a custom output module.

**Arguments:**
- `name` — module identifier
- `handler_fn` — function name to call with formatted line
- `format` — `classic`, `json`, or `cef` (selects which formatted line to pass)
- `source` — `all`, `elog`, or `event` (source filter)

**Returns:** 0 on success, 1 if name/handler empty or name already registered.

#### elog_output_enable(name) / elog_output_disable(name) / elog_output_enabled(name)

Enable, disable, or check status of a registered output module.

**Returns:** 0 on success/enabled, 1 if not registered or disabled.

#### elog_logrotate_snippet()

Output logrotate config to stdout. Consumer pipes to `/etc/logrotate.d/<project>`.
Respects `ELOG_ROTATE_FREQUENCY`, `ELOG_ROTATE_COUNT`, `ELOG_ROTATE_COMPRESS`.

```bash
elog_logrotate_snippet > /etc/logrotate.d/myapp
```

### Internal Functions

Internal functions (underscore prefix) are not part of the public API:

- `_elog_level_num(name)` / `_elog_level_name(num)` — level name/number conversion
- `_elog_json_escape(str)` — escape string for JSON embedding
- `_elog_extract_tag(msg)` / `_elog_strip_tag(msg)` — `{tag}` prefix handling
- `_elog_truncate_check()` — periodic app log truncation
- `_elog_auto_enable()` — pre-init module enable fallback
- `_elog_dispatch(api, classic, json, level, msg, flag)` — route to enabled modules
- `_elog_output_find(name)` — locate module index (sets `_ELOG_OUTPUT_IDX`)
- `_elog_event_type_valid(type)` — check if type is in canonical taxonomy
- `_elog_event_severity(type)` — default severity for event type
- `_elog_out_file/audit/syslog_file/stdout` — built-in output handlers

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ELOG_APP` | `basename $0` | Application name in log lines |
| `ELOG_LOG_DIR` | `/var/log/${ELOG_APP}` | Log directory path |
| `ELOG_LOG_FILE` | `${ELOG_LOG_DIR}/${ELOG_APP}.log` | Primary application log file |
| `ELOG_AUDIT_FILE` | `${ELOG_LOG_DIR}/audit.log` | Audit log file (always JSONL) |
| `ELOG_SYSLOG_FILE` | *(empty)* | Secondary syslog output file (empty = disabled) |
| `ELOG_LEGACY_LOG` | *(empty)* | Old log path; `elog_init()` creates symlink to new path |
| `ELOG_LEVEL` | `1` | Minimum severity: 0=debug 1=info 2=warn 3=error 4=critical |
| `ELOG_VERBOSE` | `0` | When `1`, debug-level messages emit to stdout |
| `ELOG_FORMAT` | `classic` | Output format: `classic` or `json` |
| `ELOG_TS_FORMAT` | `%b %e %H:%M:%S` | Timestamp strftime format |
| `ELOG_STDOUT` | `always` | Stdout mode: `always`, `never`, or `flag` |
| `ELOG_STDOUT_PREFIX` | `full` | Stdout prefix: `full`, `short`, or `none` |
| `ELOG_LOG_MAX_LINES` | `0` | Max app log lines before truncation (0 = disabled) |
| `ELOG_ROTATE_FREQUENCY` | `weekly` | Logrotate frequency |
| `ELOG_ROTATE_COUNT` | `12` | Logrotate keep count |
| `ELOG_ROTATE_COMPRESS` | `compress` | Logrotate compression setting |

## Event Taxonomy

23 canonical event types across 7 categories. The taxonomy is guidance —
`elog_event()` does not enforce type validation; consumers may pass any string.

| Category | Event Type | Default Severity | Description |
|----------|-----------|-----------------|-------------|
| Detection | `threat_detected` | warn | Malware or intrusion detected |
| Detection | `threshold_exceeded` | warn | Rate/count threshold breached |
| Detection | `pattern_matched` | info | Signature or pattern match |
| Detection | `scan_started` | info | Scan operation begun |
| Detection | `scan_completed` | info | Scan operation finished |
| Enforcement | `block_added` | warn | IP/host blocked |
| Enforcement | `block_removed` | info | Block expired or removed |
| Enforcement | `block_escalated` | error | Block upgraded to permanent |
| Enforcement | `quarantine_added` | warn | File quarantined |
| Enforcement | `quarantine_removed` | info | File restored from quarantine |
| Trust | `trust_added` | info | IP/host added to trust list |
| Trust | `trust_removed` | info | IP/host removed from trust list |
| Network | `rule_loaded` | info | Firewall rule applied |
| Network | `rule_removed` | info | Firewall rule removed |
| Network | `service_state` | info | Service started/stopped |
| Alert | `alert_sent` | info | Alert delivered successfully |
| Alert | `alert_failed` | error | Alert delivery failed |
| Monitor | `monitor_started` | info | Monitor daemon started |
| Monitor | `monitor_stopped` | info | Monitor daemon stopped |
| System | `config_loaded` | info | Configuration loaded |
| System | `config_error` | error | Configuration error |
| System | `file_cleaned` | info | Malicious file cleaned |
| System | `error_occurred` | error | General error |

## Custom Output Modules

Register custom output modules for additional destinations:

```bash
# CEF output module example
_my_cef_handler() {
    local line="$1"
    echo "$line" >> /var/log/cef.log
}
elog_output_register "cef" "_my_cef_handler" "classic" "event"
elog_output_enable "cef"
# Now elog_event() output also goes to /var/log/cef.log
```

## Testing

116 tests across 7 BATS files:

| File | Tests | Coverage |
|------|-------|----------|
| `00-scaffold.bats` | 3 | Library loading, version, source guard |
| `01-elog-core.bats` | 40 | elog(), formats, severity, debug, stdout, helpers |
| `02-elog-init.bats` | 19 | elog_init(), permissions, symlinks, truncation |
| `03-elog-output.bats` | 22 | Registry, dispatch, source filtering, format selection |
| `04-elog-event.bats` | 16 | Event envelope, JSON, key=value, tag, filtering |
| `05-elog-taxonomy.bats` | 8 | Type validation, severity mapping |
| `06-elog-compat.bats` | 8 | Backward compat, no-init drop-in |

```bash
make -C tests test              # Debian 12 (primary)
make -C tests test-rocky9       # Rocky 9
make -C tests test-centos6      # CentOS 6 (bash 4.1 floor)
make -C tests test-all          # Full 9-OS sequential matrix
make -C tests test-all-parallel # Full 9-OS parallel matrix
```

Tests run inside Docker containers via [batsman](https://github.com/rfxn/batsman).
CI runs lint + full matrix on every push via GitHub Actions.

## Installation

elog_lib is designed to be embedded in consuming projects, not installed
standalone. Copy the library into your project tree:

```bash
cp files/elog_lib.sh /opt/myapp/lib/
chown root:root /opt/myapp/lib/elog_lib.sh
chmod 640 /opt/myapp/lib/elog_lib.sh
```

Then source it from your application:

```bash
source /opt/myapp/lib/elog_lib.sh
```

No standalone CLI — elog_lib is a pure library. All configuration comes
from environment variables set by the consuming project.

## License

Copyright (C) 2002-2026, [R-fx Networks](https://www.rfxn.com)
— Ryan MacDonald <ryan@rfxn.com>

GNU General Public License v2. See the source files for the full license text.
