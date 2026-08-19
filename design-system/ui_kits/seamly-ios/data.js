/* One sample capture with two real problems in it, plus a clean one — so every
   screen can be seen in both its "needs a look" and "nothing to fix" state. */
const CAPTURES = [
  /* REAL capture: 7 device frames from StitchKit's own RealDevice fixtures, run
     through BatchStitcher. 884 × 9927 px. Every number below comes from the
     engine, not from imagination — 3 segment breaks (lost lock), only 3 seams
     recovered from 7 frames, and 2 of 4 content bands with undetected chrome,
     which is why the iOS status bar is sitting in the middle of the image.
     NOT a typical capture: these fixtures come from a known-broken recording
     with fast-flick gaps (tracked as a withKnownIssue in the app repo), so it
     over-states how often lock is lost. It earns its place as the BAD case —
     proof the design stays calm when a capture comes back rough. */
  { id: "c1", title: "Today", widthPx: 884, heightPx: 9927, frames: 7,
    image: "real-capture.jpg",
    marks: [
      { atPct: 7.5, kind: "confident" },
      { atPct: 9.0, kind: "flagged", n: 4 },
      { atPct: 11.0, kind: "confident" },
      { atPct: 19.3, kind: "gap", n: 1, lostPx: "lost lock" },
      { atPct: 22.5, kind: "confident" },
      { atPct: 49.6, kind: "gap", n: 2, lostPx: "lost lock" },
      { atPct: 59.0, kind: "flagged", n: 5 },
      { atPct: 68.9, kind: "gap", n: 3, lostPx: "lost lock" },
    ],
    findings: [
      { n: 1, kind: "gap", atPct: 19.3, title: "Gap after frame 1",
        question: "Recapture this stretch?",
        detail: "Tracking was lost here, so this content was never revealed.", dy: null },
      { n: 2, kind: "gap", atPct: 49.6, title: "Gap after frame 4",
        question: "Recapture this stretch?",
        detail: "Tracking was lost here, so this content was never revealed.", dy: null },
      { n: 3, kind: "gap", atPct: 68.9, title: "Gap after frame 5",
        question: "Recapture this stretch?",
        detail: "Tracking was lost here, so this content was never revealed.", dy: null },
      { n: 4, kind: "flagged", atPct: 9.0, title: "Bars uncertain — section 1",
        question: "Where do the bars end?",
        detail: "Bars weren't detected confidently here — set the crop.", dy: 0, conf: 0.41 },
      { n: 5, kind: "flagged", atPct: 59.0, title: "Bars uncertain — section 3",
        question: "Where do the bars end?",
        detail: "Bars weren't detected confidently here — set the crop.", dy: 0, conf: 0.44 },
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
