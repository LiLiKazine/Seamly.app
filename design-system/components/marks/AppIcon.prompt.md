# AppIcon

The Seamly app icon — **"Ruled, three uneven"**. A full-bleed ink field with three
horizontal joins at unequal spacing: the app's output, many captures deep. The
middle join carries `--mark-flag`, the uncertain seam.

The unequal gaps are load-bearing — they are what stops it reading as a barcode —
and the off-centre accent is what gives the mark a top and a bottom.

```jsx
<AppIcon size={120} masked />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `size` | `number` | edge length in px. Ladder: 180/120/87/80/60/58/40/29 |
| `masked` | `boolean` | applies the iOS squircle. The shipped asset is **unmasked**, full bleed |
| `title` | `string` | accessible name; omit for decorative |

## Geometry

Authoritative in percentages; the 1024 column is those values at 1024.

| Element | Y | Height | @1024 | Fill |
|---|---|---|---|---|
| Field | 0 | 100% | 0 → 1024 | `--icon-field` `#1f1d1a` |
| Join 1 | 26% | 2.8% | 266, h 29 | `--icon-join` `#ece9e3` |
| Join 2 | 47% | 2.8% | 481, h 29 | `--mark-flag` `#8a6219` |
| Join 3 | 73% | 2.8% | 747, h 29 | `--icon-join` `#ece9e3` |

Thinnest element is 29px at 1024 (2.8%), above the 20px floor, and it holds to
29pt. Below that, ship a **two-rule reduction** rather than letting the rhythm mud.

## Do not invert

Dark appearance is **identical geometry, identical field, identical paper joins**.
Only the middle join changes — to `#d9a544` — so it holds its warmth against a
dark springboard.

This is why the field and joins read `--icon-field` / `--icon-join` and **not**
`--ink` / `--paper`. Those two flip under `[data-theme="dark"]`, so building on
them would invert the mark at night: the joins would become cuts in a sheet,
which reverses the material argument. `--icon-field` and `--icon-join` are
theme-stable on purpose, the same way `--sheet` is fixed white in both themes.
The accent needs no special handling — `--mark-flag` already lifts in its dark
scope.

The tinted appearance needs no asset. iOS derives grayscale, and what carries is
the value structure: dark field, light joins.
