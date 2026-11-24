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

`scripts/setup.sh github-app` runs step 1, for a new App or for
[one that already exists](#an-app-that-already-exists), keeps the CLI's dev-token login (below)
and prints the addresses for steps 2 and 3; rerun it to see them again.

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
     `GITHUB_TOKEN` secret and restarts the server. The listen address is kept.
   - It also replaces the server's login methods with GitHub sign-in for your `gh` login
     alone:

     ```toml
     [server.auth]
     methods = ["github"]

     [server.auth.github]
     allowed_usernames = ["LOGIN"]
     ```

     The CLI is still logged in with the server's dev token, which the server now refuses:
     `fabro doctor` fails with `Diagnostics (probe failed)` and, with `-v`,
     `Authentication required.`, and so do `fabro run` and every other command that talks to
     the server. `scripts/setup.sh github-app` adds the dev token back next to GitHub sign-in
     and restarts the server. By hand, set `methods = ["dev-token", "github"]` and run
     `fabro server restart`. The web UI keeps GitHub sign-in either way.

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

### An App that already exists

`fabro install github` only registers a new App. To use one the organization already has, such
as the App of another Fabro server, give `scripts/setup.sh github-app` its slug (the last part
of `https://github.com/apps/SLUG`) when it asks for an existing App. In place of step 1 it
then:

1. reads the App's ID and client ID with `gh api apps/SLUG`, so `gh` must be logged in to an
   account that can see the App;
2. names the App's settings page, where you generate a private key (GitHub downloads a `.pem`
   file) and a new client secret. An App holds several of each, so whatever uses it today
   keeps working;
3. asks for the path of the `.pem` file and for the client secret, and stores both in the
   vault, with a random webhook secret (`fabro doctor` wants one; fidfab takes no webhooks).
   Delete the `.pem` file afterwards;
4. points `[server.integrations.github]` in `~/.fabro/settings.toml` at the App, drops the
   token strategy's `GITHUB_TOKEN` secret and restarts the server.

A step that fails leaves Fabro on the token strategy; run it again. By hand, with `KEY.pem` the
downloaded key:

```bash
base64 -w0 < KEY.pem | fabro secret set --type file --value-stdin GITHUB_APP_PRIVATE_KEY
fabro secret set GITHUB_APP_CLIENT_SECRET   # asks for the value; needs a terminal
head -c 32 /dev/urandom | base64 -w0 | fabro secret set --value-stdin GITHUB_APP_WEBHOOK_SECRET
fabro secret rm GITHUB_TOKEN
```

Then replace the table in `~/.fabro/settings.toml` with the App's own values (the App ID is
written as a string) and run `fabro server restart`:

```toml
[server.integrations.github]
strategy = "app"
app_id = "123456"
client_id = "Iv1.abc123def"
slug = "SLUG"
```

Steps 2 to 4 follow as for a new App. What differs:

- **Permissions.** The App needs every permission in [What the runs need](#what-the-runs-need),
  not only the two Fabro leaves out. It may hold more: a run's token gets the workflow's
  permissions alone.
- **Owner.** A private App installs only on the account that owns it, so it has to belong to
  the owner of the target repositories.
- **Sign-in.** No GitHub sign-in is set up: `[server.auth]` keeps its methods, apart from the
  dev-token login, which the step adds when it is missing, as in step 1. The CLI and the web UI
  keep the login they had. GitHub sign-in as in step 1 would also need
  `URL/auth/callback/github` among the App's callback URLs, `URL` being `url` under
  `[server.web]`; this has not been tried.
- **Webhooks.** Leave `[server.integrations.github.webhooks]` unset. With a strategy there
  Fabro points the App's one webhook URL at this server when it starts, away from whatever
  else receives the App's events.
- **The key.** A private key mints tokens for every installation of the App, with all of the
  App's permissions. Runs still get tokens for their own repository and the workflow's
  permissions, but the Fabro host now holds the App's full reach: prefer an App that has
  little more than fidfab needs.
- Everything that uses the App posts as `SLUG[bot]`, and shares the installation's rate limit.

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
