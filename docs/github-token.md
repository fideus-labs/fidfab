# A scoped GitHub token for Fabro runs

Every run receives Fabro's GitHub token as `GITHUB_TOKEN` in the sandbox. The agents use it to
push, open pull requests and answer review threads, and so could anything a prompt injection
talks them into. Treat it as exposed to every agent in every run, and give it no more than
those runs need.

With Fabro's default `token` strategy the run gets the vault secret `GITHUB_TOKEN` as is.
`fabro install` fills it from `gh auth token`, which is your `gh` login: an OAuth token with
`repo` scope on every repository your account can reach, no expiry, and shared with `gh` on the
host, so revoking it also logs `gh` out. The `[run.integrations.github.permissions]` table in
each `workflow.toml` does not narrow that token: Fabro only requests those permissions when it
mints run tokens from a GitHub App
([Fabro GitHub integration](https://docs.fabro.sh/integrations/github)).

| Option | What a leaked token can do | Enough for a private repository |
| --- | --- | --- |
| [GitHub App](#github-app-recommended) (recommended) | The `workflow.toml` permissions on the run's repository, for at most an hour | Yes |
| [Fine-grained token](#fine-grained-token) | The permissions below, on the repositories you pick, until it expires | No |
| [Classic token](#classic-token) | `repo` scope on everything you can reach, until it expires | Yes |

## What the runs need

Each workflow requests these in `[run.integrations.github.permissions]`:

| Repository permission | Access | Used by |
| --- | --- | --- |
| Contents | Read and write | Cloning, checkpoint pushes, `fidfab-pr-reply`, the history rewrite's force-push |
| Pull requests | Read and write | `gh pr create`, `gh pr edit`, `gh pr view`, review-thread replies and resolving |
| Issues | Read and write | `gh pr comment` (pull request comments are issue comments) |
| Checks | Read | Check runs in `fidfab-pr-status` and `gh pr checks` |
| Commit statuses | Read | Commit statuses in `fidfab-pr-status` and `gh pr checks` |
| Actions | Read | `gh run view --log-failed` for failed CI |
| Metadata | Read | Required by GitHub for every token |

Workflows (write) is left out: without it GitHub rejects a push that changes a file under
`.github/workflows/`. Fabro's App never asks for it, and a `gh` login has no `workflow` scope
unless you added it, so runs cannot edit CI configuration. Only a token with that scope, such
as a classic token created with it, lets them.

## GitHub App (recommended)

Under the `app` strategy the App's private key stays on the Fabro server. For each run Fabro
mints an installation token with exactly the workflow's permissions, for the run's repository
only, valid for an hour. It renews the sandbox's git credentials every minute and gives every
new process a fresh `GITHUB_TOKEN`. None of your own tokens reaches a sandbox, and there is no
token for you to rotate.

`scripts/setup.sh github-app` runs step 1 and prints the addresses for steps 2 and 3; rerun it
to see them again.

1. **Register the App** on the host that runs the Fabro server. `OWNER` is the organization that
   owns the target repositories:

   ```bash
   fabro install github --non-interactive --strategy app --owner org:OWNER
   ```

   - Fabro registers a private App, and GitHub installs a private App only on the account that
     owns it: use `--owner org:OWNER` for an organization's repositories (registering needs an
     organization owner), `--owner personal` for your own.
   - It needs `gh` logged in on the host, and prints a local URL. Open it in a browser on the
     host (or forward its port over SSH): it leads to GitHub's **Create GitHub App** page with
     Fabro's settings filled in, and after **Create GitHub App** GitHub returns the browser to
     that local URL.
   - Fabro then writes the App's ID, client ID and slug to `~/.fabro/settings.toml`, puts its
     private key, client secret and webhook secret in the vault, drops the token strategy's
     `GITHUB_TOKEN` secret and restarts the server. The listen address and the rest of
     `settings.toml` are kept.

   `SLUG` below is the App's slug: `slug` under `[server.integrations.github]` in
   `~/.fabro/settings.toml`.

2. **Add the two permissions Fabro leaves out.** Fabro's App gets Contents, Pull requests,
   Issues and Checks (read and write) and Metadata (read), but not Actions or Commit statuses,
   which every fidfab workflow requests. GitHub refuses a token that asks for a permission the
   installation lacks, so until both are added every run fails at its first stage. Open the
   App's permissions page:

   ```
   https://github.com/organizations/OWNER/settings/apps/SLUG/permissions   # --owner org:OWNER
   https://github.com/settings/apps/SLUG/permissions                       # --owner personal
   ```

   Under **Repository permissions** set **Actions** and **Commit statuses** to **Read-only**,
   leave **Workflows** at **No access**, and **Save changes**. The App also holds permissions
   from Fabro's registration that fidfab's runs do not request (Dependabot alerts,
   organization projects, packages, emails); they never reach a sandbox.

3. **Install it** at `https://github.com/apps/SLUG/installations/new`: pick the owner,
   **Only select repositories**, the repositories you run fidfab on, then **Install**. A run's
   token still covers only its own repository.

   If the App was installed before step 2, the new permissions wait for the installation to
   accept them. Open the installation, choose **Configure**, and accept the permission
   request:

   ```
   https://github.com/organizations/OWNER/settings/installations   # --owner org:OWNER
   https://github.com/settings/installations                       # --owner personal
   ```

   Until then runs fail as described in step 2.

4. **Check it.** `fabro doctor` should pass its GitHub App check. Then start a `verify` run on
   a branch with an open pull request: a missing permission fails its first stage, and the
   pull request comment it posts comes from `SLUG[bot]`. As with any token, a quiet pull
   request (checks green, no open review threads) does not exercise review-thread replies or
   failed CI logs; those are first used when a later run gets there.

What changes under the App:

- Pull requests, comments and review-thread replies come from `SLUG[bot]` instead of you, so
  you can approve fidfab's pull requests yourself. Commits keep your name and email when
  `[run.git.author]` is set (`scripts/setup.sh author`); otherwise the bot authors them too.
- A process keeps the `GITHUB_TOKEN` it started with, and Fabro hands out tokens with at least
  ten minutes left. Git reads the credential store Fabro renews every minute, and so does the
  image's `gh` (`docker/rootfs/usr/local/bin/gh`, a wrapper around `/usr/bin/gh`), so both keep
  working through a long agent stage. Anything else that reads `GITHUB_TOKEN` itself can fail
  with `Bad credentials` once the token it started with expires.
- The App subscribes to no webhook events, so a Fabro server reachable only on your network is
  enough.
- fidfab has not run under the App strategy yet. One thing to watch: `fidfab-pr-status` tells
  the steward's own replies apart by the token's login (`viewer`). If an installation token
  cannot read it, threads the steward already answered are listed again every round.

## Fine-grained token

Tested against a private repository, a fine-grained token did not get the access fidfab needs.
Use the GitHub App for private repositories; for public ones, check the token with step 3
before you store it.

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
   alone do not test this. Count its checks with the new token, then with your `gh` login
   (`env -u` keeps a token in your environment from standing in for the login):

   ```bash
   GH_TOKEN="$t" gh pr view NUMBER -R OWNER/REPO --json statusCheckRollup --jq '.statusCheckRollup | length'
   env -u GH_TOKEN -u GITHUB_TOKEN gh pr view NUMBER -R OWNER/REPO --json statusCheckRollup --jq '.statusCheckRollup | length'
   ```

   It works if both print the same number. A smaller first number, or an error such as
   `Resource not accessible by personal access token`, means it does not; use the GitHub App
   or a classic token instead. A token that errors fails every steward round at its status
   check, showing the error. One that silently returns fewer checks is worse: the steward does
   not see the failing ones and can report the pull request done.

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
4 and 5 of the fine-grained token.
