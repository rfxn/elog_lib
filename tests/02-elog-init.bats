#!/usr/bin/env bats
#
# Test suite for elog_init() — log file architecture
#

load helpers/elog-common

setup() {
	elog_common_setup
}

teardown() {
	elog_teardown
}

# --- elog_init() directory creation ---

@test "elog_init: creates log directory" {
	local log_dir="$TEST_TMPDIR/log/myapp"
	ELOG_APP="myapp"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/myapp.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	run elog_init
	assert_success
	[ -d "$log_dir" ]
}

@test "elog_init: sets directory permissions to 750" {
	local log_dir="$TEST_TMPDIR/log/permtest"
	ELOG_APP="permtest"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/permtest.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	elog_init
	local perms
	perms=$(stat -c '%a' "$log_dir")
	[ "$perms" = "750" ]
}

@test "elog_init: creates log files" {
	local log_dir="$TEST_TMPDIR/log/filetest"
	ELOG_APP="filetest"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/filetest.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	elog_init
	[ -f "$log_dir/filetest.log" ]
	[ -f "$log_dir/audit.log" ]
}

@test "elog_init: sets log file permissions to 640" {
	local log_dir="$TEST_TMPDIR/log/fperm"
	ELOG_APP="fperm"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/fperm.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	elog_init
	local perms
	perms=$(stat -c '%a' "$log_dir/fperm.log")
	[ "$perms" = "640" ]
	perms=$(stat -c '%a' "$log_dir/audit.log")
	[ "$perms" = "640" ]
}

@test "elog_init: is idempotent" {
	local log_dir="$TEST_TMPDIR/log/idempotent"
	ELOG_APP="idempotent"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/idempotent.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	elog_init
	# Write something to the log file
	echo "existing data" >> "$log_dir/idempotent.log"
	# Call init again
	run elog_init
	assert_success
	# Existing data preserved
	grep -q "existing data" "$log_dir/idempotent.log"
}

@test "elog_init: computes default paths from ELOG_APP" {
	local base="$TEST_TMPDIR/log"
	mkdir -p "$base"
	ELOG_APP="testapp"
	ELOG_LOG_DIR="$base/testapp"
	# Unset explicit paths to test defaults
	unset ELOG_LOG_FILE
	unset ELOG_AUDIT_FILE
	elog_init
	[ "$ELOG_LOG_FILE" = "$base/testapp/testapp.log" ]
	[ "$ELOG_AUDIT_FILE" = "$base/testapp/audit.log" ]
}

@test "elog_init: returns 1 on directory creation failure" {
	ELOG_APP="fail"
	ELOG_LOG_DIR="/proc/nonexistent/fail"
	ELOG_LOG_FILE="/proc/nonexistent/fail/fail.log"
	ELOG_AUDIT_FILE="/proc/nonexistent/fail/audit.log"
	run elog_init
	assert_failure
}

# --- Legacy symlink ---

@test "elog_init: creates legacy symlink when ELOG_LEGACY_LOG set" {
	local log_dir="$TEST_TMPDIR/log/symtest"
	local legacy_path="$TEST_TMPDIR/old_log"
	ELOG_APP="symtest"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/symtest.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	ELOG_LEGACY_LOG="$legacy_path"
	elog_init
	[ -L "$legacy_path" ]
	local target
	target=$(readlink "$legacy_path")
	[ "$target" = "$log_dir/symtest.log" ]
}

@test "elog_init: does not overwrite existing legacy path" {
	local log_dir="$TEST_TMPDIR/log/nooverwrite"
	local legacy_path="$TEST_TMPDIR/existing_log"
	echo "precious data" > "$legacy_path"
	ELOG_APP="nooverwrite"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/nooverwrite.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	ELOG_LEGACY_LOG="$legacy_path"
	elog_init
	# Should NOT be a symlink — existing file preserved
	[ ! -L "$legacy_path" ]
	grep -q "precious data" "$legacy_path"
}

@test "elog_init: no symlink when ELOG_LEGACY_LOG empty" {
	local log_dir="$TEST_TMPDIR/log/nosym"
	ELOG_APP="nosym"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/nosym.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	ELOG_LEGACY_LOG=""
	elog_init
	# Just verify init succeeds — no symlink to check
	[ -f "$log_dir/nosym.log" ]
}

# --- Auto-enable modules ---

@test "elog_init: auto-enables file module" {
	local log_dir="$TEST_TMPDIR/log/autoen"
	ELOG_APP="autoen"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/autoen.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	elog_init
	elog_output_enabled "file"
}

