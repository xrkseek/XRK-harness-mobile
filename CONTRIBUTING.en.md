# Contributing

[中文](CONTRIBUTING.md) · [Project overview](README.en.md)

## Pull requests welcome

This repository **accepts external pull requests** (code, docs, tests, and plugin samples).

- For feature ideas or bugs, [open an issue](https://github.com/xrkseek/XRK-harness-mobile/issues/new/choose) with the use case and expected behavior, or open a PR directly.
- For larger changes to protocols, data formats, permissions, or phone-control safety boundaries, please open an issue first so we can align on the approach.
- Security issues: follow [SECURITY.en.md](SECURITY.en.md) for private reporting — do not post exploit details in public issues or PRs.

## License and copyright

- First-party code is under [AGPL-3.0](LICENSE) by default. See directory notices for `sdk/` and `examples/` (MIT).
- Product name: **XRK Harness** (application id `com.xrkseek.harness`). First / current App release: **0.7.16**.
- Third-party code and bundled components: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). UI icons and fonts are listed under the Notices “Assets” section (Phosphor, Material, JetBrains Mono, etc.).
- **Do not treat DeepSeek / predecessor-brand official character art as this product’s assets or copyright claims.** Optional desktop-pet theme packs (e.g. `deepy-whale`) are independent fan themes — see each pack’s README; they are unrelated to product branding and are not an upstream official art license.
- When adding or adapting third-party material: record the project, version or commit, source files, and license; keep required attribution and modification notices; check compatibility with the destination directory’s license.

## Report an issue

Use the repository’s bug or feature template. Include the app version, Android version, host connection type, and minimal repeatable steps. Add a screenshot or short recording for UI issues after redacting private information.

## Set up development

Follow [README.en.md](README.en.md) for the toolchain and runtime. Ordinary app development does not require the maintainer’s signing key, beta-channel token, or production credentials.

- Flutter/Dart: use the repository’s Flutter version and the app’s Dart SDK requirement.
- Android: JDK 17; match the runtime ABI to the APK flavor.
- Plugin SDK: Node.js 22.19 or later. The SDK lives in `sdk/plugin-kit/` and is not published to npm.

## Keep changes focused

One PR for one independently reviewable problem. Explain the old behavior, its trigger, and the new behavior. Keep unrelated renames, formatting, and directory moves out of the change.

- Maintain interface text in the existing Chinese and English structure. Prefer existing components and icons.
- Add tests for behavior changes. For text or layout-only changes, checks or screenshots are enough.
- When changing a client, bridge, or plugin protocol, check compatibility and callers on the other side.
- Edit generator inputs, then regenerate outputs.

## Common checks

Run from the repository root. Pick checks relevant to your change and record commands and results in the PR. If a device or dependency is missing, say what was not run and why.

If CI is configured, treat Actions as the source of truth for automated checks. CI usually has no devices or real accounts — verify those separately.

**Flutter app:**

```bash
(cd app && flutter pub get && flutter analyze && flutter test)
```

**UI work on a phone (hot reload):** `tooling/dev-run.sh` installs the debug build over the release build already on the phone, then attaches Flutter so pressing `r` applies a change within seconds. It uses `adb install -r` and `flutter attach` instead of `flutter run` (a failed `flutter run` install uninstalls the app first and erases data). Animations stutter in debug — use it for layout; judge smoothness on a release build. Needs `app/android/key.properties` with the same key as the build on the phone.

**Dart communication packages:**

```bash
(cd packages/xrk_client && dart pub get && dart analyze && dart test)
(cd packages/xrk_remote && dart pub get && dart analyze && dart test)
```

**Plugin SDK:**

```bash
(cd sdk/plugin-kit && npm install && npm test)
```

The SDK type check needs its TypeScript development dependency; that test is skipped when TypeScript is missing — treat a skip as a skip, not a pass. See [SDK maintenance](sdk/plugin-kit/README.en.md).

**Interface text:** edit ARB files in `app/lib/l10n/parts/`, then:

```bash
python3 app/tool/l10n_merge.py
python3 app/tool/l10n_merge.py --check
```

**User guide:** edit `docs/guide/`, then:

```bash
python3 app/tool/guide_sync.py
python3 app/tool/guide_sync.py --check
```

**Plugin teaching skill:** edit `sdk/plugin-kit/skill/` or its inputs, then:

```bash
node sdk/plugin-kit/scripts/sync-skill.mjs
node sdk/plugin-kit/scripts/sync-skill.mjs --check
```

For APK validation, use the README build entry. Changes to Android processes, PRoot, direct launch, phone control, or update install should state ABI, Android version, launch mode, and device — desktop results do not replace a real phone.

`services/` and `infra/` online checks, deploy, and release scripts are not ordinary contribution checks. When changing companion services, test only your own local environment; do not use production credentials.

## Submit a PR

Fill in the default PR template (Chinese or English):

1. What the problem is, why the change is needed, and the resulting behavior.
2. Linked issues, main modules touched, and compatibility impact.
3. Checks run, results, and what was not verified.
4. Before/after screenshots or recordings for UI changes; use test data and redact personal content.
5. Source, license, and required notices for newly introduced material.

Before submit: exclude secrets, personal config, real chats, device serials, build caches, and private ops material. Review diagnostics and logs by hand.

Keep discussion focused on the problem, evidence, and implementation. AI-assisted changes must still be understood, verified, and owned by the submitter.
