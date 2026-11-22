#!/usr/bin/env bash
# Reads SSM_NAMES from the SSM Parameter Store path SSM_PATH and appends each to GITHUB_ENV.
#
# A name is either the parameter <path>/<name> or the numbered parts <path>/<name>/1 … /n, joined
# in numeric order. Every SecureString value is masked before anything is written. Values never
# reach the log, argv or the environment: bash holds them only in the unexported $parameters, and
# jq, reading it on stdin, does the rest.
set -euo pipefail
set +x

fail() {
  printf '::error::%s\n' "$1"
  exit 1
}

for tool in aws jq od; do
  command -v "$tool" >/dev/null || fail "$tool is not on PATH; the runner needs it."
done

: "${GITHUB_ENV:?GITHUB_ENV is not set}"
[[ -n ${AWS_REGION:-} ]] || fail "aws-region is empty."
[[ -n ${AWS_ACCESS_KEY_ID:-} ]] || fail "No AWS credentials came from configure-aws-credentials."

path="${SSM_PATH:-}"
[[ $path =~ ^/[A-Za-z0-9_./-]*$ ]] ||
  fail "path must start with / and hold only letters, digits and _ . - /."
# A trailing slash would double the one each name is joined with.
while [[ $path == */ ]]; do path="${path%/}"; done

set -f
names=()
for name in ${SSM_NAMES:-}; do
  [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
    fail "Each name must be an environment variable name: letters, digits and _, not starting with a digit."
  names+=("$name")
done
set +f
[[ ${#names[@]} -gt 0 ]] || fail "names is empty."

# The CLI follows NextToken itself and returns every page as one Parameters list.
if ! parameters="$(aws ssm get-parameters-by-path --path "${path:-/}" --recursive \
  --with-decryption --region "$AWS_REGION" --output json)"; then
  fail "aws ssm get-parameters-by-path failed for ${path:-/}; its error is above."
fi

if ! printf '%s' "$parameters" | jq -e '.Parameters | type == "array"' >/dev/null 2>&1; then
  fail "aws ssm get-parameters-by-path returned no Parameters list for ${path:-/}."
fi

# Resolves each name in $ARGS.positional to {name, secure, parts, value} or {name, error}.
# shellcheck disable=SC2016 # jq's $variables, not the shell's.
resolve='
  .Parameters as $params
  | $ARGS.positional
  | map(
      . as $name
      | ($prefix + "/" + $name) as $full
      | [$params[] | select(.Name == $full)] as $exact
      | [$params[]
          | (.Name | ltrimstr($full + "/")) as $rest
          | select((.Name | startswith($full + "/")) and ($rest | test("^[1-9][0-9]*$")))
          | . + {index: ($rest | tonumber)}]
        | sort_by(.index) as $parts
      | if ($exact | length) > 0 and ($parts | length) > 0 then
          {name: $name, error: "Both \($full) and its numbered parts \($full)/<n> exist; keep only one."}
        elif ($exact | length) > 0 then
          {name: $name, secure: ($exact[0].Type == "SecureString"),
           parts: [$exact[0].Value], value: $exact[0].Value}
        elif ($parts | length) > 0 then
          if ($parts | map(.index)) != [range(1; ($parts | length) + 1)] then
            {name: $name, error: "The parts of \($full) are not numbered 1 to n without a gap: found \($parts | map(.index) | map(tostring) | join(", "))."}
          else
            {name: $name, secure: any($parts[]; .Type == "SecureString"),
             parts: ($parts | map(.Value)), value: ($parts | map(.Value) | join(""))}
          end
        else
          {name: $name, error: "Parameter \($full) was not found, or the role cannot read it."}
        end)
'

jq_resolve() {
  local program="$1"
  shift
  printf '%s' "$parameters" | jq --arg prefix "$path" "$@" "$resolve | $program" --args "${names[@]}"
}

errors="$(jq_resolve '.[] | .error // empty' -r)"
if [[ -n $errors ]]; then
  while IFS= read -r line; do printf '::error::%s\n' "$line"; done <<<"$errors"
  exit 1
fi

# The runner masks only whole lines of its log, and not every runner version masks each line of a
# multi-line secret itself, so each line gets its own mask as well as one for the whole. Blank
# lines get none: the runner refuses an empty mask. The escaping is the Actions toolkit's: % first,
# then CR and LF.
jq_resolve '
  def escape: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
  [.[] | select(.secure) | (.parts[], .value) | (., splits("\r\n|\r|\n"))]
  | map(select(test("\\S"))) | unique | .[] | "::add-mask::" + escape
' -r

delimiter="ghadelimiter_$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
[[ $delimiter =~ ^ghadelimiter_[0-9a-f]{32}$ ]] || fail "Could not read 16 random bytes for the GITHUB_ENV delimiter."

# One string, built only once no value holds the delimiter, so GITHUB_ENV gets all or nothing.
# shellcheck disable=SC2016 # jq's $variables, not the shell's.
if ! jq_resolve '
  if any(.[]; .value | contains($delimiter)) then
    error("a value holds the heredoc delimiter")
  else
    map("\(.name)<<\($delimiter)\n\(.value)\n\($delimiter)\n") | join("")
  end
' -j --arg delimiter "$delimiter" >>"$GITHUB_ENV"; then
  fail "Could not write the values to GITHUB_ENV; nothing was written. Run the step again."
fi

printf 'Exported %s from %s.\n' "${names[*]}" "${path:-/}"
