# Findings

- Ubuntu 26.04 LTS codename is `resolute`. `ubuntu:26.04` and `ubuntu:resolute` tags exist on
  Docker Hub (multi-arch, including amd64 and arm64).
- The Dockerfile hard-coded the Docker CE apt suite as `noble`, so `UBUNTU_VERSION` was not a
  true override. The suite now comes from `VERSION_CODENAME` in `/etc/os-release`.
- Upstream repositories used by the image and their 26.04 status:
  - Docker CE: `https://download.docker.com/linux/ubuntu/dists/resolute/` exists.
  - NodeSource `setup_22.x`: uses `Suites: nodistro`, so the Ubuntu release does not matter.
  - GitHub CLI: single `stable` suite, distro-independent.
  - pixi, uv, rustup, Vite+, CodeRabbit, Serena (`uv -p 3.13`) are static or self-contained
    installers and do not depend on the Ubuntu release.
- `tests/test-tools.sh` is the only test that pins the release (`VERSION_ID`).
- Fabro's own `default` environment is `buildpack-deps:noble`; that is Fabro's, not ours, and the
  README/AGENTS.md mentions of it are left untouched.
- `docker-ce-cli`, `docker-buildx-plugin` and `docker-compose-plugin` are published for
  `resolute/stable` on amd64.
- Dockerfile `RUN` lines are not subject to Docker's own `${VAR}` substitution, so
  `${VERSION_CODENAME}` sourced from `/etc/os-release` is expanded by bash at build time.
