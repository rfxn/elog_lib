#!/usr/bin/env bats
#
# Test suite for CEF output module
#

load helpers/elog-common

setup() {
	elog_common_setup
	elog_init
	# Set up CEF output file
	ELOG_CEF_FILE="$TEST_TMPDIR/cef.log"
	export ELOG_CEF_FILE
	: > "$ELOG_CEF_FILE"
}

teardown() {
	elog_teardown
}

# --- CEF header format ---

@test "CEF: header format with all fields" {
	ELOG_CEF_VENDOR="TestVendor"
	ELOG_CEF_PRODUCT="TestProduct"
	ELOG_CEF_VERSION="2.0.0"
	elog_output_enable "cef"
	elog_event "block_added" "warn" "blocked host" "ip=203.0.113.42" > /dev/null
	[ -f "$ELOG_CEF_FILE" ]
	local line
	line=$(cat "$ELOG_CEF_FILE")
	# CEF:0|vendor|product|version|type|name|severity|extension
	[[ "$line" == CEF:0\|TestVendor\|TestProduct\|2.0.0\|block_added\|blocked\ host\|5\|* ]]
}

# --- CEF severity mapping ---

@test "CEF: severity mapping for all 5 levels" {
	elog_output_enable "cef"
	ELOG_LEVEL="0"

	: > "$ELOG_CEF_FILE"
	elog_event "test_type" "debug" "debug msg" > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	[[ "$line" == *\|1\|* ]]

	: > "$ELOG_CEF_FILE"
	elog_event "test_type" "info" "info msg" > /dev/null
	line=$(cat "$ELOG_CEF_FILE")
	[[ "$line" == *\|3\|* ]]

	: > "$ELOG_CEF_FILE"
	elog_event "test_type" "warn" "warn msg" > /dev/null
	line=$(cat "$ELOG_CEF_FILE")
	[[ "$line" == *\|5\|* ]]

	: > "$ELOG_CEF_FILE"
	elog_event "test_type" "error" "error msg" > /dev/null
	line=$(cat "$ELOG_CEF_FILE")
	[[ "$line" == *\|7\|* ]]

	: > "$ELOG_CEF_FILE"
	elog_event "test_type" "critical" "critical msg" > /dev/null
	line=$(cat "$ELOG_CEF_FILE")
	[[ "$line" == *\|10\|* ]]
}

# --- CEF extension from extras ---

@test "CEF: extension from elog_event extras" {
	elog_output_enable "cef"
	elog_event "block_added" "warn" "blocked host" "src=203.0.113.42" "reason=SSH" > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	[[ "$line" == *src=203.0.113.42* ]]
	[[ "$line" == *reason=SSH* ]]
}

# --- CEF escaping ---

@test "CEF: pipe escaping in header fields" {
	ELOG_CEF_VENDOR="Ven|dor"
	ELOG_CEF_PRODUCT="Pro|duct"
	elog_output_enable "cef"
	elog_event "block_added" "warn" "msg with | pipe" > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	# Pipes in header fields should be escaped as \|
	[[ "$line" == *'Ven\|dor'* ]]
	[[ "$line" == *'Pro\|duct'* ]]
	[[ "$line" == *'msg with \| pipe'* ]]
}

@test "CEF: backslash escaping in header fields" {
	ELOG_CEF_VENDOR=$'Ven\\dor'
	elog_output_enable "cef"
	elog_event "block_added" "warn" $'msg with \\ backslash' > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	# Backslash in vendor header should be escaped to \\ in CEF output
	# Use grep -F for exact literal matching (avoids glob/regex escaping complexity)
	echo "$line" | grep -qF 'Ven\\dor'
	echo "$line" | grep -qF 'msg with \\ backslash'
}

@test "CEF: equals escaping in extension values" {
	elog_output_enable "cef"
	elog_event "config_loaded" "info" "config ok" "detail=key=val" > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	# Equals in extension values should be escaped as \=
	[[ "$line" == *'detail=key\=val'* ]]
}

@test "CEF: newline escaping" {
	elog_output_enable "cef"
	local msg_with_nl
	msg_with_nl="line1"$'\n'"line2"
	elog_event "test_type" "info" "$msg_with_nl" > /dev/null
	local line
	line=$(head -1 "$ELOG_CEF_FILE")
	# Newline should be escaped as \n in the CEF Name field
	[[ "$line" == *'line1\nline2'* ]]
}

# --- CEF with tag ---

@test "CEF: tag extraction appears in extension" {
	elog_output_enable "cef"
	elog_event "block_added" "warn" "{sshd} blocked host" > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	[[ "$line" == *'tag=sshd'* ]]
}

# --- CEF source filtering ---

@test "CEF: module only receives event source (not elog)" {
	elog_output_enable "cef"
	: > "$ELOG_CEF_FILE"
	elog info "this is elog output" > /dev/null
	# CEF module has source=event, so elog() output should not appear
	[ "$(wc -l < "$ELOG_CEF_FILE")" -eq 0 ]
}

# --- CEF disabled by default ---

@test "CEF: disabled by default" {
	: > "$ELOG_CEF_FILE"
	elog_event "block_added" "warn" "should not appear" > /dev/null
	# CEF module is registered but not enabled
	[ "$(wc -l < "$ELOG_CEF_FILE")" -eq 0 ]
}

# --- CEF config override ---

@test "CEF: vendor/product/version config override" {
	ELOG_CEF_VENDOR="Custom Vendor"
	ELOG_CEF_PRODUCT="Custom Product"
	ELOG_CEF_VERSION="9.9.9"
	elog_output_enable "cef"
	elog_event "test_type" "info" "config test" > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	[[ "$line" == CEF:0\|Custom\ Vendor\|Custom\ Product\|9.9.9\|* ]]
}

# --- CEF message truncation ---

@test "CEF: message truncation at 128 chars" {
	elog_output_enable "cef"
	# Generate a message longer than 128 chars
	local long_msg=""
	local i
	for i in $(seq 1 20); do
		long_msg="${long_msg}abcdefg"
	done
	# long_msg is now 140 chars
	elog_event "test_type" "info" "$long_msg" > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	# Name field (between 5th and 6th pipe) should be truncated to 128 chars
	# Extract the name field
	local name_field
	name_field=$(echo "$line" | awk -F'|' '{print $6}')
	[ ${#name_field} -le 128 ]
}

# --- CEF empty extras ---

@test "CEF: empty extras produces valid CEF line" {
	elog_output_enable "cef"
	elog_event "test_type" "info" "no extras" > /dev/null
	local line
	line=$(cat "$ELOG_CEF_FILE")
	# Should be a valid CEF line starting with CEF:0|
	[[ "$line" == CEF:0\|* ]]
	# Line should end with the severity and empty extension: |3|
	[[ "$line" == *\|3\| ]]
}
