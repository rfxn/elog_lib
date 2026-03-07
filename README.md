# elog_lib — Structured Event Logging for Bash

[![CI](https://github.com/rfxn/elog_lib/actions/workflows/ci.yml/badge.svg)](https://github.com/rfxn/elog_lib/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.2-blue.svg)](https://github.com/rfxn/elog_lib)
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
- **CEF output module** — ArcSight Common Event Format (v0) with severity mapping
- **Syslog UDP output module** — RFC 5424/3164 with fire-and-forget delivery
- **GELF output module** — Graylog Extended Log Format 1.1 with UDP/HTTP transport
- **ELK JSON output module** — Elasticsearch ECS-aligned JSON with HTTP delivery
- **HTTP delivery infrastructure** — curl/wget auto-detection for GELF and ELK
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

Eight output modules are registered at source time but start disabled
(enabled by `elog_init()` or `elog_output_enable()`):

| Module | Handler | Format | Source | Description |
|--------|---------|--------|--------|-------------|
| `file` | `_elog_out_file` | classic | `elog` | Append to `ELOG_LOG_FILE` |
| `audit_file` | `_elog_out_audit` | json | `event` | Append JSONL to `ELOG_AUDIT_FILE` |
| `syslog_file` | `_elog_out_syslog_file` | classic | `elog` | Append to `ELOG_SYSLOG_FILE` |
| `stdout` | `_elog_out_stdout` | classic | `all` | Terminal output with prefix modes |
| `cef` | `_elog_out_cef` | cef | `event` | CEF format to `ELOG_CEF_FILE` |
| `syslog_udp` | `_elog_out_syslog_udp` | classic | `all` | UDP syslog (RFC 5424/3164) |
| `gelf` | `_elog_out_gelf` | gelf | `event` | GELF 1.1 via UDP or HTTP |
| `elk_json` | `_elog_out_elk_json` | elk | `event` | ECS-aligned JSON via HTTP |

**Source filtering** prevents cross-contamination: `elog()` dispatches with
`api_source="elog"` (reaches `file`, `syslog_file`, `stdout`, `syslog_udp`),
while `elog_event()` dispatches with `api_source="event"` (reaches
`audit_file`, `stdout`, `cef`, `syslog_udp`, `gelf`, `elk_json`). Modules
with `source="all"` receive both.

Custom modules can be registered with `elog_output_register` for additional
output targets.

### Dispatch Flow

```
elog("info", "message")
  → severity filter (ELOG_LEVEL)
  → _elog_auto_enable (if no init)
  → build classic + JSON lines
  → _elog_dispatch("elog", ...) → file, syslog_file, stdout, syslog_udp

elog_event("block_added", "warn", "blocked host", "ip=1.2.3.4")
  → severity filter (ELOG_LEVEL)
  → _elog_auto_enable (if no init)
  → build JSON envelope + classic line
  → stage event context + format CEF/GELF/ELK (if enabled)
  → _elog_dispatch("event", ...) → audit_file, stdout, cef, syslog_udp, gelf, elk_json
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
- `key=val` — zero or more key=value pairs added to JSON envelope (values must not contain spaces)

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
- `format` — `classic`, `json`, `cef`, `gelf`, or `elk` (selects which formatted line to pass)
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
- `_elog_severity_cef(level)` — map elog level to CEF severity (0-10)
- `_elog_cef_escape_header(str)` / `_elog_cef_escape_ext(str)` — CEF escaping
- `_elog_fmt_cef(type, level, msg, tag, extras)` — build CEF formatted string
- `_elog_out_cef(line)` — CEF file output handler
- `_elog_severity_syslog(level)` — map elog level to syslog severity (0-7)
- `_elog_syslog_pri(facility, severity)` — compute syslog PRI value
- `_elog_fmt_syslog_5424/3164(pri, ts, host, app, pid, msg)` — syslog formatters
- `_elog_udp_detect()` — probe for `/dev/udp` and `nc` at init time
- `_elog_udp_send(host, port, payload)` — fire-and-forget UDP send
- `_elog_out_syslog_udp(line)` — syslog UDP output handler
- `_elog_http_detect()` — probe for `curl` and `wget` at init time
- `_elog_http_send(url, payload, content_type)` — fire-and-forget HTTP POST
- `_elog_ts_epoch(iso_ts)` — convert ISO 8601 timestamp to Unix epoch
- `_elog_fmt_gelf(type, level, msg, tag, extras, ts, host)` — build GELF 1.1 JSON
- `_elog_out_gelf(line)` — GELF output handler (UDP/HTTP)
- `_elog_ecs_category(event_type)` — map elog type to ECS event.category
- `_elog_ecs_type(event_type)` — map elog type to ECS event.type
- `_elog_fmt_elk(type, level, msg, tag, extras, ts, host)` — build ECS-aligned JSON
- `_elog_out_elk_json(line)` — ELK JSON output handler (HTTP)

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
| `ELOG_CEF_VENDOR` | `R-fx Networks` | CEF vendor field |
| `ELOG_CEF_PRODUCT` | `${ELOG_APP}` | CEF product field |
| `ELOG_CEF_VERSION` | `${ELOG_LIB_VERSION}` | CEF product version field |
| `ELOG_CEF_FILE` | *(empty)* | CEF output file path (empty = no file output) |
| `ELOG_SYSLOG_UDP_HOST` | *(empty)* | Target syslog server (empty = disabled) |
| `ELOG_SYSLOG_UDP_PORT` | `514` | Target syslog port |
| `ELOG_SYSLOG_UDP_FACILITY` | `1` | Syslog facility code (0-23; 1 = user) |
| `ELOG_SYSLOG_UDP_FORMAT` | `5424` | Syslog format: `5424` or `3164` |
| `ELOG_SYSLOG_UDP_PAYLOAD` | `classic` | Payload format: `classic`, `json`, or `cef` |
| `ELOG_GELF_HOST` | *(empty)* | Graylog server (empty = no-op) |
| `ELOG_GELF_PORT` | `12201` | Graylog input port |
| `ELOG_GELF_TRANSPORT` | `udp` | GELF transport: `udp` or `http` |
| `ELOG_GELF_FILE` | *(empty)* | GELF capture file for testing/debug |
| `ELOG_ELK_URL` | *(empty)* | Elasticsearch ingest URL (empty = no-op) |
| `ELOG_ELK_INDEX` | `elog-events` | Target Elasticsearch index name |
| `ELOG_ELK_FILE` | *(empty)* | ELK capture file for testing/debug |

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

## SIEM Integration

### CEF Output (ArcSight Common Event Format)

Enable the built-in CEF module to write ArcSight-compatible event lines:

```bash
source /opt/myapp/lib/elog_lib.sh
ELOG_APP="myapp"
ELOG_CEF_FILE="/var/log/myapp/cef.log"
ELOG_CEF_VENDOR="R-fx Networks"
elog_init
elog_output_enable "cef"

elog_event "block_added" "warn" "blocked host" "src=203.0.113.42" "reason=SSH"
# Output: CEF:0|R-fx Networks|myapp|1.0.1|block_added|blocked host|5|src=203.0.113.42 reason=SSH
```

The CEF module only receives `elog_event()` output (source=event). Regular
`elog()` calls do not produce CEF output. CEF severity mapping: debug=1,
info=3, warn=5, error=7, critical=10.

### Syslog UDP Output (RFC 5424/3164)

Send log output to a remote syslog server via UDP:

```bash
source /opt/myapp/lib/elog_lib.sh
ELOG_APP="myapp"
ELOG_SYSLOG_UDP_HOST="syslog.example.com"
ELOG_SYSLOG_UDP_PORT="514"
ELOG_SYSLOG_UDP_FORMAT="5424"        # or "3164" for BSD format
ELOG_SYSLOG_UDP_PAYLOAD="classic"    # or "json" or "cef"
elog_init
elog_output_enable "syslog_udp"

elog info "sent to remote syslog"
elog_event "block_added" "warn" "blocked host"
# Both elog() and elog_event() reach syslog_udp (source=all)
```

UDP delivery uses fire-and-forget background subshells. Transport is
auto-detected: bash `/dev/udp` first, then `nc` fallback. If neither is
available, the module stays registered but sends nothing.

### GELF Output (Graylog Extended Log Format 1.1)

Send structured events to Graylog via UDP or HTTP:

```bash
source /opt/myapp/lib/elog_lib.sh
ELOG_APP="myapp"
ELOG_GELF_HOST="graylog.example.com"
ELOG_GELF_PORT="12201"
ELOG_GELF_TRANSPORT="udp"    # or "http" for HTTP input
elog_init
elog_output_enable "gelf"

elog_event "block_added" "warn" "blocked host" "src=203.0.113.42"
# Output: {"version":"1.1","host":"srv1","short_message":"blocked host","timestamp":1741283445,"level":4,"_app":"myapp","_pid":1234,"_event_type":"block_added","_src":"203.0.113.42"}
```

GELF field mapping follows the GELF 1.1 specification: `short_message` truncated
at 256 chars, `full_message` included when message exceeds 256 chars, `level`
uses syslog severity scale, custom fields prefixed with underscore (`_app`,
`_pid`, `_event_type`, `_tag`, plus extras). Timestamp is Unix epoch seconds.

### ELK JSON Output (Elasticsearch ECS-Aligned)

Send ECS-aligned JSON events to Elasticsearch via HTTP:

```bash
source /opt/myapp/lib/elog_lib.sh
ELOG_APP="myapp"
ELOG_ELK_URL="http://elasticsearch.example.com:9200"
ELOG_ELK_INDEX="elog-events"
elog_init
elog_output_enable "elk_json"

elog_event "block_added" "warn" "{sshd} blocked host" "ip=203.0.113.42"
# Output: {"@timestamp":"2026-03-06T14:30:45-0500","log.level":"warn","message":"blocked host","event.kind":"event","event.category":"intrusion_detection","event.type":"denied","event.action":"block_added","host.name":"srv1","process.name":"myapp","process.pid":1234,"tags":["sshd"],"labels":{"ip":"203.0.113.42"}}
```

ECS field mapping:

| ECS Field | Source | Notes |
|-----------|--------|-------|
| `@timestamp` | ISO 8601 from event | Native timestamp |
| `log.level` | elog severity name | debug, info, warn, error, critical |
| `message` | Event message | Full text |
| `event.kind` | Fixed `"event"` | ECS event kind |
| `event.category` | Mapped from elog taxonomy | intrusion_detection, configuration, network, notification, process |
| `event.type` | Mapped from elog type | denied, allowed, change, start, end, error, info |
| `event.action` | Raw elog event type | Unmodified type string |
| `host.name` | Hostname | |
| `process.name` | `$ELOG_APP` | |
| `process.pid` | `$$` | |
| `tags` | `{tag}` prefix | Array, only if tag present |
| `labels` | key=value extras | Flat key-value object |

HTTP delivery for both GELF and ELK uses fire-and-forget background subshells.
Transport is auto-detected: `curl` first, then `wget` fallback. If neither is
available, the module stays registered but sends nothing.

### Custom Output Modules

Register additional output modules for other destinations:

```bash
_my_handler() {
    local line="$1"
    echo "$line" >> /var/log/custom.log
}
elog_output_register "custom" "_my_handler" "json" "event"
elog_output_enable "custom"
```

## Testing

Tests across 11 BATS files:

| File | Coverage |
|------|----------|
| `00-scaffold.bats` | Library loading, version, source guard |
| `01-elog-core.bats` | elog(), formats, severity, debug, stdout, helpers |
| `02-elog-init.bats` | elog_init(), permissions, symlinks, truncation |
| `03-elog-output.bats` | Registry, dispatch, source filtering, format selection |
| `04-elog-event.bats` | Event envelope, JSON, key=value, tag, filtering |
| `05-elog-taxonomy.bats` | Type validation, severity mapping |
| `06-elog-compat.bats` | Backward compat, no-init drop-in |
| `07-elog-cef.bats` | CEF output module, format, escaping, severity |
| `08-elog-syslog-udp.bats` | Syslog UDP, RFC 5424/3164, PRI, payload formats |
| `09-elog-gelf.bats` | GELF 1.1 output, fields, truncation, transport |
| `10-elog-elk.bats` | ELK JSON, ECS mapping, labels, HTTP detection |

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
