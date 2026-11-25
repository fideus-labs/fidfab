# VS Code

Three ways to work with fidfab from VS Code:

**Interactive Claude Code in the sandbox image (Dev Containers).** The repository ships
`.devcontainer/devcontainer.json`, which opens your checkout inside `fidfab:latest` with the
Claude Code and Codex extensions, Serena, and the warm pixi/Cargo caches. Create the
credentials file on the host readable by you alone:

```sh
mkdir -p ~/.config/fidfab && chmod 700 ~/.config/fidfab
touch ~/.config/fidfab/agents.env && chmod 600 ~/.config/fidfab/agents.env
```

then put the agent credentials in `~/.config/fidfab/agents.env`:

```
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat…
CODEX_AUTH_JSON_B64=…
CODERABBIT_API_KEY=cr-…
```

then "Dev Containers: Reopen in Container". Run `claude` or `codex` in the integrated terminal,
diff the resulting worktree, and hand the branch to `fabro run verify --environment fidfab`.
Copy the `.devcontainer/` folder into any target repository to get the same experience there.

**Attach to a running workflow sandbox.** Start the run with `--preserve-sandbox`, find the
container with `docker ps` (named after the run), then "Dev Containers: Attach to Running
Container". You can inspect the agents' edits in `/workspace`, read the planning files, and
run tests while the workflow is paused at a gate. `fabro sandbox ssh <run>` is the terminal
equivalent.

**Fabro's VS Code remote view.** Fabro can open a VS Code tunnel into cloud (Daytona)
sandboxes ([VS Code access](https://docs.fabro.sh/human-tools/vs-code)); for local Docker
sandboxes use the two options above.

Recommended host extensions: `anthropic.claude-code`, `openai.chatgpt` (Codex),
`tamasfe.even-better-toml` for `workflow.toml`, and a Graphviz preview extension for `.fabro` files
(they are DOT).
