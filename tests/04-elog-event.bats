#!/usr/bin/env bats
#
# Test suite for elog_event() — structured event envelope
#

load helpers/elog-common

setup() {
	elog_common_setup
	# elog_event needs audit_file enabled; use elog_init for clean setup
	elog_init
}

teardown() {
	elog_teardown
}

# --- Core dispatch ---

@test "elog_event: writes JSONL to audit file" {
	: > "$ELOG_AUDIT_FILE"
	elog_event "block_added" "warn" "blocked host" > /dev/null
	[ "$(wc -l < "$ELOG_AUDIT_FILE")" -eq 1 ]
	grep -q '"type":"block_added"' "$ELOG_AUDIT_FILE"
}

@test "elog_event: does NOT write to app log" {
	: > "$ELOG_LOG_FILE"
	: > "$ELOG_AUDIT_FILE"
	elog_event "block_added" "warn" "should not be in app log" > /dev/null
	[ "$(wc -l < "$ELOG_LOG_FILE")" -eq 0 ]
	[ "$(wc -l < "$ELOG_AUDIT_FILE")" -eq 1 ]
}

# --- JSON envelope ---

@test "elog_event: JSON has mandatory fields (ts,host,app,pid,type,level,msg)" {
	: > "$ELOG_AUDIT_FILE"
	elog_event "threat_detected" "warn" "malware found" > /dev/null
	local line
	line=$(cat "$ELOG_AUDIT_FILE")
	[[ "$line" == *'"ts":'* ]]
	[[ "$line" == *'"host":'* ]]
	[[ "$line" == *'"app":"elog_test"'* ]]
	[[ "$line" == *'"pid":'* ]]
	[[ "$line" == *'"type":"threat_detected"'* ]]
	[[ "$line" == *'"level":"warn"'* ]]
	[[ "$line" == *'"msg":"malware found"'* ]]
}

@test "elog_event: single key=value pair in JSON" {
	: > "$ELOG_AUDIT_FILE"
	elog_event "block_added" "warn" "blocked host" "ip=192.0.2.1" > /dev/null
	local line
	line=$(cat "$ELOG_AUDIT_FILE")
	[[ "$line" == *'"ip":"192.0.2.1"'* ]]
}

@test "elog_event: multiple key=value pairs valid JSON" {
	: > "$ELOG_AUDIT_FILE"
	elog_event "block_added" "warn" "blocked host" "ip=198.51.100.5" "mod=sshd" > /dev/null
	local line
	line=$(cat "$ELOG_AUDIT_FILE")
	[[ "$line" == *'"ip":"198.51.100.5"'* ]]
	[[ "$line" == *'"mod":"sshd"'* ]]
	# Verify it starts and ends as JSON
	[[ "$line" == \{* ]]
	[[ "$line" == *\} ]]
}

# --- Tag extraction ---

@test "elog_event: tag extraction from {tag} prefix" {
	: > "$ELOG_AUDIT_FILE"
	elog_event "block_added" "warn" "{sshd} blocked host" > /dev/null
	local line
	line=$(cat "$ELOG_AUDIT_FILE")
	[[ "$line" == *'"tag":"sshd"'* ]]
	[[ "$line" == *'"msg":"blocked host"'* ]]
}

# --- Severity filtering ---

@test "elog_event: severity filtering (below ELOG_LEVEL suppressed)" {
	: > "$ELOG_AUDIT_FILE"
	ELOG_LEVEL="3"
	elog_event "block_added" "warn" "should be filtered" > /dev/null
	[ "$(wc -l < "$ELOG_AUDIT_FILE")" -eq 0 ]
}

# --- Input validation ---

@test "elog_event: returns 1 on empty type with stderr" {
	run elog_event "" "warn" "no type"
	assert_failure
	assert_output --partial "requires event_type"
}

@test "elog_event: returns 0 on empty message (no output)" {
	: > "$ELOG_AUDIT_FILE"
	run elog_event "block_added" "warn" ""
	assert_success
	assert_output ""
	[ "$(wc -l < "$ELOG_AUDIT_FILE")" -eq 0 ]
}

# --- JSON escaping ---

@test "elog_event: JSON-escapes context field values" {
	: > "$ELOG_AUDIT_FILE"
	elog_event "threat_detected" "warn" "found threat" 'path=/tmp/a "b" c' > /dev/null
	local line
	line=$(cat "$ELOG_AUDIT_FILE")
	[[ "$line" == *'\"b\"'* ]]
}

