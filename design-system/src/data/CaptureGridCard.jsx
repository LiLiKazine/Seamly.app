import React from "react";
import { StatusNote } from "./StatusNote.jsx";
import { CaptureSheet } from "./CaptureSheet.jsx";
import { px } from "./proxy.js";

/* Regular-width (iPad) library cell. A square grid cell is wrong for a 1:40 image,
   so every card is a fixed 3:5 window on the START of the capture, uniform height
   whatever the length — length is told by the ribbon and the number, never by
   cell size. The caption sits BELOW the sheet, on paper: a plate with a caption,
   not text burned over the image. */
export function CaptureGridCard({ title, widthPx = 884, heightPx = 15402, image,
                                 status = "ready", flaggedCount = 0, gapCount = 0,
                                 incomplete = false, marks = [], selected = false,
                                 onClick, style, ...rest }) {
  return (
    <button type="button" onClick={onClick}
      style={{ display: "flex", flexDirection: "column", gap: "var(--s-3)", width: "100%",
        padding: 0, background: "transparent", border: "none", cursor: "pointer",
        textAlign: "left", color: "var(--ink)", ...style }} {...rest}>
      <CaptureSheet image={image} marks={marks}
        style={{ width: "100%", aspectRatio: "3 / 5",
          outline: selected ? "2px solid var(--accent)" : "none", outlineOffset: 2 }} />
      <span style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        <span style={{ font: "var(--type-headline)" }}>{title}</span>
        <span style={{ font: "var(--type-mono)", fontSize: 11, color: "var(--ink-faint)",
          fontVariantNumeric: "tabular-nums" }}>{px(heightPx)} px</span>
        <span style={{ display: "flex", gap: "var(--s-2)", flexWrap: "wrap", marginTop: 2 }}>
          {status !== "ready" && <StatusNote kind={status} size="small" />}
          {incomplete && <StatusNote kind="incomplete" size="small" />}
          {flaggedCount > 0 && <StatusNote kind="flagged" count={flaggedCount} size="small" />}
          {gapCount > 0 && <StatusNote kind="gap" count={gapCount} size="small" />}
        </span>
      </span>
    </button>
  );
}
