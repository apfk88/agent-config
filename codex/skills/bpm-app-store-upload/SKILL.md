---
name: bpm-app-store-upload
description: Archive and upload the BPM iOS app to App Store Connect from /Users/kvamme/dev/personal/BPM. Use when asked to ship, archive, upload, submit a new TestFlight/App Store Connect build, or recover from closed BPM App Store version trains.
---

# BPM App Store Upload

Use this for BPM release builds from `/Users/kvamme/dev/personal/BPM`.

## Guardrails

- Start with `git status --short --branch`.
- Leave unrelated dirty files alone.
- `build/` artifacts are ignored; keep archives, export plists, and upload logs there.
- If changing version/build metadata, update every `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` entry in `BPM.xcodeproj/project.pbxproj`.
- On `master`, ask before pushing commits unless the user already gave push consent for this session.
- Do not invent or expose App Store Connect secrets. Prefer the signed-in Xcode account upload path.

## Version Check

Inspect all version fields:

```bash
rg -n "MARKETING_VERSION|CURRENT_PROJECT_VERSION" BPM.xcodeproj/project.pbxproj
```

If App Store Connect rejects with either message, bump the marketing version and build number before retrying:

- `code = 90062`, `CFBundleShortVersionString ... must contain a higher version`
- `code = 90186`, `Invalid Pre-Release Train ... is closed for new build submissions`

For BPM, the source of truth is `BPM.xcodeproj/project.pbxproj`; app, tests, UI tests, and activity extension must stay aligned.

## Upload Current Version

Run the bundled script from the BPM repo root:

```bash
bash /Users/kvamme/dev/personal/agent-config/codex/skills/bpm-app-store-upload/scripts/upload_bpm_appstore.sh
```

The script:

1. Archives `BPM.xcodeproj`, scheme `BPM`, Release, generic iOS.
2. Writes timestamped upload options under `build/`.
3. Exports with `method=app-store-connect`, `destination=upload`, automatic signing, symbols enabled.
4. Uploads through Xcode's signed-in account.

For archive-only verification:

```bash
bash /Users/kvamme/dev/personal/agent-config/codex/skills/bpm-app-store-upload/scripts/upload_bpm_appstore.sh --no-upload
```

## Commit After Metadata Changes

After a successful upload that required a version/build bump:

```bash
git diff --check -- BPM.xcodeproj/project.pbxproj
git commit -m "build: bump version to <version>" -- BPM.xcodeproj/project.pbxproj
```

Report the uploaded version/build and the exact App Store Connect terminal result, especially `Upload succeeded` or the rejection text.
