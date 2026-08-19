(function () {
  /* The app REGENERATES _ds_bundle.js during its self-check, and that rebuild
     drops any alias we add. So bind to the namespace the app assigns, and only
     fall back to the local build's name. Never depend on the alias alone. */
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
/* Compact: a ruled list. Regular: a grid of uniform 3:5 cells — never square, and
   never sized by capture length; length is told by the ribbon and the number.
   The dock stays, because the capture affordance is permanently present. */
const { NavBar, IconButton, CaptureListRow, CaptureGridCard, CaptureDock, ImportRow } = DS;

function LibraryScreen({ regular, captures, onOpen, onBack, onCapture, onVideo, onPhotos }) {
  const gutter = regular ? "var(--gutter-regular)" : "var(--gutter-compact)";
  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column",
      background: "var(--paper)" }}>
      <NavBar large title="Library" subtitle={`${captures.length} captures`}
        onBack={onBack} backLabel=""
        trailing={<IconButton symbol="plus.viewfinder" label="Capture" onClick={onCapture} />} />

      <div style={{ flexGrow: 1, overflow: "auto", padding: `0 ${gutter} var(--s-8)` }}>
        {regular ? (
          <div style={{ display: "grid",
            gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))",
            gap: "var(--s-7)", paddingTop: "var(--s-5)" }}>
            {captures.map((c) => (
              <CaptureGridCard key={c.id} title={c.title} widthPx={c.widthPx}
                heightPx={c.heightPx} marks={c.marks.filter((m) => m.n)}
                flaggedCount={flagged(c)} gapCount={gaps(c)} incomplete={c.incomplete}
                onClick={() => onOpen(c)} />
            ))}
          </div>
        ) : (
          <div>
            {captures.map((c) => (
              <CaptureListRow key={c.id} title={c.title} widthPx={c.widthPx}
                heightPx={c.heightPx} marks={c.marks.filter((m) => m.n)}
                flaggedCount={flagged(c)} gapCount={gaps(c)} incomplete={c.incomplete}
                onClick={() => onOpen(c)} />
            ))}
            <div style={{ marginTop: "var(--s-7)" }}>
              <div style={{ font: "var(--type-caps)", textTransform: "uppercase",
                letterSpacing: "var(--tracking-caps)", color: "var(--ink-faint)",
                marginBottom: "var(--s-3)" }}>Or start from something you already have</div>
              <ImportRow symbol="film" title="From Video" detail="Stitch an existing screen recording" />
              <ImportRow symbol="photo.on.rectangle" title="From Photos" detail="Pick overlapping screenshots" />
            </div>
          </div>
        )}
      </div>

      <div style={{ padding: `var(--s-5) ${gutter} var(--safe-bottom)` }}>
        <CaptureDock onRecord={onCapture} onVideo={onVideo} onPhotos={onPhotos} />
      </div>
    </div>
  );
}
Object.assign(window, { LibraryScreen });
})();
