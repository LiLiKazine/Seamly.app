(function () {
  /* The app REGENERATES _ds_bundle.js during its self-check, and that rebuild
     drops any alias we add. So bind to the namespace the app assigns, and only
     fall back to the local build's name. Never depend on the alias alone. */
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  /* Local, not from the bundle: the app's rebuild drops helper exports.
     Thin space for thousands — never a comma. */
  const px = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
/* The one screen where iPad changes the design rather than scaling it.

   Compact: the capture owns the column; the findings summary sits under it and
   tapping a margin marker jumps — never a screen transition.
   Regular: a persistent rail beside the capture, so the list stays visible while
   panning 15 000 px and stepping between problems costs nothing. */
const { NavBar, IconButton, Button, StatusNote, Icon } = DS;

function FindingLine({ f, selected, onClick }) {
  const color = f.kind === "gap" ? "var(--mark-gap)" : "var(--mark-flag)";
  return (
    <button type="button" onClick={onClick}
      style={{ display: "flex", gap: "var(--s-4)", alignItems: "flex-start", width: "100%",
        padding: "var(--s-4)", textAlign: "left", cursor: "pointer",
        background: selected ? "var(--accent-wash)" : "transparent",
        border: "none", borderBottom: "1px solid var(--rule-faint)", color: "var(--ink)" }}>
      <span style={{ width: 22, height: 22, flex: "none", borderRadius: "var(--radius-pill)",
        border: `1.5px solid ${color}`, color, font: "var(--type-caps)",
        display: "grid", placeItems: "center", marginTop: 1 }}>{f.n}</span>
      <span style={{ display: "flex", flexDirection: "column", gap: 3, minWidth: 0 }}>
        <span style={{ font: "var(--type-subheadline)" }}>{f.title}</span>
        <span style={{ font: "var(--type-mono)", fontSize: 11, color: "var(--ink-faint)",
          fontVariantNumeric: "tabular-nums" }}>
          {f.dy != null ? `dy ${f.dy > 0 ? "+" : ""}${f.dy} px` : "never revealed"}
          {f.conf != null ? ` · conf ${f.conf}` : ""}
        </span>
      </span>
    </button>
  );
}

function ReviewScreen({ regular, capture, onBack, onRepair, onExport }) {
  const [selected, setSelected] = React.useState(null);
  const [zoom, setZoom] = React.useState(1);
  const [top, setTop] = React.useState(0);
  const findings = capture.findings;

  const jump = (n) => {
    const f = findings.find((x) => x.n === n);
    if (!f) return;
    setSelected(n); setZoom(3);
    setTop(Math.max(0, Math.min(200, f.atPct * 3 - 40)));
  };

  const head = (
    <NavBar title={capture.title}
      subtitle={`${px(capture.widthPx)} × ${px(capture.heightPx)} px · ${capture.frames} frames`}
      onBack={onBack} backLabel={regular ? "Library" : ""}
      trailing={<>
        <IconButton symbol="slider.horizontal.3" label="Repair" onClick={() => onRepair(1)} />
        <IconButton symbol="square.and.arrow.up" label="Export" onClick={onExport} />
      </>} />
  );

  const stage = (
    <div style={{ flexGrow: 1, minHeight: 0, display: "flex",
      padding: `var(--s-4) ${regular ? "var(--gutter-regular)" : "var(--gutter-compact)"} var(--s-5)` }}>
      <CaptureView capture={capture} zoom={zoom} top={top} selected={selected}
        onSelect={jump} onScrub={(p) => setTop(Math.max(0, p * zoom - 20))} />
    </div>
  );

  if (regular) {
    return (
      <div style={{ height: "100%", display: "grid",
        gridTemplateColumns: "1fr var(--sidebar-width)", background: "var(--paper)" }}>
        <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>{head}{stage}</div>
        <aside style={{ borderLeft: "1px solid var(--rule)", background: "var(--paper-raised)",
          display: "grid", gridTemplateRows: "auto 1fr auto", minWidth: 0 }}>
          <div style={{ padding: "var(--safe-top) var(--s-5) var(--s-4)" }}>
            <div style={{ font: "var(--type-title3)", letterSpacing: "var(--tracking-title)" }}>
              {findings.length ? `${findings.length} to look at` : "Nothing to fix"}
            </div>
            <div style={{ font: "var(--type-footnote)", color: "var(--ink-muted)",
              marginTop: 4, textWrap: "pretty" }}>
              {findings.length
                ? "Select one to jump there. ↑ ↓ steps between them; ⏎ opens the repair."
                : "Every seam matched confidently."}
            </div>
          </div>
          <div style={{ overflow: "auto", alignContent: "start" }}>
            {findings.map((f) => (
              <FindingLine key={f.n} f={f} selected={selected === f.n} onClick={() => jump(f.n)} />
            ))}
          </div>
          <div style={{ padding: "var(--s-5)", borderTop: "1px solid var(--rule-faint)",
            display: "flex", gap: "var(--s-4)" }}>
            <Button variant="outline" onClick={() => onRepair(1)} style={{ flex: 1 }}
              disabled={!findings.length}>Repair</Button>
            <Button variant="filled" symbol="square.and.arrow.up" onClick={onExport}
              style={{ flex: 1 }}>Export</Button>
          </div>
        </aside>
      </div>
    );
  }

  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column",
      background: "var(--paper)" }}>
      {head}{stage}
      <div style={{ padding: "0 var(--gutter-compact) var(--safe-bottom)",
        display: "flex", alignItems: "center", justifyContent: "space-between",
        gap: "var(--s-4)", minHeight: 52 }}>
        {findings.length ? (
          <>
            <span style={{ display: "flex", gap: "var(--s-3)", flexWrap: "wrap" }}>
              {flagged(capture) > 0 && <StatusNote kind="flagged" count={flagged(capture)} />}
              {gaps(capture) > 0 && <StatusNote kind="gap" count={gaps(capture)} />}
            </span>
            <Button variant="filled" onClick={() => onRepair(1)}>
              Review them <Icon name="arrow.right" size={16} />
            </Button>
          </>
        ) : (
          <StatusNote kind="ready" label="Every seam matched confidently" />
        )}
      </div>
    </div>
  );
}
Object.assign(window, { ReviewScreen });
})();
