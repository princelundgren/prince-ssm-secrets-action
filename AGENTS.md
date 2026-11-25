# prince-ssm-secrets-action — instructions for agents

This repository is public: everything in it, its commits and its pull requests are public. Write
nothing about the maintainer's own machines, accounts, private repositories or employer, and no AWS
account id, role, path or parameter name of a real deployment: examples use
`arn:aws:iam::123456789012:role/example-reader` and `/ci/example`.

- **No value may reach the log, argv or an error message.** The aws output is held in one variable
  and only ever piped to jq; nothing runs under `set -x`. Every `SecureString` value, part and line
  is masked before anything is written to `GITHUB_ENV`. Keep each of these when changing
  `scripts/read-parameters.sh`, with a test.
- **Inputs reach scripts through `env:`,** never through `${{ }}` inside a `run:` block.
- **The scripts run on bash 3.2** (macOS runners): no associative arrays, `mapfile` or `${var,,}`.
  CI runs only bash 5 on Ubuntu, so check on a Mac with `BASH_UNDER_TEST=/bin/bash ./tests/run.sh`.
- **Every action is pinned by full commit SHA** with its version in a comment; Dependabot moves the
  pins. actionlint's version and checksum in `test.yml` move together, by hand. The one exception
  is the Claude review's reusable workflow at a major-version tag (`@v2`), which its maintainer
  moves on purpose. It reads the Claude token from AWS Systems Manager over GitHub OIDC, so this
  repository holds a `CI_SECRETS_AWS_ACCOUNT` secret, not a token.
- **CI** runs on GitHub-hosted runners only, never with `pull_request_target` or `workflow_run`.

## Commands

```sh
./tests/run.sh                        # the tests: plain bash and jq, with a stub aws
shellcheck scripts/*.sh tests/*.sh
actionlint                            # it skips action.yml's run: blocks; test.yml shellchecks them
```

## Reviews

Claude reviews each pull request a person opens from this repository, once it is out of draft:
read its `## Claude review of <sha>` summary, and fix or answer each 🔴 and 🟡 before the
maintainer merges. Every push starts another review, so fix a 🔵 only in a push that also fixes
something else; otherwise reply why not and resolve its thread.
