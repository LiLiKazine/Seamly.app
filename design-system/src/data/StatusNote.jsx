import React from "react";
import { Icon } from "../foundation/Icon.jsx";

/* State is NEVER colour alone: every note carries its word. A wash behind ink,
   no coloured left-border card, no bare dot. */
const KINDS = {
  ready:      { label: "Ready",      symbol: "checkmark",               tone: "ok" },
  processing: { label: "Stitching…", symbol: "list.bullet",             tone: null },
  flagged:    { label: "flagged",    symbol: "flag",                    tone: "flag" },
  gap:        { label: "gap",        symbol: "scissors",                tone: "gap" },
  incomplete: { label: "Incomplete", symbol: "exclamationmark.circle",  tone: "error" },
  bars:       { label: "bars uncertain", symbol: "rectangle.dashed",    tone: "flag" },
  failed:     { label: "Couldn't stitch", symbol: "exclamationmark.triangle", tone: "error" },
};

export function StatusNote({ kind = "ready", count, label, size = "medium", style, ...rest }) {
  const k = KINDS[kind] || KINDS.ready;
  const text = label != null ? label : (count != null ? `${count} ${k.label}` : k.label);
  const color = k.tone ? `var(--mark-${k.tone})` : "var(--ink-muted)";
  const wash = k.tone ? `var(--wash-${k.tone})` : "transparent";
  const small = size === "small";
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 5,
      height: small ? 20 : 24, padding: small ? "0 7px" : "0 9px",
      borderRadius: "var(--radius-xs)", background: wash, color,
      font: small ? "var(--type-caps)" : "var(--type-caption)",
      fontVariantNumeric: "tabular-nums", ...style }} {...rest}>
      <Icon name={k.symbol} size={small ? 11 : 13} strokeWidth={1.8} />
      {text}
    </span>
  );
}
