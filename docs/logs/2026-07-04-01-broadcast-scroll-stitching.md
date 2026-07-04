# 2026-07-04-01: Capture-by-scrolling via ReplayKit broadcast + pixel-matching stitch

**Status:** Decided (pre-implementation)

## Context

The original README described Longshot as: pick 2+ overlapping screenshots from the
Photos library, then stitch them. In brainstorming, the product owner rejected that UX —
manually taking and picking screenshots is "too troublesome." The desired experience is:
the user just **scrolls** the content they want and capture happens **automatically**.

This forces three separable decisions: (1) how to capture other apps' content, (2) how
to compute the stitch offset, (3) when/where stitching runs given platform limits.

## Options

### Capture source

| Approach | Pros | Cons |
|----------|------|------|
| Album picker (original) | Simplest; no entitlements | Rejected by owner — manual, tedious |
| In-app browser (WKWebView full-page render) | Seamless, perfect quality, no stitching | Web content only; can't capture native apps |
| **ReplayKit system broadcast (chosen)** | Captures *any* app; matches "scroll to capture" | User must start a screen recording; needs a broadcast extension under a ~50 MB memory cap; app can't auto-stop |

iOS provides **no other way** to see another app's screen, so broadcast is the only
option that satisfies "capture any app."

### Offset detection

| Approach | Pros | Cons |
|----------|------|------|
| Vision `VNTranslationalImageRegistrationRequest` | First-party, zero-code | Global registration corrupted by fixed chrome (sits at zero-offset, fights the real scroll offset); not pixel-exact; opaque, so untestable |
| **Pixel row-matching, MAD via Accelerate (chosen)** | Pixel-exact integer offset; sub-10 ms; free confidence score; deterministically unit-testable | Must handle repeated-row UI (runner-up margin) and uniform bands (variance weighting) ourselves |
| Phase correlation (vDSP FFT) | Robust to ambiguity | Overkill for clean UI; kept as a back-pocket fallback |

### When/where stitching runs

| Approach | Pros | Cons |
|----------|------|------|
| Live preview while scrolling | Nice in theory | App is backgrounded during scroll → effectively impossible to show live |
| Live stitch, shown on return | — | Little benefit; adds extension memory risk |
| **Process-after-stop (chosen)** | Simple, memory-safe, robust | No live preview (acceptable — assembly is fast) |

## Decision

Capture any app via **ReplayKit system broadcast**; the extension does lightweight
**pixel row-matching** (Accelerate) + frame selection and streams keyframes + a manifest
to an App Group; the **app assembles** the long image after the broadcast stops. No
Vision. Hard-cut seams, not feathered.

## Rationale

- Broadcast is the only API that can capture arbitrary apps — non-negotiable given the
  desired UX.
- The stitch transform is a pure integer vertical shift with *identical* overlap pixels,
  so MAD row-matching is both more accurate and more testable than Vision, and lets us
  meet the TDD-on-synthetic-fixtures goal. Fixed chrome that would corrupt Vision is
  instead used as a *signal* (identical rows → chrome bands to exclude/crop).
- Splitting lightweight matching (extension) from heavy compositing (app) keeps the
  extension under its ~50 MB memory ceiling regardless of scroll length.
- Feathering identical crisp text only blurs it, so seams are a hard cut.

## What Changed

- `README.md` — rewritten around the broadcast capture flow, the three-target
  architecture, and the Accelerate-based stitch approach; album import moved to roadmap.
- `docs/superpowers/specs/2026-07-04-broadcast-scroll-stitching-design.md` — full
  approved design (targets, capture flow, `StitchKit` internals, assembly/preview/export,
  testing, risks).

## What Was Discovered

- `VNTranslationalImageRegistrationRequest` is biased toward prominent/high-contrast
  regions and degrades on large motion; the fixed nav/tab bars (perfectly aligned at
  zero offset) actively pull its global estimate off the true scroll offset.
- Mature OSS scrolling-screenshot tools (e.g. `wayscrollshot`, Tailor) converged on
  column-sampled MAD with confidence scoring as the workhorse, reserving feature matching
  for hard cases we don't have here.
- Chrome detection needs no device tables: the contiguous run of byte-identical rows
  between two consecutive frames *is* the non-scrolling chrome.
- Open follow-ups: extreme-height output images (v1 caps + warns; tiling deferred), and
  the exact keyframe-commit threshold (~65% of scroll band → ≥30% overlap) may need
  tuning against real capture sessions.
