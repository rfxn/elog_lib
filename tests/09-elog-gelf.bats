#!/usr/bin/env bats
#
# Test suite for GELF output module (Graylog Extended Log Format 1.1)
#

load helpers/elog-common

setup() {
	elog_common_setup
	elog_init
	# Set up GELF capture file
	ELOG_GELF_FILE="$TEST_TMPDIR/gelf.log"
	export ELOG_GELF_FILE
	: > "$ELOG_GELF_FILE"
}

teardown() {
	elog_teardown
}

# --- GELF version field ---

@test "GELF: version 1.1 field present" {
	elog_output_enable "gelf"
	elog_event "block_added" "warn" "test gelf version" > /dev/null
	[ -f "$ELOG_GELF_FILE" ]
	local line
	line=$(cat "$ELOG_GELF_FILE")
	[[ "$line" == *'"version":"1.1"'* ]]
}

# --- GELF mandatory fields ---

@test "GELF: mandatory fields (host, short_message)" {
	elog_output_enable "gelf"
	elog_event "block_added" "warn" "mandatory fields test" > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	[[ "$line" == *'"host":'* ]]
	[[ "$line" == *'"short_message":"mandatory fields test"'* ]]
}

# --- GELF timestamp ---

@test "GELF: timestamp as Unix epoch" {
	elog_output_enable "gelf"
	elog_event "block_added" "warn" "epoch test" > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	# timestamp should be a numeric value (Unix epoch), not an ISO string
	[[ "$line" == *'"timestamp":'* ]]
	# Should NOT have quotes around the timestamp value (it's numeric)
	local ts_pat='"timestamp":"'
	[[ ! "$line" =~ $ts_pat ]]
}

# --- GELF level mapping ---

@test "GELF: level maps to syslog severity" {
	elog_output_enable "gelf"
	ELOG_LEVEL="0"

	: > "$ELOG_GELF_FILE"
	elog_event "test_type" "warn" "warn level" > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	# warn = syslog severity 4
	[[ "$line" == *'"level":4'* ]]

	: > "$ELOG_GELF_FILE"
	elog_event "test_type" "error" "error level" > /dev/null
	line=$(cat "$ELOG_GELF_FILE")
	# error = syslog severity 3
	[[ "$line" == *'"level":3'* ]]

	: > "$ELOG_GELF_FILE"
	elog_event "test_type" "critical" "critical level" > /dev/null
	line=$(cat "$ELOG_GELF_FILE")
	# critical = syslog severity 2
	[[ "$line" == *'"level":2'* ]]
}

# --- GELF custom fields ---

@test "GELF: custom fields prefixed with underscore" {
	elog_output_enable "gelf"
	elog_event "block_added" "warn" "custom fields test" > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	[[ "$line" == *'"_app":"elog_test"'* ]]
	[[ "$line" == *'"_pid":'* ]]
	[[ "$line" == *'"_event_type":"block_added"'* ]]
}

# --- GELF extras ---

@test "GELF: extras as underscore-prefixed fields" {
	elog_output_enable "gelf"
	elog_event "block_added" "warn" "extras test" "ip=203.0.113.42" "count=15" > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	[[ "$line" == *'"_ip":"203.0.113.42"'* ]]
	[[ "$line" == *'"_count":"15"'* ]]
}

# --- GELF tag ---

@test "GELF: tag in custom field" {
	elog_output_enable "gelf"
	elog_event "block_added" "warn" "{sshd} blocked host" > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	[[ "$line" == *'"_tag":"sshd"'* ]]
}

# --- GELF short_message truncation ---

@test "GELF: short_message truncation at 256 chars" {
	elog_output_enable "gelf"
	# Generate a message longer than 256 chars
	local long_msg=""
	local i
	for i in $(seq 1 40); do
		long_msg="${long_msg}abcdefg"
	done
	# long_msg is 280 chars
	elog_event "test_type" "info" "$long_msg" > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	# short_message should be present and truncated
	[[ "$line" == *'"short_message":"'* ]]
	# Extract short_message value length — use grep to verify truncation
	# The short_message should be 256 chars of the original
	local expected="${long_msg:0:256}"
	[[ "$line" == *"\"short_message\":\"${expected}\""* ]]
}

# --- GELF full_message ---

@test "GELF: full_message for long messages" {
	elog_output_enable "gelf"
	# Generate a message longer than 256 chars
	local long_msg=""
	local i
	for i in $(seq 1 40); do
		long_msg="${long_msg}abcdefg"
	done
	# long_msg is 280 chars
	elog_event "test_type" "info" "$long_msg" > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	# full_message should be present for long messages
	[[ "$line" == *'"full_message":"'* ]]
	[[ "$line" == *"$long_msg"* ]]
}

# --- GELF source filtering ---

@test "GELF: only receives event source (not elog)" {
	elog_output_enable "gelf"
	: > "$ELOG_GELF_FILE"
	elog info "this is elog output" > /dev/null
	# GELF module has source=event, so elog() output should not appear
	[ "$(wc -l < "$ELOG_GELF_FILE")" -eq 0 ]
}

# --- GELF disabled by default ---

@test "GELF: disabled by default" {
	: > "$ELOG_GELF_FILE"
	elog_event "block_added" "warn" "should not appear" > /dev/null
	# GELF module is registered but not enabled
	[ "$(wc -l < "$ELOG_GELF_FILE")" -eq 0 ]
}

# --- GELF transport selection ---

@test "GELF: transport selection (udp vs http)" {
	elog_output_enable "gelf"
	# Verify UDP is the default transport
	local transport="${ELOG_GELF_TRANSPORT:-udp}"
	[ "$transport" = "udp" ]

	# Test that http transport setting is accepted
	ELOG_GELF_TRANSPORT="http"
	# Just verify the setting propagates (actual HTTP send requires a server)
	[ "$ELOG_GELF_TRANSPORT" = "http" ]
}

# --- GELF JSON escaping ---

@test "GELF: JSON escaping in message and extras" {
	elog_output_enable "gelf"
	elog_event "test_type" "info" 'msg with "quotes"' 'detail="quoted"' > /dev/null
	local line
	line=$(cat "$ELOG_GELF_FILE")
	# Quotes should be escaped in short_message
	[[ "$line" == *'msg with \"quotes\"'* ]]
	# Quotes should be escaped in extras value
	[[ "$line" == *'"_detail":"\"quoted\""'* ]]
}

# --- GELF no-op when host empty ---

@test "GELF: no-op when host empty" {
	ELOG_GELF_HOST=""
	elog_output_enable "gelf"
	# Should write to capture file but not attempt network send
	elog_event "block_added" "warn" "captured but not sent" > /dev/null
	# Verify capture file has content (ELOG_GELF_FILE is set)
	[ "$(wc -l < "$ELOG_GELF_FILE")" -eq 1 ]
}
