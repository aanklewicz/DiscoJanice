# App Store release workflow

This repo ships DiscoJanice to the App Store with a **manually triggered** GitHub
Actions workflow (`.github/workflows/release.yml`) driven by Fastlane.

When you run it, it:

1. Spins up a macOS runner and selects the latest stable Xcode.
2. Imports your Apple **distribution certificate** into a temporary keychain.
3. Archives the `DiscoJanice` scheme (Release) and exports an App Store `.ipa`,
   signing via Xcode automatic signing + cloud-managed profiles.
4. Uploads the build to App Store Connect and **submits it for review**.

The marketing version comes from `MARKETING_VERSION` in the project; the build
number is whatever is committed (`CURRENT_PROJECT_VERSION`). Bump the build number
before each run — App Store Connect rejects a duplicate build number.

## One-time setup

### 1. Add the required GitHub secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add
each of these. (I can't add these for you — they're credentials.)

| Secret | What it is | How to get it |
| --- | --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | API key ID | App Store Connect → Users and Access → Integrations → App Store Connect API → create a key (**App Manager** role). Shown next to the key. |
| `APP_STORE_CONNECT_ISSUER_ID` | API issuer ID | Same page, shown above the key list. |
| `APP_STORE_CONNECT_KEY_P8` | The `.p8` key contents, base64-encoded | Download the `.p8` once at creation, then: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `BUILD_CERTIFICATE_BASE64` | Apple **Distribution** cert + private key as a base64 `.p12` | In Keychain Access, select the "Apple Distribution" cert **and** its private key → Export as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password you set when exporting the `.p12` | You choose it during export |
| `KEYCHAIN_PASSWORD` | Any random string | Used only for the throwaway CI keychain |
| `APPLE_TEAM_ID` | 10-character Developer Team ID | developer.apple.com → Membership details |

### 2. Prepare the App Store listing

Because the workflow manages **no** metadata or screenshots (you do that by hand),
before running it make sure App Store Connect has a version matching
`MARKETING_VERSION` (e.g. `2.2`) in the **Prepare for Submission** state with release
notes filled in. The workflow attaches the build to that version and submits it.

## Running a release

1. Bump `CURRENT_PROJECT_VERSION` (build number) if you haven't already.
2. Make sure the App Store version listing is prepared (step 2 above).
3. GitHub → **Actions → Release to App Store → Run workflow**.

## Notes & tuning

- **Just upload, don't submit:** set `submit_for_review: false` in `fastlane/Fastfile`.
- **Export compliance:** `Info.plist` already sets `ITSAppUsesNonExemptEncryption = false`,
  so the submission won't stall on the encryption question. If the app ever adds
  non-exempt encryption, update that key.
- **IDFA:** the lane declares the app does not use the advertising identifier
  (`add_id_info_uses_idfa: false`). Change this if that stops being true.
- **Signing:** uses automatic/cloud signing. If you'd rather pin an explicit
  provisioning profile, switch `build_app` to manual signing and add the profile as a
  secret.
- **Runner:** pinned to `macos-15`. Bump to `macos-26` (or `macos-latest`) when you
  move to an Xcode 26+ toolchain.
