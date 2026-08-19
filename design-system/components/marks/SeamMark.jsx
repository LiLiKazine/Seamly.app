import React from "react";

/* How a join is drawn ON the sheet. Deliberately quiet: principle 1 says a good
   capture must look like ONE IMAGE, so a confident join is nearly invisible and
   a flagged one is a thin ruled line — not a glowing bar. Findability is NOT this
   component's job; that belongs to MarginMarker and PositionScale, which sit off
   the image where contrast is guaranteed. That division is what lets a light
   ground work. */
const KIND = {
  confident: { color: "var(--seam-confident)", width: "var(--seam-width)", style: "solid" },
  flagged:   { color: "var(--seam-flag)",      width: "var(--seam-width-mark)", style: "solid" },
  gap:       { color: "var(--seam-gap)",       width: "var(--seam-width-mark)", style: "dashed" },
};

export function SeamMark({ kind = "confident", atPct = 0, lostPx, style, ...rest }) {
  const k = KIND[kind] || KIND.confident;
  return (
    <div aria-hidden="true"
      style={{ position: "absolute", left: 0, right: 0, top: `${atPct}%`,
        borderTop: `${k.width} ${k.style} ${k.color}`, pointerEvents: "none", ...style }}
      {...rest}>
      {kind === "gap" && lostPx != null && (
        <span style={{ position: "absolute", right: 6, top: 3, font: "var(--type-mono)",
          fontSize: 10, color: "var(--mark-gap)", background: "var(--sheet)",
          padding: "1px 4px", fontVariantNumeric: "tabular-nums" }}>
          {lostPx} px lost
        </span>
      )}
    </div>
  );
}
