# Media pipeline and the ML seam

Requirements: `FR-022`, `FR-023`, `FR-060`–`FR-067`, `FR-094`, `NFR-014`, `NFR-052`.

Media is not decoration. A photo with a capture time, a GPS fix and a content hash is the difference between a
claimed surgery and a funded one.

---

## 1. Pipeline overview

```
Device                         API                    Object storage         Worker
──────                         ───                    ──────────────         ──────
capture ──▶ downscale
        ──▶ SHA-256
        ──▶ queue locally
              │
              ├─▶ GET /media/presign ──▶ create media row (pending)
              │   ◀── upload_url ────────────────────────────┐
              ├─▶ PUT bytes ─────────────────────────────────┘
              ├─▶ POST /media/{id}/finalise
              │        └─▶ HEAD object, compute SHA-256,
              │            compare with declared, read EXIF,
              │            status=uploaded, enqueue ──────────────▶ process-media
              │                                                      ├─ thumb 320px
              │                                                      ├─ web 1280px (EXIF stripped)
              │                                                      ├─ perceptual hash
              │                                                      └─ status=processed
              └─▶ POST /media/{id}/link { entity_type, entity_id, role }
```

Bytes never transit the API (`FR-060`). This keeps the API stateless and small, and removes the most likely
memory-pressure failure in a container with 512 MB.

## 2. On-device processing

| Step | Rule | Why |
|---|---|---|
| Downscale | ≤ 1600 px long edge, JPEG q80, ≤ 500 KB (`FR-023`) | A 12 MP original is 4 MB; on EDGE that is minutes and real money for a volunteer |
| EXIF preservation | Capture time and GPS extracted **before** re-encoding and sent as metadata | Canvas re-encoding drops EXIF; the evidence value would be lost silently |
| Hash | SHA-256 over the bytes that will be uploaded | Enables server-side verification of exactly what was sent (`FR-061`) |
| Limit | 5 per sighting, 4 per intervention (before/after + 2) | Bounds device storage and upload time |
| Storage | Blob in IndexedDB, metadata row alongside | Survives app kill (`NFR-012`) |

Downscaling happens in a worker thread; on a 4 GB device, resizing five 12 MP images on the main thread visibly
freezes the UI, and a frozen UI in the cold with gloves on means the volunteer stops using the app.

## 3. Storage layout

```
s3://tnr-media-{env}/
  org/{org_id}/
    original/{yyyy}/{mm}/{media_id}.jpg      immutable, EXIF intact
    web/{yyyy}/{mm}/{media_id}.webp          1280px, EXIF stripped
    thumb/{yyyy}/{mm}/{media_id}.webp        320px, EXIF stripped
  reports/{org_id}/{report_id}.pdf
  evidence/{org_id}/{report_id}.zip
```

Bucket configuration: versioning on (`NFR-024`), public access blocked entirely, EU region only (`FR-124`),
lifecycle rule transitioning originals to infrequent access after 180 days, server-side encryption at rest.

Org-prefixed keys make a per-org export or GDPR erasure a prefix operation rather than a scan.

## 4. Integrity and immutability

| Guarantee | Mechanism |
|---|---|
| Bytes are what the device sent | Client-declared SHA-256 at presign, server-computed at finalise, compared (`FR-061`) |
| Bytes never change | No overwrite path; a replacement is a new row with `supersedes_media_id` (`FR-062`) |
| Provenance is recorded | `uploaded_by_user_id`, `captured_at`, `capture_location`, `created_at` |
| Accidental deletion is recoverable | Bucket versioning, ≥ 30 days (`NFR-024`) |
| Mismatch is loud | `status = quarantined`, alert raised, media excluded from evidence packs |

A hash mismatch is treated as a security event, not a transient error. The most likely benign cause is a proxy
re-encoding an upload; the malicious case is evidence substitution. Both need a human to look.

## 5. Derivatives

| Variant | Size | Format | EXIF |
|---|---|---|---|
| `original` | as uploaded | JPEG/PNG/HEIC as sent | **preserved** |
| `web` | 1280 px long edge | WebP q82 | stripped (`FR-063`) |
| `thumb` | 320 px long edge | WebP q75 | stripped |

Originals keep EXIF because that is the evidence. Derivatives strip it because they are what gets rendered in a
browser, embedded in a PDF and, occasionally, shown to a funder — and a stripped derivative cannot leak a
household's coordinates through an image file.

Derivative generation uses `sharp` in the worker. Failures are retried three times, then the media stays
`uploaded` and the UI falls back to a signed original URL. A missing thumbnail is a cosmetic problem; losing an
original is not, so the pipeline never mutates originals for any reason.

## 6. Serving media

`GET /v1/media/{id}/url?variant=web` → signed URL, ≤ 15 min (`FR-065`). Rules:

- Authorisation is checked against the **linked entity**, not the media row. A media object with no live link is
  not readable.
- Signed URLs are never logged (`NFR-034`), never embedded in emails, never put in a report PDF as a link
  (embedded bytes only).
