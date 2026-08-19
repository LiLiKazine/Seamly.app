# QueuePrompt

The repair model. One question at a time, zoomed to the problem. The affirmative answer is the wide primary button because most flagged seams are actually fine — the common case must be one tap.

```jsx
<QueuePrompt index={1} total={3} question="Does this line up?" onAccept={next} />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `index` | `number` |  |
| `total` | `number` |  |
| `kind` | `"flagged"|"gap"` |  |
| `question` | `string` |  |
| `detail` | `string` |  |
| `value` | `number` | current dy |
| `onNudge` | `(dir:-1|1)=>void` |  |
| `onAccept` | `()=>void` |  |
| `onSkipAll` | `()=>void` |  |
