import React from "react";
import { Icon } from "../foundation/Icon.jsx";

/* Over a capture, chrome sits on a protection GRADIENT, never a flat scrim — a
   proxy can be any brightness and a scrim dims content the user is reading. */
export function NavBar({ title, subtitle, large = false, backLabel, onBack,
                        trailing, over = false, style, ...rest }) {
  return (
    <header style={{ display: "flex", alignItems: large ? "flex-end" : "center",
      gap: "var(--s-4)", padding: large
        ? "var(--safe-top) var(--gutter-compact) var(--s-4)"
        : "var(--safe-top) var(--s-4) var(--s-4)",
      background: over ? "var(--protect-top)" : "transparent",
      borderBottom: over || large ? "none" : "1px solid var(--rule-faint)", ...style }} {...rest}>
      {onBack && (
        <button type="button" onClick={onBack}
          style={{ display: "inline-flex", alignItems: "center", gap: 2, minHeight: "var(--hit-min)",
            background: "none", border: "none", color: "var(--accent)", cursor: "pointer",
            font: "var(--type-body)", padding: 0 }}>
          <Icon name="chevron.left" size={20} />{backLabel}
        </button>
      )}
      <div style={{ flexGrow: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2 }}>
        <span style={{ font: large ? "var(--type-largetitle)" : "var(--type-headline)",
          letterSpacing: large ? "var(--tracking-display)" : "var(--tracking-title)" }}>{title}</span>
        {subtitle && <span style={{ font: "var(--type-mono)", fontSize: 11,
          color: "var(--ink-faint)", fontVariantNumeric: "tabular-nums" }}>{subtitle}</span>}
      </div>
      {trailing && <div style={{ display: "flex", alignItems: "center", gap: 2,
        marginRight: -8 }}>{trailing}</div>}
    </header>
  );
}
