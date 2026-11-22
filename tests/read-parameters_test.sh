# shellcheck shell=bash
# shellcheck disable=SC2034 # status, stdout and stderr are read by the asserts in helpers.sh.
# Tests for scripts/read-parameters.sh, against the stub `aws` in helpers.sh.

HEX=0123456789abcdef0123456789abcdef
DELIM="ghadelimiter_$HEX"

test_single_value_is_exported_and_masked() {
  fix_delimiter "$HEX"
  param /ci/example/TOKEN SecureString s3cret-token
  SSM_NAMES=TOKEN read_parameters
  assert_status 0
  assert_contains "$stdout" "::add-mask::s3cret-token"
  assert_env "TOKEN<<$DELIM"$'\n'"s3cret-token"$'\n'"$DELIM"$'\n'
}

test_aws_is_called_recursively_with_decryption_and_no_paging_flag() {
  param /ci/example/TOKEN SecureString v
  SSM_PATH=/ci/example/ SSM_NAMES=TOKEN read_parameters
  assert_status 0
  assert_equal "$(cat aws-args)" "ssm
get-parameters-by-path
--path
/ci/example
--recursive
--with-decryption
--region
eu-west-1
--output
json"
}

test_split_value_is_joined_in_numeric_order() {
  fix_delimiter "$HEX"
  # Out of order on purpose, and past 9, so a lexical sort would put /10 after /1.
  for i in 10 3 1 9 2 5 4 7 6 8; do param "/ci/example/CERT/$i" SecureString "part$i-"; done
  SSM_NAMES=CERT read_parameters
  assert_status 0
  joined="part1-part2-part3-part4-part5-part6-part7-part8-part9-part10-"
  assert_env "CERT<<$DELIM"$'\n'"$joined"$'\n'"$DELIM"$'\n'
  assert_contains "$stdout" "::add-mask::$joined"
  for i in 1 2 3 4 5 6 7 8 9 10; do assert_contains "$stdout" "::add-mask::part$i-"$'\n'; done
}

test_split_value_with_a_gap_fails() {
  for i in 1 2 4; do param "/ci/example/CERT/$i" SecureString "secret-part$i"; done
  SSM_NAMES=CERT read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::The parts of /ci/example/CERT are not numbered 1 to n without a gap: found 1, 2, 4."
  assert_not_contains "$stdout$stderr" "secret-part"
}

test_split_value_not_starting_at_one_fails() {
  for i in 2 3; do param "/ci/example/CERT/$i" SecureString "secret-part$i"; done
  SSM_NAMES=CERT read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "not numbered 1 to n without a gap"
}

test_name_and_parts_both_existing_fails() {
  param /ci/example/CERT SecureString secret-whole
  param /ci/example/CERT/1 SecureString secret-part1
  SSM_NAMES=CERT read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::Both /ci/example/CERT and its numbered parts /ci/example/CERT/<n> exist; keep only one."
  assert_not_contains "$stdout$stderr" "secret-"
}

test_missing_name_fails_naming_the_parameter() {
  param /ci/example/TOKEN SecureString secret-token
  SSM_NAMES="TOKEN MISSING" read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::Parameter /ci/example/MISSING was not found, or the role cannot read it."
  assert_not_contains "$stdout$stderr" "secret-token"
}

test_a_sibling_with_a_longer_name_is_not_a_match() {
  param /ci/example/TOKEN_OLD SecureString secret-old
  param /ci/example/TOKEN/x SecureString secret-x
  SSM_NAMES=TOKEN read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "Parameter /ci/example/TOKEN was not found"
}

test_string_value_is_not_masked() {
  fix_delimiter "$HEX"
  param /ci/example/TEAM_ID String ABCDE12345
  SSM_NAMES=TEAM_ID read_parameters
  assert_status 0
  assert_not_contains "$stdout" "::add-mask::"
  assert_not_contains "$stdout$stderr" "ABCDE12345"
  assert_env "TEAM_ID<<$DELIM"$'\n'"ABCDE12345"$'\n'"$DELIM"$'\n'
}

test_only_secure_strings_are_masked() {
  param /ci/example/TEAM_ID String plain-value
  param /ci/example/TOKEN SecureString secret-value
  SSM_NAMES=$'TEAM_ID\nTOKEN' read_parameters
  assert_status 0
  assert_equal "$(grep '::add-mask::' stdout)" "::add-mask::secret-value"
}

test_multi_line_value_masks_each_line_escaped() {
  param /ci/example/KEY SecureString $'-----BEGIN-----\r\nab%cd\nef\rgh\n  \n'
  SSM_NAMES=KEY read_parameters
  assert_status 0
  assert_equal "$(grep '::add-mask::' stdout | sort)" "$(sort <<'EOF'
::add-mask::-----BEGIN-----
::add-mask::-----BEGIN-----%0D%0Aab%25cd%0Aef%0Dgh%0A  %0A
::add-mask::ab%25cd
::add-mask::ef
::add-mask::gh
EOF
)"
  assert_not_contains "$stdout" "ab%cd"
}

