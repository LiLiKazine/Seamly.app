(function () {
  /* The app REGENERATES _ds_bundle.js during its self-check, and that rebuild
     drops any alias we add. So bind to the namespace the app assigns, and only
     fall back to the local build's name. Never depend on the alias alone. */
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  /* Local, not from the bundle: the app's rebuild drops helper exports.
     Thin space for thousands — never a comma. */
  const px = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
const { Sheet, Button, ImportRow, CueCard, PageDots, ProgressNote, Icon } = DS;

/* Export. Grouped as image vs document, because that is the decision the user is
   actually making. Dimensions stated up front — numbers carry their unit. */
function ExportSheet({ capture, onClose }) {
  return (
    <Sheet title="Export"
      trailing={<Button variant="plain" size="small" onClick={onClose}>Done</Button>}>
      <div style={{ padding: "var(--s-5) var(--gutter-compact) var(--s-8)" }}>
        <div style={{ font: "var(--type-mono)", color: "var(--ink-faint)",
          fontVariantNumeric: "tabular-nums", marginBottom: "var(--s-5)" }}>
          {px(capture.widthPx)} × {px(capture.heightPx)} px
          {capture.findings.length ? ` · ${capture.findings.length} unanswered` : ""}
        </div>
        <div style={{ font: "var(--type-caps)", textTransform: "uppercase",
          letterSpacing: "var(--tracking-caps)", color: "var(--ink-faint)",
          marginBottom: "var(--s-3)" }}>Image</div>
        <ImportRow symbol="photo" title="Save to Photos" detail="Full resolution PNG" />
        <ImportRow symbol="square.and.arrow.up" title="Share PNG" detail="Composited on demand" />
        <ImportRow symbol="doc.on.doc" title="Copy to Clipboard" />
        <div style={{ font: "var(--type-caps)", textTransform: "uppercase",
          letterSpacing: "var(--tracking-caps)", color: "var(--ink-faint)",
          margin: "var(--s-7) 0 var(--s-3)" }}>Document</div>
        <ImportRow symbol="doc.richtext" title="Export PDF" detail="Paginated for very long captures" />
      </div>
    </Sheet>
  );
}

/* First run. The only place the buzz can be taught — nothing may be drawn during
   a broadcast, so its meaning has to land before the session starts. */
const STEPS = [
  { symbol: "record.circle", title: "Tap Record, pick Seamly",
    body: "Seamly records your screen while you scroll another app. Pick Seamly in the sheet and wait for the countdown." },
  { symbol: "hand.draw", title: "A buzz means slow down",
    body: "Switch to the app you want and scroll at a steady pace. If you feel a buzz you are outrunning the frame rate — ease up, or scroll back a little." },
  { symbol: "checkmark.seal", title: "Stop and come back",
    body: "Stop from the red indicator, then return. Your capture is waiting, already stitched, with anything uncertain marked." },
];

function FirstRun({ onDone }) {
  const [p, setP] = React.useState(0);
  const s = STEPS[p];
  const last = p === STEPS.length - 1;
  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column",
      background: "var(--paper)", padding: "var(--safe-top) var(--gutter-compact) var(--safe-bottom)",
      gap: "var(--s-7)" }}>
      <div style={{ flexGrow: 1, display: "flex", flexDirection: "column",
        justifyContent: "center", gap: "var(--s-7)" }}>
        <CueCard symbol={s.symbol} when={p === 1 ? "before" : "before"}
          title={s.title} body={s.body} />
        {p === 1 && (
          <div style={{ font: "var(--type-footnote)", color: "var(--ink-muted)",
            maxWidth: "var(--measure)", textWrap: "pretty" }}>
            Seamly cannot show you anything while it records — a banner would be captured
            along with everything else. The buzz is the only signal it can send.
          </div>
        )}
      </div>
      <PageDots count={STEPS.length} index={p} />
      <Button variant="filled" size="large"
        onClick={() => (last ? onDone() : setP(p + 1))}>
        {last ? "Get started" : "Next"}
      </Button>
    </div>
  );
}
/* IMPORT. The one flow with two genuinely different kinds of progress, which is
   why ProgressNote takes an optional value rather than always showing a bar:

     reading  — decoding the video into keyframes. A real percentage exists.
     stitching— matching and compositing. There is NO percentage; the work is
                data-dependent and finishes when it finishes. Showing a fake bar
                here would be lying, so it runs indeterminate and says so.

   Errors are non-accusatory and ask rather than blame, per the voice rules. */
