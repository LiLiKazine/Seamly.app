# Seamly.app — design system

**Direction: Paper.** The capture is a sheet lying on a desk.

This system is derived from the product concept, not from any existing build. An
earlier iOS target exists; it is a throwaway spike that proves the stitching
pipeline and carries no design intent. Nothing here is lifted from it — no
palette sampled from its icon, no spacing or radii copied from its literals, no
component inventory mirroring its views.

## The concept everything serves

Every other image on your phone is uniformly true. A Seamly capture is assembled
from evidence the user produced by scrolling, and its trustworthiness **varies
along its length**: solid for 12 000 px, uncertain at three joins, missing
1 200 px where they scrolled too fast.

> A capture knows its own weak points, and can walk you through them.

The engine makes a long screenshot. The product makes one you can **trust**, by
making its doubts legible and answerable.

## Decisions this system encodes

**Return home.** The app is backgrounded while the user scrolls another app, so
its most common launch context is *"I just stopped a broadcast — what did I
get?"* It opens on the most recent capture, resolved. The capture affordance is
permanently docked (`CaptureDock`), never a toolbar icon. With no captures, the
empty state is capture-first for free.

**Repair is a queue.** `QueuePrompt` asks one question at a time, zoomed to the
problem. `StepperRow` still exists — as the advanced path, never the default.

**Teach, vanish, resolve.** Nothing may be drawn during a broadcast; it would be
recorded into the capture. The app owns four seconds before and the moment
after, which is the entire reason `CueCard` exists.

**Signal lives in the margin.** The one real weakness of a light ground is that a
thin rule over white captured content can be missed. So `SeamMark` stays quiet on
the sheet — a good capture must look like one image — and `MarginMarker` plus
`PositionScale` carry findability from the margin, where the ground is always
paper and contrast is guaranteed whatever was captured. This is the load-bearing
rule of the direction.

## Principles

1. A good capture must look like **one image**. Only doubt draws attention.
2. Every doubt is locatable and paired with its fix.
3. Never show the middle of a tall image. Crops are top-anchored.
4. Position is always answerable.
5. Nothing is drawn during a broadcast.
6. Numbers carry units and don't reflow. Mono, tabular, thin-space thousands.

## Foundations

**Colour** — warm uncoated stock (`--paper` #ece9e3) a shade darker than white, so
a capture's own edge separates it from the app. One accent, bookbinder's blue
(`--accent` #33456b). Four muted marks — `--mark-flag`, `--mark-gap`,
`--mark-error`, `--mark-ok` — plus iOS red `--mark-rec` for live broadcast, which
must never be restyled. Dark theme is a **night desk**, not an inversion: the
ground darkens, the sheet stays paper-white, because a capture has its own
brightness and must not be dimmed.

**Type** — SF Pro via `-apple-system`, and the iOS pt ladder 1:1
(34/28/22/20/17/16/15/13/12/11). That ladder is **identical on iPhone and iPad** —
Apple does not vary it by size class; iPad gets more content, not bigger type.
Mono with tabular figures for every measurement. The paper feeling comes from
margin and measure, not from a serif: a display serif would fight Dynamic Type.

**Space** — 4 pt base. Gutters run wider than a typical iOS app (20 / 32) because
a document has margins; that is the direction showing up in the numbers.

**Radii** — sheets are square (`--radius-sheet: 0`). Rounding is for controls only.

**Depth** — a rule plus a lifted edge. Paper, not glass; no large blurs. Chrome
over a capture sits on a protection gradient, never a flat scrim, because a proxy
can be any brightness and a scrim dims what the user is reading.

## Components

| Group | Components |
|---|---|
| `foundation/` | **Icon** — keyed by SF Symbol name, inline paths, no CDN |
| `actions/` | **Button** · **IconButton** |
| `capture/` | **CaptureDock** · **ImportRow** |
| `data/` | **CaptureSheet** · **CaptureListRow** · **CaptureGridCard** · **StatusNote** |
| `marks/` | **SeamMark** · **MarginMarker** · **PositionScale** |
| `repair/` | **QueuePrompt** · **StepperRow** |
| `feedback/` | **CueCard** · **EmptyState** · **ProgressNote** |
| `navigation/` | **NavBar** · **Sheet** · **PageDots** |

Each has a `.d.ts` contract and a `.prompt.md` with a usage example. The bundle
exposes them at `window.SeamlyApp_f9e883` (the project namespace), with
`window.SeamlyPaper` aliased to the same object so the UI kit reads legibly.

## Deliberately absent

- **No token specimen cards.** The pane already lists every token with its value
  and source file; a card restating them is a second copy of a browser you have.
  The four cards here document things tokens can't: how doubt is drawn, how
  repair works, the palette's reasoning, and the voice.
- **No icon-font or CDN dependency.** Icons are inline paths. Nothing to fail
  offline or drift under you.
- **No logotype.** None exists yet; "Seamly" is set in SF Pro Display until one
  is designed.
- **No webfonts.** SF Pro is the real typeface and ships with the platform.

## Building

Components are authored as JSX in `src/` and bundled with esbuild:

**The `--footer:js` flag is not optional.** esbuild's `--global-name` only
defines `window.SeamlyApp_f9e883`; the `window.SeamlyPaper` alias documented
above is appended by that footer. A build without it drops the alias, and any
code that reaches for `SeamlyPaper` alone gets `undefined` — the UI kit
survives only because it falls back through
`SeamlyKit || SeamlyApp_f9e883 || SeamlyPaper`.

```
npx esbuild src/index.js --bundle --format=iife --global-name=SeamlyApp_f9e883 \
  --jsx=transform --alias:react=./src/react-shim.js \
  --footer:js='window.SeamlyPaper=SeamlyApp_f9e883;' --outfile=_ds_bundle.js
```

React is taken from the host global, so nothing is vendored.
