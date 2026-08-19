# SeamMark

Drawn ON the sheet, deliberately quiet: principle 1 says a good capture must look like one image. Findability is NOT this component's job — that is MarginMarker and PositionScale.

```jsx
<SeamMark kind="flagged" atPct={38} />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `kind` | `"confident"|"flagged"|"gap"` |  |
| `atPct` | `number` | position down the sheet |
| `lostPx` | `number` | required for gap — always label what was lost |
