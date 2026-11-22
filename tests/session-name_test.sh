# shellcheck shell=bash
# Tests for scripts/session-name.sh.

test_session_name_joins_repository_and_run_id() {
  GITHUB_REPOSITORY=octo-org/example GITHUB_RUN_ID=123456 run_script session-name.sh
  assert_status 0
  assert_equal "$(cat "$GITHUB_OUTPUT")" "name=octo-org-example-123456"
}

test_session_name_replaces_characters_sts_refuses() {
  GITHUB_REPOSITORY='octo_org/ex ample+=,.@-é' GITHUB_RUN_ID=7 run_script session-name.sh
  assert_status 0
  # é is two bytes in UTF-8, so it becomes two dashes, between the kept - and the joining one.
  assert_equal "$(cat "$GITHUB_OUTPUT")" "name=octo-org-ex-ample+=,.@----7"
}

test_session_name_is_cut_to_64_characters_keeping_the_run_id() {
  GITHUB_REPOSITORY="octo-org/$(printf 'r%.0s' {1..80})" GITHUB_RUN_ID=99 run_script session-name.sh
  assert_status 0
  name="$(sed 's/^name=//' "$GITHUB_OUTPUT")"
  assert_equal "${#name}" "64"
  assert_equal "$name" "octo-org-$(printf 'r%.0s' {1..52})-99"
}

test_session_name_needs_the_run_id() {
  unset GITHUB_RUN_ID
  GITHUB_REPOSITORY=octo-org/example run_script session-name.sh
  assert_status 1
}
