# Testing 1.1.0 beta 1

## Clean install

- Quit the previous app before installing the new one.
- Install from the DMG into Applications, then launch from there.
- Confirm the menu bar item, onboarding, Accessibility and Input Monitoring permissions.
- The new neutral bundle ID has separate preferences/permission grants.
- Revoke and restore each permission and verify status/recovery after relaunch.

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
- The beta uses ad-hoc signing and is not notarized. Production distribution requires
  a Developer ID Application certificate and successful Apple notarization.
