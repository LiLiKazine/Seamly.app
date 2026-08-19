import React from "react";
export function PageDots({ count = 3, index = 0, style, ...rest }) {
  return (
    <div role="tablist" aria-label="Page" style={{ display: "flex", gap: 6,
      justifyContent: "center", ...style }} {...rest}>
      {Array.from({ length: count }, (_, i) => (
        <span key={i} role="tab" aria-selected={i === index} style={{ width: i === index ? 18 : 6,
          height: 6, borderRadius: "var(--radius-pill)",
          background: i === index ? "var(--accent)" : "var(--rule-strong)",
          transition: "width var(--dur-base) var(--ease-standard)" }} />
      ))}
    </div>
  );
}
