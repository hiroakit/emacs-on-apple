# Contributing

Changes to this repository go through a Pull Request.

## PR size

**Keep a PR small enough to review.** A large diff takes long to review, and
the reviewer ends up either approving without confidence or leaving it alone.
Defect detection drops once a single review goes past 200-400 lines, per
[SmartBear: Best Practices for Code Review](https://smartbear.com/learn/code-review/best-practices-for-peer-code-review/),
based on a 10-month study of 2,500 reviews and 3.2 million lines at Cisco
([Code Review at Cisco Systems](https://static0.smartbear.co/support/media/resources/cc/book/code-review-cisco-case-study.pdf)).
The limit here is 300 lines.

### Rules

1. **300 changed lines or fewer** (additions + deletions). CI fails above it.
2. **One PR, one purpose.** Do not mix a new patch with a build script
   cleanup, or a documentation update with a configuration change.

### What is counted

| Category | Paths | Effect |
| --- | --- | --- |
| Counted | Everything not listed below (`*.patch`, `build.sh`, `*.plist`, `package-distribution.xml`, `.github/`, ...) | **fails above 300 lines** |
| Not counted | Paths listed in [.github/pr-size-ignore](.github/pr-size-ignore) | ignored |

Only paths whose line count says nothing about review effort are excluded:

- **`docs/`** -- research notes and work instructions; being long is normal
- `LICENSE` -- upstream license text, carried verbatim
- Images and design files
- Xcode / SwiftPM generated files (`*.pbxproj`, `xcuserdata/`, `Package.resolved`)

**Patches and the build script are counted.** They are the substance of this
repository, and their line count is the review effort.

To exclude something else, add a line to
[.github/pr-size-ignore](.github/pr-size-ignore). The syntax is the same as
`.gitignore` (leading `/` anchors to the root, trailing `/` matches a
directory, `*` `**` `?`, `!` negates, `#` comments). The threshold and the
matching logic live in [.github/scripts/pr-size-limit.js](.github/scripts/pr-size-limit.js).

### When a change goes past 300 lines

Split it. Useful seams:

- preparatory refactoring -> the change itself
- adding a patch -> applying it from the build script
- signing and packaging changes -> build procedure changes

When a split is genuinely impossible (rebasing onto a new upstream release,
for example), say so in the PR description and point out where the reviewer
should look closely.

## Checking locally

Confirm the build passes on macOS before opening a PR.

```sh
sh build.sh emacs26
```

When adding or changing a patch, confirm that it applies cleanly and that
`build.sh` actually invokes it.
