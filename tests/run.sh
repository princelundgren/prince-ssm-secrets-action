#!/usr/bin/env bash
# Runs every test_* function in tests/*_test.sh, each in a subshell with a fresh temp dir, and
# exits non-zero if any fails. Plain bash and jq only, so it needs nothing installed.
set -uo pipefail

tests_dir="$(cd "$(dirname "$0")" && pwd)"
export REPO_DIR="${tests_dir%/tests}"

# shellcheck source=tests/helpers.sh
. "$tests_dir/helpers.sh"
for file in "$tests_dir"/*_test.sh; do
  # shellcheck disable=SC1090
  . "$file"
done

passed=0
failed=0
for test in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
  TEST_TMP="$(mktemp -d)"
  # Not an if condition, which would switch set -e off inside the subshell.
  (set -e; cd "$TEST_TMP"; setup; "$test") >"$TEST_TMP.log" 2>&1
  test_status=$?
  if [[ $test_status -eq 0 ]]; then
    passed=$((passed + 1))
    printf 'ok     %s\n' "$test"
  else
    failed=$((failed + 1))
    printf 'FAIL   %s\n' "$test"
    sed 's/^/       /' "$TEST_TMP.log"
  fi
  rm -rf "$TEST_TMP" "$TEST_TMP.log"
done

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
