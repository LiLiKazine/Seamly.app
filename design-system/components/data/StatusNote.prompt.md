# StatusNote

State is never colour alone — every note carries its word.

```jsx
<StatusNote kind="flagged" count={3} size="small" />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `kind` | `"ready"|"processing"|"flagged"|"gap"|"incomplete"|"bars"|"failed"` |  |
| `count` | `number` |  |
| `label` | `string` | overrides the default word |
| `size` | `"small"|"medium"` |  |
