# Contributing

Thank you for helping improve Universal BLE. This document describes how we work in this repository and what we expect from contributions.

## Reporting issues

Use [GitHub Issues](https://github.com/Navideck/universal_ble/issues). Include the platform (Android, iOS, macOS, Windows, Linux, Web), Flutter/Dart versions, and a minimal way to reproduce the problem when possible.

## Pull requests

- Open PRs against the `main` branch.
- Keep changes focused: one logical concern per PR is easier to review than a large mixed refactor.
- Update `CHANGELOG.md` when the change is user-visible (new behavior, fixes, or breaking API changes). Follow the existing bullet style (`* …`, `* BREAKING CHANGE: …` where appropriate).
- Do not commit secrets, local paths, or generated build artifacts unrelated to the change.

## Environment

Requirements are defined in `pubspec.yaml` (Dart SDK and Flutter). Use a stable Flutter channel unless a maintainer asks otherwise.

From the repo root:

```sh
flutter pub get
```

## Checks to run before opening a PR

These mirror [.github/workflows/pull_request.yml](.github/workflows/pull_request.yml):

```sh
flutter analyze
flutter test
flutter test --platform chrome
```

Fix any analyzer issues. The project uses [flutter_lints](https://pub.dev/packages/flutter_lints) via [analysis_options.yaml](analysis_options.yaml) (which includes `package:flutter_lints/flutter.yaml`).

Format Dart code with the SDK formatter:

```sh
dart format .
```

If you only touched specific files, you may format those paths instead of the whole tree.

## Pigeon and generated code

Host–native APIs are defined in [pigeon/universal_ble.dart](pigeon/universal_ble.dart). If you change that file, regenerate outputs and include them in the same PR:

```sh
./build_pigeon.sh
```

That runs `dart run pigeon --input pigeon/universal_ble.dart` and formats `lib/src/universal_ble_pigeon/universal_ble.g.dart`. Regenerated Kotlin, Swift, and C++ files land under `android/`, `darwin/`, and `windows/` as configured in the Pigeon `@ConfigurePigeon` block—keep those in sync with the Dart definitions.

## Code conventions

- **Dart:** Follow effective Dart style, existing naming in `lib/`, and analyzer rules. Prefer extending existing patterns (platform interface → pigeon channel → native implementations) over new parallel abstractions unless discussed first.
- **Native:** Match the style and structure of the surrounding file on each platform (Kotlin, Swift, C++). When a Pigeon API changes, update every generated implementation and any hand-written glue so all targets stay consistent.
- **Tests:** Add or extend tests under `test/` when behavior is non-trivial or regression-prone. Use `flutter_test` like the existing suite.
- **Example:** If the change affects how integrators use the plugin, consider updating the `example/` app so it stays a working reference.

## Platform-specific APIs and parameters

- **Single-platform features:** Prefer not adding a new public API when only one platform can implement it, unless none of the existing APIs can be extended or adapted to cover the behavior. For example, something like Android-only `requestConnectionPriority` should only become its own method if `connect`, `platformConfig`, or another existing entry point cannot reasonably subsume it.
- **Single-platform parameters:** When a value applies to one platform only, attach it via a platform-scoped bag (for example `startScan` takes an optional `platformConfig` object for options that only affect a given OS). That keeps the main method signature stable and makes it obvious which settings are platform-specific.
- **Shared parameters:** If more than one platform supports the same option, add it as a normal method parameter on the shared API. Document that implementations on platforms without that capability must ignore the parameter (no-op or documented limitation).

## License

By contributing, you agree that your contributions will be licensed under the same terms as the project: [BSD 3-Clause License](LICENSE).