- Funders receive media only inside a generated report or evidence pack, never through this endpoint.

## 7. Upload validation

| Check | Rule |
|---|---|
| MIME allowlist | `image/jpeg`, `image/png`, `image/webp`, `image/heic` only (`FR-066`) |
| Magic bytes | Validated at finalise against the declared type; mismatch ⟹ quarantine |
| Size | ≤ 8 MB per object, rejected at presign |
| Dimensions | ≥ 320 px long edge (below that it is useless as evidence) |
| Count | Enforced per entity in the service layer |

No SVG (script vector), no video in Phase 1 (cost, and no validated need).

## 8. Garbage collection

Media with no `media_link` after 48 hours is deleted and the deletion is logged (`FR-067`). This handles the
common case of a volunteer starting a sighting, attaching photos, then abandoning the form.

The 48-hour window is generous on purpose: a photo may legitimately arrive before its parent record is accepted
(`05-offline-first-and-sync.md` §7), and reaping evidence because sync was slow would be unforgivable. The GC job
also refuses to run if the media table's unlinked count exceeds a sanity threshold, on the assumption that a
linking bug is more likely than a thousand simultaneously abandoned forms.

## 9. The ML seam — ear-notch detection

### 9.1 Why it is deferred

Automatic ear-notch detection is the headline "AI" feature in the strategy, and it is the right thing to build
**second**. It requires a labelled corpus of Romanian street-dog ear photographs taken on cheap phones in bad
light. That corpus does not exist and cannot be bought. It is precisely what Phase 1 usage produces.

Building a detector first would mean training on clean Western shelter photos and shipping a model that fails in
the field, which would burn the operator trust the product depends on.

### 9.2 What Phase 1 builds instead

1. **Human-in-the-loop capture.** The volunteer records observed notched counts (`FR-028`); the vet records
   `ear_notch_applied` when performing surgery (`FR-098`). These are the labels.
2. **A labelling substrate.** `media_link.role`, a perceptual hash for near-duplicate detection, and a review
   queue where a coordinator can confirm or correct notch observations. Confirmed observations paired with photos
   are training data with provenance.
3. **The interface the model will implement**, defined now so a swap does not ripple:

```ts
interface NotchDetector {
  detect(input: { mediaId: string; variant: 'web' }): Promise<{
    notchPresent: boolean | 'uncertain';
    side?: 'left' | 'right' | 'both';
    confidence: number;          // 0..1
    modelVersion: string;
    inferredAt: string;
  }>;
}
```

Phase 1 ships `ManualNotchDetector`, which returns the human observation with `confidence: 1` and
`modelVersion: 'human'`. Every consumer already handles a confidence score and an `uncertain` verdict, so the
model arrives as a configuration change rather than a refactor.

### 9.3 Phase 1.5 plan (`TNR-110`)

- Model: a small object detector (YOLO-class) fine-tuned on the accumulated corpus, exported to ONNX.
- Deployment: a separate Python FastAPI container invoked by the worker; **never** on the request path.
- Threshold policy: high-confidence positives auto-apply; anything uncertain enters the human review queue.
  Model output is stored as `inferred_notch_*` fields and **never overwrites a human observation**.
- Evaluation gate: ≥ 0.9 precision on a held-out set before any auto-apply is enabled. False positives are the
  expensive error — they mean a dog that needs sterilising is skipped.
- Corpus threshold to start: ≥ 5,000 labelled ear crops with balanced classes.

### 9.4 Other ML candidates, ranked

| Candidate | Value | Status |
|---|---|---|
| Ear-notch detection | Directly prevents wasted trapping | Phase 1.5, seam built now |
| Body-condition scoring from photos | Triage prioritisation | Phase 2+, needs vet-labelled data |
| Individual re-identification | Real population estimates via mark-recapture | Research-grade; not committed |
| Pack-size estimation from a photo | Better estimates than a stressed human count | Phase 2, low priority |
| Abandonment-hotspot prediction | Aims campaigns; strong donor narrative | Needs ≥ 2 seasons of data |

Every one of these is worthless without the corpus. That ordering is the whole reason Phase 1 exists.

## 10. Cost control

Media is the most likely cost blow-out (`NFR-052`). Controls:

- Object storage with **zero egress fees** (Cloudflare R2) — ADR-0009. Evidence packs of a photo-heavy campaign
  would otherwise dominate the bill.
- Derivatives mean a browser never downloads an original.
- Signed URLs are short-lived, so hotlinking cannot amplify egress.
- Evidence packs **stream** the archive rather than buffering it, keeping worker memory flat regardless of pack
  size.
- Lifecycle transition of originals to infrequent access after 180 days.

## 11. Open questions

> **OQ-MEDIA-1** — HEIC from iPhones: transcode server-side or reject with a clear message? Most field devices are
> Android, so this is currently a low-frequency edge. Decide before the first iOS-heavy customer.

> **OQ-MEDIA-2** — Should originals be moved to cold storage after a grant period closes? Cheaper, but slows
> evidence-pack regeneration. Needs a real cost measurement first.
