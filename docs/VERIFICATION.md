# Verification — 1.1.0 beta 1

- Debug: 40 tests passed, 2 skipped, no failures.
- Release: 35 tests passed, 2 skipped, no failures.
- Two tests require additional Latin keyboard layouts not installed on the test Mac.
- Five state-machine tests intentionally run only in Debug because they require debug hooks.
- Production logging privacy regressions passed.
- Universal arm64/x86_64 build succeeded; code signature verified as ad-hoc with no Team ID.
- Source and app payload were scanned for known personal identifiers, home-directory paths,
  private-key markers and common token formats; no matches were found in the clean payload.
- No previous Git history, user settings, log files, credentials or signing certificates
  are included in this source publication.

This is a targeted review, not a guarantee of absence of every possible sensitive value.
The public GitHub account hosting the project is visible. No personal signing identity
is embedded in this beta. Future Developer ID signatures identify the certificate owner.

Manual keyboard, permission, secure-field, Intel runtime and second-Mac installation
checks remain for beta testing. Apple notarization is not complete. See TESTING.md.
