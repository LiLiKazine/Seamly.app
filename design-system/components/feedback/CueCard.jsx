import React from "react";
import { Icon } from "../foundation/Icon.jsx";

/* The app's UI during a broadcast is a VIBRATION — nothing may be drawn on screen
   or it lands in the capture. So the meaning of the buzz has to be taught before
   the session and explained after it. This component is the only place that
   happens, which is why it exists at all. */
export function CueCard({ symbol = "hand.draw", when = "before", title, body,
                         style, ...rest }) {
  return (
    <div style={{ display: "flex", gap: "var(--s-5)", padding: "var(--s-5)",
      background: "var(--paper-raised)", border: "1px solid var(--rule)",
      borderRadius: "var(--radius-sm)", ...style }} {...rest}>
      <Icon name={symbol} size={28} strokeWidth={1.4}
        style={{ color: "var(--accent)", marginTop: 2 }} />
      <div style={{ display: "flex", flexDirection: "column", gap: 5, minWidth: 0 }}>
        <span style={{ font: "var(--type-caps)", textTransform: "uppercase",
          letterSpacing: "var(--tracking-caps)", color: "var(--ink-faint)" }}>
          {when === "before" ? "Before you start" : "What that buzz meant"}
        </span>
        <span style={{ font: "var(--type-headline)" }}>{title}</span>
        <span style={{ font: "var(--type-footnote)", color: "var(--ink-muted)",
          maxWidth: "var(--measure)", textWrap: "pretty" }}>{body}</span>
      </div>
    </div>
  );
}
