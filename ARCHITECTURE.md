# Traces Architecture

High-level: PhotoKit owns the photo library, SQLite owns
our derived indexes, and SwiftUI only displays resolved assets and sections.

## Current Boundaries

`PhotoLibraryService` owns PhotoKit fetching and change APIs. It is the place
where we keep the image-only rule, build `PHFetchResult<PHAsset>` values, and
read live or persistent photo-library changes.

`PhotoLibraryViewModel` is the main-actor bridge between PhotoKit and SwiftUI.
It exposes display state, starts indexing after authorization, and updates the
lazy fetch result when the library changes.

`IndexManager` is the retrieval and indexing coordinator. It is an actor so
indexing state is isolated, overlapping indexing jobs are serialized, and
callers can run indexing work asynchronously away from main-actor UI state.

`IndexStore` is the SQLite/GRDB boundary. It should contain SQL details,
migrations, batched writes, pruning, and future vector-extension queries.

SwiftUI views should not know whether a related row came from location buckets,
date logic, Vision embeddings, or a vector table. They should receive section
models that are already grouped and labeled for display, while keeping thumbnail
layout and navigation in the view layer.

## Index Layers

The index should have two layers.

The metadata index is fast and cheap. It stores fields we can read from
`PHAsset` without loading image content: identifier, dates, dimensions, media
subtypes, asset kind, favorite state, location, location buckets, index version,
and metadata fingerprint.

The embedding index is slower and content-based. It should be built in a
separate batched process because it needs image data. This keeps the app useful
quickly after launch, even if semantic results are still being generated.

## Fingerprints

The metadata fingerprint answers one question: does the row in `indexed_photo`
still match the current `PHAsset` metadata and the current metadata index
version?

It should not include semantic embedding data. Embeddings need their own
freshness model because they can change when the embedding model, Vision request
revision, crop strategy, or processing code changes.

This gives us two independent rebuild paths:

1. Metadata changed or metadata index version changed: rebuild the cheap
   metadata row.
2. Embedding model changed or embedding row is missing/stale: rebuild the
   slower content embedding.

## Related-Photo Retrieval

The UI should ask for related sections, not for specific SQL queries. A future
API could look like:

```swift
func relatedSections(for input: PhotoIndexInput) async throws -> [RelatedSection]
```

Each section should have a stable kind, a display title, and ranked asset ids.
The retrieval implementation can then change without changing the view.

The first useful sections are:

1. Over the years.
2. Same place, earlier years.
3. Same place.
4. Similar photos.
5. Similar screenshots.

Each section should be produced by a small candidate source plus a reranker.
`IndexStore` should expose simple query primitives such as nearby candidates
for a location bucket radius, asset kind, optional date direction, and limit.
`RelatedPhotosService` should own the product logic: progressive widening,
year grouping, fallback rules, de-duping, labels, and reranking.

For the same-place sections, SQLite should narrow the candidate pool with cheap
filters: location buckets, asset kind, favorite state, date windows when
needed, selected-id exclusion, and a hard limit. Swift can then group by year,
filter exact product rules, and rank the final candidates. This keeps retrieval
intentional without making SQL responsible for every display rule.

The "Over the years" row uses fixed date windows for now: 10+ years ago,
5-10 years ago, 2-5 years ago, and recent. It fetches bounded candidates per
window, progressively widens the location bucket radius, and displays the row
only when at least two candidates are available. The row can show up to six
photos, preferring favorites first and then closer locations.

Favorites are a cheap metadata ranking signal. SQLite should order bounded
candidate pools with favorites first so favorites are not pushed out by the
limit, and Swift reranking should preserve that product rule before applying
location, date, and distance tie-breaks. After favorites, location closeness
should generally win before date nuance so the matches feel physically tighter.

Semantic sections should plug into the same section API later. Until embeddings
exist, the app should not show empty "Similar photos" rows.

## Semantic Indexing

PhotoKit gives us metadata such as media type, media subtypes, dates,
dimensions, and location. It does not expose the private semantic index used by
the Photos app, so Traces should build its own local content index.

The best first Apple-native option is Vision feature prints:

- `VNGenerateImageFeaturePrintRequest` generates image feature prints.
- `VNFeaturePrintObservation` exposes feature-print data, element count, and
  element type, and can compute a distance to another feature print.
- Apple's Core ML format reference describes Vision scene feature prints as a
  2048-float vector for the scene feature-print model.

For the first implementation, store the raw feature-print `Data` and enough
metadata to know how it was created:

- asset id
- embedding kind, for example `vision_feature_print`
- model or request revision
- crop/scale option
- element type
- element count
- fingerprint or source metadata version
- status: pending, ready, failed
- last error and indexed time

This keeps the architecture honest: the metadata row can be ready while the
embedding row is still pending.

## SQLite Vector Search

Start with regular SQLite storage and Swift reranking. That is easier to debug
and is likely enough while semantic search is filtered by asset kind, location,
date, or a candidate limit.

If we need full-library vector search, hide the implementation behind
`IndexStore` and evaluate SQLite vector options then:

- `sqlite-vec` uses `vec0` virtual tables, supports KNN queries, and supports
  metadata columns for filtering. It is pure C and designed to run anywhere
  SQLite runs, but it is still pre-1.0.
- `sqlite-vector` stores vectors as BLOBs in ordinary tables and has iOS
  packaging examples, but its license and integration story need to be checked
  before adopting it.

The important rule is that vector search should be an implementation detail of
the store. Views and ranking code should not care whether candidates came from
plain SQL, Swift distance checks, `sqlite-vec`, or another extension.

## Background Work Shape

Indexing should run as staged batches:

1. Reconcile metadata from PhotoKit.
2. Mark missing or stale embeddings as pending.
3. Generate embeddings in bounded batches.
4. Write each batch in one database transaction.
5. Save enough progress to resume after app relaunch.

This is not true background execution yet. For the demo, it is enough that the
work runs while the app is open, avoids blocking the grid, and can resume.

## Research Notes

- Apple Photos persistent changes:
  https://developer.apple.com/documentation/photos/phphotolibrary
- Apple Vision feature prints:
  https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest
- Apple image similarity sample:
  https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print
- Apple feature-print observation:
  https://developer.apple.com/documentation/vision/vnfeatureprintobservation
- Core ML VisionFeaturePrint format:
  https://apple.github.io/coremltools/mlmodel/Format/VisionFeaturePrint.html
- sqlite-vec:
  https://github.com/asg017/sqlite-vec
- sqlite-vec KNN and metadata docs:
  https://alexgarcia.xyz/sqlite-vec/features/knn.html
  https://alexgarcia.xyz/sqlite-vec/features/vec0.html
