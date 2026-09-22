# AutoSwitch for macOS

Typed with the wrong keyboard layout? AutoSwitch can correct the word and switch
the keyboard layout so you can keep writing. For example: `akuo` → `שלום`.
It runs in the menu bar and processes corrections locally using macOS spelling APIs.

## Download

Get the complete app from this repository's [Releases](https://github.com/Zvi-Yafi/AutoSwitch/releases).
**1.1.0 beta 1 is a testing release, ad-hoc signed and not notarized by Apple.**
It includes both Apple Silicon and Intel executables and requires macOS 13 or later.
Intel execution and installation on a separate Mac still need manual testing.
This beta may be blocked by Gatekeeper; it is not advertised as a notarized release.

## Install and try it

1. Quit any older AutoSwitch instance using its menu bar menu.
2. Open the DMG and drag AutoSwitch to Applications.
3. Launch it from Applications and complete permission onboarding: Accessibility and
   Input Monitoring are required for correction across apps.
4. Enable the keyboard layouts you use in macOS settings, then test in TextEdit.
5. Use the AutoSwitch menu bar icon to open settings or disable correction.

This clean release uses the neutral bundle identifier `com.autoswitch.app`.
Older installations used a different identifier, so permissions and preferences
may need to be set again. The beta does not import previous settings automatically.

## Features

- Correct words typed using a different keyboard layout and switch the input source.
- Select target layouts and a preferred target; language availability depends on macOS
  input sources and dictionaries. Best-effort language support is optional.
- Include or exclude apps, ignore words, and configure ambiguous-word handling.
- Skip the next correction: Command–Shift–semicolon by default.
- Undo a recent correction: Command–Z within 2.5 seconds by default.
- English and Hebrew interface.

## Privacy and limitations

No application account, cloud correction service or analytics is used by this code.
Release builds suppress word-level diagnostic logging. Basic local logs may include
app identifiers and operational events; logging can be disabled in settings.
Developer debug builds can log typed text only when Debug logging is selected.

Correction is heuristic: it can miss words or make unwanted changes. Secure-field
recognition depends on macOS Accessibility information and is not a guarantee for
all third-party password fields. Rapid focus changes and compatibility with individual
apps need manual testing. See the [test checklist](docs/TESTING.md).

## Build

Install Xcode and its command-line tools (Swift tools 5.9 or later).

```sh
swift test
RELEASE_MODE=test scripts/package_release.sh
scripts/make_dmg.sh
```

The packaging script creates a universal app with no personal signing identity.
For Developer ID signing and notarization, see [release instructions](docs/RELEASE.md).

## Contributing and license

Report reproducible problems through Issues, including your macOS version, keyboard
layouts and affected application. Never include passwords or private text in reports.
Contributions are welcome. Licensed under [MIT](LICENSE).
