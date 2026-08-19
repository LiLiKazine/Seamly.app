import React from "react";
import { Icon } from "../foundation/Icon.jsx";

export function ImportRow({ symbol, title, detail, onClick, style, ...rest }) {
  return (
    <button type="button" onClick={onClick}
      style={{ display: "flex", alignItems: "center", gap: "var(--s-4)", width: "100%",
        minHeight: 56, padding: "var(--s-3) 0", background: "transparent", border: "none",
        borderBottom: "1px solid var(--rule-faint)", cursor: "pointer", textAlign: "left",
        color: "var(--ink)", ...style }} {...rest}>
      <Icon name={symbol} size={20} style={{ color: "var(--accent)" }} />
      <span style={{ flexGrow: 1, display: "flex", flexDirection: "column", gap: 1 }}>
        <span style={{ font: "var(--type-body)" }}>{title}</span>
        {detail && <span style={{ font: "var(--type-caption)", color: "var(--ink-faint)" }}>{detail}</span>}
      </span>
      <Icon name="chevron.right" size={16} style={{ color: "var(--ink-faint)" }} />
    </button>
  );
}
