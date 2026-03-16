#!/usr/bin/env bats
#
# Test suite for output module registry
#

load helpers/elog-common

setup() {
	elog_common_setup
}

teardown() {
	elog_teardown
}

# --- Registration ---

@test "elog_output_register: registers new module" {
	# Built-ins already registered (8), add a custom one
	elog_output_register "custom" "my_handler" "json" "event"
	[[ ${#_ELOG_OUTPUT_NAMES[@]} -eq 9 ]]
	[[ "${_ELOG_OUTPUT_NAMES[8]}" == "custom" ]]
	[[ "${_ELOG_OUTPUT_HANDLERS[8]}" == "my_handler" ]]
	[[ "${_ELOG_OUTPUT_FORMATS[8]}" == "json" ]]
	[[ "${_ELOG_OUTPUT_SOURCES[8]}" == "event" ]]
}

@test "elog_output_register: new module starts disabled" {
	elog_output_register "disabled_test" "handler_fn" "classic" "all"
	! elog_output_enabled "disabled_test"
}

@test "elog_output_register: rejects empty name" {
	run elog_output_register "" "handler_fn"
	assert_failure
	assert_output --partial "name cannot be empty"
}

@test "elog_output_register: rejects empty handler" {
	run elog_output_register "test_mod" ""
	assert_failure
	assert_output --partial "handler function cannot be empty"
}

@test "elog_output_register: rejects duplicate name" {
	run elog_output_register "file" "another_handler"
	assert_failure
	assert_output --partial "already registered"
}

# --- Enable/Disable ---

@test "elog_output_enable: enables a registered module" {
	! elog_output_enabled "file"
	elog_output_enable "file"
	elog_output_enabled "file"
}

@test "elog_output_disable: disables a registered module" {
	elog_output_enable "file"
	elog_output_enabled "file"
	elog_output_disable "file"
	! elog_output_enabled "file"
}

@test "elog_output_enable: fails for unregistered module" {
	run elog_output_enable "nonexistent"
	assert_failure
	assert_output --partial "not registered"
}

@test "elog_output_disable: fails for unregistered module" {
	run elog_output_disable "nonexistent"
	assert_failure
	assert_output --partial "not registered"
}

@test "elog_output_enabled: returns 1 for unregistered module" {
	! elog_output_enabled "nonexistent"
}

# --- _elog_output_find ---

@test "_elog_output_find: finds registered module" {
	_elog_output_find "file"
	[ "$_ELOG_OUTPUT_IDX" -ge 0 ]
}

@test "_elog_output_find: returns 1 for unknown module" {
	! _elog_output_find "unknown_module"
	[ "$_ELOG_OUTPUT_IDX" -eq -1 ]
}

# --- Source filtering ---

@test "dispatch: file module (source=elog) receives elog() output" {
	: > "$ELOG_LOG_FILE"
	elog_output_enable "file"
	elog info "elog source test" > /dev/null
	grep -q "elog source test" "$ELOG_LOG_FILE"
}

@test "dispatch: audit_file module (source=event) does NOT receive elog() output" {
	: > "$ELOG_AUDIT_FILE"
	elog_output_enable "file"
	elog_output_enable "audit_file"
	elog info "should not appear in audit" > /dev/null
	[ "$(wc -l < "$ELOG_AUDIT_FILE")" -eq 0 ]
}

@test "dispatch: stdout module (source=all) receives elog() output" {
	elog_output_enable "stdout"
	run elog info "stdout receives elog"
	assert_success
	assert_output --partial "stdout receives elog"
}

@test "dispatch: disabled module receives nothing" {
	: > "$ELOG_LOG_FILE"
	_ELOG_INIT_DONE=1  # prevent auto-enable fallback
	elog_output_disable "file"
	elog_output_enable "stdout"
	elog info "only stdout" > /dev/null
	[ "$(wc -l < "$ELOG_LOG_FILE")" -eq 0 ]
}

# --- Format selection ---

@test "dispatch: file module uses ELOG_FORMAT=classic" {
	: > "$ELOG_LOG_FILE"
	ELOG_FORMAT="classic"
	elog_output_enable "file"
	elog info "classic line" > /dev/null
	local line
	line=$(cat "$ELOG_LOG_FILE")
	# Classic format contains hostname and (pid): pattern
	local pat='^[A-Z][a-z]{2} '
	[[ "$line" =~ $pat ]]
}

@test "dispatch: file module uses ELOG_FORMAT=json" {
	: > "$ELOG_LOG_FILE"
	ELOG_FORMAT="json"
	elog_output_enable "file"
	elog info "json line" > /dev/null
	local line
	line=$(cat "$ELOG_LOG_FILE")
	[[ "$line" == \{* ]]
	[[ "$line" == *\} ]]
}

@test "dispatch: syslog_file writes when enabled" {
	local syslog="$TEST_TMPDIR/syslog_dispatch"
	: > "$syslog"
	ELOG_SYSLOG_FILE="$syslog"
	elog_output_enable "syslog_file"
	elog_output_enable "file"
	elog info "syslog dispatch test" > /dev/null
	grep -q "syslog dispatch test" "$syslog"
}

# --- Module registry invariant ---

@test "elog: 8 built-in modules always registered after source" {
	# Verify the invariant that modules are always present — direct-write
	# fallback was removed; dispatch is the only code path
	[ "${#_ELOG_OUTPUT_NAMES[@]}" -eq 8 ]
	# Verify known module names
	local _found_file=0 _found_audit=0 _found_stdout=0
	local _i
	for _i in "${!_ELOG_OUTPUT_NAMES[@]}"; do
		case "${_ELOG_OUTPUT_NAMES[$_i]}" in
			file)       _found_file=1 ;;
			audit_file) _found_audit=1 ;;
			stdout)     _found_stdout=1 ;;
		esac
	done
	[ "$_found_file" -eq 1 ]
	[ "$_found_audit" -eq 1 ]
	[ "$_found_stdout" -eq 1 ]
}

# --- Multiple modules ---

@test "dispatch: multiple modules receive output simultaneously" {
	: > "$ELOG_LOG_FILE"
	local syslog="$TEST_TMPDIR/multi_syslog"
	: > "$syslog"
	ELOG_SYSLOG_FILE="$syslog"
	elog_output_enable "file"
	elog_output_enable "syslog_file"
	elog_output_enable "stdout"
	run elog info "multi target"
	assert_success
	assert_output --partial "multi target"
	grep -q "multi target" "$ELOG_LOG_FILE"
	grep -q "multi target" "$syslog"
}

# --- Custom module ---

@test "dispatch: custom module receives output" {
	local custom_file="$TEST_TMPDIR/custom_output"
	: > "$custom_file"
	# Define handler function
	_test_custom_handler() {
		echo "$1" >> "$custom_file"
	}
	elog_output_register "test_custom" "_test_custom_handler" "classic" "all"
	elog_output_enable "test_custom"
	elog_output_enable "file"
	elog info "custom module test" > /dev/null
	grep -q "custom module test" "$custom_file"
}