function ImportSheet({ source = "video", phase = "reading", progress = 0.42,
                       frames = 0, error, onCancel, onRetry, onOpen }) {
  const isVideo = source === "video";
  const done = phase === "done";

  return (
    <Sheet title={isVideo ? "From Video" : "From Photos"}
      leading={!done && <Button variant="plain" size="small" onClick={onCancel}>Cancel</Button>}
      trailing={done && <Button variant="plain" size="small" onClick={onOpen}>Open</Button>}>
      <div style={{ padding: "var(--s-6) var(--gutter-compact) var(--s-8)",
        display: "flex", flexDirection: "column", gap: "var(--s-5)" }}>

        <div style={{ display: "flex", alignItems: "center", gap: "var(--s-4)" }}>
          <Icon name={isVideo ? "film" : "photo.on.rectangle"} size={22}
            style={{ color: "var(--accent)" }} />
          <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
            <span style={{ font: "var(--type-headline)" }}>
              {isVideo ? "Screen recording" : "6 screenshots"}
            </span>
            <span style={{ font: "var(--type-mono)", fontSize: 11, color: "var(--ink-faint)",
              fontVariantNumeric: "tabular-nums" }}>
              {isVideo ? "0:48 · 1 179 × 2 556" : "1 179 × 2 556 each"}
            </span>
          </div>
        </div>

        {error ? (
          <>
            <div style={{ padding: "var(--s-4)", background: "var(--wash-error)",
              color: "var(--mark-error)", font: "var(--type-footnote)",
              borderRadius: "var(--radius-xs)" }}>{error}</div>
            <div style={{ display: "flex", gap: "var(--s-4)" }}>
              <Button variant="outline" onClick={onCancel} style={{ flex: 1 }}>Cancel</Button>
              <Button variant="filled" onClick={onRetry} style={{ flex: 1 }}>Try again</Button>
            </div>
          </>
        ) : done ? (
          <>
            <div style={{ display: "flex", alignItems: "center", gap: "var(--s-3)",
              font: "var(--type-body)" }}>
              <Icon name="checkmark" size={18} style={{ color: "var(--mark-ok)" }} />
              Stitched.
            </div>
            <div style={{ font: "var(--type-mono)", color: "var(--ink-muted)",
              fontVariantNumeric: "tabular-nums" }}>
              {frames} frames · 884 × 15 402 px
            </div>
          </>
        ) : (
          <>
            <ProgressNote
              label={phase === "reading" ? "Reading video…" : "Stitching…"}
              value={phase === "reading" ? progress : undefined} />
            <div style={{ font: "var(--type-footnote)", color: "var(--ink-muted)",
              maxWidth: "var(--measure)", textWrap: "pretty" }}>
              {phase === "reading"
                ? "Decoding the recording into keyframes. Only frames that moved are kept."
                : "Matching each frame against the last. This has no percentage — it finishes when the seams are found."}
            </div>
            {phase === "stitching" && frames > 0 && (
              <div style={{ font: "var(--type-mono)", color: "var(--ink-faint)",
                fontVariantNumeric: "tabular-nums" }}>{frames} keyframes kept</div>
            )}
          </>
        )}
      </div>
    </Sheet>
  );
}

Object.assign(window, { ExportSheet, FirstRun, ImportSheet });
})();
