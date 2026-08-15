# emacs-on-apple

[![Build Status](https://app.bitrise.io/app/6ab4eec93dedce2f/status.svg?token=fACOUtKMmLpTGHZClpKN-Q)](https://app.bitrise.io/app/6ab4eec93dedce2f)

Emacs for Apple devices.

# Usage

```sh
# Required autoconf, automake, pkg-config, Xcode Command Line Tools
# Experimental: Emacs 30.2. See docs/roadmap.md Phase 0 for status.
sh build.sh emacs30

# Launch the built app through Launch Services, as Finder does.
open "$PWD/pkg/Applications/Emacs/Emacs.app"
```

The verified Emacs source archive is cached in `.cache/downloads/` and reused
across builds. The `clean` command removes `src/` and `pkg/`, but keeps this
download cache. Remove `.cache/` when you need to force a fresh download.
The source version and SHA-256 are pinned in `emacs-source.lock`; update that
file to select a different Emacs source. Bitrise derives its download-cache
key from the lockfile automatically.

# Objective

Immediate

- Get buildable on Bitrise CI
- Get launchable on clean installed macOS
- Get the Apple Notarization
- **Keep Emacs current with modern macOS app lifecycle events**

Finally

- Support Xcode
- Support iPadOS
- Support Sandbox style macOS App
- Distribute on Mac App Store

Porting to Swift was investigated and **dropped**. Every AppKit lifecycle
API is reachable from Objective-C, so the port would carry significant
cost with no additional capability -- and would forfeit the ability to
contribute changes back upstream. See [docs/swift-migration.md](./docs/swift-migration.md).

# Documentation

Start here if you are picking up this work:

- [docs/roadmap.md](./docs/roadmap.md) -- **work instructions, start at Phase 0**
- [docs/macos-lifecycle.md](./docs/macos-lifecycle.md) -- what Emacs 30.2 implements today and what it lacks
- [docs/macos-app-launching.md](./docs/macos-app-launching.md) -- launch commands and Launch Services troubleshooting
- [docs/swift-migration.md](./docs/swift-migration.md) -- background research on why Swift was dropped

# Dependency

- [GNU Emacs](https://savannah.gnu.org/git/?group=emacs)
- [An enhanced inline patch: takaxp/ns-inline-patch](https://github.com/takaxp/ns-inline-patch)

# Related Works

- [A Mitsuharu Yamamoto Emacs: emacs-mac](https://bitbucket.org/mituharu/emacs-mac)
- [Emacs Plus](https://github.com/d12frosted/homebrew-emacs-plus)
- [Emacs mac port formulae for the Homebrew package manager](https://github.com/railwaycat/homebrew-emacsmacport)
- [GNU Emacs For Mac OS X](https://emacsformacosx.com)
- [A Vincent Goulet Emacs: emacs-modified-macos](https://gitlab.com/vigou3/emacs-modified-macos/)

# Supporting

- macOS Sequoia
- Emacs v30.2

# Contributing

Pull Request are always welcome.  
Shall we enjoy social coding!

Keep a PR reviewable: changes are limited to 300 lines and CI enforces it.
See [CONTRIBUTING.md](./CONTRIBUTING.md).

# License

Licensed under [the GPLv3 license](./LICENSE).
