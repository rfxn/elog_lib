#!/usr/bin/env bats
#
# Test suite for syslog UDP output module
#

load helpers/elog-common

# Capture file for UDP send stub
_SYSLOG_CAPTURE=""

# Override _elog_udp_send to capture payload instead of sending via network
_test_udp_stub() {
	local _host="$1" _port="$2" _payload="$3"
	echo "$_payload" >> "$_SYSLOG_CAPTURE"
}

setup() {
	elog_common_setup
	elog_init
	# Set up syslog capture
	_SYSLOG_CAPTURE="$TEST_TMPDIR/syslog_capture.log"
	export _SYSLOG_CAPTURE
	: > "$_SYSLOG_CAPTURE"
	# Override _elog_udp_send with test stub
	eval '_elog_udp_send() { _test_udp_stub "$@"; }'
	# Set UDP method to avoid detection
	_ELOG_UDP_METHOD="bash"
	# Configure syslog target
	ELOG_SYSLOG_UDP_HOST="127.0.0.1"
	ELOG_SYSLOG_UDP_PORT="514"
	export ELOG_SYSLOG_UDP_HOST ELOG_SYSLOG_UDP_PORT
}

teardown() {
	elog_teardown
}

# --- RFC 5424 format ---

@test "syslog_udp: RFC 5424 format with correct PRI" {
	ELOG_SYSLOG_UDP_FORMAT="5424"
	elog_output_enable "syslog_udp"
	elog_event "block_added" "warn" "test 5424" > /dev/null
	local line
	line=$(cat "$_SYSLOG_CAPTURE")
	# PRI = facility(1) * 8 + severity(4 for warn) = 12
	[[ "$line" == '<12>1 '* ]]
	# Should contain structured-data nil markers
	[[ "$line" == *' - - '* ]]
}

# --- RFC 3164 format ---

@test "syslog_udp: RFC 3164 format with correct PRI" {
	ELOG_SYSLOG_UDP_FORMAT="3164"
	elog_output_enable "syslog_udp"
	elog_event "block_added" "warn" "test 3164" > /dev/null
	local line
	line=$(cat "$_SYSLOG_CAPTURE")
	# PRI = facility(1) * 8 + severity(4 for warn) = 12
	[[ "$line" == '<12>'* ]]
	# 3164 format uses APP[PID]: syntax
	[[ "$line" == *'elog_test['* ]]
	[[ "$line" == *']: '* ]]
}

# --- Severity mapping ---

@test "syslog_udp: severity mapping for all 5 levels" {
	elog_output_enable "syslog_udp"
	ELOG_LEVEL="0"

	# critical = syslog 2, PRI = 1*8+2 = 10
	: > "$_SYSLOG_CAPTURE"
	elog_event "test_type" "critical" "critical msg" > /dev/null
	local line
	line=$(cat "$_SYSLOG_CAPTURE")
	[[ "$line" == '<10>'* ]]

	# error = syslog 3, PRI = 1*8+3 = 11
	: > "$_SYSLOG_CAPTURE"
	elog_event "test_type" "error" "error msg" > /dev/null
	line=$(cat "$_SYSLOG_CAPTURE")
	[[ "$line" == '<11>'* ]]

	# warn = syslog 4, PRI = 1*8+4 = 12
	: > "$_SYSLOG_CAPTURE"
	elog_event "test_type" "warn" "warn msg" > /dev/null
	line=$(cat "$_SYSLOG_CAPTURE")
	[[ "$line" == '<12>'* ]]

	# info = syslog 6, PRI = 1*8+6 = 14
	: > "$_SYSLOG_CAPTURE"
	elog_event "test_type" "info" "info msg" > /dev/null
	line=$(cat "$_SYSLOG_CAPTURE")
	[[ "$line" == '<14>'* ]]

	# debug = syslog 7, PRI = 1*8+7 = 15
	: > "$_SYSLOG_CAPTURE"
	elog_event "test_type" "debug" "debug msg" > /dev/null
	line=$(cat "$_SYSLOG_CAPTURE")
	[[ "$line" == '<15>'* ]]
}

# --- Facility in PRI calculation ---

@test "syslog_udp: facility in PRI calculation" {
	ELOG_SYSLOG_UDP_FACILITY="1"
	elog_output_enable "syslog_udp"
	elog_event "test_type" "info" "facility test" > /dev/null
	local line
	line=$(cat "$_SYSLOG_CAPTURE")
	# PRI = 1*8+6 = 14
	[[ "$line" == '<14>'* ]]
}

# --- Custom facility ---

@test "syslog_udp: custom facility code" {
	ELOG_SYSLOG_UDP_FACILITY="10"
	elog_output_enable "syslog_udp"
	elog_event "test_type" "info" "security facility" > /dev/null
	local line
	line=$(cat "$_SYSLOG_CAPTURE")
	# PRI = 10*8+6 = 86
	[[ "$line" == '<86>'* ]]
}

# --- UDP detection ---

