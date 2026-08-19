/* One sample capture with two real problems in it, plus a clean one — so every
   screen can be seen in both its "needs a look" and "nothing to fix" state. */
const CAPTURES = [
  { id: "c1", title: "Today", widthPx: 884, heightPx: 15402, frames: 9,
    marks: [
      { atPct: 21, kind: "confident" },
      { atPct: 38, kind: "flagged", n: 1 },
      { atPct: 55, kind: "confident" },
      { atPct: 68, kind: "gap", n: 2, lostPx: "1 200" },
      { atPct: 84, kind: "flagged", n: 3 },
    ],
    findings: [
      { n: 1, kind: "flagged", atPct: 38, title: "Seam after frame 4",
        question: "Does this line up?",
        detail: "The match here was uncertain — an ad may have loaded between frames.",
        dy: 750, conf: 0.54 },
      { n: 2, kind: "gap", atPct: 68, title: "Gap · 1 200 px",
        question: "Recapture this stretch?",
        detail: "The scroll outran the frame rate here, so this content was never revealed.",
        dy: null },
      { n: 3, kind: "flagged", atPct: 84, title: "Seam after frame 8",
        question: "Does this line up?",
        detail: "A collapsing header can shift the match by a few pixels.",
        dy: -120, conf: 0.61 },
    ] },
  { id: "c2", title: "Today", widthPx: 884, heightPx: 6210, frames: 4,
    marks: [{ atPct: 33, kind: "confident" }, { atPct: 71, kind: "confident" }],
    findings: [] },
  { id: "c3", title: "Yesterday", widthPx: 1179, heightPx: 22940, frames: 14,
    marks: [{ atPct: 44, kind: "flagged", n: 1 }], incomplete: true,
    findings: [{ n: 1, kind: "flagged", atPct: 44, title: "Seam after frame 6",
      question: "Does this line up?", detail: "", dy: 310, conf: 0.58 }] },
  { id: "c4", title: "16 August", widthPx: 884, heightPx: 4120, frames: 3,
    marks: [{ atPct: 52, kind: "confident" }], findings: [] },
];
const flagged = (c) => c.findings.filter((f) => f.kind === "flagged").length;
const gaps = (c) => c.findings.filter((f) => f.kind === "gap").length;
Object.assign(window, { CAPTURES, flagged, gaps });
