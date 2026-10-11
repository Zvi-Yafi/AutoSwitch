# Verification — 1.1.0 (build 9)

Verified on 2026-10-11 for direct distribution from GitHub.

- Debug: 40 tests passed, 2 skipped, no failures.
- Release: 35 tests passed, 2 skipped, no failures.
- Two tests require additional Latin keyboard layouts not installed on the test Mac.
- Five state-machine tests intentionally run only in Debug because they require debug hooks.
- Production logging privacy regressions passed.
- Release tests also passed from a clean source snapshot (35 passed, 2 skipped).
- Universal arm64/x86_64 build succeeded; Developer ID signature verified with
  Hardened Runtime and a secure timestamp.
- Apple accepted both the app and DMG for notarization; both tickets were stapled
  and validated. Gatekeeper accepted both as `Notarized Developer ID`.
- Mounted the final DMG read-only and verified the included app's signature,
  notarization ticket and version (1.1.0, build 9). The DMG checksum passed.
- Source and app payload were scanned for known personal identifiers, home-directory paths,
  private-key markers and common token formats; no matches were found in the clean payload.
- No previous private Git history, user settings, log files, credentials or private
  signing keys are included in this source publication.

This is a targeted review, not a guarantee of absence of every possible sensitive value.
The public GitHub account hosting the project is visible. The signed downloads
include the public Developer ID certificate, which identifies the certificate owner.
The private key and notarization credentials remain in the local Keychain.

The maintainer reported that the earlier beta installed and worked in local manual
tests. This release changes distribution and build metadata, not correction behavior.
Full keyboard, permission and secure-field coverage, Intel runtime testing and
installation on a separate Mac remain outstanding. See TESTING.md.
