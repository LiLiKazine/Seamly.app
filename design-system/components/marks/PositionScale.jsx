import React from "react";

/* Principle 4: position is always answerable. The entire capture squeezed into a
   ruled scale, with the viewport as a bracket and every mark as a tick. Ruled,
   not filled — a document's edge scale rather than a video scrubber.
   Goes horizontal below --vp-short, where a vertical scale would eat the little
   height a landscape viewport has. */
export function PositionScale({ heightPx, viewportTopPct = 0, viewportPct = 14,
                               marks = [], orientation = "vertical", onScrub,
                               style, ...rest }) {
  const h = orientation === "horizontal";
  const tone = { flagged: "var(--mark-flag)", gap: "var(--mark-gap)", confident: "var(--rule-strong)" };

  const scrub = (e) => {
    if (!onScrub) return;
    const r = e.currentTarget.getBoundingClientRect();
    const pct = h ? ((e.clientX - r.left) / r.width) * 100 : ((e.clientY - r.top) / r.height) * 100;
    onScrub(Math.max(0, Math.min(100, pct)));
  };

  return (
    <div onClick={scrub} role="slider" aria-label="Position in capture"
      aria-valuenow={Math.round(viewportTopPct)} aria-valuemin={0} aria-valuemax={100}
      style={{ position: "relative", flex: "none",
        width: h ? "100%" : "var(--scale-rail)", height: h ? "var(--scale-rail)" : "100%",
        cursor: onScrub ? (h ? "ew-resize" : "ns-resize") : "default",
        [h ? "borderTop" : "borderLeft"]: "1px solid var(--rule)", ...style }}
      {...rest}>
      {/* graduations every 10% — a scale, so it reads as measurement */}
      {Array.from({ length: 11 }, (_, i) => (
        <span key={i} aria-hidden="true" style={{ position: "absolute",
          background: "var(--rule)",
          ...(h ? { left: `${i * 10}%`, top: 0, width: 1, height: i % 5 ? 4 : 8 }
                : { top: `${i * 10}%`, left: 0, height: 1, width: i % 5 ? 4 : 8 }) }} />
      ))}
      {marks.map((m, i) => (
        <span key={i} title={m.label} aria-hidden="true" style={{ position: "absolute",
          background: tone[m.kind] || tone.confident,
          ...(h ? { left: `${m.atPct}%`, top: 0, width: 2, height: "100%" }
                : { top: `${m.atPct}%`, left: 0, height: 2, width: "100%" }) }} />
      ))}
      <span aria-hidden="true" style={{ position: "absolute",
        border: "1.5px solid var(--accent)", borderRadius: 1,
        background: "var(--accent-wash)",
        transition: `${h ? "left" : "top"} var(--dur-jump) var(--ease-out)`,
        ...(h ? { left: `${viewportTopPct}%`, width: `${viewportPct}%`, top: 0, bottom: 0 }
              : { top: `${viewportTopPct}%`, height: `${viewportPct}%`, left: 0, right: 0 }) }} />
    </div>
  );
}
