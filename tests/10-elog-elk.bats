#!/usr/bin/env bats
#
# Test suite for ELK JSON output module (ECS-aligned)
#

load helpers/elog-common

setup() {
	elog_common_setup
	elog_init
	# Set up ELK capture file
	ELOG_ELK_FILE="$TEST_TMPDIR/elk.log"
	export ELOG_ELK_FILE
	: > "$ELOG_ELK_FILE"
}

teardown() {
	elog_teardown
}

# --- ECS @timestamp ---

@test "ELK: @timestamp field in ISO 8601" {
	elog_output_enable "elk_json"
	elog_event "block_added" "warn" "timestamp test" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	# @timestamp should be in ISO 8601 format (not Unix epoch)
	[[ "$line" == *'"@timestamp":"'* ]]
	# Should contain date-like pattern
	local ts_pat='"@timestamp":"[0-9]{4}-[0-9]{2}-[0-9]{2}T'
	[[ "$line" =~ $ts_pat ]]
}

# --- ECS log.level ---

@test "ELK: log.level matches elog severity" {
	elog_output_enable "elk_json"
	elog_event "block_added" "warn" "level test" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"log.level":"warn"'* ]]

	: > "$ELOG_ELK_FILE"
	elog_event "test_type" "error" "error level" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"log.level":"error"'* ]]
}

# --- ECS message ---

@test "ELK: message field contains full text" {
	elog_output_enable "elk_json"
	elog_event "block_added" "warn" "full message text here" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"message":"full message text here"'* ]]
}

# --- ECS event.kind ---

@test "ELK: event.kind is 'event'" {
	elog_output_enable "elk_json"
	elog_event "block_added" "warn" "kind test" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.kind":"event"'* ]]
}

# --- ECS event.category mapping ---

@test "ELK: event.category mapping" {
	elog_output_enable "elk_json"

	# Detection → intrusion_detection
	: > "$ELOG_ELK_FILE"
	elog_event "threat_detected" "warn" "detection test" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.category":"intrusion_detection"'* ]]

	# Trust → configuration
	: > "$ELOG_ELK_FILE"
	elog_event "trust_added" "info" "trust test" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.category":"configuration"'* ]]

	# Network → network
	: > "$ELOG_ELK_FILE"
	elog_event "rule_loaded" "info" "network test" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.category":"network"'* ]]

	# Alert → notification
	: > "$ELOG_ELK_FILE"
	elog_event "alert_sent" "info" "alert test" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.category":"notification"'* ]]

	# Monitor → process
	: > "$ELOG_ELK_FILE"
	elog_event "monitor_started" "info" "monitor test" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.category":"process"'* ]]

	# System → configuration
	: > "$ELOG_ELK_FILE"
	elog_event "config_loaded" "info" "config test" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.category":"configuration"'* ]]
}

# --- ECS event.type mapping ---

@test "ELK: event.type mapping" {
	elog_output_enable "elk_json"

	# block_added → denied
	: > "$ELOG_ELK_FILE"
	elog_event "block_added" "warn" "type test" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.type":"denied"'* ]]

	# block_removed → allowed
	: > "$ELOG_ELK_FILE"
	elog_event "block_removed" "info" "type test" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.type":"allowed"'* ]]

	# trust_added → change
	: > "$ELOG_ELK_FILE"
	elog_event "trust_added" "info" "type test" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.type":"change"'* ]]

	# monitor_stopped → end
	: > "$ELOG_ELK_FILE"
	elog_event "monitor_stopped" "info" "type test" > /dev/null
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.type":"end"'* ]]
}

# --- ECS event.action ---

@test "ELK: event.action is raw elog type" {
	elog_output_enable "elk_json"
	elog_event "block_added" "warn" "action test" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"event.action":"block_added"'* ]]
}

# --- ECS host.name and process ---

@test "ELK: host.name and process.name/pid" {
	elog_output_enable "elk_json"
	elog_event "block_added" "warn" "host test" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"host.name":'* ]]
	[[ "$line" == *'"process.name":"elog_test"'* ]]
	[[ "$line" == *'"process.pid":'* ]]
}

# --- ECS tags array ---

@test "ELK: tags array from tag" {
	elog_output_enable "elk_json"
	elog_event "block_added" "warn" "{sshd} blocked host" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"tags":["sshd"]'* ]]
}

# --- ECS labels object ---

@test "ELK: labels object from extras" {
	elog_output_enable "elk_json"
	elog_event "block_added" "warn" "labels test" "ip=203.0.113.42" "reason=SSH" > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	[[ "$line" == *'"labels":{'* ]]
	[[ "$line" == *'"ip":"203.0.113.42"'* ]]
	[[ "$line" == *'"reason":"SSH"'* ]]
}

# --- ECS source filtering ---

@test "ELK: only receives event source (not elog)" {
	elog_output_enable "elk_json"
	: > "$ELOG_ELK_FILE"
	elog info "this is elog output" > /dev/null
	# elk_json module has source=event, so elog() output should not appear
	[ "$(wc -l < "$ELOG_ELK_FILE")" -eq 0 ]
}

# --- ECS disabled by default ---

@test "ELK: disabled by default" {
	: > "$ELOG_ELK_FILE"
	elog_event "block_added" "warn" "should not appear" > /dev/null
	# elk_json module is registered but not enabled
	[ "$(wc -l < "$ELOG_ELK_FILE")" -eq 0 ]
}

# --- ECS JSON escaping ---

@test "ELK: JSON escaping in labels" {
	elog_output_enable "elk_json"
	elog_event "test_type" "info" "escape test" 'detail="quoted"' > /dev/null
	local line
	line=$(cat "$ELOG_ELK_FILE")
	# Quotes should be escaped in labels value
	[[ "$line" == *'"detail":"\"quoted\""'* ]]
}

# --- ECS no-op when URL empty ---

@test "ELK: no-op when URL empty" {
	ELOG_ELK_URL=""
	elog_output_enable "elk_json"
	# Should write to capture file but not attempt HTTP send
	elog_event "block_added" "warn" "captured but not sent" > /dev/null
	# Verify capture file has content (ELOG_ELK_FILE is set)
	[ "$(wc -l < "$ELOG_ELK_FILE")" -eq 1 ]
}

# --- HTTP method detection ---

@test "ELK: HTTP method detection" {
	_ELOG_HTTP_METHOD=""
	_elog_http_detect
	[[ "$_ELOG_HTTP_METHOD" == "curl" || "$_ELOG_HTTP_METHOD" == "wget" || "$_ELOG_HTTP_METHOD" == "none" ]]
	[ -n "$_ELOG_HTTP_METHOD" ]
}
