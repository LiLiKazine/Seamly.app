# CaptureSheet

Top-anchored crop — principle 3. Never centre-crop a 1:40 image. The white sheet edge is what separates capture from app.

```jsx
<CaptureSheet image={proxy} marks={marks} style={{width:46,height:62}} />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `image` | `string` |  |
| `ribbon` | `boolean` | the whole capture squeezed, showing length |
| `marks` | `Array<{atPct,kind}>` | ticks on the ribbon |
