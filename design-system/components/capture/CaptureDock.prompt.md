# CaptureDock

Return-home IA: permanently present, never a toolbar icon. Capped at --column-max so it does not balloon on iPad.

```jsx
<CaptureDock onRecord={start} onVideo={pickVideo} onPhotos={pickPhotos} />
```

When live capture cannot work on the device — an iPad app on a Mac, or ReplayKit reporting itself unavailable because of Screen Time, an MDM profile, AirPlay mirroring or another recorder — the hero's slot carries a sentence instead of the Record button. A Record button with nothing behind it swallows the tap in silence, and App Review read that silence as functionality hidden from them (guideline 5.6, 2026-08-27). The two import buttons stay either side of the sentence because they are exactly what it tells the user to use.

```jsx
<CaptureDock
  unavailable="Screen recording isn't available right now. Import a screen recording or screenshots instead."
  onVideo={pickVideo} onPhotos={pickPhotos} />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `onRecord` | `()=>void` |  |
| `onVideo` | `()=>void` |  |
| `onPhotos` | `()=>void` |  |
| `recording` | `boolean` |  |
| `unavailable` | `string \| null` | Replaces the Record button with this sentence. Footnote, --ink-muted, centred; always ends by naming the import alternatives. |
