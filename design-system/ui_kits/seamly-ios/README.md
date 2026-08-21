# Seamly for iPhone & iPad — UI kit

Live click-through. Every screen resolves the library as
`window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper` — the last is
an alias appended by the bundle's `--footer:js`, not the primary name — so changing
a component changes the screens.

- **Compact / Regular** switches size class. It is the point of the kit: Review
  gains a persistent findings rail at regular width, and Library becomes a 3:5
  grid. These are two designs, not one layout reflowed.
- **Desk / Night desk** switches theme. The sheet stays white in both — a capture
  has its own brightness and must not be dimmed.
- **First launch** (on Home) shows the empty state, which is capture-first.
- **Import** runs the video-import flow. It advances by itself; **Make it fail**
  forces the error state.

Screens: `HomeScreen` · `LibraryScreen` · `ReviewScreen` · `RepairQueue` ·
`Sheets` (export, import, first run).

**Import is the reason `ProgressNote` takes an optional value.** Reading the
recording has a real percentage; stitching does not — the work is data-dependent
and finishes when the seams are found. So the second phase runs indeterminate and
says so in words, rather than showing a bar that would be a lie. `CaptureView` is shared by Home, Review and the
queue so all three agree where a mark sits: on screen a mark is at
`atPct * zoom - top`, which keeps the margin marker and the rule on the sheet
locked together.

## How it loads (and why it ignores _ds_bundle.js)

Nothing is fetched at render time. React is vendored under `vendor/`, and the
screens are precompiled from the `.jsx` sources into `kit.js`:

```
for n in CaptureView HomeScreen LibraryScreen ReviewScreen RepairQueue Sheets App; do
  esbuild $n.jsx --jsx=transform --outfile=/tmp/$n.js
done && cat /tmp/{CaptureView,HomeScreen,LibraryScreen,ReviewScreen,RepairQueue,Sheets,App}.js > kit.js
```

Edit the `.jsx` files, re-run that, and re-upload `kit.js`.

**Each screen file is wrapped in an IIFE, and must stay that way.** Classic
scripts share one global lexical scope, so two files both writing
`const { NavBar } = window.SeamlyApp_f9e883` at top level throw
`Identifier 'NavBar' has already been declared` — which kills every script after
it and renders the kit blank.

### The kit ships its own component bundle

`components.js` is built from the same `src/` as the design system, but the kit
loads **that** rather than `../../_ds_bundle.js`. This is deliberate.

The app regenerates `_ds_bundle.js` on every self-check, and that rebuild is not
ours: it exports a different set (21 components, no `px`, no `PROXY_PATTERN`), it
sweeps in `ui_kits/**/*.jsx`, and its React binding evaluated to `null` at load
time — throwing `Cannot read properties of null (reading 'useState')` before the
kit ever ran. Three separate blank-screen failures all traced back to depending
on a file the app owns and rewrites.

So the kit depends only on files it controls. `_ds_bundle.js` still exists and is
what the design agent consumes; the kit simply does not load it.

Rebuild both after changing a component:

```
esbuild src/index.js --bundle --format=iife --global-name=SeamlyKit \
  --jsx=transform --alias:react=./src/react-shim.js \
  --outfile=ui_kits/seamly-ios/components.js
```