@test "elog_init: auto-enables audit_file module" {
	local log_dir="$TEST_TMPDIR/log/auditauto"
	ELOG_APP="auditauto"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/auditauto.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	elog_init
	elog_output_enabled "audit_file"
}

@test "elog_init: auto-enables syslog_file when ELOG_SYSLOG_FILE set" {
	local log_dir="$TEST_TMPDIR/log/syslogauto"
	ELOG_APP="syslogauto"
	ELOG_LOG_DIR="$log_dir"
	ELOG_LOG_FILE="$log_dir/syslogauto.log"
	ELOG_AUDIT_FILE="$log_dir/audit.log"
	ELOG_SYSLOG_FILE="$TEST_TMPDIR/syslog"
	elog_init
	elog_output_enabled "syslog_file"
}

# --- elog_logrotate_snippet() ---

@test "elog_logrotate_snippet: produces logrotate config" {
	ELOG_APP="rottest"
	ELOG_LOG_DIR="/var/log/rottest"
	ELOG_LOG_FILE="/var/log/rottest/rottest.log"
	ELOG_AUDIT_FILE="/var/log/rottest/audit.log"
	run elog_logrotate_snippet
	assert_success
	assert_output --partial "/var/log/rottest/rottest.log"
	assert_output --partial "/var/log/rottest/audit.log"
	assert_output --partial "weekly"
	assert_output --partial "rotate 12"
	assert_output --partial "compress"
	assert_output --partial "create 640 root root"
	assert_output --partial "postrotate"
}

@test "elog_logrotate_snippet: respects custom rotation vars" {
	ELOG_APP="custom"
	ELOG_LOG_DIR="/var/log/custom"
	ELOG_LOG_FILE="/var/log/custom/custom.log"
	ELOG_AUDIT_FILE="/var/log/custom/audit.log"
	ELOG_ROTATE_FREQUENCY="daily"
	ELOG_ROTATE_COUNT="30"
	ELOG_ROTATE_COMPRESS="nocompress"
	run elog_logrotate_snippet
	assert_success
	assert_output --partial "daily"
	assert_output --partial "rotate 30"
	assert_output --partial "nocompress"
}

# --- Log truncation ---

@test "_elog_truncate_check: truncates when over limit" {
	local logfile="$TEST_TMPDIR/trunc.log"
	ELOG_LOG_FILE="$logfile"
	ELOG_LOG_MAX_LINES="5"
	# Write 10 lines
	local i
	for i in 1 2 3 4 5 6 7 8 9 10; do
		echo "line $i" >> "$logfile"
	done
	_elog_truncate_check
	local count
	count=$(wc -l < "$logfile")
	count="${count## }"
	[ "$count" -eq 5 ]
	# Should have the last 5 lines
	grep -q "^line 10$" "$logfile"
	grep -q "^line 6$" "$logfile"
	# Should not have early lines (anchor to avoid "line 1" matching "line 10")
	! grep -q "^line 1$" "$logfile"
}

@test "_elog_truncate_check: no-op when under limit" {
	local logfile="$TEST_TMPDIR/notrunc.log"
	ELOG_LOG_FILE="$logfile"
	ELOG_LOG_MAX_LINES="100"
	echo "line 1" >> "$logfile"
	echo "line 2" >> "$logfile"
	_elog_truncate_check
	local count
	count=$(wc -l < "$logfile")
	count="${count## }"
	[ "$count" -eq 2 ]
}

@test "_elog_truncate_check: no-op when ELOG_LOG_MAX_LINES=0" {
	local logfile="$TEST_TMPDIR/nomax.log"
	ELOG_LOG_FILE="$logfile"
	ELOG_LOG_MAX_LINES="0"
	local i
	for i in 1 2 3 4 5; do
		echo "line $i" >> "$logfile"
	done
	_elog_truncate_check
	local count
	count=$(wc -l < "$logfile")
	count="${count## }"
	[ "$count" -eq 5 ]
}

@test "_elog_truncate_check: preserves inode" {
	local logfile="$TEST_TMPDIR/inode.log"
	ELOG_LOG_FILE="$logfile"
	ELOG_LOG_MAX_LINES="3"
	local i
	for i in 1 2 3 4 5 6; do
		echo "line $i" >> "$logfile"
	done
	local inode_before
	inode_before=$(stat -c '%i' "$logfile")
	_elog_truncate_check
	local inode_after
	inode_after=$(stat -c '%i' "$logfile")
	[ "$inode_before" = "$inode_after" ]
}
