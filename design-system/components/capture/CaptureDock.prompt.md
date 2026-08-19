# CaptureDock

Return-home IA: permanently present, never a toolbar icon. Capped at --column-max so it does not balloon on iPad.

```jsx
<CaptureDock onRecord={start} onVideo={pickVideo} onPhotos={pickPhotos} />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `onRecord` | `()=>void` |  |
| `onVideo` | `()=>void` |  |
| `onPhotos` | `()=>void` |  |
| `recording` | `boolean` |  |
