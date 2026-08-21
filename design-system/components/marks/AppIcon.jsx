import React from "react";

/* The Seamly app icon: "Ruled, three uneven".

   A full-bleed ink field with three horizontal joins at UNEQUAL spacing — the
   app's output, many captures deep. The middle join carries --mark-flag, the
   uncertain seam. The unequal gaps are the defence against reading as a
   barcode, and the off-centre accent is what gives the mark a top and a bottom.

   Percentages are authoritative. At 1024 the joins land at y 266 / 481 / 747,
   each 29px tall — the thinnest element, above the 20px floor, and it holds to
   29pt. Below that ship the two-rule reduction rather than letting the rhythm
   mud.

   DO NOT INVERT for dark. Field and joins come from --icon-field/--icon-join,
   which are theme-stable by design; only the accent moves, and it moves by
   itself via --mark-flag's dark scope. Inverting would make the joins read as
   cuts in a sheet, which is the opposite of the material argument.

   Drawn unmasked and full bleed — iOS applies the squircle. `masked` is for
   previews that need to show the icon as the springboard will. */

const JOINS = [
  { y: 26, fill: "var(--icon-join)" },
  { y: 47, fill: "var(--mark-flag)" },   // the uncertain seam
  { y: 73, fill: "var(--icon-join)" },
];
const JOIN_H = 2.8;

export function AppIcon({ size = 120, masked = false, title, style, ...rest }) {
  /* crispEdges: at 40px a join is barely over 1 device px, and antialiasing
     turns the rhythm to mush. The geometry is axis-aligned, so there is
     nothing to lose by snapping it. */
  const svg = (
    <svg viewBox="0 0 100 100" width={size} height={size}
      shapeRendering="crispEdges" role={title ? "img" : "presentation"}
      aria-label={title || undefined} aria-hidden={title ? undefined : "true"}
      style={masked ? undefined : { display: "block", ...style }} {...(masked ? {} : rest)}>
      <rect width="100" height="100" fill="var(--icon-field)" />
      {JOINS.map((j) => (
        <rect key={j.y} y={j.y} width="100" height={JOIN_H} fill={j.fill} />
      ))}
    </svg>
  );

  if (!masked) return svg;
  return (
    <div style={{ width: size, height: size, borderRadius: "22.37%",
      overflow: "hidden", lineHeight: 0, flex: "none", ...style }} {...rest}>
      {svg}
    </div>
  );
}
