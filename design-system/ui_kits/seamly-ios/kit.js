/* ---- CaptureView ---- */
(function() {
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  const PROXY = DS && DS.PROXY_PATTERN || "repeating-linear-gradient(180deg,#fff 0 11px,#b9c3d0 11px 16px,#fff 16px 30px,#c8d1dc 30px 35px,#fff 35px 58px,#e6ebf1 58px 96px)";
  const { CaptureSheet, SeamMark, MarginMarker, PositionScale } = DS;
  function CaptureView({
    capture,
    zoom = 1,
    top = 0,
    selected,
    onSelect,
    onScrub,
    showScale = true,
    compactScale = false
  }) {
    const screenPct = (m) => m.atPct * zoom - top;
    const visible = (p) => p >= -2 && p <= 102;
    return /* @__PURE__ */ React.createElement("div", { style: { display: "flex", flexGrow: 1, minHeight: 0, gap: "var(--s-3)" } }, /* @__PURE__ */ React.createElement("div", { style: { position: "relative", width: "var(--margin-rail)", flex: "none" } }, capture.marks.filter((m) => m.n).map((m) => {
      const p = screenPct(m);
      return visible(p) && /* @__PURE__ */ React.createElement(
        MarginMarker,
        {
          key: m.n,
          n: m.n,
          kind: m.kind,
          atPct: p,
          selected: selected === m.n,
          onClick: () => onSelect && onSelect(m.n)
        }
      );
    })), /* @__PURE__ */ React.createElement(CaptureSheet, { ribbon: false, style: { flexGrow: 1, minWidth: 0, position: "relative" } }, /* @__PURE__ */ React.createElement("div", { style: { position: "absolute", inset: 0, overflow: "hidden" } }, /* @__PURE__ */ React.createElement("div", { style: {
      position: "absolute",
      left: 0,
      right: 0,
      top: `${-top}%`,
      height: `${zoom * 100}%`,
      transition: "top var(--dur-jump) var(--ease-out), height var(--dur-jump) var(--ease-out)",
      backgroundImage: capture.image ? `url(${capture.image})` : PROXY,
      backgroundPosition: "top center",
      backgroundSize: capture.image ? "100% auto" : "auto",
      backgroundRepeat: "no-repeat",
      backgroundColor: "#fff"
    } }, capture.marks.map((m, i) => /* @__PURE__ */ React.createElement(SeamMark, { key: i, kind: m.kind, atPct: m.atPct, lostPx: m.lostPx }))))), showScale && /* @__PURE__ */ React.createElement(
      PositionScale,
      {
        heightPx: capture.heightPx,
        viewportTopPct: top,
        viewportPct: 100 / zoom,
        marks: capture.marks.filter((m) => m.n).map((m) => ({ atPct: m.atPct, kind: m.kind })),
        orientation: compactScale ? "horizontal" : "vertical",
        onScrub
      }
    ));
  }
  Object.assign(window, { CaptureView });
})();
/* ---- HomeScreen ---- */
(function() {
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  const px = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  const { NavBar, IconButton, CaptureDock, StatusNote, EmptyState, Button, Icon } = DS;
  function HomeScreen({
    regular,
    capture,
    empty,
    onLibrary,
    onReview,
    onRepair,
    onHelp,
    onCapture,
    onVideo,
    onPhotos
  }) {
    const marks = capture ? capture.findings.length : 0;
    const gutter = regular ? "var(--gutter-regular)" : "var(--gutter-compact)";
    if (empty) {
      return /* @__PURE__ */ React.createElement("div", { style: {
        height: "100%",
        display: "flex",
        flexDirection: "column",
        background: "var(--paper)"
      } }, /* @__PURE__ */ React.createElement(
        NavBar,
        {
          large: true,
          title: "Seamly",
          subtitle: "Capture beyond the screen",
          trailing: /* @__PURE__ */ React.createElement(IconButton, { symbol: "questionmark.circle", label: "How it works", onClick: onHelp })
        }
      ), /* @__PURE__ */ React.createElement("div", { style: {
        flexGrow: 1,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: `0 ${gutter}`
      } }, /* @__PURE__ */ React.createElement(
        EmptyState,
        {
          symbol: "plus.viewfinder",
          title: "Nothing captured yet",
          body: "Record your screen while you scroll another app, and Seamly stitches everything you reveal into one image."
        }
      )), /* @__PURE__ */ React.createElement("div", { style: { padding: `var(--s-5) ${gutter} var(--safe-bottom)` } }, /* @__PURE__ */ React.createElement(CaptureDock, { onRecord: onCapture, onVideo, onPhotos })));
    }
    return /* @__PURE__ */ React.createElement("div", { style: {
      height: "100%",
      display: "flex",
      flexDirection: "column",
      background: "var(--paper)"
    } }, /* @__PURE__ */ React.createElement(
      NavBar,
      {
        title: "Seamly",
        trailing: /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement(IconButton, { symbol: "list.bullet", label: "Library", onClick: onLibrary }), /* @__PURE__ */ React.createElement(IconButton, { symbol: "questionmark.circle", label: "How it works", onClick: onHelp }))
      }
    ), /* @__PURE__ */ React.createElement("div", { style: {
      padding: `0 ${gutter}`,
      display: "flex",
      alignItems: "baseline",
      justifyContent: "space-between",
      gap: "var(--s-4)"
    } }, /* @__PURE__ */ React.createElement("span", { style: { font: "var(--type-largetitle)", letterSpacing: "var(--tracking-display)" } }, capture.title), /* @__PURE__ */ React.createElement("span", { style: {
      font: "var(--type-mono)",
      color: "var(--ink-faint)",
      fontVariantNumeric: "tabular-nums"
    } }, px(capture.widthPx), " \xD7 ", px(capture.heightPx), " px")), /* @__PURE__ */ React.createElement("div", { style: {
      flexGrow: 1,
      minHeight: 0,
      display: "flex",
      padding: `var(--s-5) ${gutter}`,
      maxWidth: regular ? 720 : "none",
      width: "100%",
      margin: "0 auto"
    } }, /* @__PURE__ */ React.createElement(CaptureView, { capture, onSelect: onRepair })), /* @__PURE__ */ React.createElement("div", { style: {
      padding: `0 ${gutter}`,
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: "var(--s-4)",
      minHeight: 44
    } }, marks > 0 ? /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("span", { style: { display: "flex", gap: "var(--s-3)", flexWrap: "wrap" } }, flagged(capture) > 0 && /* @__PURE__ */ React.createElement(StatusNote, { kind: "flagged", count: flagged(capture) }), gaps(capture) > 0 && /* @__PURE__ */ React.createElement(StatusNote, { kind: "gap", count: gaps(capture) })), /* @__PURE__ */ React.createElement(Button, { variant: "plain", onClick: onReview }, "Review them ", /* @__PURE__ */ React.createElement(Icon, { name: "arrow.right", size: 16 }))) : /* @__PURE__ */ React.createElement("span", { style: {
      display: "flex",
      alignItems: "center",
      gap: "var(--s-4)",
      width: "100%",
      justifyContent: "space-between"
    } }, /* @__PURE__ */ React.createElement(StatusNote, { kind: "ready", label: "Every seam matched confidently" }), /* @__PURE__ */ React.createElement(Button, { variant: "plain", onClick: onReview }, "Open"))), /* @__PURE__ */ React.createElement("div", { style: { padding: `var(--s-5) ${gutter} var(--safe-bottom)` } }, /* @__PURE__ */ React.createElement(CaptureDock, { onRecord: onCapture, onVideo, onPhotos })));
  }
  Object.assign(window, { HomeScreen });
})();
/* ---- LibraryScreen ---- */
(function() {
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  const { NavBar, IconButton, CaptureListRow, CaptureGridCard, CaptureDock, ImportRow } = DS;
  function LibraryScreen({ regular, captures, onOpen, onBack, onCapture, onVideo, onPhotos }) {
    const gutter = regular ? "var(--gutter-regular)" : "var(--gutter-compact)";
    return /* @__PURE__ */ React.createElement("div", { style: {
      height: "100%",
      display: "flex",
      flexDirection: "column",
      background: "var(--paper)"
    } }, /* @__PURE__ */ React.createElement(
      NavBar,
      {
        large: true,
        title: "Library",
        subtitle: `${captures.length} captures`,
        onBack,
        backLabel: "",
        trailing: /* @__PURE__ */ React.createElement(IconButton, { symbol: "plus.viewfinder", label: "Capture", onClick: onCapture })
      }
    ), /* @__PURE__ */ React.createElement("div", { style: { flexGrow: 1, overflow: "auto", padding: `0 ${gutter} var(--s-8)` } }, regular ? /* @__PURE__ */ React.createElement("div", { style: {
      display: "grid",
      gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))",
      gap: "var(--s-7)",
      paddingTop: "var(--s-5)"
    } }, captures.map((c) => /* @__PURE__ */ React.createElement(
      CaptureGridCard,
      {
        key: c.id,
        title: c.title,
        widthPx: c.widthPx,
        heightPx: c.heightPx,
        image: c.image,
        marks: c.marks.filter((m) => m.n),
        flaggedCount: flagged(c),
        gapCount: gaps(c),
        incomplete: c.incomplete,
        onClick: () => onOpen(c)
      }
    ))) : /* @__PURE__ */ React.createElement("div", null, captures.map((c) => /* @__PURE__ */ React.createElement(
      CaptureListRow,
      {
        key: c.id,
        title: c.title,
        widthPx: c.widthPx,
        heightPx: c.heightPx,
        image: c.image,
        marks: c.marks.filter((m) => m.n),
        flaggedCount: flagged(c),
        gapCount: gaps(c),
        incomplete: c.incomplete,
        onClick: () => onOpen(c)
      }
    )), /* @__PURE__ */ React.createElement("div", { style: { marginTop: "var(--s-7)" } }, /* @__PURE__ */ React.createElement("div", { style: {
      font: "var(--type-caps)",
      textTransform: "uppercase",
      letterSpacing: "var(--tracking-caps)",
      color: "var(--ink-faint)",
      marginBottom: "var(--s-3)"
    } }, "Or start from something you already have"), /* @__PURE__ */ React.createElement(ImportRow, { symbol: "film", title: "From Video", detail: "Stitch an existing screen recording" }), /* @__PURE__ */ React.createElement(ImportRow, { symbol: "photo.on.rectangle", title: "From Photos", detail: "Pick overlapping screenshots" })))), /* @__PURE__ */ React.createElement("div", { style: { padding: `var(--s-5) ${gutter} var(--safe-bottom)` } }, /* @__PURE__ */ React.createElement(CaptureDock, { onRecord: onCapture, onVideo, onPhotos })));
  }
  Object.assign(window, { LibraryScreen });
})();
/* ---- ReviewScreen ---- */
(function() {
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  const px = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  const { NavBar, IconButton, Button, StatusNote, Icon } = DS;
  function FindingLine({ f, selected, onClick }) {
    const color = f.kind === "gap" ? "var(--mark-gap)" : "var(--mark-flag)";
    return /* @__PURE__ */ React.createElement(
      "button",
      {
        type: "button",
        onClick,
        style: {
          display: "flex",
          gap: "var(--s-4)",
          alignItems: "flex-start",
          width: "100%",
          padding: "var(--s-4)",
          textAlign: "left",
          cursor: "pointer",
          background: selected ? "var(--accent-wash)" : "transparent",
          border: "none",
          borderBottom: "1px solid var(--rule-faint)",
          color: "var(--ink)"
        }
      },
      /* @__PURE__ */ React.createElement("span", { style: {
        width: 22,
        height: 22,
        flex: "none",
        borderRadius: "var(--radius-pill)",
        border: `1.5px solid ${color}`,
        color,
        font: "var(--type-caps)",
        display: "grid",
        placeItems: "center",
        marginTop: 1
      } }, f.n),
      /* @__PURE__ */ React.createElement("span", { style: { display: "flex", flexDirection: "column", gap: 3, minWidth: 0 } }, /* @__PURE__ */ React.createElement("span", { style: { font: "var(--type-subheadline)" } }, f.title), /* @__PURE__ */ React.createElement("span", { style: {
        font: "var(--type-mono)",
        fontSize: 11,
        color: "var(--ink-faint)",
        fontVariantNumeric: "tabular-nums"
      } }, f.dy != null ? `dy ${f.dy > 0 ? "+" : ""}${f.dy} px` : "never revealed", f.conf != null ? ` \xB7 conf ${f.conf}` : ""))
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
      setSelected(n);
      setZoom(3);
      setTop(Math.max(0, Math.min(200, f.atPct * 3 - 40)));
    };
    const head = /* @__PURE__ */ React.createElement(
      NavBar,
      {
        title: capture.title,
        subtitle: `${px(capture.widthPx)} \xD7 ${px(capture.heightPx)} px \xB7 ${capture.frames} frames`,
        onBack,
        backLabel: regular ? "Library" : "",
        trailing: /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement(IconButton, { symbol: "slider.horizontal.3", label: "Repair", onClick: () => onRepair(1) }), /* @__PURE__ */ React.createElement(IconButton, { symbol: "square.and.arrow.up", label: "Export", onClick: onExport }))
      }
    );
    const stage = /* @__PURE__ */ React.createElement("div", { style: {
      flexGrow: 1,
      minHeight: 0,
      display: "flex",
      padding: `var(--s-4) ${regular ? "var(--gutter-regular)" : "var(--gutter-compact)"} var(--s-5)`
    } }, /* @__PURE__ */ React.createElement(
      CaptureView,
      {
        capture,
        zoom,
        top,
        selected,
        onSelect: jump,
        onScrub: (p) => setTop(Math.max(0, p * zoom - 20))
      }
    ));
    if (regular) {
      return /* @__PURE__ */ React.createElement("div", { style: {
        height: "100%",
        display: "grid",
        gridTemplateColumns: "1fr var(--sidebar-width)",
        background: "var(--paper)"
      } }, /* @__PURE__ */ React.createElement("div", { style: { display: "flex", flexDirection: "column", minWidth: 0 } }, head, stage), /* @__PURE__ */ React.createElement("aside", { style: {
        borderLeft: "1px solid var(--rule)",
        background: "var(--paper-raised)",
        display: "grid",
        gridTemplateRows: "auto 1fr auto",
        minWidth: 0
      } }, /* @__PURE__ */ React.createElement("div", { style: { padding: "var(--safe-top) var(--s-5) var(--s-4)" } }, /* @__PURE__ */ React.createElement("div", { style: { font: "var(--type-title3)", letterSpacing: "var(--tracking-title)" } }, findings.length ? `${findings.length} to look at` : "Nothing to fix"), /* @__PURE__ */ React.createElement("div", { style: {
        font: "var(--type-footnote)",
        color: "var(--ink-muted)",
        marginTop: 4,
        textWrap: "pretty"
      } }, findings.length ? "Select one to jump there. \u2191 \u2193 steps between them; \u23CE opens the repair." : "Every seam matched confidently.")), /* @__PURE__ */ React.createElement("div", { style: { overflow: "auto", alignContent: "start" } }, findings.map((f) => /* @__PURE__ */ React.createElement(FindingLine, { key: f.n, f, selected: selected === f.n, onClick: () => jump(f.n) }))), /* @__PURE__ */ React.createElement("div", { style: {
        padding: "var(--s-5)",
        borderTop: "1px solid var(--rule-faint)",
        display: "flex",
        gap: "var(--s-4)"
      } }, /* @__PURE__ */ React.createElement(
        Button,
        {
          variant: "outline",
          onClick: () => onRepair(1),
          style: { flex: 1 },
          disabled: !findings.length
        },
        "Repair"
      ), /* @__PURE__ */ React.createElement(
        Button,
        {
          variant: "filled",
          symbol: "square.and.arrow.up",
          onClick: onExport,
          style: { flex: 1 }
        },
        "Export"
      ))));
    }
    return /* @__PURE__ */ React.createElement("div", { style: {
      height: "100%",
      display: "flex",
      flexDirection: "column",
      background: "var(--paper)"
    } }, head, stage, /* @__PURE__ */ React.createElement("div", { style: {
      padding: "0 var(--gutter-compact) var(--safe-bottom)",
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: "var(--s-4)",
      minHeight: 52
    } }, findings.length ? /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("span", { style: { display: "flex", gap: "var(--s-3)", flexWrap: "wrap" } }, flagged(capture) > 0 && /* @__PURE__ */ React.createElement(StatusNote, { kind: "flagged", count: flagged(capture) }), gaps(capture) > 0 && /* @__PURE__ */ React.createElement(StatusNote, { kind: "gap", count: gaps(capture) })), /* @__PURE__ */ React.createElement(Button, { variant: "filled", onClick: () => onRepair(1) }, "Review them ", /* @__PURE__ */ React.createElement(Icon, { name: "arrow.right", size: 16 }))) : /* @__PURE__ */ React.createElement(StatusNote, { kind: "ready", label: "Every seam matched confidently" })));
  }
  Object.assign(window, { ReviewScreen });
})();
/* ---- RepairQueue ---- */
(function() {
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  const { QueuePrompt, StepperRow, Button, NavBar, IconButton, EmptyState } = DS;
  function RepairQueue({ regular, capture, startAt = 1, onDone, onClose }) {
    const findings = capture.findings;
    const [i, setI] = React.useState(Math.max(0, findings.findIndex((f2) => f2.n === startAt)));
    const [dy, setDy] = React.useState({});
    const [manual, setManual] = React.useState(false);
    const [done, setDone] = React.useState([]);
    const f = findings[i];
    const gutter = regular ? "var(--gutter-regular)" : "var(--gutter-compact)";
    const advance = () => {
      const next = done.concat(f.n);
      setDone(next);
      if (i + 1 < findings.length) {
        setI(i + 1);
        setManual(false);
      } else onDone(next.length);
    };
    const nudge = (d) => setDy({ ...dy, [f.n]: (dy[f.n] != null ? dy[f.n] : f.dy || 0) + d * 2 });
    if (!f) {
      return /* @__PURE__ */ React.createElement("div", { style: { height: "100%", display: "flex", flexDirection: "column", background: "var(--paper)" } }, /* @__PURE__ */ React.createElement(NavBar, { title: "Repair", trailing: /* @__PURE__ */ React.createElement(IconButton, { symbol: "xmark", label: "Close", onClick: onClose }) }), /* @__PURE__ */ React.createElement(EmptyState, { symbol: "checkmark.seal", title: "Nothing to fix", body: "Every seam matched confidently." }));
    }
    const value = dy[f.n] != null ? dy[f.n] : f.dy;
    return /* @__PURE__ */ React.createElement("div", { style: { height: "100%", display: "flex", flexDirection: "column", background: "var(--paper)" } }, /* @__PURE__ */ React.createElement(
      NavBar,
      {
        title: "Repair",
        subtitle: `${done.length} of ${findings.length} answered`,
        trailing: /* @__PURE__ */ React.createElement(IconButton, { symbol: "xmark", label: "Close", onClick: onClose })
      }
    ), /* @__PURE__ */ React.createElement("div", { style: {
      flexGrow: 1,
      minHeight: 0,
      display: "flex",
      padding: `var(--s-3) ${gutter} var(--s-5)`,
      maxWidth: regular ? 620 : "none",
      width: "100%",
      margin: "0 auto"
    } }, /* @__PURE__ */ React.createElement(
      CaptureView,
      {
        capture,
        zoom: 6,
        top: Math.max(0, f.atPct * 6 - 42),
        selected: f.n,
        showScale: false
      }
    )), /* @__PURE__ */ React.createElement(
      QueuePrompt,
      {
        index: i + 1,
        total: findings.length,
        kind: f.kind,
        question: f.question,
        detail: f.detail,
        value,
        onNudge: nudge,
        onAccept: advance,
        onSkipAll: () => onDone(done.length),
        style: { padding: `var(--s-5) ${gutter} var(--safe-bottom)` }
      },
      !manual ? /* @__PURE__ */ React.createElement(
        "button",
        {
          type: "button",
          onClick: () => setManual(true),
          style: {
            alignSelf: "flex-start",
            background: "none",
            border: "none",
            padding: 0,
            font: "var(--type-footnote)",
            color: "var(--accent)",
            cursor: "pointer"
          }
        },
        "Adjust manually"
      ) : /* @__PURE__ */ React.createElement("div", { style: {
        background: "var(--paper)",
        border: "1px solid var(--rule)",
        borderRadius: "var(--radius-sm)",
        padding: "0 var(--s-4)"
      } }, /* @__PURE__ */ React.createElement(
        StepperRow,
        {
          label: "Offset",
          value: value || 0,
          step: 1,
          min: -4e3,
          max: 4e3,
          onChange: (v) => setDy({ ...dy, [f.n]: v })
        }
      ), /* @__PURE__ */ React.createElement(
        StepperRow,
        {
          label: "Top bar",
          value: 94,
          step: 5,
          min: 0,
          max: 600,
          hint: "Repeated chrome cropped from this segment",
          onChange: () => {
          }
        }
      ))
    ));
  }
  Object.assign(window, { RepairQueue });
})();
/* ---- Sheets ---- */
(function() {
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  const px = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  const { Sheet, Button, ImportRow, CueCard, PageDots, ProgressNote, Icon } = DS;
  function ExportSheet({ capture, onClose }) {
    return /* @__PURE__ */ React.createElement(
      Sheet,
      {
        title: "Export",
        trailing: /* @__PURE__ */ React.createElement(Button, { variant: "plain", size: "small", onClick: onClose }, "Done")
      },
      /* @__PURE__ */ React.createElement("div", { style: { padding: "var(--s-5) var(--gutter-compact) var(--s-8)" } }, /* @__PURE__ */ React.createElement("div", { style: {
        font: "var(--type-mono)",
        color: "var(--ink-faint)",
        fontVariantNumeric: "tabular-nums",
        marginBottom: "var(--s-5)"
      } }, px(capture.widthPx), " \xD7 ", px(capture.heightPx), " px", capture.findings.length ? ` \xB7 ${capture.findings.length} unanswered` : ""), /* @__PURE__ */ React.createElement("div", { style: {
        font: "var(--type-caps)",
        textTransform: "uppercase",
        letterSpacing: "var(--tracking-caps)",
        color: "var(--ink-faint)",
        marginBottom: "var(--s-3)"
      } }, "Image"), /* @__PURE__ */ React.createElement(ImportRow, { symbol: "photo", title: "Save to Photos", detail: "Full resolution PNG" }), /* @__PURE__ */ React.createElement(ImportRow, { symbol: "square.and.arrow.up", title: "Share PNG", detail: "Composited on demand" }), /* @__PURE__ */ React.createElement(ImportRow, { symbol: "doc.on.doc", title: "Copy to Clipboard" }), /* @__PURE__ */ React.createElement("div", { style: {
        font: "var(--type-caps)",
        textTransform: "uppercase",
        letterSpacing: "var(--tracking-caps)",
        color: "var(--ink-faint)",
        margin: "var(--s-7) 0 var(--s-3)"
      } }, "Document"), /* @__PURE__ */ React.createElement(ImportRow, { symbol: "doc.richtext", title: "Export PDF", detail: "Paginated for very long captures" }))
    );
  }
  const STEPS = [
    {
      symbol: "record.circle",
      title: "Tap Record, pick Seamly",
      body: "Seamly records your screen while you scroll another app. Pick Seamly in the sheet and wait for the countdown."
    },
    {
      symbol: "hand.draw",
      title: "A buzz means slow down",
      body: "Switch to the app you want and scroll at a steady pace. If you feel a buzz you are outrunning the frame rate \u2014 ease up, or scroll back a little."
    },
    {
      symbol: "checkmark.seal",
      title: "Stop and come back",
      body: "Stop from the red indicator, then return. Your capture is waiting, already stitched, with anything uncertain marked."
    }
  ];
  function FirstRun({ onDone }) {
    const [p, setP] = React.useState(0);
    const s = STEPS[p];
    const last = p === STEPS.length - 1;
    return /* @__PURE__ */ React.createElement("div", { style: {
      height: "100%",
      display: "flex",
      flexDirection: "column",
      background: "var(--paper)",
      padding: "var(--safe-top) var(--gutter-compact) var(--safe-bottom)",
      gap: "var(--s-7)"
    } }, /* @__PURE__ */ React.createElement("div", { style: {
      flexGrow: 1,
      display: "flex",
      flexDirection: "column",
      justifyContent: "center",
      gap: "var(--s-7)"
    } }, /* @__PURE__ */ React.createElement(
      CueCard,
      {
        symbol: s.symbol,
        when: p === 1 ? "before" : "before",
        title: s.title,
        body: s.body
      }
    ), p === 1 && /* @__PURE__ */ React.createElement("div", { style: {
      font: "var(--type-footnote)",
      color: "var(--ink-muted)",
      maxWidth: "var(--measure)",
      textWrap: "pretty"
    } }, "Seamly cannot show you anything while it records \u2014 a banner would be captured along with everything else. The buzz is the only signal it can send.")), /* @__PURE__ */ React.createElement(PageDots, { count: STEPS.length, index: p }), /* @__PURE__ */ React.createElement(
      Button,
      {
        variant: "filled",
        size: "large",
        onClick: () => last ? onDone() : setP(p + 1)
      },
      last ? "Get started" : "Next"
    ));
  }
  function ImportSheet({
    source = "video",
    phase = "reading",
    progress = 0.42,
    frames = 0,
    error,
    onCancel,
    onRetry,
    onOpen
  }) {
    const isVideo = source === "video";
    const done = phase === "done";
    return /* @__PURE__ */ React.createElement(
      Sheet,
      {
        title: isVideo ? "From Video" : "From Photos",
        leading: !done && /* @__PURE__ */ React.createElement(Button, { variant: "plain", size: "small", onClick: onCancel }, "Cancel"),
        trailing: done && /* @__PURE__ */ React.createElement(Button, { variant: "plain", size: "small", onClick: onOpen }, "Open")
      },
      /* @__PURE__ */ React.createElement("div", { style: {
        padding: "var(--s-6) var(--gutter-compact) var(--s-8)",
        display: "flex",
        flexDirection: "column",
        gap: "var(--s-5)"
      } }, /* @__PURE__ */ React.createElement("div", { style: { display: "flex", alignItems: "center", gap: "var(--s-4)" } }, /* @__PURE__ */ React.createElement(
        Icon,
        {
          name: isVideo ? "film" : "photo.on.rectangle",
          size: 22,
          style: { color: "var(--accent)" }
        }
      ), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", flexDirection: "column", gap: 2 } }, /* @__PURE__ */ React.createElement("span", { style: { font: "var(--type-headline)" } }, isVideo ? "Screen recording" : "6 screenshots"), /* @__PURE__ */ React.createElement("span", { style: {
        font: "var(--type-mono)",
        fontSize: 11,
        color: "var(--ink-faint)",
        fontVariantNumeric: "tabular-nums"
      } }, isVideo ? "0:48 \xB7 1 179 \xD7 2 556" : "1 179 \xD7 2 556 each"))), error ? /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("div", { style: {
        padding: "var(--s-4)",
        background: "var(--wash-error)",
        color: "var(--mark-error)",
        font: "var(--type-footnote)",
        borderRadius: "var(--radius-xs)"
      } }, error), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: "var(--s-4)" } }, /* @__PURE__ */ React.createElement(Button, { variant: "outline", onClick: onCancel, style: { flex: 1 } }, "Cancel"), /* @__PURE__ */ React.createElement(Button, { variant: "filled", onClick: onRetry, style: { flex: 1 } }, "Try again"))) : done ? /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("div", { style: {
        display: "flex",
        alignItems: "center",
        gap: "var(--s-3)",
        font: "var(--type-body)"
      } }, /* @__PURE__ */ React.createElement(Icon, { name: "checkmark", size: 18, style: { color: "var(--mark-ok)" } }), "Stitched."), /* @__PURE__ */ React.createElement("div", { style: {
        font: "var(--type-mono)",
        color: "var(--ink-muted)",
        fontVariantNumeric: "tabular-nums"
      } }, frames, " frames \xB7 884 \xD7 15 402 px")) : /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement(
        ProgressNote,
        {
          label: phase === "reading" ? "Reading video\u2026" : "Stitching\u2026",
          value: phase === "reading" ? progress : void 0
        }
      ), /* @__PURE__ */ React.createElement("div", { style: {
        font: "var(--type-footnote)",
        color: "var(--ink-muted)",
        maxWidth: "var(--measure)",
        textWrap: "pretty"
      } }, phase === "reading" ? "Decoding the recording into keyframes. Only frames that moved are kept." : "Matching each frame against the last. This has no percentage \u2014 it finishes when the seams are found."), phase === "stitching" && frames > 0 && /* @__PURE__ */ React.createElement("div", { style: {
        font: "var(--type-mono)",
        color: "var(--ink-faint)",
        fontVariantNumeric: "tabular-nums"
      } }, frames, " keyframes kept")))
    );
  }
  Object.assign(window, { ExportSheet, FirstRun, ImportSheet });
})();
/* ---- App ---- */
(function() {
  const DS = window.SeamlyKit || window.SeamlyApp_f9e883 || window.SeamlyPaper;
  const FRAMES = { compact: { w: 393, h: 812 }, regular: { w: 900, h: 700 } };
  function Chip({ active, children, onClick }) {
    return /* @__PURE__ */ React.createElement(
      "button",
      {
        type: "button",
        onClick,
        style: {
          height: 30,
          padding: "0 12px",
          borderRadius: "var(--radius-sm)",
          border: "1px solid " + (active ? "transparent" : "var(--rule)"),
          background: active ? "var(--accent)" : "transparent",
          color: active ? "var(--ink-inverse)" : "var(--ink-muted)",
          font: "var(--type-footnote)",
          cursor: "pointer"
        }
      },
      children
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
    React.useEffect(() => {
      if (!imp || imp.error || imp.phase === "done") return;
      const t = setTimeout(() => setImp((v) => {
        if (!v) return v;
        if (v.phase === "reading") {
          const next = v.progress + 0.22;
          if (next < 1) return Object.assign({}, v, { progress: next });
          if (v.failNext)
            return Object.assign({}, v, { error: "Couldn't read that video \u2014 Seamly may not be able to decode this format. Try a different recording?" });
          return Object.assign({}, v, { phase: "stitching", progress: 1, frames: 9 });
        }
        return Object.assign({}, v, { phase: "done" });
      }), 750);
      return () => clearTimeout(t);
    }, [imp]);
    const startImport = (source, failNext) => setImp({ source, phase: "reading", progress: 0.12, frames: 0, failNext });
    const regular = sizeClass === "regular";
    const frame = FRAMES[sizeClass];
    const capture = CAPTURES.find((c) => c.id === id) || CAPTURES[0];
    React.useEffect(() => {
      document.documentElement.setAttribute("data-theme", theme);
    }, [theme]);
    const body = () => {
      switch (screen) {
        case "library":
          return /* @__PURE__ */ React.createElement(
            LibraryScreen,
            {
              regular,
              captures: CAPTURES,
              onOpen: (c) => {
                setId(c.id);
                setScreen("review");
              },
              onBack: () => setScreen("home"),
              onCapture: () => setScreen("firstrun"),
              onVideo: () => startImport("video"),
              onPhotos: () => startImport("photos")
            }
          );
        case "review":
          return /* @__PURE__ */ React.createElement(
            ReviewScreen,
            {
              regular,
              capture,
              onBack: () => setScreen("library"),
              onRepair: (n) => {
                setStartAt(n);
                setScreen("repair");
              },
              onExport: () => setOverlay("export")
            }
          );
        case "repair":
          return /* @__PURE__ */ React.createElement(
            RepairQueue,
            {
              regular,
              capture,
              startAt,
              onDone: () => setScreen("review"),
              onClose: () => setScreen("review")
            }
          );
        case "firstrun":
          return /* @__PURE__ */ React.createElement(FirstRun, { onDone: () => setScreen("home") });
        default:
          return /* @__PURE__ */ React.createElement(
            HomeScreen,
            {
              regular,
              capture,
              empty,
              onLibrary: () => setScreen("library"),
              onReview: () => setScreen("review"),
              onRepair: (n) => {
                setStartAt(n);
                setScreen("repair");
              },
              onHelp: () => setScreen("firstrun"),
              onCapture: () => setScreen("firstrun"),
              onVideo: () => startImport("video"),
              onPhotos: () => startImport("photos")
            }
          );
      }
    };
    return /* @__PURE__ */ React.createElement("div", { style: {
      minHeight: "100vh",
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: 16,
      padding: 20,
      background: theme === "dark" ? "#0d0c0b" : "#d9d5cd"
    } }, /* @__PURE__ */ React.createElement("div", { style: {
      display: "flex",
      gap: 18,
      alignItems: "center",
      flexWrap: "wrap",
      justifyContent: "center"
    } }, /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: 6 } }, /* @__PURE__ */ React.createElement(Chip, { active: !regular, onClick: () => setSizeClass("compact") }, "Compact \xB7 iPhone"), /* @__PURE__ */ React.createElement(Chip, { active: regular, onClick: () => setSizeClass("regular") }, "Regular \xB7 iPad")), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: 6 } }, ["home", "library", "review", "repair", "firstrun"].map((s) => /* @__PURE__ */ React.createElement(Chip, { key: s, active: screen === s, onClick: () => {
      setScreen(s);
      setOverlay(null);
    } }, s === "firstrun" ? "first run" : s))), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: 6 } }, /* @__PURE__ */ React.createElement(Chip, { active: !!imp, onClick: () => startImport("video") }, "Import"), imp && !imp.error && imp.phase !== "done" && /* @__PURE__ */ React.createElement(Chip, { onClick: () => setImp(Object.assign({}, imp, { failNext: true })) }, "Make it fail")), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: 6 } }, /* @__PURE__ */ React.createElement(Chip, { active: theme === "light", onClick: () => setTheme("light") }, "Desk"), /* @__PURE__ */ React.createElement(Chip, { active: theme === "dark", onClick: () => setTheme("dark") }, "Night desk"), screen === "home" && /* @__PURE__ */ React.createElement(Chip, { active: empty, onClick: () => setEmpty(!empty) }, "First launch"))), /* @__PURE__ */ React.createElement("div", { style: {
      width: frame.w,
      height: frame.h,
      position: "relative",
      overflow: "hidden",
      background: "var(--paper)",
      borderRadius: 10,
      boxShadow: "0 20px 60px -24px rgba(0,0,0,.55), 0 0 0 1px rgba(0,0,0,.18)",
      transition: "width var(--dur-base) var(--ease-standard)"
    } }, body(), imp && /* @__PURE__ */ React.createElement("div", { style: {
      position: "absolute",
      inset: 0,
      display: "flex",
      flexDirection: "column",
      justifyContent: "flex-end",
      background: "rgba(31,29,26,.34)"
    } }, /* @__PURE__ */ React.createElement("div", { style: { maxHeight: "72%" } }, /* @__PURE__ */ React.createElement(
      ImportSheet,
      {
        source: imp.source,
        phase: imp.phase,
        progress: imp.progress,
        frames: imp.frames,
        error: imp.error,
        onCancel: () => setImp(null),
        onRetry: () => startImport(imp.source),
        onOpen: () => {
          setImp(null);
          setId("c1");
          setScreen("review");
        }
      }
    ))), overlay === "export" && /* @__PURE__ */ React.createElement("div", { style: {
      position: "absolute",
      inset: 0,
      display: "flex",
      flexDirection: "column",
      justifyContent: "flex-end",
      background: "rgba(31,29,26,.34)"
    }, onClick: () => setOverlay(null) }, /* @__PURE__ */ React.createElement("div", { onClick: (e) => e.stopPropagation(), style: { maxHeight: "72%" } }, /* @__PURE__ */ React.createElement(ExportSheet, { capture, onClose: () => setOverlay(null) })))), /* @__PURE__ */ React.createElement("div", { style: {
      font: "var(--type-caption)",
      color: theme === "dark" ? "#7d766c" : "#6b665e",
      fontFamily: "var(--font-ui)"
    } }, regular ? "Regular width: Review gains a persistent findings rail; Library becomes a 3:5 grid." : "Compact width: findings sit under the capture; tapping a margin marker jumps without a screen change."));
  }
  Object.assign(window, { App });
})();
