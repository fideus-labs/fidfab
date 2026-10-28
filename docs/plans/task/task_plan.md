# Task Plan: Upgrade the sandbox image to Ubuntu 26.04

## Goal

The fidfab Docker sandbox image builds from `ubuntu:26.04` instead of `ubuntu:24.04`, with every
hard-coded 24.04/noble reference (Dockerfile, tests, docs, lint config) updated to match.

## Next Step

Implementation done. Unverified here: `tests/validate-workflows.sh`, hadolint and the image build/test (see progress.md). CI runs validate-workflows and hadolint on every push; the image job runs on `workflow_dispatch` with `build_image=true`.

## Current Phase

Phase 4

## Phases

### Phase 1: Discovery

- [x] Find every reference to 24.04 / noble in the repository
- [x] Confirm upstream apt repositories and the base image support 26.04 (resolute)
- [x] Record findings in findings.md
- **Status:** complete

### Phase 2: Implementation

- [x] Bump `UBUNTU_VERSION` default in `docker/Dockerfile`
- [x] Derive the Docker CE apt suite from `/etc/os-release` instead of hard-coding `noble`
- [x] Update `tests/test-tools.sh` VERSION_ID check (expects `${UBUNTU_VERSION:-26.04}`; `tests/test-image.sh` passes `UBUNTU_VERSION` through)
- [x] Update README, Dockerfile comment and `.hadolint.yaml` comment
- **Status:** complete

### Phase 3: Verification

- [x] `scripts/sync-components.sh --check`
- [ ] `tests/validate-workflows.sh` (skipped: `fabro` is not installed in the sandbox; no `.fabro` or `workflow.toml` changed)
- [x] `shellcheck -S warning` on all shell scripts; `node --check tests/acp-smoke.mjs`
- [ ] hadolint on the Dockerfile (skipped: not installed; the edited RUN body passed `shellcheck` and `bash -n`)
- [x] Verify the apt packages the Dockerfile installs exist in the 26.04 archive
- [ ] `docker/build.sh && tests/test-image.sh` (skipped: no Docker daemon in this sandbox)
- **Status:** complete with skipped checks (see progress.md)

### Phase 4: Delivery

- [x] Mark acceptance criteria, update progress.md and findings.md
- **Status:** complete

## Acceptance criteria

| Criterion | Met? |
|-----------|------|
| `docker/Dockerfile` defaults to `ubuntu:26.04` | yes |
| No apt source hard-codes the `noble` suite; the suite follows the base image | yes |
| `tests/test-tools.sh` asserts `VERSION_ID=26.04` by default and follows a `UBUNTU_VERSION` override | yes |
| README, Dockerfile header and `.hadolint.yaml` no longer say 24.04 | yes |
| Offline checks pass: sync-components --check, shellcheck, node --check | yes |
| `tests/validate-workflows.sh` and hadolint | not verified: `fabro` and hadolint are not installed in the sandbox (no `.fabro`/`workflow.toml` changed) |
| Image builds and `tests/test-image.sh` passes | not verifiable here: no Docker daemon in the sandbox. Packages, base image tag and apt suites were verified against the upstream indexes instead; see findings.md |

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Derive the Docker CE apt suite from `VERSION_CODENAME` | `UBUNTU_VERSION` is a build arg; a hard-coded codename silently breaks any override. |
| Keep `NODE_MAJOR=22` and other pins | The task is the base image only; NodeSource uses a distro-independent `nodistro` suite. |

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| No Docker daemon in the sandbox | 1 | Verified packages, tags and apt suites via upstream indexes; full build left to CI (`workflow_dispatch` with `build_image`). |
