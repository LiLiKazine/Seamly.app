import React from "react";
import { Icon } from "../foundation/Icon.jsx";
export function EmptyState({ symbol = "photo", title, body, children, style, ...rest }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center",
      gap: "var(--s-4)", padding: "var(--s-10) var(--gutter-compact)",
      textAlign: "center", ...style }} {...rest}>
      <Icon name={symbol} size={40} strokeWidth={1.2} style={{ color: "var(--ink-faint)" }} />
      <span style={{ font: "var(--type-title3)", letterSpacing: "var(--tracking-title)" }}>{title}</span>
      {body && <span style={{ font: "var(--type-footnote)", color: "var(--ink-muted)",
        maxWidth: "var(--measure)", textWrap: "pretty" }}>{body}</span>}
      {children}
    </div>
  );
}
