# SwiftUI feasibility — Seamly design system (Paper)

Verified by compiling `SeamlyTokens.swift`:

```
xcrun swiftc -typecheck -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) \
  -target arm64-apple-ios26.0-simulator -swift-version 6 SeamlyTokens.swift
```

Clean under Swift 6 language mode against the iOS 26.2 SDK. The port is not
speculative — it builds.

## Maps cleanly

| Token | SwiftUI |
|---|---|
| Colour, both themes | `UIColor { traits in }` → `Color`. In production move these to an asset catalog so they resolve without code. |
| The pt ladder | `Font.largeTitle` … `Font.caption2`. **This is the big win:** the ladder is Apple's, so every role inherits Dynamic Type for free. Nothing hard-codes a size. |
| Spacing scale | `CGFloat` constants. 4pt base is native. |
| Radii | `RoundedRectangle(cornerRadius:style: .continuous)` — note `.cornerRadius(_:)` gives circular, not continuous, curvature. |
| 44pt hit target | `.frame(minWidth: 44, minHeight: 44)` |
| Tabular figures | `.monospacedDigit()` |
| Protection gradient | `LinearGradient` overlay — a direct port |
| Thin-space thousands | `NumberFormatter.groupingSeparator = "\u{2009}"` |
| Size classes | `@Environment(\.horizontalSizeClass)` |

## Needs adaptation — read before building

**Line-height does not port.** CSS `line-height: 1.4` is a *multiplier*; SwiftUI's
`.lineSpacing()` is *additive leading in points*. Porting the number directly gives
the wrong result at every size, and worse as Dynamic Type scales. Either compute
`lineSpacing = (multiplier - 1) × pointSize` per text style, or accept the system
default. The mocks are the reference for intent, not for the number.

**Tracking does not scale.** `.tracking()` is absolute points. The CSS uses `em`,
which scales with the type. Acceptable on display sizes and uppercase labels (both
capped in size); do **not** apply tracking to body copy that grows with Dynamic Type.

**`--measure: 38ch` has no equivalent.** There is no `ch` unit. Explainer copy
should use `.frame(maxWidth:)` in points tuned per text style, or simply
`.fixedSize(horizontal: false, vertical: true)` and let the column do the work.
Do not convert 38ch to a magic point number and call it done.

**Do not port the breakpoints.** `--bp-regular: 700px` and `--vp-short: 500px` are
web stand-ins for something iOS already knows. Use `horizontalSizeClass` and
`verticalSizeClass`. They are also *more correct*: Split View and Stage Manager
report compact at widths the pixel breakpoint would call regular.

**Multi-shadow needs splitting.** `--lift-sheet` is two shadows; SwiftUI takes one
per `.shadow()`. The `0 1px 0` component is really a hairline, so express it as a
border overlay rather than a second shadow — that is what `seamlySheetLift()` does.

## Must not be changed in the port

- **The capture sheet is white in both themes.** `SeamlyColor.sheet` is a fixed
  value, not a semantic background. A capture has its own brightness; resolving it
  against the theme would dim the user's content in dark mode. This is the single
  easiest thing to "fix" by accident.
- **`markRec` is iOS system red** for the live broadcast indicator. Never restyle.
- **Sheets are square** (`SeamlyRadius.sheet = 0`). Rounding a document reads as a
  bubble, which is the direction's whole point.
- **State is never colour alone.** Every mark carries its word.

## Open question for the engineer

The kit's margin markers are positioned as `atPct * zoom - top` against the capture.
In SwiftUI that wants a `GeometryReader` around the sheet with the markers in an
overlay sharing the same coordinate space, so the marker and the rule on the sheet
cannot drift apart. That alignment is load-bearing — it is what lets a light ground
carry signal in the margin — so it is worth getting right before anything else in
Review is built.