@test "elog_event: key=value with embedded equals in value" {
	: > "$ELOG_AUDIT_FILE"
	elog_event "config_loaded" "info" "config ok" "detail=key=val" > /dev/null
	local line
	line=$(cat "$ELOG_AUDIT_FILE")
	[[ "$line" == *'"detail":"key=val"'* ]]
}

# --- Custom module dispatch ---

@test "elog_event: custom module (source=event) receives events" {
	local custom_file="$TEST_TMPDIR/custom_event"
	: > "$custom_file"
	_test_event_handler() {
		echo "$1" >> "$custom_file"
	}
	elog_output_register "test_event_mod" "_test_event_handler" "json" "event"
	elog_output_enable "test_event_mod"
	elog_event "block_added" "warn" "custom dispatch" > /dev/null
	grep -q '"type":"block_added"' "$custom_file"
}

@test "elog_event: stdout (source=all) receives events" {
	elog_output_enable "stdout"
	ELOG_STDOUT="always"
	run elog_event "block_added" "warn" "stdout event"
	assert_success
	assert_output --partial "[block_added]"
	assert_output --partial "stdout event"
}

# --- Classic format ---

@test "elog_event: classic format includes [type] prefix" {
	elog_output_enable "stdout"
	ELOG_STDOUT="always"
	run elog_event "block_added" "warn" "classic format"
	assert_success
	assert_output --partial "[block_added]"
}

# --- Auto-enable fallback ---

@test "elog_event: auto-enables audit_file if init not called" {
	# Reset to pre-init state
	_ELOG_INIT_DONE=0
	local i
	for i in "${!_ELOG_OUTPUT_NAMES[@]}"; do
		_ELOG_OUTPUT_ENABLED[$i]=0
	done
	local audit="$TEST_TMPDIR/auto_audit.log"
	: > "$audit"
	ELOG_AUDIT_FILE="$audit"
	elog_event "block_added" "warn" "auto enable test" > /dev/null
	[ "$(wc -l < "$audit")" -eq 1 ]
}

# --- Classic format newline sanitization ---

@test "elog_event: classic format sanitizes embedded newlines" {
	# elog_event dispatches classic line to stdout (source=all, format=classic)
	elog_output_enable "stdout"
	ELOG_STDOUT="always"
	ELOG_STDOUT_PREFIX="full"
	run elog_event "test_type" "info" $'line1\nline2'
	assert_success
	# Output should contain literal backslash-n, not an actual newline
	assert_output --partial 'line1\nline2'
}

# --- Truncation counter ---

@test "elog_event: does NOT increment app log truncation counter" {
	local before="$_ELOG_WRITE_COUNT"
	elog_event "block_added" "warn" "no truncate" > /dev/null
	[ "$_ELOG_WRITE_COUNT" -eq "$before" ]
}

@test "elog_event: increments audit write counter" {
	local before="$_ELOG_AUDIT_WRITE_COUNT"
	elog_event "block_added" "warn" "audit count" > /dev/null
	[ "$_ELOG_AUDIT_WRITE_COUNT" -gt "$before" ]
}

@test "elog_event: truncates audit log when ELOG_AUDIT_MAX_LINES set" {
	local audit="$TEST_TMPDIR/audit-trunc.log"
	ELOG_AUDIT_FILE="$audit"
	ELOG_AUDIT_MAX_LINES=5
	# Force truncation check on every write for this test
	_ELOG_TRUNCATE_CHECK_INTERVAL=1
	_ELOG_AUDIT_WRITE_COUNT=0
	local i
	for i in 1 2 3 4 5 6 7 8 9 10; do
		elog_event "test" "info" "event $i" > /dev/null
	done
	local count
	count=$(wc -l < "$audit")
	count="${count## }"
	[ "$count" -le 5 ]
}

@test "elog_event: audit log not truncated when ELOG_AUDIT_MAX_LINES=0" {
	local audit="$TEST_TMPDIR/audit-notrunc.log"
	ELOG_AUDIT_FILE="$audit"
	ELOG_AUDIT_MAX_LINES=0
	_ELOG_TRUNCATE_CHECK_INTERVAL=1
	_ELOG_AUDIT_WRITE_COUNT=0
	local i
	for i in 1 2 3 4 5 6 7 8 9 10; do
		elog_event "test" "info" "event $i" > /dev/null
	done
	local count
	count=$(wc -l < "$audit")
	count="${count## }"
	[ "$count" -eq 10 ]
}
