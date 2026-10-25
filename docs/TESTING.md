# Testing 1.1.4

See VERIFICATION.md for the tested snapshot, observed results and limitations.
Focused regressions are `scripts/run_monitor_startup_regression.py`,
`scripts/run_permissions_onboarding_regression.py` and
`scripts/run_geresh_policy_regression.sh`.

## Clean install and permission transitions

- Quit the previous app, install from the DMG into Applications and launch it.
- Confirm the menu bar item and the single Accessibility permission guide.
- Grant Accessibility while the guide is open. Without clicking Start Using or
  restarting, type the hello test below in TextEdit and confirm correction.
- Repeat with the guide closed before granting permission. Confirm correction
  starts after the grant without reopening the guide.
- Complete the guide and confirm the settings window contains its controls.
- Disable correction and verify it stays stopped; enable it and verify recovery.
- Revoke and regrant Accessibility while the app is running and verify recovery.
- Inspect operational logs: repeated settings changes and startup requests must
  not create duplicate active event taps. Input Monitoring is not a second gate.
- Repeat a browser-download installation on a separate Mac or clean VM. A local
  permission/preferences reset is useful but is not equivalent to that test.

## Typing and overrides

- In TextEdit, with English layout active, type `akuo` plus a space: check `שלום`.
- With Hebrew layout active, type `יקךךם` plus a space: check `hello`.
- Test punctuation, Enter, fast typing and long text.
- Test ambiguous words and abbreviations with both ambiguity settings; confirm wanted
  English abbreviations and valid Hebrew words are not incorrectly changed.
- Test undo within/after the configured time window and skip-next shortcut.
- Test ignored words, app allow/block lists, toggling correction, and settings import/export.
- Repeat in the apps you actually use, including browsers and messaging clients.

## Sensitive contexts and focus

- Use only dummy text in password-field tests; confirm no corrections are inserted.
- Test password managers and custom browser password fields.
- Change windows, apps, text fields and caret position while a correction is pending.
- Check that a correction never deletes or inserts text in a different field.
- Accessibility lookup currently treats an inspection failure as non-secure; injection
  does not revalidate focus within every posted event. These are known review items,
  not established guarantees. Disable correction in apps where behavior is uncertain.

## Release checks

- Apple Silicon: run tests and verify the packaged app launches and types correctly.
- Intel: test execution on an actual Intel Mac; compilation alone is insufficient.
- Check installation from a browser download on a different Mac.
- Check logs contain no typed text in this production build.
- Verify the downloaded app with `codesign --verify --deep --strict` and
  `spctl --assess --type execute --verbose`. Production releases use Developer ID signing
  and Apple notarization; the earlier beta used ad-hoc signing.
