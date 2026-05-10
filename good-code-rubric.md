# Traces Good Code Rubric

Optimise for: clarity at the call site, composable SwiftUI, small cohesive files,
obvious side effects, explicit PhotoKit and persistence boundaries, responsive UI,
and safe iteration over large photo libraries.

Use this rubric for coding decisions, reviews, and folder-structure choices in
Traces.

---

## North Star Principles

- Functional core, imperative shell: keep pure ranking, mapping, validation, and
  indexing decisions separate from PhotoKit, SQLite, disk, and UI side effects.
- SwiftUI as a view layer: views declare UI and local interaction state; services,
  stores, actors, and models do the durable work.
- One source of truth: each state value has one owner, and child views receive
  immutable values, bindings, or observable models intentionally.
- Service folders are for real boundaries: PhotoKit, image loading, persistence,
  indexing orchestration, location, networking, and other system integrations.
- Large-library first: avoid eager materialization of huge `PHAsset` lists, giant
  SQL `IN` clauses, unbounded image requests, and repeated full-library scans.
- Accessibility and privacy are product requirements, not polish.
- No premature architecture: use feature and service folders to reduce
  navigation cost, not to perform architecture theater.

---

## Rules

### 1. Repo and Folder Structure

Organise by feature or domain, then by responsibility inside that folder. Avoid
top-level buckets that become dumping grounds.

For now, keep the structure simple: group code by clear product or system
responsibility, and introduce new folders only when they make the code easier to
find and maintain.

As the app grows, prefer a structure like this:

```text
Traces/
  App/                  # App entry point, dependency assembly, app-wide routing
  Features/
    Library/
      Views/
      ViewModels/
      Models/
    PhotoDetail/
      Views/
      ViewModels/
      Models/
  Services/
    Photos/             # PhotoKit authorization, fetches, changes, image loading
    Indexing/           # Index orchestration and semantic search services
  Persistence/          # GRDB/AppDatabase/stores/migrations
  Shared/
    UI/                 # Small reusable views/modifiers
    Foundation/         # Tiny cross-cutting value types or extensions
```

Use this target shape gradually. Do not move files just because the folder exists.
Move code when a folder has a distinct responsibility or when a file is becoming
hard to scan.

Dependency direction:

- `App/` may assemble dependencies and pass them into features.
- `Features/*/Views` may depend on their view models, models, and shared UI.
- `Features/*/ViewModels` may depend on services, stores, actors, and domain
  models.
- `Services/*` may depend on Apple frameworks and persistence protocols/types.
- `Persistence/` owns database setup, migrations, and low-level stores.
- `Shared/` depends on little or nothing project-specific.
- Views should not construct PhotoKit fetches, database queries, or indexing
  transactions directly.

Folder names to prefer:

- `Features`, `Views`, `ViewModels`, `Models`, `Services`, `Persistence`,
  `Indexing`, `Photos`, `Shared`, `Resources`.

Folder names to avoid unless tightly scoped:

- `Utils`, `Helpers`, `Common`, `Managers`, `Misc`, `Extensions`.

### 2. File Size and Cohesion

- Prefer Swift files under 250 lines.
- Files up to 400 lines are acceptable when they are single-responsibility and
  internally organized.
- Split earlier when a file mixes UI composition, PhotoKit, database work,
  ranking logic, and formatting.
- SwiftUI `body` values should be easy to scan. Extract subviews when a branch,
  toolbar, overlay, row, empty state, or section has its own responsibility.
- Keep extensions close to the type they support unless they are reused by
  multiple features.

### 3. Swift Naming

Optimize for clarity at the use site, following the
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).

- Include the words needed to avoid ambiguity.
- Omit words that only repeat type information.
- Name variables and parameters by role, not by weak type names like `data`,
  `object`, `item`, or `value` when the role is clearer.
- Prefer fluent call sites:

```swift
indexManager.relatedPhotos(for: input, limit: 20)
photoLibraryService.fetchAssets(withLocalIdentifiers: ids)
```

Side-effect naming:

- `fetch...` means PhotoKit, network, or another external read.
- `load...` means local disk, database, or long-lived in-memory state hydration.
- `save...`, `write...`, `upsert...`, `delete...`, `prune...`, or `wipe...`
  means persistence mutation.
- `request...` means permission, user prompt, or cancellable async system work.
- `compute...`, `rank...`, `make...`, `map...`, and initializers should be pure
  unless the Apple API convention clearly says otherwise.

Type naming:

- `View` is a SwiftUI view.
- `ViewModel` owns UI state and user actions; keep it `@MainActor` unless there
  is a specific reason not to.
- `Service` wraps an external framework or app-wide capability.
- `Store` performs persistence reads and writes.
- `Actor` or `Manager` coordinates concurrency/stateful workflows. Do not use
  `Manager` for a vague bucket.

### 4. SwiftUI State and View Boundaries

Follow Apple's
[SwiftUI data-flow and state-management guidance](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app)
for property wrapper choice, bindings, observation, and environment values. This
rubric only adds the project-specific expectations below.

