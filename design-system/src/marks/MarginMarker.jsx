import React from "react";

/* THE answer to the paper direction's one real weakness.

   On a light ground a thin rule over white captured content can be missed. So the
   signal does not live on the image — it lives in the MARGIN, where the ground is
   always paper and contrast is guaranteed regardless of what was captured. A
   numbered ring, a proof-reader's mark: legible, countable, and tappable, and it
   ties the mark on the sheet to its row in the queue by number. */
export function MarginMarker({ n, kind = "flagged", atPct = 0, selected = false,
                              onClick, style, ...rest }) {
  const color = kind === "gap" ? "var(--mark-gap)"
    : kind === "confident" ? "var(--ink-faint)" : "var(--mark-flag)";
  return (
    <button type="button" onClick={onClick} aria-label={`Mark ${n}`}
      style={{ position: "absolute", top: `${atPct}%`, left: 0,
        width: 24, height: 24, marginTop: -12, borderRadius: "var(--radius-pill)",
        background: selected ? color : "var(--paper)",
        color: selected ? "var(--sheet)" : color,
        border: `1.5px solid ${color}`, font: "var(--type-caps)",
        fontVariantNumeric: "tabular-nums", display: "grid", placeItems: "center",
        cursor: "pointer", padding: 0,
        transition: "background var(--dur-press) var(--ease-standard)", ...style }}
      {...rest}>
      {n}
    </button>
  );
}
