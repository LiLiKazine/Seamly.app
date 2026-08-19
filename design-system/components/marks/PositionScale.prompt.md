# PositionScale

Principle 4: position is always answerable. Ruled like a document edge scale, not filled like a scrubber.

```jsx
<PositionScale heightPx={15402} viewportTopPct={22} marks={marks} onScrub={setTop} />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `heightPx` | `number` |  |
| `viewportTopPct` | `number` |  |
| `viewportPct` | `number` |  |
| `marks` | `Array<{atPct,kind,label}>` |  |
| `orientation` | `"vertical"|"horizontal"` | horizontal below --vp-short |
| `onScrub` | `(pct:number)=>void` |  |
