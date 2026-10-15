# Verification — 1.1.1 (build 10)

Verified on 2026-10-15 for direct distribution from GitHub.

- Updated Input Monitoring onboarding to register access in the background and
  handle granted, denied and pending states before opening macOS privacy settings.

- Debug: 40 tests passed, 2 skipped, no failures.
- Release: 35 tests passed, 2 skipped, no failures.
- Two tests require additional Latin keyboard layouts not installed on the test Mac.
- Five state-machine tests intentionally run only in Debug because they require debug hooks.
- Production logging privacy regressions passed.
- Universal arm64/x86_64 build succeeded; Developer ID signature verified with
  Hardened Runtime and a secure timestamp.
- Apple accepted both the app and DMG for notarization; both tickets were stapled
  and validated. Gatekeeper accepted both as `Notarized Developer ID`.
- Mounted the final DMG read-only and verified the included app's signature,
  notarization ticket and version (1.1.1, build 10). The DMG checksum passed.
- No previous private Git history, user settings, log files, credentials or private
  signing keys are included in this source publication.

This is a targeted review, not a guarantee of absence of every possible sensitive value.
The public GitHub account hosting the project is visible. The signed downloads
include the public Developer ID certificate, which identifies the certificate owner.
The private key and notarization credentials remain in the local Keychain.

The maintainer reported that the earlier beta installed and worked in local manual
tests. This release changes permission onboarding and build metadata; the language
correction engine is unchanged. First-launch permission prompts on a clean Mac,
full keyboard and secure-field coverage, Intel runtime testing and installation on
a separate Mac remain outstanding. See TESTING.md.
