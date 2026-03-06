#!/usr/bin/env bats
#
# Test suite for event taxonomy — type validation and severity mapping
#

load helpers/elog-common

setup() {
	elog_common_setup
}

teardown() {
	elog_teardown
}

# --- Type validation ---

@test "_elog_event_type_valid: all 23 types are valid" {
	local types=(
		threat_detected threshold_exceeded pattern_matched scan_started scan_completed
		block_added block_removed block_escalated quarantine_added quarantine_removed
		trust_added trust_removed
		rule_loaded rule_removed service_state
		alert_sent alert_failed
		monitor_started monitor_stopped
		config_loaded config_error file_cleaned error_occurred
	)
	local t
	for t in "${types[@]}"; do
		_elog_event_type_valid "$t" || {
			echo "FAIL: $t should be valid" >&2
			return 1
		}
	done
	[ "${#types[@]}" -eq 23 ]
}

@test "_elog_event_type_valid: unknown type returns 1" {
	! _elog_event_type_valid "bogus_type"
}

@test "_elog_event_type_valid: empty string returns 1" {
	! _elog_event_type_valid ""
}

# --- Severity mapping ---

@test "_elog_event_severity: warn-level types" {
	local types=(threat_detected threshold_exceeded block_added quarantine_added)
	local t
	for t in "${types[@]}"; do
		run _elog_event_severity "$t"
		assert_output "warn"
	done
}

@test "_elog_event_severity: error-level types" {
	local types=(block_escalated alert_failed config_error error_occurred)
	local t
	for t in "${types[@]}"; do
		run _elog_event_severity "$t"
		assert_output "error"
	done
}

@test "_elog_event_severity: info-level types" {
	local types=(
		pattern_matched scan_started scan_completed
		block_removed quarantine_removed
		trust_added trust_removed
		rule_loaded rule_removed service_state
		alert_sent
		monitor_started monitor_stopped
		config_loaded file_cleaned
	)
	local t
	for t in "${types[@]}"; do
		run _elog_event_severity "$t"
		assert_output "info"
	done
}

@test "_elog_event_severity: unknown type returns info" {
	run _elog_event_severity "bogus_type"
	assert_output "info"
}

# --- Integration: elog_event works with unknown type ---

@test "elog_event: works with unknown type (not enforced)" {
	elog_init
	: > "$ELOG_AUDIT_FILE"
	elog_event "custom_event" "info" "unknown type allowed" > /dev/null
	[ "$(wc -l < "$ELOG_AUDIT_FILE")" -eq 1 ]
	grep -q '"type":"custom_event"' "$ELOG_AUDIT_FILE"
}
