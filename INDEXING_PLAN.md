1. Done: Built and manually validated the metadata index, lazy PhotoKit display,
   related-photo UI, batched indexing, pruning, persistent change tokens,
   favorite-aware ranking, location/date rows, de-duping, and focused tests.
2. Next: Add semantic indexing as a second index layer, separate from the fast
   metadata index. The existing metadata fingerprint should stay focused on
   `PHAsset` metadata freshness, while embeddings get their own freshness model.
3. Design the embedding table and lifecycle:
   - asset id
   - embedding kind, for example `vision_feature_print`
   - Vision request revision / model version
   - image request size or crop strategy
   - source metadata fingerprint or index version
   - status: pending, ready, failed
   - raw feature-print data, last error, and indexed time
4. Generate embeddings in bounded batches after metadata indexing is available.
   The app should show location/date rows quickly, then add semantic rows once
   embeddings are ready.
5. Start semantic retrieval without a vector extension: load a bounded candidate
   set from SQLite, compare Vision feature prints in Swift, keep regular photos
   and screenshots separate, and return sections through the existing
   `RelatedPhotosService` API.
6. Evaluate sqlite-vec only after the simple Swift-reranked version proves too
   slow or too limited for the demo.
7. Add high-value tests for embedding freshness, wipe/reindex behavior,
   screenshot/photo separation, semantic ranking, and migration safety.
8. Later: Add a "see more" flow so a related row can open as its own album-like
   result view.
