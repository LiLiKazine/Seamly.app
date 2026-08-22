# 2026-08-22 — Record did nothing: SwiftUI will not route touches into a faded representable

The dock's hero — the one way into live capture — swallowed every tap on device.
No sheet, no feedback, nothing. The pipeline behind it was fine; the touch never
arrived.

## Root cause

`CaptureDock` hid the system picker by fading it:

```swift
BroadcastPickerButton()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .opacity(0.02)          // ← the bug
```

**SwiftUI declines to deliver touches into a near-transparent
`UIViewRepresentable` host.** Its cutoff sits far above UIKit's documented 0.01
alpha floor for `hitTest`, and `0.02` was chosen against that UIKit number — the
wrong threshold for the layer that actually does the routing.

## Why nothing caught it

Every ordinary check passed while the button was dead:

| Check | Broken build | Reality |
|---|---|---|
| View present, frame correct | `bounds={{0,0},{234,52}}` | ✅ but inert |
| Internal `UIButton` resizes | `frame={{5,5},{234,52}}` `mask=18` | ✅ |
| Action wired | `touchUpInside=["buttonPressed:"]` `enabled=true` | ✅ |
| `window.hitTest(centre)` | `-> UIButton` | ✅ **lies** |
| XCUITest `isHittable` | `true` | ✅ **lies** |
| Real tap delivered | *nothing* | ❌ |

`hitTest` called by hand bypasses SwiftUI's routing and honours only UIKit's 0.01
rule, so it cheerfully returned the button. `isHittable` is built on the same
query, which is why `testHomeShowsRecordFirst` and `testLibraryListsTheCapture`
both asserted the dock's hero and both stayed green through a completely
non-functional Record button.

The failure was only visible by attaching a target to the picker's private
`UIButton` and watching whether a real tap ever produced `touchDown`. It did not
at `0.02`; it did at `1.0`. One variable, decisive flip.

## The fix

Restack rather than fade. The picker sits at the **bottom** of the `ZStack` at
full opacity and the accent slab is painted opaque **on top** of it, with
`allowsHitTesting(false)` on the covers so the touch falls through:

```
ZStack {
    BroadcastPickerButton()          // opacity 1.0, fills the slab
    RoundedRectangle(...).fill(...)  // .allowsHitTesting(false)
    HStack { icon; label }           // .allowsHitTesting(false)
}
```

Occlusion costs nothing: z-order does not affect hit-testing. This removes the
dependence on an undocumented threshold entirely, rather than tuning the magic
number up to sit near a cliff whose position Apple can move.

## The guard

Because no UI test can see this failure, the invariant is enforced in the app.
`BroadcastPickerButton` carries a `#if DEBUG` check that trips if the picker or
its representable host renders below alpha 0.95, with a message naming the
offender and the fix. It is deliberately scoped to those two views — anything
higher is a container UIKit may legitimately animate mid-transition, and checking
those would trip on a push rather than on the mistake.

Verified both ways: reintroducing `.opacity(0.02)` crashes
`testHomeShowsRecordFirst` in 3.0 s; removing it returns the suite to 9/9.

## Also corrected

The comment claiming *"the other call site in this app sizes it explicitly for
the same reason"* referred to the removed `HomeView` disc. There is only one call
site. It was reasoning cited as precedent that no longer existed.

## Not verified here

The simulator has no broadcast service, so tapping Record presents no system
sheet there and no automated run can assert the end-to-end path. Touch delivery
to the picker's own control is confirmed; **that the sheet now appears needs one
tap on real hardware.**