- Keep durable UI state on the main actor.
- Prefer explicit initializer injection for feature dependencies. Use environment
  values for app-wide dependencies or platform values, not as a hiding place for
  arbitrary services.
- Keep `body` declarative. Move permission checks, fetch construction, indexing,
  sorting, and database writes into view models, services, stores, or pure
  helpers.
- Avoid doing expensive work in `body`, property getters read by `body`, or
  frequently recreated subviews.
- Navigation state should be typed and stable. Avoid passing heavyweight
  framework objects through navigation paths when a local identifier is enough.

### 5. Services, Stores, and Side Effects

Service folders are encouraged when they make system boundaries easier to find.
The test for a service is simple: it talks to the outside world or coordinates a
system capability.

Good service responsibilities:

- PhotoKit authorization and fetch construction.
- Photo library change observation and persistent change token handling.
- Image request/caching adapters.
- Database setup, migrations, and stores.
- Indexing orchestration that batches work and protects concurrency.
- Location, networking, file import/export, or cloud integrations if added.

Service rules:

- Services return app-owned models or framework results appropriate for large
  collections. For photo grids, prefer `PHFetchResult<PHAsset>` over eagerly
  copying every `PHAsset` into arrays.
- Stores own SQL and transactions. Views and view models should not contain SQL.
- Batch database writes and metadata scans. Avoid one transaction per asset.
- Avoid giant SQL `IN` lists on large libraries. Chunk or use temporary tables.
- Make cancellation explicit for image requests, indexing tasks, and long async
  work.
- Register and unregister observers predictably.
- Treat limited-library access as a first-class state, not a footnote.
- Keep iCloud-backed assets and network access behavior deliberate.

### 6. Functional Core and Domain Logic

Pure logic should be testable without PhotoKit, SwiftUI, GRDB, files, network,
or real user photos.

Put pure logic in focused types or functions for:

- photo fingerprinting and index input derivation,
- bucketing,
- semantic or related-photo ranking,
- sorting and filtering rules,
- authorization-state mapping,
- display formatting.

Keep side effects at the shell:

- PhotoKit fetches,
- image requests,
- SQLite reads/writes,
- app lifecycle events,
- permission prompts,
- file system access,
- logs and metrics.

Inside pure logic, assume inputs have already been normalized. Use `precondition`
or `assert` only for programmer errors that should be impossible after boundary
validation.

### 7. PhotoKit Rules

