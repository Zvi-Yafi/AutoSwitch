# Testing 1.1.2

For the targeted 1.1.2 results and remaining coverage, see VERIFICATION.md.
The isolated regression scripts are `scripts/run_geresh_policy_regression.sh`
and `scripts/run_permissions_onboarding_regression.py`.

The maintainer tested the preceding beta locally and reported that installation and
application behavior worked. The distribution changes in 1.1.0 add Developer ID
signing and notarization. The checklist below remains useful for wider testing;
it does not mean every scenario has been verified.

## Clean install

- Quit the previous app before installing the new one.
- Install from the DMG into Applications, then launch from there.
- Confirm the menu bar item, onboarding, Accessibility and Input Monitoring permissions.
- The new neutral bundle ID has separate preferences/permission grants.
- Revoke and restore each permission and verify status/recovery after relaunch.
- On a Mac where AutoSwitch has not requested Input Monitoring, confirm onboarding
  triggers registration and remains responsive while the system prompt is open.
- Try allowing and denying the system prompt; confirm the permission button updates
  when granted and opens Input Monitoring settings when denied or still pending.

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
  `spctl --assess --type execute --verbose`. Version 1.1.0 uses Developer ID signing
  and Apple notarization; the earlier beta used ad-hoc signing.
