import React from "react";
import { Icon } from "../foundation/Icon.jsx";

/* 44pt target always, even when the glyph is 18. `count` renders a numeral
   beside the glyph rather than a bare dot — state is never colour alone. */
export function IconButton({ symbol, label, count, tone = "ink", onClick, style, ...rest }) {
  const color = tone === "ink" ? "var(--ink-muted)" : `var(--mark-${tone})`;
  return (
    <button type="button" onClick={onClick} aria-label={label} title={label}
      style={{ minWidth: "var(--hit-min)", height: "var(--hit-min)", padding: "0 var(--s-3)",
        display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 5,
        background: "transparent", border: "none", color, cursor: "pointer",
        borderRadius: "var(--radius-sm)", ...style }} {...rest}>
      <Icon name={symbol} size={20} />
      {count != null && count > 0 && (
        <span style={{ font: "var(--type-mono)", fontVariantNumeric: "tabular-nums" }}>{count}</span>
      )}
    </button>
  );
}
