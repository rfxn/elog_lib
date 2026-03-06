#!/usr/bin/env bats
# 00-scaffold.bats — validate project skeleton

load helpers/elog-common

setup() {
	elog_common_setup
}

teardown() {
	elog_teardown
}

@test "ELOG_LIB_VERSION is set and follows semver" {
	[[ -n "$EXPECTED_VERSION" ]]
	local semver_pat='^[0-9]+\.[0-9]+\.[0-9]+$'
	[[ "$EXPECTED_VERSION" =~ $semver_pat ]]
}

@test "source guard prevents double-sourcing side effects" {
	local ver_before="$ELOG_LIB_VERSION"
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/elog_lib.sh"
	[[ "$ELOG_LIB_VERSION" == "$ver_before" ]]
}

@test "output registry arrays initialized with built-in modules" {
	[[ ${#_ELOG_OUTPUT_NAMES[@]} -eq 4 ]]
	[[ "${_ELOG_OUTPUT_NAMES[0]}" == "file" ]]
	[[ "${_ELOG_OUTPUT_NAMES[1]}" == "audit_file" ]]
	[[ "${_ELOG_OUTPUT_NAMES[2]}" == "syslog_file" ]]
	[[ "${_ELOG_OUTPUT_NAMES[3]}" == "stdout" ]]
}
