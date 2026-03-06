#!/usr/bin/env bats
#
# Test suite for backward compatibility — no-init drop-in pattern
# These tests validate BFD's usage: set ELOG_* vars, call elog() directly,
# never call elog_init(). Setup must NOT call elog_init().
#

load helpers/elog-common

setup() {
	elog_common_setup
	# Create files but do NOT call elog_init — that's the point of these tests
	: > "$ELOG_LOG_FILE"
	: > "$ELOG_AUDIT_FILE"
}

teardown() {
	elog_teardown
}

# --- No-init drop-in tests ---

@test "elog writes to file without elog_init" {
	elog info "no-init file write"
	[ "$(wc -l < "$ELOG_LOG_FILE")" -eq 1 ]
	grep -q "no-init file write" "$ELOG_LOG_FILE"
}

@test "elog writes to syslog without elog_init" {
	local syslog="$TEST_TMPDIR/syslog.log"
	: > "$syslog"
	ELOG_SYSLOG_FILE="$syslog"
	elog info "syslog no-init" > /dev/null
	[ "$(wc -l < "$syslog")" -eq 1 ]
	grep -q "syslog no-init" "$syslog"
}

@test "elog stdout works without elog_init" {
	ELOG_STDOUT="always"
	run elog info "stdout no-init"
	assert_success
	assert_output --partial "stdout no-init"
}

@test "audit_file stays empty from elog without elog_init" {
	elog info "elog not event" > /dev/null
	[ "$(wc -l < "$ELOG_AUDIT_FILE")" -eq 0 ]
}

@test "ELOG_STDOUT=never suppresses without elog_init" {
	ELOG_STDOUT="never"
	run elog info "should be suppressed"
	assert_success
	assert_output ""
	# File still written
	[ "$(wc -l < "$ELOG_LOG_FILE")" -eq 1 ]
	grep -q "should be suppressed" "$ELOG_LOG_FILE"
}

@test "ELOG_FORMAT=json works without elog_init" {
	ELOG_FORMAT="json"
	run elog info "json no-init"
	assert_success
	# stdout should be JSON
	assert_output --partial '"msg":"json no-init"'
	# file should be JSON too
	grep -q '"msg":"json no-init"' "$ELOG_LOG_FILE"
}

@test "dynamic ELOG_LOG_FILE change between calls" {
	local file1="$TEST_TMPDIR/log1.log"
	local file2="$TEST_TMPDIR/log2.log"
	: > "$file1"
	: > "$file2"
	# Write to first file
	ELOG_LOG_FILE="$file1"
	elog info "first log" > /dev/null
	# Change to second file mid-flight (BFD eout() pattern)
	ELOG_LOG_FILE="$file2"
	elog info "second log" > /dev/null
	# Verify each file got its own message
	grep -q "first log" "$file1"
	grep -q "second log" "$file2"
	# First file should NOT have second message
	! grep -q "second log" "$file1"
}

@test "elog_critical convenience wrapper" {
	run elog_critical "critical message"
	assert_success
	assert_output --partial "critical message"
}
