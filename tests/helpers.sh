# shellcheck shell=bash
# Test helpers, sourced by tests/run.sh. Each test runs in $TEST_TMP with a stub `aws` first on
# PATH that prints the parameters added with `param` as one get-parameters-by-path response.

BASH_UNDER_TEST="${BASH_UNDER_TEST:-bash}"

setup() {
  mkdir -p bin
  cat >bin/aws <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TEST_TMP/aws-args"
if [[ -n ${AWS_STUB_EXIT:-} ]]; then
  echo "An error occurred (AccessDeniedException) when calling the GetParametersByPath operation" >&2
  exit "$AWS_STUB_EXIT"
fi
if [[ -f $TEST_TMP/aws-raw ]]; then cat "$TEST_TMP/aws-raw"; exit 0; fi
touch "$TEST_TMP/params.jsonl"
jq -s '{Parameters: .}' "$TEST_TMP/params.jsonl"
EOF
  chmod +x bin/aws
  export TEST_TMP
  export PATH="$TEST_TMP/bin:$PATH"
  export GITHUB_ENV="$TEST_TMP/github_env" GITHUB_OUTPUT="$TEST_TMP/github_output"
  : >"$GITHUB_ENV"
  : >"$GITHUB_OUTPUT"
  export AWS_REGION=eu-west-1 AWS_ACCESS_KEY_ID=stub-key AWS_SECRET_ACCESS_KEY=stub-secret
  export AWS_SESSION_TOKEN=stub-token SSM_PATH=/ci/example SSM_NAMES=""
  unset AWS_STUB_EXIT
}

# param <full name> <type> <value>
param() {
  jq -cn --arg n "$1" --arg t "$2" --arg v "$3" '{Name: $n, Type: $t, Value: $v}' >>params.jsonl
}

# Makes `od` print the given 32 hex digits, so the heredoc delimiter is known.
fix_delimiter() {
  cat >bin/od <<EOF
#!/usr/bin/env bash
echo " ${1:0:16}"
echo " ${1:16:16}"
EOF
  chmod +x bin/od
}

# run_script <script>: runs it with $BASH_UNDER_TEST; sets $status, $stdout and $stderr.
run_script() {
  "$BASH_UNDER_TEST" "$REPO_DIR/scripts/$1" >stdout 2>stderr && status=0 || status=$?
  stdout="$(cat stdout)"
  stderr="$(cat stderr)"
}

read_parameters() { run_script read-parameters.sh; }

fail_test() {
  printf 'assertion failed: %s\n--- status: %s\n--- stdout:\n%s\n--- stderr:\n%s\n--- GITHUB_ENV:\n%s\n' \
    "$1" "${status:-}" "${stdout:-}" "${stderr:-}" "$(cat "$GITHUB_ENV")"
  exit 1
}

assert_status() { [[ $status -eq $1 ]] || fail_test "status $status, expected $1"; }
assert_contains() { [[ $1 == *"$2"* ]] || fail_test "expected to contain: $2"; }
assert_not_contains() { [[ $1 != *"$2"* ]] || fail_test "expected not to contain: $2"; }
assert_equal() { [[ $1 == "$2" ]] || fail_test "expected: $2"$'\n'"actual: $1"; }

# assert_env <expected>: GITHUB_ENV byte for byte; $(cat) alone would drop trailing newlines.
assert_env() {
  local actual
  actual="$(cat "$GITHUB_ENV"; printf x)"
  [[ $actual == "${1}x" ]] || fail_test "GITHUB_ENV differs; expected:"$'\n'"$1"
}

assert_failed_cleanly() {
  assert_status 1
  [[ ! -s $GITHUB_ENV ]] || fail_test "GITHUB_ENV should be empty"
  assert_not_contains "$stdout" "::add-mask::"
}
