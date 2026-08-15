# Launching the built macOS app

Use Launch Services when testing the GUI or macOS lifecycle behavior.
Running the Mach-O executable directly does not reproduce a Finder launch and can create a terminal frame when attached to a TTY.

## Launch commands

Run these commands from the repository root.

| Purpose | Command |
| --- | --- |
| Launch as if double-clicked in Finder | `open "$PWD/pkg/Applications/Emacs/Emacs.app"` |
| Launch a separate test instance | `open -n "$PWD/pkg/Applications/Emacs/Emacs.app"` |
| Run a non-GUI smoke test | `pkg/Applications/Emacs/Emacs.app/Contents/MacOS/Emacs --batch -Q ...` |

Prefer the exact bundle path for development builds.
Commands such as `open -a Emacs` and `open -b org.gnu.Emacs` ask Launch Services to select an application by name or bundle identifier.
They are ambiguous when several Emacs builds have been registered on the same Mac.

## When to register the app explicitly

Finder or `open` normally registers an application when it launches the bundle.
Explicit registration is useful for a copied or modified test bundle when Launch Services has stale metadata or does not discover the bundle at its new path.

Typical cases are:

- copying a test application under `/private/tmp`;
- changing `CFBundleIdentifier`, `CFBundleName`, `CFBundleVersion`, or `CFBundleExecutable`;
- replacing the executable without changing the bundle modification date;
- seeing Finder launch the exact bundle while a name-based command, Dock action, or Apple Event selects a different build;
- finding that a deleted build path is still registered.

Register only the intended bundle:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -v \
  "$PWD/pkg/Applications/Emacs/Emacs.app"
```

The `-f` option updates the registration even when the modification date is unchanged.
The `-v` option prints registration progress.
This operation updates Launch Services metadata; it does not repair the executable, code signature, or application resources.

Do not use `lsregister -kill` or `lsregister -delete` for a repository-local launch problem.
Those options reset or delete the user's Launch Services database and affect unrelated applications.

## Inspecting the current registration

The following command is read-only and helps identify deleted paths or duplicate Emacs registrations:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -dump 2>/dev/null \
  | rg -n -C 12 'org\.gnu\.Emacs|/Emacs[^/]*\.(app|base)'
```

Inspect the bundle itself independently of Launch Services:

```sh
plutil -extract CFBundleIdentifier raw \
  pkg/Applications/Emacs/Emacs.app/Contents/Info.plist
plutil -extract CFBundleExecutable raw \
  pkg/Applications/Emacs/Emacs.app/Contents/Info.plist
```

For an A/B test, give each copied application a unique `CFBundleIdentifier` and `CFBundleName` before registration.
Otherwise Launch Services may treat both copies as candidates for the same application.

## Recording lifecycle tests

Record the following information when testing Dock reopen, appearance changes, termination, login or logout, and sleep or wake:

- macOS version and build;
- Emacs version and commit;
- absolute application path;
- exact launch command;
- whether `lsregister -f -v` was run;
- bundle identifier used by each test variant;
- visible windows and process state before and after the action.

On 2026-08-15, a Phase 2-D investigation found that Finder could launch the built application while command-driven attempts did not expose a GUI window to Accessibility.
The Launch Services database also contained registrations for deleted Emacs builds and did not show the current repository bundle in the inspected results.
These observations do not prove that registration caused the missing window, but they make the launch path and registration state required inputs for the next reproduction.
