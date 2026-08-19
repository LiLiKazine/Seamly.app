import React from "react";
import { Icon } from "../foundation/Icon.jsx";
import { StatusNote } from "./StatusNote.jsx";
import { CaptureSheet } from "./CaptureSheet.jsx";
import { px } from "./proxy.js";

/* Compact-width library row. Ruled, not carded — a document lists things on rules. */
export function CaptureListRow({ title, widthPx = 884, heightPx = 15402, image,
                                status = "ready", flaggedCount = 0, gapCount = 0,
                                incomplete = false, marks = [], onClick, style, ...rest }) {
  return (
    <button type="button" onClick={onClick}
      style={{ display: "flex", alignItems: "center", gap: "var(--s-4)", width: "100%",
        padding: "var(--s-4) 0", background: "transparent", border: "none",
        borderBottom: "1px solid var(--rule-faint)", cursor: "pointer",
        textAlign: "left", color: "var(--ink)", ...style }} {...rest}>
      <CaptureSheet image={image} marks={marks}
        style={{ width: 46, height: 62, flex: "none" }} />
      <span style={{ display: "flex", flexDirection: "column", gap: 4, flexGrow: 1, minWidth: 0 }}>
        <span style={{ font: "var(--type-headline)" }}>{title}</span>
        <span style={{ font: "var(--type-mono)", fontSize: 11, color: "var(--ink-faint)",
          fontVariantNumeric: "tabular-nums" }}>{px(widthPx)} × {px(heightPx)} px</span>
        <span style={{ display: "flex", gap: "var(--s-2)", flexWrap: "wrap" }}>
          {status !== "ready" && <StatusNote kind={status} size="small" />}
          {incomplete && <StatusNote kind="incomplete" size="small" />}
          {flaggedCount > 0 && <StatusNote kind="flagged" count={flaggedCount} size="small" />}
          {gapCount > 0 && <StatusNote kind="gap" count={gapCount} size="small" />}
        </span>
      </span>
      <Icon name="chevron.right" size={16} style={{ color: "var(--ink-faint)" }} />
    </button>
  );
}
