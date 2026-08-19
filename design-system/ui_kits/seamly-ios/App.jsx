(function () {
  /* The app REGENERATES _ds_bundle.js during its self-check, and that rebuild
     drops any alias we add. So bind to the namespace the app assigns, and only
     fall back to the local build's name. Never depend on the alias alone. */
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
/* Click-through shell. The size-class switcher is the point: compact and regular
   are two different answers, not one layout at two widths — most visible on
   Review, where regular gains a persistent findings rail. */
const FRAMES = { compact: { w: 393, h: 812 }, regular: { w: 900, h: 700 } };

function Chip({ active, children, onClick }) {
  return (
    <button type="button" onClick={onClick}
      style={{ height: 30, padding: "0 12px", borderRadius: "var(--radius-sm)",
        border: "1px solid " + (active ? "transparent" : "var(--rule)"),
        background: active ? "var(--accent)" : "transparent",
        color: active ? "var(--ink-inverse)" : "var(--ink-muted)",
        font: "var(--type-footnote)", cursor: "pointer" }}>{children}</button>
  );
}

function App() {
  const [sizeClass, setSizeClass] = React.useState("compact");
  const [theme, setTheme] = React.useState("light");
  const [screen, setScreen] = React.useState("home");
  const [id, setId] = React.useState("c1");
  const [startAt, setStartAt] = React.useState(1);
  const [overlay, setOverlay] = React.useState(null);
  const [empty, setEmpty] = React.useState(false);
  const [imp, setImp] = React.useState(null);

  /* Import advances reading -> stitching -> done. The two phases are deliberately
     different: reading has a real percentage, stitching does not. */
  React.useEffect(() => {
    if (!imp || imp.error || imp.phase === "done") return;
    const t = setTimeout(() => setImp((v) => {
      if (!v) return v;
      if (v.phase === "reading") {
        const next = v.progress + 0.22;
        if (next < 1) return Object.assign({}, v, { progress: next });
        if (v.failNext)
          return Object.assign({}, v, { error: "Couldn't read that video — Seamly may not be able to decode this format. Try a different recording?" });
        return Object.assign({}, v, { phase: "stitching", progress: 1, frames: 9 });
      }
      return Object.assign({}, v, { phase: "done" });
    }), 750);
    return () => clearTimeout(t);
  }, [imp]);

  const startImport = (source, failNext) =>
    setImp({ source: source, phase: "reading", progress: 0.12, frames: 0, failNext: failNext });

  const regular = sizeClass === "regular";
  const frame = FRAMES[sizeClass];
  const capture = CAPTURES.find((c) => c.id === id) || CAPTURES[0];

  React.useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
  }, [theme]);

  const body = () => {
    switch (screen) {
      case "library":
        return <LibraryScreen regular={regular} captures={CAPTURES}
          onOpen={(c) => { setId(c.id); setScreen("review"); }}
          onBack={() => setScreen("home")} onCapture={() => setScreen("firstrun")}
          onVideo={() => startImport("video")} onPhotos={() => startImport("photos")} />;
      case "review":
        return <ReviewScreen regular={regular} capture={capture}
          onBack={() => setScreen("library")}
          onRepair={(n) => { setStartAt(n); setScreen("repair"); }}
          onExport={() => setOverlay("export")} />;
      case "repair":
        return <RepairQueue regular={regular} capture={capture} startAt={startAt}
          onDone={() => setScreen("review")} onClose={() => setScreen("review")} />;
      case "firstrun":
        return <FirstRun onDone={() => setScreen("home")} />;
      default:
        return <HomeScreen regular={regular} capture={capture} empty={empty}
          onLibrary={() => setScreen("library")}
          onReview={() => setScreen("review")}
          onRepair={(n) => { setStartAt(n); setScreen("repair"); }}
          onHelp={() => setScreen("firstrun")}
          onCapture={() => setScreen("firstrun")}
          onVideo={() => startImport("video")} onPhotos={() => startImport("photos")} />;
    }
  };

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column",
      alignItems: "center", gap: 16, padding: 20,
      background: theme === "dark" ? "#0d0c0b" : "#d9d5cd" }}>
      <div style={{ display: "flex", gap: 18, alignItems: "center", flexWrap: "wrap",
        justifyContent: "center" }}>
        <div style={{ display: "flex", gap: 6 }}>
          <Chip active={!regular} onClick={() => setSizeClass("compact")}>Compact · iPhone</Chip>
          <Chip active={regular} onClick={() => setSizeClass("regular")}>Regular · iPad</Chip>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          {["home", "library", "review", "repair", "firstrun"].map((s) => (
            <Chip key={s} active={screen === s} onClick={() => { setScreen(s); setOverlay(null); }}>
              {s === "firstrun" ? "first run" : s}
            </Chip>
          ))}
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          <Chip active={!!imp} onClick={() => startImport("video")}>Import</Chip>
          {imp && !imp.error && imp.phase !== "done" && (
            <Chip onClick={() => setImp(Object.assign({}, imp, { failNext: true }))}>Make it fail</Chip>
          )}
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          <Chip active={theme === "light"} onClick={() => setTheme("light")}>Desk</Chip>
          <Chip active={theme === "dark"} onClick={() => setTheme("dark")}>Night desk</Chip>
          {screen === "home" && (
            <Chip active={empty} onClick={() => setEmpty(!empty)}>First launch</Chip>
          )}
        </div>
      </div>

      <div style={{ width: frame.w, height: frame.h, position: "relative",
        overflow: "hidden", background: "var(--paper)",
        borderRadius: 10, boxShadow: "0 20px 60px -24px rgba(0,0,0,.55), 0 0 0 1px rgba(0,0,0,.18)",
        transition: "width var(--dur-base) var(--ease-standard)" }}>
        {body()}
        {imp && (
          <div style={{ position: "absolute", inset: 0, display: "flex",
            flexDirection: "column", justifyContent: "flex-end",
            background: "rgba(31,29,26,.34)" }}>
            <div style={{ maxHeight: "72%" }}>
              <ImportSheet source={imp.source} phase={imp.phase} progress={imp.progress}
                frames={imp.frames} error={imp.error}
                onCancel={() => setImp(null)}
                onRetry={() => startImport(imp.source)}
                onOpen={() => { setImp(null); setId("c1"); setScreen("review"); }} />
            </div>
          </div>
        )}
        {overlay === "export" && (
          <div style={{ position: "absolute", inset: 0, display: "flex",
            flexDirection: "column", justifyContent: "flex-end",
            background: "rgba(31,29,26,.34)" }} onClick={() => setOverlay(null)}>
            <div onClick={(e) => e.stopPropagation()} style={{ maxHeight: "72%" }}>
              <ExportSheet capture={capture} onClose={() => setOverlay(null)} />
            </div>
          </div>
        )}
      </div>

      <div style={{ font: "var(--type-caption)", color: theme === "dark" ? "#7d766c" : "#6b665e",
        fontFamily: "var(--font-ui)" }}>
        {regular
          ? "Regular width: Review gains a persistent findings rail; Library becomes a 3:5 grid."
          : "Compact width: findings sit under the capture; tapping a margin marker jumps without a screen change."}
      </div>
    </div>
  );
}

Object.assign(window, { App });

})();
