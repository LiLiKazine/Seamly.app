import React from "react";

/* Icons are keyed by the SF SYMBOL NAME the Swift source will use, so a mock and
   the codebase always name the same glyph. Paths are inline — no icon font, no
   CDN, nothing to go stale or fail offline. In production use the real SF Symbol;
   never ship these paths into the Swift target. */
export const SF_PATHS = {
  "chevron.left": "M12.5 4.5 7 10l5.5 5.5",
  "chevron.right": "M7.5 4.5 13 10l-5.5 5.5",
  "chevron.up": "M4.5 12.5 10 7l5.5 5.5",
  "chevron.down": "M4.5 7.5 10 13l5.5-5.5",
  "record.circle": "M10 2.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z@M10 6.2a3.8 3.8 0 1 0 0 7.6 3.8 3.8 0 0 0 0-7.6z",
  "plus.viewfinder": "M3 7V4.5A1.5 1.5 0 0 1 4.5 3H7M13 3h2.5A1.5 1.5 0 0 1 17 4.5V7M17 13v2.5a1.5 1.5 0 0 1-1.5 1.5H13M7 17H4.5A1.5 1.5 0 0 1 3 15.5V13@M10 7.5v5M7.5 10h5",
  "film": "M2.5 4h15a1.5 1.5 0 0 1 0 0v12H2.5z@M6.5 4v12M13.5 4v12",
  "photo.on.rectangle": "M2.5 5.5h12v11h-12z@M6.5 5.5V4a1.5 1.5 0 0 1 1.5-1.5h8A1.5 1.5 0 0 1 17.5 4v9",
  "flag": "M5 17V3.5h10l-2 3 2 3H5",
  "scissors": "M7 13 15.5 3M13 13 4.5 3@M5.5 12.3a2.2 2.2 0 1 0 0 4.4 2.2 2.2 0 0 0 0-4.4z@M14.5 12.3a2.2 2.2 0 1 0 0 4.4 2.2 2.2 0 0 0 0-4.4z",
  "rectangle.dashed": "M4 3.5h3M9 3.5h2M13 3.5h3M16.5 5v3M16.5 10v2M16.5 14v2M13 16.5h3M9 16.5h2M4 16.5h3M3.5 14v2M3.5 10v2M3.5 5v3",
  "slider.horizontal.3": "M3 6h9M15 6h2M3 14h3M9 14h8@M13.5 4.2a1.8 1.8 0 1 0 0 3.6 1.8 1.8 0 0 0 0-3.6z@M7.5 12.2a1.8 1.8 0 1 0 0 3.6 1.8 1.8 0 0 0 0-3.6z",
  "square.and.arrow.up": "M10 13V3.5M6.5 7 10 3.5 13.5 7@M4.5 11v4.5a1.5 1.5 0 0 0 1.5 1.5h8a1.5 1.5 0 0 0 1.5-1.5V11",
  "doc.on.doc": "M7 7h10v10H7z@M13 7V4.5A1.5 1.5 0 0 0 11.5 3h-7A1.5 1.5 0 0 0 3 4.5v7A1.5 1.5 0 0 0 4.5 13H7",
  "doc.richtext": "M5 3h6l4 4v10a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z@M11 3v4h4@M6.5 11h7M6.5 14h4",
  "photo": "M2.5 4h15v12h-15z@M2.5 13.5 7.5 9l4 3.5 2.5-2 3.5 3@M7 8.2a1.3 1.3 0 1 0 0-2.6 1.3 1.3 0 0 0 0 2.6z",
  "checkmark": "M4.5 10.5 8 14l7.5-7.5",
  "checkmark.seal": "M10 2.5 12 4l2.4-.2.6 2.3 1.9 1.4-1 2.2 1 2.2-1.9 1.4-.6 2.3L12 15.2 10 16.8 8 15.2l-2.4.3-.6-2.3L3.1 11.8l1-2.2-1-2.2 1.9-1.4.6-2.3L8 4z@M7.2 10 9 11.8l3.8-3.8",
  "xmark": "M5.5 5.5l9 9M14.5 5.5l-9 9",
  "minus": "M5 10h10",
  "plus": "M10 5v10M5 10h10",
  "questionmark.circle": "M10 2.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z@M8 7.8a2 2 0 1 1 2.6 1.9c-.5.2-.6.6-.6 1v.6@M10 14.3h.01",
  "exclamationmark.circle": "M10 2.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z@M10 6v5M10 13.6h.01",
  "exclamationmark.triangle": "M10 3 18 16.5H2z@M10 8v4M10 14.6h.01",
  "hand.draw": "M7 10V4.5a1.5 1.5 0 0 1 3 0V9m0-1.5a1.5 1.5 0 0 1 3 0V10m0-1a1.5 1.5 0 0 1 3 0v4a4 4 0 0 1-4 4h-2a5 5 0 0 1-4-2l-2.2-3a1.5 1.5 0 0 1 2.4-1.8L7 12",
  "arrow.right": "M4 10h12M11.5 5.5 16 10l-4.5 4.5",
  "arrow.up.arrow.down": "M6 16V4M3 7l3-3 3 3@M14 4v12M11 13l3 3 3-3",
  "trash": "M4 5.5h12M8 5.5V4a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v1.5M5.5 5.5 6 16a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1l.5-10.5",
  "list.bullet": "M6 6h11M6 10h11M6 14h11@M3.4 6h.01M3.4 10h.01M3.4 14h.01",
};

/* Size tracks the adjacent text: 11/13 in captions, 17 in rows, 22 in headers,
   28-44 in empty states. */
export function Icon({ name, size = 20, strokeWidth = 1.6, style, ...rest }) {
  const raw = SF_PATHS[name];
  if (!raw) return null;
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none"
      stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round"
      strokeLinejoin="round" aria-hidden="true"
      style={{ flex: "none", display: "block", ...style }} {...rest}>
      {raw.split("@").map((d, i) => <path key={i} d={d} />)}
    </svg>
  );
}
