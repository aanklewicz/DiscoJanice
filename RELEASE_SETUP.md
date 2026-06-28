# App Store release workflow

This repo ships DiscoJanice to the App Store with a **manually triggered** GitHub
Actions workflow (`.github/workflows/release.yml`) driven by Fastlane.

When you run it, it:

1. Spins up a macOS runner and selects the latest stable Xcode.
2. Imports your Apple **distribution certificate** into a temporary keychain.
3. Archives the `DiscoJanice` scheme (Release) and exports an App Store `.ipa`,
   signing manually with your distribution certificate and an App Store profile it
   downloads via the API key.
4. Uploads the build to App Store Connect. **It does not submit for review** — you do
   that by hand (see "After the workflow runs" below).

The marketing version comes from `MARKETING_VERSION` in the project; the build
number is whatever is committed (`CURRENT_PROJECT_VERSION`). **Bump the build number
before each run** — App Store Connect rejects a duplicate build number.

> **Heads-up:** a `workflow_dispatch` workflow only appears in the Actions UI (and is
> only runnable with `gh workflow run`) once the workflow file exists on the repo's
> **default branch**. These files are currently on `version-2.2`, so merge them into
> `main` first. After that you can dispatch it against any branch with `--ref`.

---

## 0. Prerequisites (one time)

Install and authenticate the GitHub CLI, and point it at this repo so you can omit
`-R` on every command:

```bash
brew install gh                       # if you don't already have it
gh auth login                         # choose GitHub.com → HTTPS → login in browser
cd ~/path/to/DiscoJanice              # work from inside the repo, or…
gh repo set-default aanklewicz/DiscoJanice
```

Confirm you're talking to the right repo:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner   # -> aanklewicz/DiscoJanice
```

Everything below assumes macOS (for `base64`/`security`/Keychain) and that you run the
`gh` commands from inside the repo (or with `-R aanklewicz/DiscoJanice`).

---

## 1. Gather the credentials

### 1a. App Store Connect API key (`.p8`)

1. App Store Connect → **Users and Access → Integrations → App Store Connect API**.
2. Click **+** to generate a key. Give it the **App Manager** role (minimum needed to
   upload a build and submit for review).
3. Note two values on that page:
   - **Key ID** — shown in the key row (e.g. `2X9R4HXF34`).
   - **Issuer ID** — shown above the table (a UUID, e.g. `57246542-96fe-…`).
4. **Download** the `.p8` (`AuthKey_<KEYID>.p8`). Apple only lets you download it once —
   keep it somewhere safe.

### 1b. Apple Distribution certificate (`.p12`)

This is the certificate that authorizes **App Store** uploads. It is **not** the same as
the certs you may already have in Keychain Access:

- **Apple Development: …** — only for building/running on devices. Not for the App Store.
- **Developer ID Application / Installer: …** — for distributing Mac apps *outside* the
  App Store (direct download + notarization). Not for the App Store.

If **My Certificates** has no **Apple Distribution: …** row, create one first (takes a
few seconds and doesn't affect your existing certs):

1. Xcode → **Settings** (⌘,) → **Accounts**.
2. Select your Apple ID, select your team, then **Manage Certificates…**.
3. Click **+** (bottom-left) → **Apple Distribution**. The certificate and its private
   key are added to your login keychain.

Then export it with the private key:

1. Open **Keychain Access** → **My Certificates**.
2. Find **Apple Distribution: Adam Anklewicz (TEAMID)**. Expand the disclosure
   triangle so both the certificate **and** its private key are selected.
3. Right-click → **Export 2 items…** → save as `distribution.p12`.
4. Set an export password — this becomes the `P12_PASSWORD` secret.

Confirm the identity is present and grab its Team ID at the same time:

```bash
# Lists code-signing identities; the Team ID is the 10-char code in parentheses,
# e.g. "Apple Distribution: Jane Dev (ABCDE12345)"
security find-identity -p codesigning -v

# Or read it straight off the cert's Organizational Unit (OU):
security find-certificate -c "Apple Distribution" -p \
  | openssl x509 -noout -subject
