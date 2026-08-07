# AGENTS.md

## Repository model

- This repository builds GNU Emacs 30.2 for supported macOS versions. Read
  `README.md` first and use `docs/roadmap.md` as the current work guide.
- `build.sh` downloads the official GNU Emacs tarball and applies the numbered
  patches in the repository root. Make GNU Emacs source or packaging-template
  changes by adding or updating those patches and wiring them into `build.sh`.
- `src/` and `pkg/` are ignored build outputs. Do not make source changes only
  inside them; those changes disappear on the next clean build.
- Preserve unrelated local and untracked work. Do not assume an untracked
  checkout or build artifact is disposable merely because Git ignores it.

## Verification

- Do not infer a user-visible macOS bug solely from a missing AppKit delegate
  method, notification handler, or source-code match. Check AppKit's default
  behavior and reproduce the reported behavior before proposing a patch.
- For lifecycle behavior such as Dock reopen, application termination,
  login/logout, sleep/wake, and appearance changes, prefer an isolated A/B test
  on supported macOS hardware. Record the macOS version, Emacs build, exact user
  action, and observed state.
- When adding or changing a patch, verify that it applies cleanly to a fresh
  official Emacs 30.2 source tree and that `build.sh` invokes it in the intended
  order.
- Run `sh build.sh emacs30` when full validation is warranted. It starts by
  deleting `src/` and `pkg/`, so confirm that no local artifacts there need to
  be preserved before running it. Report explicitly if the full build or
  hardware-dependent verification was not run.

## Change scope

- Follow `CONTRIBUTING.md`: keep a pull request to one purpose and at most 300
  counted changed lines. Patches and `build.sh` count toward that limit.
- Keep detailed research and design rationale in `docs/`; keep this file limited
  to durable instructions for working in the repository.
