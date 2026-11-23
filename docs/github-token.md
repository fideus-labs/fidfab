# A scoped GitHub token for Fabro runs

Every run receives Fabro's GitHub token as `GITHUB_TOKEN` in the sandbox. The agents use it to
push, open pull requests and answer review threads, and so could anything a prompt injection
talks them into. Treat it as exposed to every agent in every run, and give it no more than
those runs need.

With Fabro's default `token` strategy the run gets the vault secret `GITHUB_TOKEN` as is.
`fabro install` fills it from `gh auth token`, which is your `gh` login: an OAuth token with
`repo` scope on every repository your account can reach, no expiry, and shared with `gh` on the
host, so revoking it also logs `gh` out. The `[run.integrations.github] permissions` table in
each `workflow.toml` does not narrow that token: Fabro only requests those permissions when it
mints run tokens from a GitHub App
([Fabro GitHub integration](https://docs.fabro.sh/integrations/github)).

| Option | What a leaked token can do | Reads CI checks |
| --- | --- | --- |
| Fine-grained token (below) | The permissions below, on the repositories you pick, until it expires | Check it (step 3) |
| GitHub App (`strategy = "app"`) | The `workflow.toml` permissions on the installed repositories, for one hour | Yes |
| Classic token | `repo` scope on everything you can reach, until it expires | Yes |

## What the runs need

| Repository permission | Access | Used by |
| --- | --- | --- |
| Contents | Read and write | Fabro's clone and checkpoint pushes, `fidfab-pr-reply`, the history rewrite's force-push |
| Pull requests | Read and write | `gh pr create`, `gh pr edit`, `gh pr view`, review-thread replies and resolving |
| Issues | Read and write | `gh pr comment` (pull request comments are issue comments) |
| Actions | Read | `gh run view --log-failed` for failed CI |
| Commit statuses | Read | Status checks in `fidfab-pr-status` and `gh pr checks` |
| Metadata | Read | Required by GitHub for every token |

Workflows (write) is left out: without it GitHub rejects a push that changes a file under
`.github/workflows/`. Add it only if runs should edit CI configuration. Your `gh` token lacks
the matching `workflow` scope too, so leaving it out changes nothing.

## Fine-grained token

1. Open the form with the permissions above filled in, after replacing `OWNER` with the user
   or organization that owns the target repositories:

   ```
   https://github.com/settings/personal-access-tokens/new?name=fidfab+Fabro+runs&description=GITHUB_TOKEN+for+fidfab+sandboxes&target_name=OWNER&expires_in=90&contents=write&pull_requests=write&issues=write&actions=read&statuses=read&metadata=read
   ```

   The link cannot choose repositories: under **Repository access** select **Only select
   repositories** and pick the repositories you run fidfab on. Then **Generate token**.

   - A fine-grained token covers one owner. Runs against repositories of several owners need a
     GitHub App or a classic token.
   - If the organization requires approval, the token stays `pending`, able to read only public
     repositories, until an organization owner approves it.
   - An outside collaborator on an organization repository cannot use a fine-grained token
     there.

2. Read it into a shell variable, so it stays out of your shell history:

   ```bash
   printf 'GitHub token: '; read -rs t; echo   # works in bash and zsh
   ```

3. Check that it can read CI results. GitHub lists the Checks API among what fine-grained
   tokens cannot do, and `fidfab-pr-status` reads check runs through
   `gh pr view --json statusCheckRollup`. Use a pull request in one of the selected
   repositories with at least one check run, such as a GitHub Actions job; commit statuses
   alone do not test this. If any selected repository is private, use a private one: a public
   repository shows its checks to any token. Count its checks with the new token, then with your `gh` login
   (`env -u` keeps a token in your environment from standing in for the login):

   ```bash
   GH_TOKEN="$t" gh pr view NUMBER -R OWNER/REPO --json statusCheckRollup --jq '.statusCheckRollup | length'
   env -u GH_TOKEN -u GITHUB_TOKEN gh pr view NUMBER -R OWNER/REPO --json statusCheckRollup --jq '.statusCheckRollup | length'
   ```

   It works if both print the same number. A smaller first number, or an error such as
   `Resource not accessible by personal access token`, means it does not; use a GitHub App or a classic token instead. A token that
   errors fails every steward round at its status check, showing the error. One that silently
   returns fewer checks is worse: the steward does not see the failing ones and can report the
   pull request done.

4. Store it in the Fabro vault and clear the variable:

   ```bash
   printf %s "$t" | fabro secret set --value-stdin --description "fine-grained token, fidfab target repositories" GITHUB_TOKEN
   unset t
   ```

5. Run `fabro doctor`, then a `verify` run on a branch with an open pull request. It clones,
   pushes, edits and comments on the pull request, and reads its checks. A run uses only the
   permissions of the steps it takes, though: on a quiet pull request (checks green, no open
   review threads) the steward stops there, without answering review threads or reading
   failed CI logs (Actions read). Those are first used when a later run gets there; a
   `Resource not accessible` error at that step means the token lacks its permission in the
   table above.

`scripts/setup.sh` leaves the secret alone once Fabro is installed, but rerunning the
`fabro install --github-strategy token` command from the README's step 1 copies `gh auth token`
into it again.

When the token expires, clones and pushes fail. **Regenerate token** on the token's GitHub page
keeps its permissions and repositories; store the new value with steps 2 to 4. Deleting it
there does not affect `gh` on the host.

## Classic token

A classic token reads checks but cannot be limited to repositories. Compared with the `gh`
token it only adds an expiry and separates the two, so revoking one leaves the other working.
Create it with the `repo` scope (add `workflow` if runs should edit CI configuration) at
`https://github.com/settings/tokens/new?scopes=repo&description=fidfab+Fabro+runs`. If the
organization uses SAML single sign-on, authorize the token for it with **Configure SSO** on the
token list; until then it cannot reach that organization's repositories. Then follow steps 2,
4 and 5 above.

## GitHub App

`fabro install github` switches the server to the `app` strategy: it registers an App, which you
install on the target repositories, and Fabro then mints each run a one-hour token with exactly
the `workflow.toml` permissions. Grant the App at least those permissions, including Checks
(read). Pull requests and replies then come from the App's bot account instead of yours.
fidfab has not run under the App strategy yet; see the
[Fabro GitHub integration](https://docs.fabro.sh/integrations/github) for its setup and
webhooks.
