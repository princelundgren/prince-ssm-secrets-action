#!/usr/bin/env bash
# Writes the default role session name, "<owner>-<repo>-<run id>", to the step's outputs as `name`.
# STS allows only [A-Za-z0-9+=,.@-] and at most 64 characters in a session name; the cut falls on
# the repository part, so the run id always survives.
set -euo pipefail
set +x

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is not set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"

# Byte-wise ranges, so a locale can't widen [A-Za-z].
LC_ALL=C
suffix="-${GITHUB_RUN_ID//[^A-Za-z0-9+=,.@-]/-}"
repository="${GITHUB_REPOSITORY//[^A-Za-z0-9+=,.@-]/-}"
name="${repository:0:$((64 - ${#suffix}))}${suffix}"

printf 'name=%s\n' "$name" >>"$GITHUB_OUTPUT"
