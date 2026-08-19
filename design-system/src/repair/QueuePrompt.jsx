import React from "react";
import { Button } from "../actions/Button.jsx";
import { Icon } from "../foundation/Icon.jsx";

/* The repair model, made concrete: ONE question at a time, zoomed to the problem,
   answerable in a tap. The user never hunts through a 15 000 px image, and never
   scans a form for the control that matters.

   The affirmative answer is the WIDE, primary one — most flagged seams are
   actually fine, and the common case should be one tap. */
export function QueuePrompt({ index = 1, total = 3, kind = "flagged", question,
                             detail, value, unit = "px", onNudge, onAccept, onSkipAll,
                             children, style, ...rest }) {
  return (
    <section style={{ background: "var(--paper-raised)", borderTop: "1px solid var(--rule)",
      padding: "var(--s-5) var(--gutter-compact) var(--s-7)",
      display: "flex", flexDirection: "column", gap: "var(--s-5)", ...style }} {...rest}>

      <header style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
        <span style={{ font: "var(--type-caps)", textTransform: "uppercase",
          letterSpacing: "var(--tracking-caps)",
          color: kind === "gap" ? "var(--mark-gap)" : "var(--mark-flag)" }}>
          {kind === "gap" ? "Gap" : "Uncertain seam"}
        </span>
        <span style={{ font: "var(--type-mono)", color: "var(--ink-faint)",
          fontVariantNumeric: "tabular-nums" }}>{index} of {total}</span>
      </header>

      {children}

      <div style={{ display: "flex", flexDirection: "column", gap: "var(--s-2)" }}>
        <h2 style={{ font: "var(--type-title3)", letterSpacing: "var(--tracking-title)",
          margin: 0 }}>{question}</h2>
        {detail && <p style={{ font: "var(--type-footnote)", color: "var(--ink-muted)",
          margin: 0, maxWidth: "var(--measure)", textWrap: "pretty" }}>{detail}</p>}
      </div>

      <div style={{ display: "flex", alignItems: "stretch", gap: "var(--s-3)" }}>
        <button type="button" onClick={() => onNudge && onNudge(-1)} aria-label="Nudge up"
          style={{ width: 52, borderRadius: "var(--radius-sm)", background: "var(--paper-sunk)",
            border: "1px solid var(--rule)", color: "var(--ink)", cursor: "pointer",
            display: "grid", placeItems: "center" }}>
          <Icon name="chevron.up" size={20} />
        </button>
        <Button variant="filled" size="large" onClick={onAccept} style={{ flexGrow: 1 }}>
          Looks right
        </Button>
        <button type="button" onClick={() => onNudge && onNudge(1)} aria-label="Nudge down"
          style={{ width: 52, borderRadius: "var(--radius-sm)", background: "var(--paper-sunk)",
            border: "1px solid var(--rule)", color: "var(--ink)", cursor: "pointer",
            display: "grid", placeItems: "center" }}>
          <Icon name="chevron.down" size={20} />
        </button>
      </div>

      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        {value != null ? (
          <span style={{ font: "var(--type-mono)", color: "var(--ink-muted)",
            fontVariantNumeric: "tabular-nums" }}>dy {value > 0 ? "+" : ""}{value} {unit}</span>
        ) : <span />}
        <button type="button" onClick={onSkipAll}
          style={{ background: "none", border: "none", padding: "var(--s-2) 0",
            font: "var(--type-footnote)", color: "var(--ink-muted)", cursor: "pointer" }}>
          Skip all
        </button>
      </div>
    </section>
  );
}
