# prince-ssm-secrets-action

[![Test](https://github.com/princelundgren/prince-ssm-secrets-action/actions/workflows/test.yml/badge.svg)](https://github.com/princelundgren/prince-ssm-secrets-action/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A composite GitHub Action that assumes an AWS IAM role over GitHub OIDC, reads one AWS Systems
Manager Parameter Store path, and exports the parameters you name to the job's environment, with
every `SecureString` value masked in the log. No AWS key is stored in the repository.

## What it does

- **Assumes the role** with
  [`aws-actions/configure-aws-credentials`](https://github.com/aws-actions/configure-aws-credentials)
  for 15 minutes. The AWS credentials go only to the read step, never to the job's environment,
  though any later step of the job could assume the role itself (see "Security notes").
- **Reads the path once:** `aws ssm get-parameters-by-path --recursive --with-decryption`, which
  returns every parameter under the path, decrypted; only the names you list are exported.
- **Joins split values:** a name is either the parameter `<path>/<name>` or the numbered parts
  `<path>/<name>/1` … `<path>/<name>/n`, joined in numeric order. Parts let a value outgrow a
  parameter's size limit (4 KB standard, 8 KB advanced).
- **Fails, naming the parameter,** when a name is missing, its parts have a gap, or both the name
  and its parts exist. No value appears in an error.
- **Masks before it writes:** each `SecureString` value, each of its parts and each line of a
  multi-line value. `String` values aren't masked, so plain values such as an id stay readable in
  the log.
- **Writes `GITHUB_ENV` with a random heredoc delimiter,** checked not to occur in any value, so a
  value can't add a variable of its own.

## Usage

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write # for the OIDC token the role is assumed with
    steps:
      - uses: princelundgren/prince-ssm-secrets-action@<commit sha> # v1.0.0
        with:
          role-arn: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/example-reader
          aws-region: eu-west-1
          path: /ci/example
          names: |
            API_TOKEN
            SIGNING_CERTIFICATE

      - run: ./deploy.sh # sees $API_TOKEN and $SIGNING_CERTIFICATE
```

With the parameters `/ci/example/API_TOKEN`, `/ci/example/SIGNING_CERTIFICATE/1` and
`/ci/example/SIGNING_CERTIFICATE/2`, the job gets `API_TOKEN` and `SIGNING_CERTIFICATE`, the two
parts joined. A full ARN such as `arn:aws:iam::123456789012:role/example-reader` works as well; an
Actions variable keeps the account id out of the workflow file.

## Inputs

| Input | Required | Description |
| --- | --- | --- |
| `role-arn` | yes | ARN of the IAM role to assume |
| `path` | yes | Parameter Store path to read, such as `/ci/example` |
| `names` | yes | Names to export, relative to `path`, separated by spaces or newlines. Each must be a valid environment variable name and becomes one |
| `aws-region` | yes | Region of the parameters |
| `role-session-name` | no | Defaults to `<owner>-<repo>-<run id>`, with characters STS refuses turned into `-` and the repository part cut so the whole fits in 64 |

The action has no outputs: values reach the job only through its environment.

## What the caller needs

- **`permissions: id-token: write`** on the job, and on the calling job too when the step is in a
  reusable workflow: a called workflow can't get a permission its caller didn't grant.
- **An IAM role that trusts GitHub's OIDC provider** (`token.actions.githubusercontent.com`), with
  a trust policy narrowed by `sub` (and `job_workflow_ref` for a reusable workflow) to the
  repositories and refs that may read. See GitHub's
  [Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).
- **The role's permissions:** `ssm:GetParametersByPath` on the path itself,
  `arn:aws:ssm:<region>:<account>:parameter/ci/example`, which Parameter Store authorizes against
  the path, not each parameter it returns; and `kms:Decrypt` on the key, if the `SecureString`
  values use a customer managed key rather than `aws/ssm`.
- **On the runner:** bash, `jq` and the AWS CLI v2, as GitHub-hosted Ubuntu and macOS runners have.
  Windows runners aren't supported.

## Security notes

- **Every later step of the job sees the values,** through `GITHUB_ENV`, third-party actions
  included. Put the step in a job that runs only steps you trust, pinned by commit SHA.
- **Earlier steps are trusted too:** one that sets `PATH`, `BASH_ENV`, a proxy or an AWS endpoint
  variable through `GITHUB_ENV` can redirect or hook the read.
- **The trust policy is the boundary, not this step:** `id-token: write` holds for the whole job,
  so any step in it can request its own OIDC token and assume the role.
- **The role reads the whole path:** `GetParametersByPath` returns every parameter under it,
  decrypted, and an IAM deny on a sub-path doesn't stop it. Point `path` at a subtree holding only
  what the job may see.
- **Store anything sensitive as `SecureString`:** `String` values aren't masked, so they can show
  in the log, such as in later steps' environment listing.
- **The account id isn't masked:** it is part of `role-arn`, which the log shows with the step's
  inputs. Keep it in an Actions variable rather than the workflow file.
- **Pin this action by commit SHA,** not a tag: a moved tag would run new code with your role.
  Dependabot's `github-actions` updates keep the pin current.
- **Masking hides a value in the log, not from the job:** a step can still send a value anywhere.
  A short value can also mask unrelated text that happens to match it.
- On a self-hosted runner that outlives the job, the values sit in the job's runner files while it
  runs, as repository secrets do.

## Development

The tests run the scripts against a stub `aws` and need only bash and jq:

```sh
./tests/run.sh
shellcheck scripts/*.sh tests/*.sh
actionlint
```

## Contributing

Issues and pull requests are welcome. [`AGENTS.md`](AGENTS.md) has the conventions; the `Test`
workflow runs shellcheck, actionlint and the tests on every pull request.

## License

[MIT](LICENSE).
