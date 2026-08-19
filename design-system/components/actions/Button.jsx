import React from "react";
import { Icon } from "../foundation/Icon.jsx";

/* PAPER buttons: filled is a solid ink-blue slab, tonal is a wash, plain is bare
   type. Radius is small — this is a document, not a bubble. */
const VARIANTS = {
  filled: { background: "var(--accent)", color: "var(--ink-inverse)", border: "1px solid transparent" },
  tonal:  { background: "var(--accent-wash)", color: "var(--accent)", border: "1px solid transparent" },
  outline:{ background: "transparent", color: "var(--ink)", border: "1px solid var(--rule-strong)" },
  plain:  { background: "transparent", color: "var(--accent)", border: "1px solid transparent" },
  danger: { background: "var(--wash-error)", color: "var(--mark-error)", border: "1px solid transparent" },
};
const SIZES = { small: { height: 36, font: "var(--type-footnote)", pad: "0 12px" },
                medium: { height: 44, font: "var(--type-headline)", pad: "0 18px" },
                large: { height: 52, font: "var(--type-headline)", pad: "0 22px" } };

export function Button({ variant = "filled", size = "medium", symbol, children,
                         disabled = false, onClick, style, ...rest }) {
  const v = VARIANTS[variant] || VARIANTS.filled;
  const s = SIZES[size] || SIZES.medium;
  return (
    <button type="button" onClick={onClick} disabled={disabled}
      style={{ ...v, height: s.height, font: s.font, padding: s.pad,
        minWidth: "var(--hit-min)", borderRadius: "var(--radius-sm)",
        display: "inline-flex", alignItems: "center", justifyContent: "center",
        gap: "var(--s-3)", cursor: disabled ? "default" : "pointer",
        opacity: disabled ? "var(--disabled-opacity)" : 1,
        transition: "background var(--dur-press) var(--ease-standard)", ...style }}
      {...rest}>
      {symbol && <Icon name={symbol} size={size === "small" ? 16 : 18} />}
      {children}
    </button>
  );
}
