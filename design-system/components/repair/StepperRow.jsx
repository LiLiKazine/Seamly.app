import React from "react";
import { Icon } from "../foundation/Icon.jsx";

/* The ADVANCED path, never the default. Available behind "Adjust manually" for
   people who want the number; the queue is what everyone else uses.
   Tabular figures so the row does not reflow as the value steps. */
export function StepperRow({ label, value = 0, unit = "px", step = 1, min, max,
                            hint, onChange, style, ...rest }) {
  const set = (d) => {
    let v = value + d * step;
    if (min != null) v = Math.max(min, v);
    if (max != null) v = Math.min(max, v);
    onChange && onChange(v);
  };
  const btn = {
    width: 44, height: 34, display: "grid", placeItems: "center", cursor: "pointer",
    background: "transparent", border: "none", color: "var(--accent)",
  };
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "var(--s-4)",
      minHeight: "var(--hit-min)", padding: "var(--s-3) 0",
      borderBottom: "1px solid var(--rule-faint)", ...style }} {...rest}>
      <div style={{ flexGrow: 1, minWidth: 0 }}>
        <div style={{ font: "var(--type-body)" }}>{label}</div>
        {hint && <div style={{ font: "var(--type-caption)", color: "var(--ink-faint)" }}>{hint}</div>}
      </div>
      <span style={{ font: "var(--type-mono)", color: "var(--ink-muted)",
        fontVariantNumeric: "tabular-nums", minWidth: 68, textAlign: "right" }}>
        {value} {unit}
      </span>
      <div style={{ display: "flex", background: "var(--paper-sunk)",
        borderRadius: "var(--radius-sm)", border: "1px solid var(--rule)" }}>
        <button type="button" style={btn} onClick={() => set(-1)} aria-label={`Decrease ${label}`}>
          <Icon name="minus" size={16} />
        </button>
        <span style={{ width: 1, background: "var(--rule)" }} />
        <button type="button" style={btn} onClick={() => set(1)} aria-label={`Increase ${label}`}>
          <Icon name="plus" size={16} />
        </button>
      </div>
    </div>
  );
}
