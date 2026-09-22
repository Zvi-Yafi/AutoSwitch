# Release workflow

Source and downloadable releases belong in this repository. No HTML site is required.

## Local beta

```sh
swift test
swift test -c release
RELEASE_MODE=test scripts/package_release.sh
scripts/make_dmg.sh
```

The full app contains arm64 and x86_64 executables. Test mode always uses ad-hoc
signing, without embedding a personal developer certificate. Label these downloads
as testing prereleases and disclose that they are not notarized.

## Production distribution

Install your own Developer ID Application certificate with its private key in Keychain.
Create a `notarytool` profile named `AutoSwitch-Notary`, using your own Apple account.
Do not commit credentials, certificate private keys, or personal account configuration.
Apple Development certificates are not the distribution certificate.

Update the version/build number in Info.plist and commit the reviewed source, then run:

```sh
scripts/release.sh
codesign --verify --deep --strict build/AutoSwitch.app
xcrun stapler validate build/AutoSwitch.app
xcrun stapler validate build/AutoSwitch.dmg
spctl --assess --type execute --verbose build/AutoSwitch.app
shasum -a 256 build/AutoSwitch.dmg
```

`CODESIGN_IDENTITY` selects a signing identity; `NOTARY_PROFILE` selects the Keychain
profile. Signed distribution certificates identify their owner; no private key is
included in the app. Upload the DMG, checksum and release notes against the matching tag.

Complete the manual testing checklist before declaring a stable release.
See [Apple's Developer ID guide](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
