#!/bin/bash
# elog-common.bash — shared BATS helper for elog_lib tests
# Sources elog_lib.sh and provides setup/teardown functions.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export PROJECT_ROOT

# Source library under test
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/files/elog_lib.sh"

# Expected version from sourced library — tests use this instead of hardcoded strings
EXPECTED_VERSION="$ELOG_LIB_VERSION"
export EXPECTED_VERSION

# Load bats-support and bats-assert if available
if [[ -d /usr/local/lib/bats/bats-support ]]; then
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-support/load.bash
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-assert/load.bash
fi

elog_common_setup() {
	TEST_TMPDIR=$(mktemp -d)
	export TEST_TMPDIR

	# Reset source guard to allow re-sourcing for clean state
	_ELOG_LIB_LOADED=""
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/elog_lib.sh"

	# Set up test log files
	ELOG_LOG_FILE="$TEST_TMPDIR/test.log"
	ELOG_AUDIT_FILE="$TEST_TMPDIR/audit.log"
	ELOG_SYSLOG_FILE=""
	export ELOG_LOG_FILE ELOG_AUDIT_FILE ELOG_SYSLOG_FILE

	# Reset to defaults
	ELOG_APP="elog_test"
	ELOG_LEVEL="1"
	ELOG_FORMAT="classic"
	ELOG_VERBOSE="0"
	ELOG_STDOUT="always"
	ELOG_STDOUT_PREFIX="full"
	ELOG_LOG_MAX_LINES="0"
	ELOG_LEGACY_LOG=""
	ELOG_LOG_DIR="$TEST_TMPDIR"
	export ELOG_APP ELOG_LEVEL ELOG_FORMAT ELOG_VERBOSE
	export ELOG_STDOUT ELOG_STDOUT_PREFIX ELOG_LOG_MAX_LINES
	export ELOG_LEGACY_LOG ELOG_LOG_DIR

	# Reset internal state
	_ELOG_INIT_DONE=0
	_ELOG_WRITE_COUNT=0
}

elog_teardown() {
	rm -rf "$TEST_TMPDIR"
}
