import React from "react";
import { PROXY_PATTERN, PROXY_PATTERN_DENSE } from "./proxy.js";

/* A capture rendered as a SHEET: white, square-cornered, its own edge and lift,
   sitting on the paper ground. Never bled to the screen edge — the edge is what
   tells you where the capture stops and the app begins, which is the job a black
   canvas does in a dark system.

   Principle 3: the crop is TOP-anchored. The middle of a 1:40 image is an
   unrecognisable slice that reads as "not stitched". The `ribbon` shows the whole
   capture squeezed, so length is legible without a misleading crop. */
export function CaptureSheet({ image, ribbon = true, marks = [], children,
                              style, ...rest }) {
  return (
    <div style={{ position: "relative", background: "var(--sheet)",
      borderRadius: "var(--radius-sheet)", boxShadow: "var(--lift-sheet)",
      overflow: "hidden", ...style }} {...rest}>
      <div style={{ position: "absolute", inset: ribbon ? "0 10px 0 0" : 0,
        background: image ? `url(${image}) top center / 100% auto no-repeat` : PROXY_PATTERN,
        backgroundColor: "#fff" }} />
      {ribbon && (
        <div style={{ position: "absolute", inset: "0 0 0 auto", width: 10,
          borderLeft: "1px solid rgba(31,29,26,.12)",
          background: image ? `url(${image}) center / 100% 100% no-repeat` : PROXY_PATTERN_DENSE,
          backgroundColor: "#fff", opacity: 0.85 }}>
          {marks.map((m, i) => (
            <span key={i} aria-hidden="true" style={{ position: "absolute", left: 0, right: 0,
              top: `${m.atPct}%`, height: 2,
              background: m.kind === "gap" ? "var(--mark-gap)" : "var(--mark-flag)" }} />
          ))}
        </div>
      )}
      {children}
    </div>
  );
}
