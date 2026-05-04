# Traces Indexing Goals

1. Set up the database foundation with GRDB and SQLite.
   - Add GRDB to the `Traces` app target.
   - Open a `Traces.sqlite` database in Application Support.
   - Run migrations on launch.
   - Prove the app can create and open the database.

2. Create the first metadata-only index schema.
   - Add an `indexed_photo` table.
   - Add enough fields to identify, fingerprint, and version indexed photos.
   - Do not add location, embeddings, or query ranking yet.

3. Fetch photos only from PhotoKit.
   - Use `PHAsset.fetchAssets(with: .image, options:)`.
   - Do not let videos enter the indexing pipeline.
   - Keep this rule close to the PhotoKit fetch layer.

4. Define the single indexing input model.
   - Add `PhotoIndexInput`.
   - Extract the minimal fields we index from each `PHAsset`.
   - Keep fingerprint creation in one place.

5. Make indexing resumable.
   - Detect missing rows.
   - Detect stale rows when `index_version` changes.
   - Detect stale rows when a photo fingerprint changes.
   - Index only missing or stale photos.

6. Make indexing easy to wipe.
   - Add a simple wipe operation for the indexed rows.
   - Use this during early development when the schema or indexing rules change.

7. Add a simple app-visible indexing status.
   - Show idle, indexing progress, completed, or failed.
   - Run indexing asynchronously while the app is open.
   - Defer true iOS background processing until the basic path works.

8. Prove the flow end to end.
   - Launch the app.
   - Fetch image assets.
   - Build `PhotoIndexInput` values.
   - Store rows in SQLite.
   - Relaunch and confirm already-indexed photos are skipped.

9. Add focused automated tests.
   - Test migrations with an in-memory database.
   - Test fingerprint behavior.
   - Test missing/stale detection.
   - Test wipe and reindex behavior.
   - Test photo-only filtering through app-owned abstractions, not PhotoKit itself.

10. Add location buckets after metadata-only indexing works.
    - Add lat/lon fields and bucket columns.
    - Query nearby buckets.
    - Filter exact distances in Swift.

11. Add semantic/vector indexing later.
    - Add embeddings behind the same indexing interface.
    - Use sqlite-vec only after the SQLite and metadata indexing path is stable.
