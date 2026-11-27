/// The app's version, shown at the bottom of You so a build can be told
/// apart at a glance. Must match `version:` in app/pubspec.yaml (a test
/// checks); bump both with every change (AGENTS.md → Versioning).
const appVersion = '0.8.0';
const appBuild = 8;

/// What this version line of the UI is called.
const appUiLabel = 'v3 UI';

String get versionLabel => 'Tempo $appVersion ($appBuild) · $appUiLabel';
