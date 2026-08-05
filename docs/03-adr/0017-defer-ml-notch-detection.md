# ADR-0017: Defer ear-notch ML; build the seam and the corpus first

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: media pipeline, product scope, Phase 1.5 planning

## Context

Automatic detection of ear notches — the surgical mark showing an animal is already sterilised — is the headline
"AI" capability in the strategy. It prevents wasted trapping, which is a genuine, expensive field problem.

The strategy document proposes a lightweight image-processing model on the server. The question is when.

## Options considered

### Option A — Ship notch detection in the Phase 1 MVP

**For:** Compelling demo; strong differentiation; addresses a real cost.
**Against:** No training data exists. Romanian street-dog ear photographs, taken on cheap phones, in bad light, at
awkward angles, are not a public dataset and cannot be bought. Training on clean Western shelter imagery would
produce a model that fails in the field — and a false negative means re-trapping an already-sterilised dog, which
is precisely the failure the feature exists to prevent. Shipping a detector that is wrong in the field would burn
the operator trust the entire product depends on. It also consumes the scarcest resource — solo founder time —
before the core loops work.

### Option B — Third-party vision API

**For:** No training needed.
**Against:** General-purpose vision models do not recognise ear notches; this is a narrow domain concept. Per-call
cost, and sending evidence media to a third party creates a GDPR and data-residency problem for no benefit.

### Option C — Defer the model, build the seam and the corpus

Ship human-in-the-loop capture now: volunteers record observed notch counts (`FR-028`), vets record
`ear_notch_applied` (`FR-098`). Those, paired with photos, are labelled training data with provenance. Define the
`NotchDetector` interface now and implement it with a `ManualNotchDetector`.

**For:** Every consumer already handles a confidence score and an `uncertain` verdict, so the model arrives as a
configuration change rather than a refactor. The corpus accumulates as a by-product of normal usage. The feature
ships when it can actually work.
**Against:** No AI story in the initial sales conversation; the corpus takes a season to accumulate; a competitor
could claim the capability first (and, most likely, claim it without it working).

## Decision

**Option C.** Detail in
[`../02-architecture/07-media-and-ml-pipeline.md`](../02-architecture/07-media-and-ml-pipeline.md) §9.

Phase 1.5 (`TNR-110`) gating conditions:

- ≥ 5,000 labelled ear crops with balanced classes.
- ≥ 0.9 precision on a held-out set before any automatic application. **False positives are the expensive error** —
  a wrongly detected notch means an unsterilised dog is skipped, which is the opposite of the product's purpose.
- Deployed as a separate Python service invoked by the worker, never on the request path.
- Model output stored in `inferred_notch_*` fields and **never** overwriting a human observation.

## Consequences

**Positive** — engineering effort goes to the loops that create value now; when the model ships it will be trained
on exactly the distribution it must serve; the interface is designed before the implementation, which usually
produces a better interface; no third-party media exposure.

**Negative** — no AI differentiation in early sales conversations; the corpus depends on adoption, so slow adoption
delays the model; competitors may claim the capability sooner.

**Neutral** — the same seam supports other vision features later (body-condition scoring, individual
re-identification), all of which have the same corpus dependency.

## Revisit when

The corpus threshold is met, or a partner offers a suitable labelled dataset under acceptable terms.
