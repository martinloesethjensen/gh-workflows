# gh-workflows

Centralised reusable GitHub Actions workflows for distributing unsigned iOS apps via [AltStore Classic](https://altstore.io) and macOS apps as DMGs.

---

## Workflows

### `build-ipa.yml` — Build & Release IPA

Builds an **unsigned** IPA from an Xcode project, creates a GitHub Release on the calling repo, then notifies `altstore-source` so its `apps.json` is kept up to date.

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `scheme_name` | string | yes | — | Xcode scheme to archive |
| `bundle_id` | string | yes | — | App bundle identifier |
| `app_name` | string | yes | — | Used as the IPA filename prefix |
| `min_os_version` | string | no | `15.0` | `IPHONEOS_DEPLOYMENT_TARGET` |

| Secret | Required | Description |
|---|---|---|
| `ALTSTORE_SOURCE_PAT` | yes | Fine-grained PAT — Contents read+write on `martinloesethjensen/altstore-source` |

**What it does:**

1. Archives the app with `xcodebuild` — no signing (`CODE_SIGNING_ALLOWED=NO`).
2. Wraps the `.app` bundle in a `Payload/` folder and zips it as `{app_name}-{tag}.ipa`.
3. Creates a GitHub Release on the calling repo and attaches the IPA.
4. Fires a `repository_dispatch` (`app_release`) to `martinloesethjensen/altstore-source` with the bundle ID, version, download URL, byte size, and release notes.

---

### `build-dmg.yml` — Build & Release macOS DMG

Builds an **unsigned** macOS DMG from an Xcode project and uploads it to the GitHub Release created on the calling repo. Designed to run alongside `build-ipa.yml` for apps that have both iOS and macOS targets.

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `scheme_name` | string | yes | — | Xcode scheme to archive (must have a macOS target) |
| `app_name` | string | yes | — | Used as the DMG filename prefix |
| `min_macos_version` | string | no | `13.0` | `MACOSX_DEPLOYMENT_TARGET` |

No secrets required — uses the default `GITHUB_TOKEN` for the release upload.

**What it does:**

1. Archives the app with `xcodebuild` for `generic/platform=macOS` — no signing.
2. Stages the `.app` bundle with an `/Applications` symlink (drag-and-drop install).
3. Creates a compressed DMG with `hdiutil` and uploads it to the GitHub Release.

> **Note:** The DMG is unsigned. Users must right-click → Open on first launch to bypass Gatekeeper, or you can notarise separately.

---

### `update-altstore-source.yml` — Update AltStore Source JSON

Triggered by the `repository_dispatch` event from `build-ipa.yml`. Prepends a new version entry into the matching app's `versions` array in `apps.json` and pushes the change to `main`.

This workflow has no inputs — it reads everything from `github.event.client_payload`.

| Secret | Required | Description |
|---|---|---|
| `ALTSTORE_SOURCE_PAT` | yes | Same PAT as above — used to checkout and push to `altstore-source` |

---

## Usage

### App repo (iOS only) — copy to `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  release:
    uses: martinloesethjensen/gh-workflows/.github/workflows/build-ipa.yml@main
    with:
      scheme_name: MyApp
      bundle_id:   com.example.myapp
      app_name:    MyApp
    secrets:
      ALTSTORE_SOURCE_PAT: ${{ secrets.ALTSTORE_SOURCE_PAT }}
```

### App repo (iOS + macOS) — copy to `.github/workflows/release.yml`

Both jobs run in parallel on the same tag. The IPA job creates the release; the DMG job uploads to it.

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  ios:
    uses: martinloesethjensen/gh-workflows/.github/workflows/build-ipa.yml@main
    with:
      scheme_name: MyApp
      bundle_id:   com.example.myapp
      app_name:    MyApp
    secrets:
      ALTSTORE_SOURCE_PAT: ${{ secrets.ALTSTORE_SOURCE_PAT }}

  macos:
    uses: martinloesethjensen/gh-workflows/.github/workflows/build-dmg.yml@main
    with:
      scheme_name: MyApp   # must have a macOS target
      app_name:    MyApp
```

### `altstore-source` repo — copy this file to `.github/workflows/update-source.yml`

```yaml
name: Update AltStore Source

on:
  repository_dispatch:
    types:
      - app_release

permissions:
  contents: write

jobs:
  update:
    uses: martinloesethjensen/gh-workflows/.github/workflows/update-altstore-source.yml@main
    secrets:
      ALTSTORE_SOURCE_PAT: ${{ secrets.ALTSTORE_SOURCE_PAT }}
```

---

## One-time setup checklist

- [ ] **Create a fine-grained PAT** at GitHub → Settings → Developer settings → Fine-grained personal access tokens.
  - Repository access: `martinloesethjensen/altstore-source` only.
  - Permissions → Contents: **Read and write**.
  - Name it anything (e.g. `ALTSTORE_SOURCE_PAT`).

- [ ] **Add the PAT as a secret** named `ALTSTORE_SOURCE_PAT` in every app repo that will call `build-ipa.yml` (Settings → Secrets and variables → Actions → New repository secret).

- [ ] **Add the PAT as a secret** named `ALTSTORE_SOURCE_PAT` in `martinloesethjensen/altstore-source` as well (needed by `update-altstore-source.yml` to push).

- [ ] **Add an app entry** to `apps.json` in `altstore-source` for each new app **before** the first release. The `versions` array must exist (can be empty `[]`). Example skeleton:
  ```json
  {
    "name": "My App",
    "bundleIdentifier": "com.example.myapp",
    "developerName": "Your Name",
    "localizedDescription": "Short description.",
    "iconURL": "https://example.com/icon.png",
    "tintColor": "4A90E2",
    "versions": []
  }
  ```

- [ ] **Copy the caller workflows** from `example-callers/` in this repo into the right repos:
  - `app-repo-release.yml` → iOS-only app repo's `.github/workflows/release.yml`
  - `app-repo-release-with-dmg.yml` → iOS + macOS app repo's `.github/workflows/release.yml`
  - `altstore-source-update-source.yml` → `altstore-source`'s `.github/workflows/update-source.yml`

- [ ] **Tag a release** in an app repo (`git tag v1.0.0 && git push origin v1.0.0`) and verify the full pipeline runs end-to-end.
