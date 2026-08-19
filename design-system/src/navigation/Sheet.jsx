import React from "react";

/* Paper sheets slide up as paper: a square top edge with a rule, not a big
   rounded glass card. Radius stays small so it reads as a sheet, not a bubble. */
export function Sheet({ title, leading, trailing, children, style, ...rest }) {
  return (
    <section style={{ background: "var(--paper)", borderTop: "1px solid var(--rule-strong)",
      borderTopLeftRadius: "var(--radius-lg)", borderTopRightRadius: "var(--radius-lg)",
      boxShadow: "var(--lift-modal)", display: "flex", flexDirection: "column",
      overflow: "hidden", ...style }} {...rest}>
      <header style={{ display: "flex", alignItems: "center", gap: "var(--s-4)",
        padding: "var(--s-4) var(--gutter-compact)", borderBottom: "1px solid var(--rule-faint)",
        minHeight: 56 }}>
        <div style={{ flex: "1 0 0", display: "flex", justifyContent: "flex-start" }}>{leading}</div>
        <span style={{ font: "var(--type-headline)" }}>{title}</span>
        <div style={{ flex: "1 0 0", display: "flex", justifyContent: "flex-end" }}>{trailing}</div>
      </header>
      <div style={{ flexGrow: 1, overflow: "auto" }}>{children}</div>
    </section>
  );
}