test_masks_come_before_anything_else_on_stdout() {
  param /ci/example/TOKEN SecureString secret-value
  SSM_NAMES=TOKEN read_parameters
  assert_status 0
  assert_equal "$(head -n 1 stdout)" "::add-mask::secret-value"
  assert_equal "$(grep -c -v '::add-mask::' stdout)" "1"
}

test_multi_line_and_trailing_newline_survive_in_github_env() {
  fix_delimiter "$HEX"
  param /ci/example/KEY SecureString $'line1\nline2\n'
  param /ci/example/TEAM_ID String team
  SSM_NAMES="KEY TEAM_ID" read_parameters
  assert_status 0
  assert_env "KEY<<$DELIM"$'\nline1\nline2\n\n'"$DELIM"$'\n'"TEAM_ID<<$DELIM"$'\nteam\n'"$DELIM"$'\n'
}

test_value_holding_the_delimiter_fails_and_writes_nothing() {
  fix_delimiter "$HEX"
  param /ci/example/FINE SecureString fine-value
  param /ci/example/EVIL SecureString "x"$'\n'"$DELIM"$'\n'"INJECTED=1"
  SSM_NAMES="FINE EVIL" read_parameters
  assert_status 1
  [[ ! -s $GITHUB_ENV ]] || fail_test "GITHUB_ENV should be empty"
  assert_contains "$stdout" "::error::Could not write the values to GITHUB_ENV; nothing was written."
  assert_not_contains "$stderr" "INJECTED"
}

test_delimiter_is_random_and_well_formed() {
  param /ci/example/TOKEN SecureString v
  SSM_NAMES=TOKEN read_parameters
  first="$(head -n 1 "$GITHUB_ENV")"
  : >"$GITHUB_ENV"
  SSM_NAMES=TOKEN read_parameters
  second="$(head -n 1 "$GITHUB_ENV")"
  [[ $first =~ ^TOKEN\<\<ghadelimiter_[0-9a-f]{32}$ ]] || fail_test "bad delimiter line: $first"
  [[ $first != "$second" ]] || fail_test "delimiter repeated: $first"
}

test_parts_with_any_secure_string_mask_the_joined_value() {
  param /ci/example/CERT/1 String aaa
  param /ci/example/CERT/2 SecureString bbb
  SSM_NAMES=CERT read_parameters
  assert_status 0
  assert_contains "$stdout" "::add-mask::aaabbb"
  assert_contains "$stdout" "::add-mask::bbb"
}

test_root_path_reads_top_level_names() {
  fix_delimiter "$HEX"
  param /TOKEN SecureString v
  SSM_PATH=/ SSM_NAMES=TOKEN read_parameters
  assert_status 0
  assert_contains "$(cat aws-args)" $'--path\n/\n'
  assert_env "TOKEN<<$DELIM"$'\nv\n'"$DELIM"$'\n'
}

test_invalid_name_fails_without_echoing_it() {
  SSM_NAMES='TOKEN BAD=NAME' read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::Each name must be an environment variable name"
  assert_not_contains "$stdout" "BAD=NAME"
  [[ ! -f aws-args ]] || fail_test "aws should not run"
}

test_empty_names_fails() {
  SSM_NAMES=$' \n ' read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::names is empty."
}

test_relative_path_fails() {
  SSM_PATH=ci/example SSM_NAMES=TOKEN read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::path must start with /"
}

test_aws_failure_fails_clearly() {
  export AWS_STUB_EXIT=254
  SSM_NAMES=TOKEN read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::aws ssm get-parameters-by-path failed for /ci/example"
}

test_non_json_response_fails_clearly() {
  printf 'secret-garbage' >aws-raw
  SSM_NAMES=TOKEN read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::aws ssm get-parameters-by-path returned no Parameters list"
  assert_not_contains "$stdout$stderr" "secret-garbage"
}

test_missing_credentials_fail() {
  unset AWS_ACCESS_KEY_ID
  SSM_NAMES=TOKEN read_parameters
  assert_failed_cleanly
  assert_contains "$stdout" "::error::No AWS credentials"
}

test_xtrace_from_the_caller_is_switched_off() {
  param /ci/example/TOKEN SecureString secret-value
  SSM_NAMES=TOKEN "$BASH_UNDER_TEST" -x "$REPO_DIR/scripts/read-parameters.sh" >stdout 2>stderr &&
    status=0 || status=$?
  stdout="$(cat stdout)" stderr="$(cat stderr)"
  assert_status 0
  assert_contains "$stderr" "+ set +x"
  assert_not_contains "$stderr" "secret-value"
}
