(function () {
  /* The app REGENERATES _ds_bundle.js during its self-check, and that rebuild
     drops any alias we add. So bind to the namespace the app assigns, and only
     fall back to the local build's name. Never depend on the alias alone. */
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
/* Repair as a QUEUE. The user never hunts a 15 000 px image: each problem is
   presented zoomed, with one question and a wide affirmative answer, because most
   flagged seams turn out fine and the common case must be one tap.
   The steppers are still here — behind "Adjust manually", where they belong. */
const { QueuePrompt, StepperRow, Button, NavBar, IconButton, EmptyState } = DS;

function RepairQueue({ regular, capture, startAt = 1, onDone, onClose }) {
  const findings = capture.findings;
  const [i, setI] = React.useState(Math.max(0, findings.findIndex((f) => f.n === startAt)));
  const [dy, setDy] = React.useState({});
  const [manual, setManual] = React.useState(false);
  const [done, setDone] = React.useState([]);

  const f = findings[i];
  const gutter = regular ? "var(--gutter-regular)" : "var(--gutter-compact)";

  const advance = () => {
    const next = done.concat(f.n);
    setDone(next);
    if (i + 1 < findings.length) { setI(i + 1); setManual(false); }
    else onDone(next.length);
  };
  const nudge = (d) => setDy({ ...dy, [f.n]: (dy[f.n] != null ? dy[f.n] : f.dy || 0) + d * 2 });

  if (!f) {
    return (
      <div style={{ height: "100%", display: "flex", flexDirection: "column", background: "var(--paper)" }}>
        <NavBar title="Repair" trailing={<IconButton symbol="xmark" label="Close" onClick={onClose} />} />
        <EmptyState symbol="checkmark.seal" title="Nothing to fix" body="Every seam matched confidently." />
      </div>
    );
  }

  const value = dy[f.n] != null ? dy[f.n] : f.dy;

  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column", background: "var(--paper)" }}>
      <NavBar title="Repair" subtitle={`${done.length} of ${findings.length} answered`}
        trailing={<IconButton symbol="xmark" label="Close" onClick={onClose} />} />

      <div style={{ flexGrow: 1, minHeight: 0, display: "flex",
        padding: `var(--s-3) ${gutter} var(--s-5)`,
        maxWidth: regular ? 620 : "none", width: "100%", margin: "0 auto" }}>
        {/* zoomed hard to the problem — the user sees the seam, not the capture */}
        <CaptureView capture={capture} zoom={6} top={Math.max(0, f.atPct * 6 - 42)}
          selected={f.n} showScale={false} />
      </div>

      <QueuePrompt index={i + 1} total={findings.length} kind={f.kind}
        question={f.question} detail={f.detail} value={value}
        onNudge={nudge} onAccept={advance} onSkipAll={() => onDone(done.length)}
        style={{ padding: `var(--s-5) ${gutter} var(--safe-bottom)` }}>
        {!manual ? (
          <button type="button" onClick={() => setManual(true)}
            style={{ alignSelf: "flex-start", background: "none", border: "none", padding: 0,
              font: "var(--type-footnote)", color: "var(--accent)", cursor: "pointer" }}>
            Adjust manually
          </button>
        ) : (
          <div style={{ background: "var(--paper)", border: "1px solid var(--rule)",
            borderRadius: "var(--radius-sm)", padding: "0 var(--s-4)" }}>
            <StepperRow label="Offset" value={value || 0} step={1} min={-4000} max={4000}
              onChange={(v) => setDy({ ...dy, [f.n]: v })} />
            <StepperRow label="Top bar" value={94} step={5} min={0} max={600}
              hint="Repeated chrome cropped from this segment" onChange={() => {}} />
          </div>
        )}
      </QueuePrompt>
    </div>
  );
}
Object.assign(window, { RepairQueue });
})();
