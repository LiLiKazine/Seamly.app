# IconButton

44pt target even with an 18px glyph. A count renders as a numeral — state is never colour alone.

```jsx
<IconButton symbol="flag" label="Marks" count={3} tone="flag" />
```

## Props

| Prop | Type | Notes |
|---|---|---|
| `symbol` | `string` | SF Symbol name |
| `label` | `string` | accessible label, required |
| `count` | `number` | renders a numeral, not a bare dot |
| `tone` | `"ink"|"flag"|"gap"|"error"` |  |
