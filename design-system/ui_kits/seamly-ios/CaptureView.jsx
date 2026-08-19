(function () {
  /* The app REGENERATES _ds_bundle.js during its self-check, and that rebuild
     drops any alias we add. So bind to the namespace the app assigns, and only
     fall back to the local build's name. Never depend on the alias alone. */
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  const PROXY = (DS && DS.PROXY_PATTERN) ||
    "repeating-linear-gradient(180deg,#fff 0 11px,#b9c3d0 11px 16px,#fff 16px 30px," +
    "#c8d1dc 30px 35px,#fff 35px 58px,#e6ebf1 58px 96px)";
/* Shared by Home, Review and the repair queue: the sheet, its margin markers and
   its position scale, kept in one place so all three agree about where a mark is.

   Marks live at a percentage of the WHOLE capture. On screen a mark sits at
   `atPct * zoom - top`, so the margin marker and the rule on the sheet always
   move together — that alignment is the whole point of the margin carrying signal. */
const { CaptureSheet, SeamMark, MarginMarker, PositionScale } = DS;

function CaptureView({ capture, zoom = 1, top = 0, selected, onSelect, onScrub,
                      showScale = true, compactScale = false }) {
  const screenPct = (m) => m.atPct * zoom - top;
  const visible = (p) => p >= -2 && p <= 102;

  return (
    <div style={{ display: "flex", flexGrow: 1, minHeight: 0, gap: "var(--s-3)" }}>
      {/* left margin — always paper, so contrast never depends on the capture */}
      <div style={{ position: "relative", width: "var(--margin-rail)", flex: "none" }}>
        {capture.marks.filter((m) => m.n).map((m) => {
          const p = screenPct(m);
          return visible(p) && (
            <MarginMarker key={m.n} n={m.n} kind={m.kind} atPct={p}
              selected={selected === m.n} onClick={() => onSelect && onSelect(m.n)} />
          );
        })}
      </div>

      <CaptureSheet ribbon={false} style={{ flexGrow: 1, minWidth: 0, position: "relative" }}>
        <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
          <div style={{ position: "absolute", left: 0, right: 0, top: `${-top}%`,
            height: `${zoom * 100}%`,
            transition: "top var(--dur-jump) var(--ease-out), height var(--dur-jump) var(--ease-out)",
            backgroundImage: capture.image ? `url(${capture.image})` : PROXY,
            backgroundPosition: "top center",
            backgroundSize: capture.image ? "100% auto" : "auto",
            backgroundRepeat: "no-repeat",
            backgroundColor: "#fff" }}>
            {capture.marks.map((m, i) => (
              <SeamMark key={i} kind={m.kind} atPct={m.atPct} lostPx={m.lostPx} />
            ))}
          </div>
        </div>
      </CaptureSheet>

      {showScale && (
        <PositionScale heightPx={capture.heightPx} viewportTopPct={top}
          viewportPct={100 / zoom}
          marks={capture.marks.filter((m) => m.n).map((m) => ({ atPct: m.atPct, kind: m.kind }))}
          orientation={compactScale ? "horizontal" : "vertical"} onScrub={onScrub} />
      )}
    </div>
  );
}
Object.assign(window, { CaptureView });
})();