```

### 1c. Team ID

The 10-character Developer **Team ID** (from the command above, or
developer.apple.com → **Membership details**).

---

## 2. Add the GitHub secrets

These are credentials, so add them yourself. Both a CLI and a UI path are below.

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Key ID from step 1a |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from step 1a |
| `APP_STORE_CONNECT_KEY_P8` | Base64 of the `.p8` file from step 1a |
| `BUILD_CERTIFICATE_BASE64` | Base64 of `distribution.p12` from step 1b |
| `P12_PASSWORD` | The `.p12` export password from step 1b |
| `KEYCHAIN_PASSWORD` | Any random string (throwaway CI keychain) |
| `APPLE_TEAM_ID` | 10-char Team ID from step 1c |

### Option A — `gh` CLI (recommended)

Run these from the repo directory, substituting your real values. The two
file-backed secrets are piped through `base64`; `gh secret set` reads the value from
stdin when `--body` is omitted:

```bash
# Plain string values
gh secret set APP_STORE_CONNECT_KEY_ID    --body "2X9R4HXF34"
gh secret set APP_STORE_CONNECT_ISSUER_ID --body "57246542-96fe-1a63-e053-0824d011072a"
gh secret set APPLE_TEAM_ID               --body "ABCDE12345"
gh secret set P12_PASSWORD                --body "your-p12-export-password"

# Random keychain password (generated on the spot)
gh secret set KEYCHAIN_PASSWORD           --body "$(openssl rand -base64 24)"

# File-backed values, base64-encoded into the secret
base64 -i AuthKey_2X9R4HXF34.p8 | gh secret set APP_STORE_CONNECT_KEY_P8
base64 -i distribution.p12      | gh secret set BUILD_CERTIFICATE_BASE64
```

Verify all seven are present:

```bash
gh secret list
```

You should see exactly: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
`APP_STORE_CONNECT_KEY_P8`, `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`,
`KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`.

### Option B — Web UI

**Settings → Secrets and variables → Actions → New repository secret**, and add each
row from the table. For the two base64 secrets, generate the value first and copy it to
the clipboard:

```bash
base64 -i AuthKey_2X9R4HXF34.p8 | pbcopy   # then paste into APP_STORE_CONNECT_KEY_P8
base64 -i distribution.p12      | pbcopy   # then paste into BUILD_CERTIFICATE_BASE64
```

---

## 3. Prepare the App Store listing

The workflow manages **no** metadata or screenshots — you do that by hand. Before (or
after) running it, create a version matching `MARKETING_VERSION` (e.g. `2.2`) in App
Store Connect. You'll fill in the **What's New** release notes there as part of the
manual submit step below; Apple requires them, which is why the workflow does not submit.

---

## 4. Run a release

1. Bump `CURRENT_PROJECT_VERSION` (build number) if you haven't already, and push.
2. Trigger the workflow:

```bash
# Dispatch against main (default branch)
gh workflow run release.yml

# …or dispatch the workflow file as it exists on a specific branch
gh workflow run release.yml --ref version-2.2
```

UI equivalent: **Actions → Release to App Store → Run workflow**.

---

## After the workflow runs (manual submit)

The workflow uploads the build but intentionally does **not** submit it. Once the run
succeeds:

1. Wait for the build to finish **processing** in App Store Connect (a few minutes;
   you'll get an email, or watch **TestFlight / Builds**).
2. Open the **App Store** tab → your `2.2` version.
3. Attach the processed build under **Build**.
4. Fill in **What's New in This Version** (release notes) and anything else.
5. Click **Add for Review** → **Submit**.

### Watch it run

```bash
gh run list --workflow=release.yml             # find the run
gh run watch                                   # live status of the latest run
gh run view --log                              # full logs of the latest run
gh run view <run-id> --log-failed              # just the failed step's logs
```

If a run fails, the workflow also uploads gym logs and `fastlane/report.xml` as a
`fastlane-logs` artifact:

```bash
gh run download <run-id> -n fastlane-logs
```

---

## 5. Notes & tuning

- **Auto-submit instead of manual:** the lane uploads only (`submit_for_review: false`).
  To submit automatically you'd set it to `true` *and* supply the "What's New" notes
  (e.g. add `fastlane/metadata/<locale>/release_notes.txt` and drop `skip_metadata`),
  since Apple requires release notes to submit.
- **Export compliance:** `Info.plist` already sets `ITSAppUsesNonExemptEncryption = false`,
  so review won't stall on the encryption question. Update that key if the app ever adds
  non-exempt encryption.
- **Signing:** manual distribution signing — `get_provisioning_profile` downloads an App
  Store profile via the API key, and `build_app` signs with the `Apple Distribution`
  certificate imported from `BUILD_CERTIFICATE_BASE64`. The App ID needs its iCloud
  key-value storage capability enabled so the profile matches the app's entitlement.
- **Runner:** pinned to `macos-15` (Xcode 16.x). Bump to `macos-26` / `macos-latest`
  when you move to an Xcode 26+ toolchain.
- **Rotating a secret later:** re-run the relevant `gh secret set …` command; it
  overwrites in place.
