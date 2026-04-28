# Repository Instructions

## Project Overview

- Traces is an iOS SwiftUI app for browsing a user's photo library by time, place, and semantics.
- The Xcode project is `Traces.xcodeproj`.
- The primary scheme is `Traces`.
- Main app code lives in `Traces/`.
- Unit tests live in `TracesTests/` and currently use Swift Testing.
- UI and launch-performance tests live in `TracesUITests/` and use XCTest.

## Code Quality

- Write code that follows `good-code-rubric.md` if that file exists in the repo.
- Match the surrounding Swift and SwiftUI style before introducing new patterns.
- Prefer small, focused changes that preserve the app's existing architecture.
- Keep UI state on the main actor. This project currently uses SwiftUI and `ObservableObject` for view models.
- Use clear Swift names that read well at call sites. Avoid abbreviations unless they are standard Apple API terminology.
- Add comments only when they explain non-obvious behavior, lifecycle constraints, or platform quirks.

## iOS And SwiftUI Conventions

- Keep SwiftUI views composable. Extract subviews when a body becomes hard to scan or when a view has a distinct responsibility.
- Keep model and Photos framework work out of deeply nested view builders where practical.
- Be careful with PhotoKit authorization, limited-library access, iCloud-backed assets, request cancellation, and main-thread UI updates.
- Do not change bundle identifiers, signing settings, provisioning, entitlements, app groups, or privacy strings unless the task explicitly requires it.
- When adding privacy-sensitive functionality, update generated Info.plist keys in the Xcode project and explain why.

## Xcode Workflow

- Use workspace-local DerivedData so command-line builds stay inside the repo sandbox:

```sh
xcodebuild -project Traces.xcodeproj -scheme Traces -configuration Debug -derivedDataPath .build/DerivedData build
```

- For simulator builds, prefer a generic simulator destination:

```sh
xcodebuild -project Traces.xcodeproj -scheme Traces -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData build
```

- For test runs, choose an available iPhone simulator from `xcrun simctl list devices available`, then run:

```sh
xcodebuild test -project Traces.xcodeproj -scheme Traces -destination 'platform=iOS Simulator,name=<SIMULATOR_NAME>' -derivedDataPath .build/DerivedData
```

- For focused unit tests, use `-only-testing:TracesTests/TestTypeName/testName` when possible.
- For focused UI tests, use `-only-testing:TracesUITests/TestTypeName/testName` when possible.
- If simulator services or signing prevent validation in the current environment, report the exact command attempted and the relevant failure.

## Testing Expectations

- Add or update tests when behavior changes, especially for data transformation, authorization state handling, and view model logic.
- Prefer Swift Testing (`import Testing`, `@Test`, `#expect`) for new unit tests in `TracesTests`.
- Use XCTest for UI tests, launch tests, and performance tests in `TracesUITests`.
- Do not mix Swift Testing and XCTest APIs in the same test file unless the existing file already does so.
- Keep tests deterministic. Avoid relying on a real user photo library unless the task is explicitly about manual or simulator UI validation.

## Codex Workflow

- Use `rg`/`rg --files` for search.
- Read the relevant files before editing; do not infer project structure from memory.
- Use `apply_patch` for manual file edits.
- Do not revert user changes or unrelated work.
- Avoid touching `Traces.xcodeproj/project.pbxproj` unless adding/removing files, build settings, capabilities, or privacy metadata requires it.
- Keep generated outputs in ignored locations such as `.build/`.

## Completion Criteria

- Relevant code builds or the blocking environment issue is clearly documented.
- Relevant unit/UI tests pass, or the exact command and failure are reported.
- The final response summarizes what changed and how it was verified.