Use Apple's
[PhotoKit authorization and privacy guidance](https://developer.apple.com/documentation/photokit/requesting_authorization_to_access_photos)
as the baseline.

- Centralize PhotoKit fetch construction in a photos service or closely related
  model layer.
- Prefer `PHFetchResult` for large library display and indexing paths.
- Use `PHFetchOptions` intentionally: sort descriptors, predicates, fetch limits,
  source types, and incremental-change settings should be visible at the service
  boundary.
- Handle `.authorized`, `.limited`, `.denied`, `.restricted`, `.notDetermined`,
  and `@unknown default`.
- When access is `.limited`, keep UI and indexing correct for the selected
  subset and support changes to that selection.
- Use `PHPhotoLibraryChangeObserver` or persistent changes for library updates;
  do not rerun a full scan on every navigation event.
- Use `PHCachingImageManager` or a service wrapper for scrolling thumbnail grids.
  Start and stop caching as visible/preheated ranges change.
- Track image request IDs when requests may outlive the cell/view that started
  them, and cancel stale requests.
- Be explicit about delivery mode, target size, content mode, resize mode, and
  whether iCloud network access is allowed.
- Do not retain full-resolution images longer than needed.

### 8. Persistence and Indexing

- Keep database setup and migrations in persistence-owned files.
- Keep SQL in stores, not in view models or SwiftUI views.
- Prefer typed values at store boundaries over raw `Row` or loosely typed
  dictionaries.
- Store enough metadata to decide whether a photo needs reindexing without
  recomputing everything.
- Batch writes in one transaction per batch.
- Chunk large delete/update/read sets.
- Make index versioning explicit and bump it when fingerprinting or ranking
  inputs change.
- Long-running indexing belongs off the main actor. Publish only small UI state
  changes back to the main actor.
- Guard against overlapping indexing runs with actor state or another explicit
  concurrency control.

### 9. Concurrency and Responsiveness

Use Apple's
[responsiveness guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
as the baseline for main-thread work.

- Main-actor work in response to taps should stay tiny. Avoid synchronous
  PhotoKit scans, database writes, image decoding, or heavy sorting on the main
  actor.
- Use actors for mutable state that must be protected across tasks.
- Prefer structured concurrency. Keep unstructured `Task {}` blocks near the UI
  or lifecycle event that starts them, store handles when cancellation matters,
  and cancel in `deinit`, `onDisappear`, or replacement flows as appropriate.
- Avoid priority inversions: do not make high-priority UI tasks wait on
  long-running background work when a snapshot or partial result would do.
- Add progress or staged updates for work that can take noticeable time.
- Measure performance before broad rewrites. Prefer one focused improvement,
  then verify.

### 10. Error Handling

- Use typed errors for app-level recoverable failures.
- Let low-level errors propagate until a boundary can show UI, retry, log, or
  map them to a user-facing state.
- Do not silently swallow errors.
- Avoid `try?` unless loss of the error is truly irrelevant and documented by the
  surrounding code.
- Use `@unknown default` for Apple enums that can grow.
- User-facing errors should be actionable and privacy-conscious.

### 11. Privacy and Security

- Do not change bundle identifiers, signing, entitlements, app groups, or privacy
  strings unless the task explicitly requires it.
- When adding privacy-sensitive capability, update generated Info.plist settings
  in the Xcode project and explain why.
- Ask for the narrowest Photos authorization that supports the feature.
- Treat local identifiers, metadata, locations, and timestamps as private user
  data.
- Do not log personal metadata, exact coordinates, filenames, or full local
  identifiers unless a debug task explicitly requires it.
- Keep exported files and generated debug data out of the repo unless they are
  intended fixtures.

### 12. Accessibility and UI Quality

Use Apple's
[accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
as the baseline.

- Use system controls, fonts, colors, navigation, and materials unless a custom
  design solves a real product problem.
- Support Dynamic Type. Do not hard-code layouts that break with larger text.
- Provide useful accessibility labels, values, hints, and traits for custom
  controls and photo-related actions.
- Do not convey meaning by color alone.
- Maintain sufficient contrast in light and dark appearances.
- Keep tappable controls comfortably sized and spaced.
- Respect Reduce Motion for nonessential animation.
- Make empty, loading, denied, limited, and error states explicit.

### 13. Testing Philosophy

Use Apple's
[Swift Testing](https://developer.apple.com/documentation/testing) and
[XCTest](https://developer.apple.com/documentation/xctest) docs as the baseline.

- Prefer Swift Testing for new unit tests in `TracesTests`:

```swift
import Testing

@Test(arguments: [
    // table cases
])
func ranksRelatedPhotosByOlderThenNearestDate() {
    // #expect(...)
}
```

- Use XCTest for UI tests, launch tests, and performance tests in
  `TracesUITests`.
- Test pure logic with table tests and edge cases.
- Add focused tests for authorization-state mapping, indexing decisions,
  fingerprint/version changes, related-photo ranking, and database store
  behavior.
- Keep tests deterministic. Do not require a real user photo library unless the
  task is explicitly manual or simulator validation.
- Avoid mock-heavy tests that mirror implementation details. Prefer small
  protocols or injected services only where they simplify a real boundary.
- For async code, await the behavior directly when possible and keep timing-based
  waits rare.
- Do not mix Swift Testing and XCTest APIs in the same test file unless that file
  already does.

### 14. Comments, TODOs, and Documentation

- Add comments only for non-obvious lifecycle, platform, privacy, concurrency, or
  performance constraints.
- Public or cross-feature APIs should be understandable from their declaration
  and a short documentation comment when the behavior is not obvious.
- TODOs must include a trigger or decision bookmark.

Good:

```swift
// TODO: If thumbnail preheating expands beyond the visible month, add request cancellation.
```

Bad:

```swift
// TODO: fix
```

---

## Smells

Structure smells:

- A new top-level folder named `Utils`, `Helpers`, `Common`, or `Managers`.
- SQL, PhotoKit fetch options, or image request code inside SwiftUI views.
- A service that does not wrap an external boundary or app-wide capability.
- A shared folder that grows faster than feature folders.

SwiftUI smells:

- Expensive work in `body`.
- A view model doing database loops on the main actor.
- Navigation paths carrying heavyweight framework objects.
- Repeated `.task` work that reruns full indexing when returning to a screen.

PhotoKit smells:

- Eagerly converting a large fetch result into `[PHAsset]`.
- Ignoring `.limited` authorization.
- Image requests without cancellation in reusable thumbnail views.
- Full-resolution image retention in grid paths.

Persistence/indexing smells:

- One transaction per asset.
- Giant `IN` lists for 100k-photo paths.
- Indexing runs that can overlap silently.
- Index version changes without migration/reconciliation behavior.

Testing smells:

- Tests that require the developer's real photo library.
- Mock-heavy tests that break on harmless refactors.
- Tests that assert private implementation order rather than user-visible or
  domain behavior.

---

## PR Checklist

- [ ] Files are small and cohesive, or the larger file has a clear reason.
- [ ] Folder placement follows feature/domain/service responsibility.
- [ ] Views contain UI composition, not PhotoKit/database/indexing work.
- [ ] UI state that mutates views is isolated to the main actor.
- [ ] PhotoKit authorization, limited access, change handling, and cancellation
      are handled where relevant.
- [ ] Large library paths avoid eager asset arrays, giant SQL lists, and
      per-asset transactions.
- [ ] Pure logic is separated enough to test without real Photos data.
- [ ] Errors propagate to a boundary that can retry, log, or show UI.
- [ ] Privacy-sensitive data is not logged or persisted unnecessarily.
- [ ] Accessibility states and labels are covered for new UI.
- [ ] Swift Testing covers new pure logic or view-model behavior where useful.
- [ ] XCTest remains the tool for UI, launch, and performance tests.
- [ ] Build/tests were run, or the exact environment blocker is documented.
