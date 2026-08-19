(function () {
  /* The app REGENERATES _ds_bundle.js during its self-check, and that rebuild
     drops any alias we add. So bind to the namespace the app assigns, and only
     fall back to the local build's name. Never depend on the alias alone. */
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  /* Local, not from the bundle: the app's rebuild drops helper exports.
     Thin space for thousands — never a comma. */
  const px = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
/* RETURN HOME. The app is backgrounded while the user scrolls another app, so the
   most common launch context is "I just stopped a broadcast — what did I get?"
   This screen answers that before anything else: the newest capture, resolved,
   with its marks already visible and one way into fixing them.
   The dock is permanently present — the hero is never a toolbar icon. */
const { NavBar, IconButton, CaptureDock, StatusNote, EmptyState, Button, Icon } = DS;

function HomeScreen({ regular, capture, empty, onLibrary, onReview, onRepair,
                     onHelp, onCapture, onVideo, onPhotos }) {
  const marks = capture ? capture.findings.length : 0;
  const gutter = regular ? "var(--gutter-regular)" : "var(--gutter-compact)";

  if (empty) {
    return (
      <div style={{ height: "100%", display: "flex", flexDirection: "column",
        background: "var(--paper)" }}>
        <NavBar large title="Seamly" subtitle="Capture beyond the screen"
          trailing={<IconButton symbol="questionmark.circle" label="How it works" onClick={onHelp} />} />
        <div style={{ flexGrow: 1, display: "flex", flexDirection: "column",
          justifyContent: "center", padding: `0 ${gutter}` }}>
          <EmptyState symbol="plus.viewfinder" title="Nothing captured yet"
            body="Record your screen while you scroll another app, and Seamly stitches everything you reveal into one image." />
        </div>
        <div style={{ padding: `var(--s-5) ${gutter} var(--safe-bottom)` }}>
          <CaptureDock onRecord={onCapture} onVideo={onVideo} onPhotos={onPhotos} />
        </div>
      </div>
    );
  }

  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column",
      background: "var(--paper)" }}>
      <NavBar title="Seamly"
        trailing={<>
          <IconButton symbol="list.bullet" label="Library" onClick={onLibrary} />
          <IconButton symbol="questionmark.circle" label="How it works" onClick={onHelp} />
        </>} />

      <div style={{ padding: `0 ${gutter}`, display: "flex", alignItems: "baseline",
        justifyContent: "space-between", gap: "var(--s-4)" }}>
        <span style={{ font: "var(--type-largetitle)", letterSpacing: "var(--tracking-display)" }}>
          {capture.title}
        </span>
        <span style={{ font: "var(--type-mono)", color: "var(--ink-faint)",
          fontVariantNumeric: "tabular-nums" }}>
          {px(capture.widthPx)} × {px(capture.heightPx)} px
        </span>
      </div>

      <div style={{ flexGrow: 1, minHeight: 0, display: "flex",
        padding: `var(--s-5) ${gutter}`, maxWidth: regular ? 720 : "none",
        width: "100%", margin: "0 auto" }}>
        <CaptureView capture={capture} onSelect={onRepair} />
      </div>

      <div style={{ padding: `0 ${gutter}`, display: "flex", alignItems: "center",
        justifyContent: "space-between", gap: "var(--s-4)", minHeight: 44 }}>
        {marks > 0 ? (
          <>
            <span style={{ display: "flex", gap: "var(--s-3)", flexWrap: "wrap" }}>
              {flagged(capture) > 0 && <StatusNote kind="flagged" count={flagged(capture)} />}
              {gaps(capture) > 0 && <StatusNote kind="gap" count={gaps(capture)} />}
            </span>
            <Button variant="plain" onClick={onReview}>
              Review them <Icon name="arrow.right" size={16} />
            </Button>
          </>
        ) : (
          <span style={{ display: "flex", alignItems: "center", gap: "var(--s-4)", width: "100%",
            justifyContent: "space-between" }}>
            <StatusNote kind="ready" label="Every seam matched confidently" />
            <Button variant="plain" onClick={onReview}>Open</Button>
          </span>
        )}
      </div>

      <div style={{ padding: `var(--s-5) ${gutter} var(--safe-bottom)` }}>
        <CaptureDock onRecord={onCapture} onVideo={onVideo} onPhotos={onPhotos} />
      </div>
    </div>
  );
}
Object.assign(window, { HomeScreen });
})();