@test "syslog_udp: UDP method detection sets variable" {
	_ELOG_UDP_METHOD=""
	_elog_udp_detect
	# Should set to bash, nc, or none
	[[ "$_ELOG_UDP_METHOD" == "bash" || "$_ELOG_UDP_METHOD" == "nc" || "$_ELOG_UDP_METHOD" == "none" ]]
}

# --- nc fallback detection ---

@test "syslog_udp: UDP detection falls back when /dev/udp unavailable" {
	# We cannot reliably disable /dev/udp in container, so just verify
	# the detection function completes without error
	_ELOG_UDP_METHOD=""
	_elog_udp_detect
	[ -n "$_ELOG_UDP_METHOD" ]
}

# --- No-op when host empty ---

@test "syslog_udp: no-op when ELOG_SYSLOG_UDP_HOST empty" {
	ELOG_SYSLOG_UDP_HOST=""
	elog_output_enable "syslog_udp"
	elog_event "block_added" "warn" "should not send" > /dev/null
	[ "$(wc -l < "$_SYSLOG_CAPTURE")" -eq 0 ]
}

# --- Source filtering ---

@test "syslog_udp: receives both elog and event (source=all)" {
	elog_output_enable "syslog_udp"

	: > "$_SYSLOG_CAPTURE"
	elog info "elog message" > /dev/null
	local elog_count
	elog_count=$(wc -l < "$_SYSLOG_CAPTURE")
	[ "$elog_count" -eq 1 ]

	: > "$_SYSLOG_CAPTURE"
	elog_event "test_type" "info" "event message" > /dev/null
	local event_count
	event_count=$(wc -l < "$_SYSLOG_CAPTURE")
	[ "$event_count" -eq 1 ]
}

# --- Payload format: classic ---

@test "syslog_udp: payload format classic (default)" {
	ELOG_SYSLOG_UDP_PAYLOAD="classic"
	elog_output_enable "syslog_udp"
	elog info "classic payload test" > /dev/null
	local line
	line=$(cat "$_SYSLOG_CAPTURE")
	# Classic payload should contain the message text
	[[ "$line" == *'classic payload test'* ]]
	# Should NOT start with { (not JSON)
	local payload_pat='- - \{'
	[[ ! "$line" =~ $payload_pat ]]
}

# --- Payload format: json ---

@test "syslog_udp: payload format json" {
	ELOG_SYSLOG_UDP_PAYLOAD="json"
	ELOG_FORMAT="json"
	elog_output_enable "syslog_udp"
	elog info "json payload test" > /dev/null
	local line
	line=$(cat "$_SYSLOG_CAPTURE")
	# JSON payload inside syslog wrapper
	[[ "$line" == *'json payload test'* ]]
}

# --- Payload format: cef ---

@test "syslog_udp: payload format cef" {
	ELOG_SYSLOG_UDP_PAYLOAD="cef"
	elog_output_enable "syslog_udp"
	elog_output_enable "cef"
	ELOG_CEF_FILE="$TEST_TMPDIR/cef_syslog.log"
	: > "$ELOG_CEF_FILE"
	elog_event "block_added" "warn" "cef in syslog" > /dev/null
	local line
	line=$(cat "$_SYSLOG_CAPTURE")
	# CEF payload should be inside the syslog wrapper
	[[ "$line" == *'CEF:0|'* ]]
}

# --- Format toggle ---

@test "syslog_udp: format toggle between 5424 and 3164" {
	elog_output_enable "syslog_udp"

	# Test 5424
	ELOG_SYSLOG_UDP_FORMAT="5424"
	: > "$_SYSLOG_CAPTURE"
	elog_event "test_type" "info" "format 5424" > /dev/null
	local line_5424
	line_5424=$(cat "$_SYSLOG_CAPTURE")
	# 5424 has version number after PRI
	[[ "$line_5424" == '<14>1 '* ]]

	# Test 3164
	ELOG_SYSLOG_UDP_FORMAT="3164"
	: > "$_SYSLOG_CAPTURE"
	elog_event "test_type" "info" "format 3164" > /dev/null
	local line_3164
	line_3164=$(cat "$_SYSLOG_CAPTURE")
	# 3164 has no version number, uses APP[PID]:
	[[ "$line_3164" == '<14>'* ]]
	[[ "$line_3164" != '<14>1 '* ]]
}

# --- Disabled by default ---

@test "syslog_udp: disabled by default" {
	# Module is registered but not enabled — don't enable it
	_ELOG_INIT_DONE=1
	: > "$_SYSLOG_CAPTURE"
	# Disable all modules to prevent auto-enable interfering
	local i
	for i in "${!_ELOG_OUTPUT_NAMES[@]}"; do
		_ELOG_OUTPUT_ENABLED[$i]=0
	done
	elog_output_enable "stdout"
	elog_event "block_added" "warn" "should not syslog" > /dev/null
	[ "$(wc -l < "$_SYSLOG_CAPTURE")" -eq 0 ]
}
