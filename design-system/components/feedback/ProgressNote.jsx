import React from "react";
/* Determinate for reading a video (there is a real percentage); indeterminate
   sweep for stitching, which genuinely has none. Never fake progress. */
export function ProgressNote({ label, value, style, ...rest }) {
  const indeterminate = value == null;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--s-3)",
      padding: "var(--s-4) var(--s-5)", background: "var(--paper-raised)",
      border: "1px solid var(--rule)", borderRadius: "var(--radius-sm)", ...style }} {...rest}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <span style={{ font: "var(--type-footnote)" }}>{label}</span>
        {!indeterminate && <span style={{ font: "var(--type-mono)", color: "var(--ink-muted)",
          fontVariantNumeric: "tabular-nums" }}>{Math.round(value * 100)}%</span>}
      </div>
      <div style={{ height: 3, background: "var(--paper-sunk)", overflow: "hidden" }}>
        <div style={{ height: "100%", background: "var(--accent)",
          width: indeterminate ? "38%" : `${Math.round(value * 100)}%`,
          transition: "width var(--dur-base) var(--ease-out)" }} />
      </div>
    </div>
  );
}
