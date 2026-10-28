# Task Plan: Upgrade the sandbox image to Ubuntu 26.04

## Goal

The fidfab Docker sandbox image builds from `ubuntu:26.04` instead of `ubuntu:24.04`, with every
hard-coded 24.04/noble reference (Dockerfile, tests, docs, lint config) updated to match.

## Next Step

Done. All phases complete; see progress.md for verification results.

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
- [x] Update `tests/test-tools.sh` VERSION_ID check
- [x] Update README, Dockerfile comment and `.hadolint.yaml` comment
- **Status:** complete

### Phase 3: Verification

- [x] `tests/validate-workflows.sh`, `scripts/sync-components.sh --check`
- [x] `shellcheck -S warning` on all shell scripts; `node --check tests/acp-smoke.mjs`
- [x] hadolint on the Dockerfile (if available)
- [x] Verify the apt packages the Dockerfile installs exist in the 26.04 archive
- [x] `docker/build.sh && tests/test-image.sh` if a Docker daemon is available (it is not in this sandbox)
- **Status:** complete

### Phase 4: Delivery

- [x] Mark acceptance criteria, update progress.md and findings.md
- **Status:** complete

## Acceptance criteria

| Criterion | Met? |
|-----------|------|
| `docker/Dockerfile` defaults to `ubuntu:26.04` | yes |
| No apt source hard-codes the `noble` suite; the suite follows the base image | yes |
| `tests/test-tools.sh` asserts `VERSION_ID=26.04` | yes |
| README, Dockerfile header and `.hadolint.yaml` no longer say 24.04 | yes |
| Offline checks pass (validate-workflows, sync-components --check, shellcheck, node --check, hadolint) | yes |
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
