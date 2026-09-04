var SeamlyKit = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/index.js
  var index_exports = {};
  __export(index_exports, {
    AppIcon: () => AppIcon,
    Button: () => Button,
    CaptureDock: () => CaptureDock,
    CaptureGridCard: () => CaptureGridCard,
    CaptureListRow: () => CaptureListRow,
    CaptureSheet: () => CaptureSheet,
    CueCard: () => CueCard,
    EmptyState: () => EmptyState,
    Icon: () => Icon,
    IconButton: () => IconButton,
    ImportRow: () => ImportRow,
    MarginMarker: () => MarginMarker,
    NavBar: () => NavBar,
    PROXY_PATTERN: () => PROXY_PATTERN,
    PROXY_PATTERN_DENSE: () => PROXY_PATTERN_DENSE,
    PageDots: () => PageDots,
    PositionScale: () => PositionScale,
    ProgressNote: () => ProgressNote,
    QueuePrompt: () => QueuePrompt,
    SF_PATHS: () => SF_PATHS,
    SeamMark: () => SeamMark,
    Sheet: () => Sheet,
    StatusNote: () => StatusNote,
    StepperRow: () => StepperRow,
    px: () => px
  });

  // src/react-shim.js
  var R = globalThis.React;
  var react_shim_default = R;
  var useState = R.useState;
  var useEffect = R.useEffect;
  var useRef = R.useRef;
  var useMemo = R.useMemo;
  var useCallback = R.useCallback;
  var Fragment = R.Fragment;
  var createElement = R.createElement;

  // src/foundation/Icon.jsx
  var SF_PATHS = {
    "chevron.left": "M12.5 4.5 7 10l5.5 5.5",
    "chevron.right": "M7.5 4.5 13 10l-5.5 5.5",
    "chevron.up": "M4.5 12.5 10 7l5.5 5.5",
    "chevron.down": "M4.5 7.5 10 13l5.5-5.5",
    "record.circle": "M10 2.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z@M10 6.2a3.8 3.8 0 1 0 0 7.6 3.8 3.8 0 0 0 0-7.6z",
    "plus.viewfinder": "M3 7V4.5A1.5 1.5 0 0 1 4.5 3H7M13 3h2.5A1.5 1.5 0 0 1 17 4.5V7M17 13v2.5a1.5 1.5 0 0 1-1.5 1.5H13M7 17H4.5A1.5 1.5 0 0 1 3 15.5V13@M10 7.5v5M7.5 10h5",
    "film": "M2.5 4h15a1.5 1.5 0 0 1 0 0v12H2.5z@M6.5 4v12M13.5 4v12",
    "photo.on.rectangle": "M2.5 5.5h12v11h-12z@M6.5 5.5V4a1.5 1.5 0 0 1 1.5-1.5h8A1.5 1.5 0 0 1 17.5 4v9",
    "flag": "M5 17V3.5h10l-2 3 2 3H5",
    "scissors": "M7 13 15.5 3M13 13 4.5 3@M5.5 12.3a2.2 2.2 0 1 0 0 4.4 2.2 2.2 0 0 0 0-4.4z@M14.5 12.3a2.2 2.2 0 1 0 0 4.4 2.2 2.2 0 0 0 0-4.4z",
    "rectangle.dashed": "M4 3.5h3M9 3.5h2M13 3.5h3M16.5 5v3M16.5 10v2M16.5 14v2M13 16.5h3M9 16.5h2M4 16.5h3M3.5 14v2M3.5 10v2M3.5 5v3",
    "slider.horizontal.3": "M3 6h9M15 6h2M3 14h3M9 14h8@M13.5 4.2a1.8 1.8 0 1 0 0 3.6 1.8 1.8 0 0 0 0-3.6z@M7.5 12.2a1.8 1.8 0 1 0 0 3.6 1.8 1.8 0 0 0 0-3.6z",
    "square.and.arrow.up": "M10 13V3.5M6.5 7 10 3.5 13.5 7@M4.5 11v4.5a1.5 1.5 0 0 0 1.5 1.5h8a1.5 1.5 0 0 0 1.5-1.5V11",
    "doc.on.doc": "M7 7h10v10H7z@M13 7V4.5A1.5 1.5 0 0 0 11.5 3h-7A1.5 1.5 0 0 0 3 4.5v7A1.5 1.5 0 0 0 4.5 13H7",
    "doc.richtext": "M5 3h6l4 4v10a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z@M11 3v4h4@M6.5 11h7M6.5 14h4",
    "photo": "M2.5 4h15v12h-15z@M2.5 13.5 7.5 9l4 3.5 2.5-2 3.5 3@M7 8.2a1.3 1.3 0 1 0 0-2.6 1.3 1.3 0 0 0 0 2.6z",
    "checkmark": "M4.5 10.5 8 14l7.5-7.5",
    "checkmark.seal": "M10 2.5 12 4l2.4-.2.6 2.3 1.9 1.4-1 2.2 1 2.2-1.9 1.4-.6 2.3L12 15.2 10 16.8 8 15.2l-2.4.3-.6-2.3L3.1 11.8l1-2.2-1-2.2 1.9-1.4.6-2.3L8 4z@M7.2 10 9 11.8l3.8-3.8",
    "xmark": "M5.5 5.5l9 9M14.5 5.5l-9 9",
    "minus": "M5 10h10",
    "plus": "M10 5v10M5 10h10",
    "questionmark.circle": "M10 2.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z@M8 7.8a2 2 0 1 1 2.6 1.9c-.5.2-.6.6-.6 1v.6@M10 14.3h.01",
    "exclamationmark.circle": "M10 2.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z@M10 6v5M10 13.6h.01",
    "exclamationmark.triangle": "M10 3 18 16.5H2z@M10 8v4M10 14.6h.01",
    "hand.draw": "M7 10V4.5a1.5 1.5 0 0 1 3 0V9m0-1.5a1.5 1.5 0 0 1 3 0V10m0-1a1.5 1.5 0 0 1 3 0v4a4 4 0 0 1-4 4h-2a5 5 0 0 1-4-2l-2.2-3a1.5 1.5 0 0 1 2.4-1.8L7 12",
    "arrow.right": "M4 10h12M11.5 5.5 16 10l-4.5 4.5",
    "arrow.up.arrow.down": "M6 16V4M3 7l3-3 3 3@M14 4v12M11 13l3 3 3-3",
    "trash": "M4 5.5h12M8 5.5V4a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v1.5M5.5 5.5 6 16a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1l.5-10.5",
    "list.bullet": "M6 6h11M6 10h11M6 14h11@M3.4 6h.01M3.4 10h.01M3.4 14h.01"
  };
  function Icon({ name, size = 20, strokeWidth = 1.6, style, ...rest }) {
    const raw = SF_PATHS[name];
    if (!raw) return null;
    return /* @__PURE__ */ react_shim_default.createElement(
      "svg",
      {
        width: size,
        height: size,
        viewBox: "0 0 20 20",
        fill: "none",
        stroke: "currentColor",
        strokeWidth,
        strokeLinecap: "round",
        strokeLinejoin: "round",
        "aria-hidden": "true",
        style: { flex: "none", display: "block", ...style },
        ...rest
      },
      raw.split("@").map((d, i) => /* @__PURE__ */ react_shim_default.createElement("path", { key: i, d }))
    );
  }

  // src/actions/Button.jsx
  var VARIANTS = {
    filled: { background: "var(--accent)", color: "var(--ink-inverse)", border: "1px solid transparent" },
    tonal: { background: "var(--accent-wash)", color: "var(--accent)", border: "1px solid transparent" },
    outline: { background: "transparent", color: "var(--ink)", border: "1px solid var(--rule-strong)" },
    plain: { background: "transparent", color: "var(--accent)", border: "1px solid transparent" },
    danger: { background: "var(--wash-error)", color: "var(--mark-error)", border: "1px solid transparent" }
  };
  var SIZES = {
    small: { height: 36, font: "var(--type-footnote)", pad: "0 12px" },
    medium: { height: 44, font: "var(--type-headline)", pad: "0 18px" },
    large: { height: 52, font: "var(--type-headline)", pad: "0 22px" }
  };
  function Button({
    variant = "filled",
    size = "medium",
    symbol,
    children,
    disabled = false,
    onClick,
    style,
    ...rest
  }) {
    const v = VARIANTS[variant] || VARIANTS.filled;
    const s = SIZES[size] || SIZES.medium;
    return /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick,
        disabled,
        style: {
          ...v,
          height: s.height,
          font: s.font,
          padding: s.pad,
          minWidth: "var(--hit-min)",
          borderRadius: "var(--radius-sm)",
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          gap: "var(--s-3)",
          cursor: disabled ? "default" : "pointer",
          opacity: disabled ? "var(--disabled-opacity)" : 1,
          transition: "background var(--dur-press) var(--ease-standard)",
          ...style
        },
        ...rest
      },
      symbol && /* @__PURE__ */ react_shim_default.createElement(Icon, { name: symbol, size: size === "small" ? 16 : 18 }),
      children
    );
  }

  // src/actions/IconButton.jsx
  function IconButton({ symbol, label, count, tone = "ink", onClick, style, ...rest }) {
    const color = tone === "ink" ? "var(--ink-muted)" : `var(--mark-${tone})`;
    return /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick,
        "aria-label": label,
        title: label,
        style: {
          minWidth: "var(--hit-min)",
          height: "var(--hit-min)",
          padding: "0 var(--s-3)",
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 5,
          background: "transparent",
          border: "none",
          color,
          cursor: "pointer",
          borderRadius: "var(--radius-sm)",
          ...style
        },
        ...rest
      },
      /* @__PURE__ */ react_shim_default.createElement(Icon, { name: symbol, size: 20 }),
      count != null && count > 0 && /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-mono)", fontVariantNumeric: "tabular-nums" } }, count)
    );
  }

  // src/navigation/NavBar.jsx
  function NavBar({
    title,
    subtitle,
    large = false,
    backLabel,
    onBack,
    trailing,
    over = false,
    style,
    ...rest
  }) {
    return /* @__PURE__ */ react_shim_default.createElement("header", { style: {
      display: "flex",
      alignItems: large ? "flex-end" : "center",
      gap: "var(--s-4)",
      padding: large ? "var(--safe-top) var(--gutter-compact) var(--s-4)" : "var(--safe-top) var(--s-4) var(--s-4)",
      background: over ? "var(--protect-top)" : "transparent",
      borderBottom: over || large ? "none" : "1px solid var(--rule-faint)",
      ...style
    }, ...rest }, onBack && /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick: onBack,
        style: {
          display: "inline-flex",
          alignItems: "center",
          gap: 2,
          minHeight: "var(--hit-min)",
          background: "none",
          border: "none",
          color: "var(--accent)",
          cursor: "pointer",
          font: "var(--type-body)",
          padding: 0
        }
      },
      /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "chevron.left", size: 20 }),
      backLabel
    ), /* @__PURE__ */ react_shim_default.createElement("div", { style: { flexGrow: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2 } }, /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: large ? "var(--type-largetitle)" : "var(--type-headline)",
      letterSpacing: large ? "var(--tracking-display)" : "var(--tracking-title)"
    } }, title), subtitle && /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-mono)",
      fontSize: 11,
      color: "var(--ink-faint)",
      fontVariantNumeric: "tabular-nums"
    } }, subtitle)), trailing && /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      display: "flex",
      alignItems: "center",
      gap: 2,
      marginRight: -8
    } }, trailing));
  }

  // src/navigation/Sheet.jsx
  function Sheet({ title, leading, trailing, children, style, ...rest }) {
    return /* @__PURE__ */ react_shim_default.createElement("section", { style: {
      background: "var(--paper)",
      borderTop: "1px solid var(--rule-strong)",
      borderTopLeftRadius: "var(--radius-lg)",
      borderTopRightRadius: "var(--radius-lg)",
      boxShadow: "var(--lift-modal)",
      display: "flex",
      flexDirection: "column",
      overflow: "hidden",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement("header", { style: {
      display: "flex",
      alignItems: "center",
      gap: "var(--s-4)",
      padding: "var(--s-4) var(--gutter-compact)",
      borderBottom: "1px solid var(--rule-faint)",
      minHeight: 56
    } }, /* @__PURE__ */ react_shim_default.createElement("div", { style: { flex: "1 0 0", display: "flex", justifyContent: "flex-start" } }, leading), /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-headline)" } }, title), /* @__PURE__ */ react_shim_default.createElement("div", { style: { flex: "1 0 0", display: "flex", justifyContent: "flex-end" } }, trailing)), /* @__PURE__ */ react_shim_default.createElement("div", { style: { flexGrow: 1, overflow: "auto" } }, children));
  }

  // src/navigation/PageDots.jsx
  function PageDots({ count = 3, index = 0, style, ...rest }) {
    return /* @__PURE__ */ react_shim_default.createElement("div", { role: "tablist", "aria-label": "Page", style: {
      display: "flex",
      gap: 6,
      justifyContent: "center",
      ...style
    }, ...rest }, Array.from({ length: count }, (_, i) => /* @__PURE__ */ react_shim_default.createElement("span", { key: i, role: "tab", "aria-selected": i === index, style: {
      width: i === index ? 18 : 6,
      height: 6,
      borderRadius: "var(--radius-pill)",
      background: i === index ? "var(--accent)" : "var(--rule-strong)",
      transition: "width var(--dur-base) var(--ease-standard)"
    } })));
  }

  // src/feedback/CueCard.jsx
  function CueCard({
    symbol = "hand.draw",
    when = "before",
    title,
    body,
    style,
    ...rest
  }) {
    return /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      display: "flex",
      gap: "var(--s-5)",
      padding: "var(--s-5)",
      background: "var(--paper-raised)",
      border: "1px solid var(--rule)",
      borderRadius: "var(--radius-sm)",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement(
      Icon,
      {
        name: symbol,
        size: 28,
        strokeWidth: 1.4,
        style: { color: "var(--accent)", marginTop: 2 }
      }
    ), /* @__PURE__ */ react_shim_default.createElement("div", { style: { display: "flex", flexDirection: "column", gap: 5, minWidth: 0 } }, /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-caps)",
      textTransform: "uppercase",
      letterSpacing: "var(--tracking-caps)",
      color: "var(--ink-faint)"
    } }, when === "before" ? "Before you start" : "What that buzz meant"), /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-headline)" } }, title), /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-footnote)",
      color: "var(--ink-muted)",
      maxWidth: "var(--measure)",
      textWrap: "pretty"
    } }, body)));
  }

  // src/feedback/EmptyState.jsx
  function EmptyState({ symbol = "photo", title, body, children, style, ...rest }) {
    return /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: "var(--s-4)",
      padding: "var(--s-10) var(--gutter-compact)",
      textAlign: "center",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement(Icon, { name: symbol, size: 40, strokeWidth: 1.2, style: { color: "var(--ink-faint)" } }), /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-title3)", letterSpacing: "var(--tracking-title)" } }, title), body && /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-footnote)",
      color: "var(--ink-muted)",
      maxWidth: "var(--measure)",
      textWrap: "pretty"
    } }, body), children);
  }

  // src/feedback/ProgressNote.jsx
  function ProgressNote({ label, value, style, ...rest }) {
    const indeterminate = value == null;
    return /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      display: "flex",
      flexDirection: "column",
      gap: "var(--s-3)",
      padding: "var(--s-4) var(--s-5)",
      background: "var(--paper-raised)",
      border: "1px solid var(--rule)",
      borderRadius: "var(--radius-sm)",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement("div", { style: { display: "flex", justifyContent: "space-between", alignItems: "baseline" } }, /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-footnote)" } }, label), !indeterminate && /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-mono)",
      color: "var(--ink-muted)",
      fontVariantNumeric: "tabular-nums"
    } }, Math.round(value * 100), "%")), /* @__PURE__ */ react_shim_default.createElement("div", { style: { height: 3, background: "var(--paper-sunk)", overflow: "hidden" } }, /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      height: "100%",
      background: "var(--accent)",
      width: indeterminate ? "38%" : `${Math.round(value * 100)}%`,
      transition: "width var(--dur-base) var(--ease-out)"
    } })));
  }

  // src/marks/SeamMark.jsx
  var KIND = {
    confident: { color: "var(--seam-confident)", width: "var(--seam-width)", style: "solid" },
    flagged: { color: "var(--seam-flag)", width: "var(--seam-width-mark)", style: "solid" },
    gap: { color: "var(--seam-gap)", width: "var(--seam-width-mark)", style: "dashed" }
  };
  function SeamMark({ kind = "confident", atPct = 0, lostPx, style, ...rest }) {
    const k = KIND[kind] || KIND.confident;
    return /* @__PURE__ */ react_shim_default.createElement(
      "div",
      {
        "aria-hidden": "true",
        style: {
          position: "absolute",
          left: 0,
          right: 0,
          top: `${atPct}%`,
          borderTop: `${k.width} ${k.style} ${k.color}`,
          pointerEvents: "none",
          ...style
        },
        ...rest
      },
      kind === "gap" && lostPx != null && /* @__PURE__ */ react_shim_default.createElement("span", { style: {
        position: "absolute",
        right: 6,
        top: 3,
        font: "var(--type-mono)",
        fontSize: 10,
        color: "var(--mark-gap)",
        background: "var(--sheet)",
        padding: "1px 4px",
        fontVariantNumeric: "tabular-nums"
      } }, lostPx, " px lost")
    );
  }

  // src/marks/AppIcon.jsx
  var JOINS = [
    { y: 26, fill: "var(--icon-join)" },
    { y: 47, fill: "var(--mark-flag)" },
    // the uncertain seam
    { y: 73, fill: "var(--icon-join)" }
  ];
  var JOIN_H = 2.8;
  function AppIcon({ size = 120, masked = false, title, style, ...rest }) {
    const svg = /* @__PURE__ */ react_shim_default.createElement(
      "svg",
      {
        viewBox: "0 0 100 100",
        width: size,
        height: size,
        shapeRendering: "crispEdges",
        role: title ? "img" : "presentation",
        "aria-label": title || void 0,
        "aria-hidden": title ? void 0 : "true",
        style: masked ? void 0 : { display: "block", ...style },
        ...masked ? {} : rest
      },
      /* @__PURE__ */ react_shim_default.createElement("rect", { width: "100", height: "100", fill: "var(--icon-field)" }),
      JOINS.map((j) => /* @__PURE__ */ react_shim_default.createElement("rect", { key: j.y, y: j.y, width: "100", height: JOIN_H, fill: j.fill }))
    );
    if (!masked) return svg;
    return /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      width: size,
      height: size,
      borderRadius: "22.37%",
      overflow: "hidden",
      lineHeight: 0,
      flex: "none",
      ...style
    }, ...rest }, svg);
  }

  // src/marks/MarginMarker.jsx
  function MarginMarker({
    n,
    kind = "flagged",
    atPct = 0,
    selected = false,
    onClick,
    style,
    ...rest
  }) {
    const color = kind === "gap" ? "var(--mark-gap)" : kind === "confident" ? "var(--ink-faint)" : "var(--mark-flag)";
    return /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick,
        "aria-label": `Mark ${n}`,
        style: {
          position: "absolute",
          top: `${atPct}%`,
          left: 0,
          width: 24,
          height: 24,
          marginTop: -12,
          borderRadius: "var(--radius-pill)",
          background: selected ? color : "var(--paper)",
          color: selected ? "var(--sheet)" : color,
          border: `1.5px solid ${color}`,
          font: "var(--type-caps)",
          fontVariantNumeric: "tabular-nums",
          display: "grid",
          placeItems: "center",
          cursor: "pointer",
          padding: 0,
          transition: "background var(--dur-press) var(--ease-standard)",
          ...style
        },
        ...rest
      },
      n
    );
  }

  // src/marks/PositionScale.jsx
  function PositionScale({
    heightPx,
    viewportTopPct = 0,
    viewportPct = 14,
    marks = [],
    orientation = "vertical",
    onScrub,
    style,
    ...rest
  }) {
    const h = orientation === "horizontal";
    const tone = { flagged: "var(--mark-flag)", gap: "var(--mark-gap)", confident: "var(--rule-strong)" };
    const scrub = (e) => {
      if (!onScrub) return;
      const r = e.currentTarget.getBoundingClientRect();
      const pct = h ? (e.clientX - r.left) / r.width * 100 : (e.clientY - r.top) / r.height * 100;
      onScrub(Math.max(0, Math.min(100, pct)));
    };
    return /* @__PURE__ */ react_shim_default.createElement(
      "div",
      {
        onClick: scrub,
        role: "slider",
        "aria-label": "Position in capture",
        "aria-valuenow": Math.round(viewportTopPct),
        "aria-valuemin": 0,
        "aria-valuemax": 100,
        style: {
          position: "relative",
          flex: "none",
          width: h ? "100%" : "var(--scale-rail)",
          height: h ? "var(--scale-rail)" : "100%",
          cursor: onScrub ? h ? "ew-resize" : "ns-resize" : "default",
          [h ? "borderTop" : "borderLeft"]: "1px solid var(--rule)",
          ...style
        },
        ...rest
      },
      Array.from({ length: 11 }, (_, i) => /* @__PURE__ */ react_shim_default.createElement("span", { key: i, "aria-hidden": "true", style: {
        position: "absolute",
        background: "var(--rule)",
        ...h ? { left: `${i * 10}%`, top: 0, width: 1, height: i % 5 ? 4 : 8 } : { top: `${i * 10}%`, left: 0, height: 1, width: i % 5 ? 4 : 8 }
      } })),
      marks.map((m, i) => /* @__PURE__ */ react_shim_default.createElement("span", { key: i, title: m.label, "aria-hidden": "true", style: {
        position: "absolute",
        background: tone[m.kind] || tone.confident,
        ...h ? { left: `${m.atPct}%`, top: 0, width: 2, height: "100%" } : { top: `${m.atPct}%`, left: 0, height: 2, width: "100%" }
      } })),
      /* @__PURE__ */ react_shim_default.createElement("span", { "aria-hidden": "true", style: {
        position: "absolute",
        border: "1.5px solid var(--accent)",
        borderRadius: 1,
        background: "var(--accent-wash)",
        transition: `${h ? "left" : "top"} var(--dur-jump) var(--ease-out)`,
        ...h ? { left: `${viewportTopPct}%`, width: `${viewportPct}%`, top: 0, bottom: 0 } : { top: `${viewportTopPct}%`, height: `${viewportPct}%`, left: 0, right: 0 }
      } })
    );
  }

  // src/capture/CaptureDock.jsx
  function CaptureDock({
    onRecord,
    onVideo,
    onPhotos,
    recording = false,
    unavailable = null,
    style,
    ...rest
  }) {
    const side = {
      width: 52,
      height: 52,
      flex: "none",
      display: "grid",
      placeItems: "center",
      background: "var(--paper-raised)",
      border: "1px solid var(--rule)",
      borderRadius: "var(--radius-sm)",
      color: "var(--ink)",
      cursor: "pointer"
    };
    return /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      display: "flex",
      alignItems: "center",
      gap: "var(--s-4)",
      maxWidth: "var(--column-max)",
      margin: "0 auto",
      width: "100%",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement("button", { type: "button", onClick: onVideo, "aria-label": "From a screen recording", style: side }, /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "film", size: 20 })), unavailable ? /* @__PURE__ */ react_shim_default.createElement("p", { style: {
      flexGrow: 1,
      margin: 0,
      minHeight: 52,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      textAlign: "center",
      font: "var(--type-footnote)",
      color: "var(--ink-muted)"
    } }, unavailable) : /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick: onRecord,
        style: {
          flexGrow: 1,
          height: 52,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: "var(--s-3)",
          cursor: "pointer",
          borderRadius: "var(--radius-sm)",
          border: "1px solid transparent",
          background: recording ? "var(--mark-rec)" : "var(--accent)",
          color: "var(--ink-inverse)",
          font: "var(--type-headline)"
        }
      },
      /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "record.circle", size: 20, strokeWidth: 1.8 }),
      recording ? "Recording" : "Record"
    ), /* @__PURE__ */ react_shim_default.createElement("button", { type: "button", onClick: onPhotos, "aria-label": "From screenshots", style: side }, /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "photo.on.rectangle", size: 20 })));
  }

  // src/capture/ImportRow.jsx
  function ImportRow({ symbol, title, detail, onClick, style, ...rest }) {
    return /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick,
        style: {
          display: "flex",
          alignItems: "center",
          gap: "var(--s-4)",
          width: "100%",
          minHeight: 56,
          padding: "var(--s-3) 0",
          background: "transparent",
          border: "none",
          borderBottom: "1px solid var(--rule-faint)",
          cursor: "pointer",
          textAlign: "left",
          color: "var(--ink)",
          ...style
        },
        ...rest
      },
      /* @__PURE__ */ react_shim_default.createElement(Icon, { name: symbol, size: 20, style: { color: "var(--accent)" } }),
      /* @__PURE__ */ react_shim_default.createElement("span", { style: { flexGrow: 1, display: "flex", flexDirection: "column", gap: 1 } }, /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-body)" } }, title), detail && /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-caption)", color: "var(--ink-faint)" } }, detail)),
      /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "chevron.right", size: 16, style: { color: "var(--ink-faint)" } })
    );
  }

  // src/data/StatusNote.jsx
  var KINDS = {
    ready: { label: "Ready", symbol: "checkmark", tone: "ok" },
    processing: { label: "Stitching\u2026", symbol: "list.bullet", tone: null },
    flagged: { label: "flagged", symbol: "flag", tone: "flag" },
    gap: { label: "gap", symbol: "scissors", tone: "gap" },
    incomplete: { label: "Incomplete", symbol: "exclamationmark.circle", tone: "error" },
    bars: { label: "bars uncertain", symbol: "rectangle.dashed", tone: "flag" },
    failed: { label: "Couldn't stitch", symbol: "exclamationmark.triangle", tone: "error" }
  };
  function StatusNote({ kind = "ready", count, label, size = "medium", style, ...rest }) {
    const k = KINDS[kind] || KINDS.ready;
    const text = label != null ? label : count != null ? `${count} ${k.label}` : k.label;
    const color = k.tone ? `var(--mark-${k.tone})` : "var(--ink-muted)";
    const wash = k.tone ? `var(--wash-${k.tone})` : "transparent";
    const small = size === "small";
    return /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 5,
      height: small ? 20 : 24,
      padding: small ? "0 7px" : "0 9px",
      borderRadius: "var(--radius-xs)",
      background: wash,
      color,
      font: small ? "var(--type-caps)" : "var(--type-caption)",
      fontVariantNumeric: "tabular-nums",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement(Icon, { name: k.symbol, size: small ? 11 : 13, strokeWidth: 1.8 }), text);
  }

  // src/data/proxy.js
  var PROXY_PATTERN = "repeating-linear-gradient(180deg,#fff 0 11px,#b9c3d0 11px 16px,#fff 16px 30px,#c8d1dc 30px 35px,#fff 35px 58px,#e6ebf1 58px 96px)";
  var PROXY_PATTERN_DENSE = "repeating-linear-gradient(180deg,#fff 0 4px,#c8d1dc 4px 6px,#fff 6px 12px,#e6ebf1 12px 20px)";
  var px = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, "\u2009");

  // src/data/CaptureSheet.jsx
  function CaptureSheet({
    image,
    ribbon = true,
    marks = [],
    children,
    style,
    ...rest
  }) {
    return /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      position: "relative",
      background: "var(--sheet)",
      borderRadius: "var(--radius-sheet)",
      boxShadow: "var(--lift-sheet)",
      overflow: "hidden",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      position: "absolute",
      inset: ribbon ? "0 10px 0 0" : 0,
      backgroundImage: image ? `url(${image})` : PROXY_PATTERN,
      backgroundPosition: "top center",
      backgroundSize: image ? "100% auto" : "auto",
      backgroundRepeat: "no-repeat",
      backgroundColor: "#fff"
    } }), ribbon && /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      position: "absolute",
      inset: "0 0 0 auto",
      width: 10,
      borderLeft: "1px solid rgba(31,29,26,.12)",
      backgroundImage: image ? `url(${image})` : PROXY_PATTERN_DENSE,
      backgroundPosition: "center",
      backgroundSize: image ? "100% 100%" : "auto",
      backgroundRepeat: "no-repeat",
      backgroundColor: "#fff",
      opacity: 0.85
    } }, marks.map((m, i) => /* @__PURE__ */ react_shim_default.createElement("span", { key: i, "aria-hidden": "true", style: {
      position: "absolute",
      left: 0,
      right: 0,
      top: `${m.atPct}%`,
      height: 2,
      background: m.kind === "gap" ? "var(--mark-gap)" : "var(--mark-flag)"
    } }))), children);
  }

  // src/data/CaptureListRow.jsx
  function CaptureListRow({
    title,
    widthPx = 884,
    heightPx = 15402,
    image,
    status = "ready",
    flaggedCount = 0,
    gapCount = 0,
    incomplete = false,
    marks = [],
    onClick,
    style,
    ...rest
  }) {
    return /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick,
        style: {
          display: "flex",
          alignItems: "center",
          gap: "var(--s-4)",
          width: "100%",
          padding: "var(--s-4) 0",
          background: "transparent",
          border: "none",
          borderBottom: "1px solid var(--rule-faint)",
          cursor: "pointer",
          textAlign: "left",
          color: "var(--ink)",
          ...style
        },
        ...rest
      },
      /* @__PURE__ */ react_shim_default.createElement(
        CaptureSheet,
        {
          image,
          marks,
          style: { width: 46, height: 62, flex: "none" }
        }
      ),
      /* @__PURE__ */ react_shim_default.createElement("span", { style: { display: "flex", flexDirection: "column", gap: 4, flexGrow: 1, minWidth: 0 } }, /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-headline)" } }, title), /* @__PURE__ */ react_shim_default.createElement("span", { style: {
        font: "var(--type-mono)",
        fontSize: 11,
        color: "var(--ink-faint)",
        fontVariantNumeric: "tabular-nums"
      } }, px(widthPx), " \xD7 ", px(heightPx), " px"), /* @__PURE__ */ react_shim_default.createElement("span", { style: { display: "flex", gap: "var(--s-2)", flexWrap: "wrap" } }, status !== "ready" && /* @__PURE__ */ react_shim_default.createElement(StatusNote, { kind: status, size: "small" }), incomplete && /* @__PURE__ */ react_shim_default.createElement(StatusNote, { kind: "incomplete", size: "small" }), flaggedCount > 0 && /* @__PURE__ */ react_shim_default.createElement(StatusNote, { kind: "flagged", count: flaggedCount, size: "small" }), gapCount > 0 && /* @__PURE__ */ react_shim_default.createElement(StatusNote, { kind: "gap", count: gapCount, size: "small" }))),
      /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "chevron.right", size: 16, style: { color: "var(--ink-faint)" } })
    );
  }

  // src/data/CaptureGridCard.jsx
  function CaptureGridCard({
    title,
    widthPx = 884,
    heightPx = 15402,
    image,
    status = "ready",
    flaggedCount = 0,
    gapCount = 0,
    incomplete = false,
    marks = [],
    selected = false,
    onClick,
    style,
    ...rest
  }) {
    return /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick,
        style: {
          display: "flex",
          flexDirection: "column",
          gap: "var(--s-3)",
          width: "100%",
          padding: 0,
          background: "transparent",
          border: "none",
          cursor: "pointer",
          textAlign: "left",
          color: "var(--ink)",
          ...style
        },
        ...rest
      },
      /* @__PURE__ */ react_shim_default.createElement(
        CaptureSheet,
        {
          image,
          marks,
          style: {
            width: "100%",
            aspectRatio: "3 / 5",
            outline: selected ? "2px solid var(--accent)" : "none",
            outlineOffset: 2
          }
        }
      ),
      /* @__PURE__ */ react_shim_default.createElement("span", { style: { display: "flex", flexDirection: "column", gap: 3 } }, /* @__PURE__ */ react_shim_default.createElement("span", { style: { font: "var(--type-headline)" } }, title), /* @__PURE__ */ react_shim_default.createElement("span", { style: {
        font: "var(--type-mono)",
        fontSize: 11,
        color: "var(--ink-faint)",
        fontVariantNumeric: "tabular-nums"
      } }, px(heightPx), " px"), /* @__PURE__ */ react_shim_default.createElement("span", { style: { display: "flex", gap: "var(--s-2)", flexWrap: "wrap", marginTop: 2 } }, status !== "ready" && /* @__PURE__ */ react_shim_default.createElement(StatusNote, { kind: status, size: "small" }), incomplete && /* @__PURE__ */ react_shim_default.createElement(StatusNote, { kind: "incomplete", size: "small" }), flaggedCount > 0 && /* @__PURE__ */ react_shim_default.createElement(StatusNote, { kind: "flagged", count: flaggedCount, size: "small" }), gapCount > 0 && /* @__PURE__ */ react_shim_default.createElement(StatusNote, { kind: "gap", count: gapCount, size: "small" })))
    );
  }

  // src/repair/QueuePrompt.jsx
  function QueuePrompt({
    index = 1,
    total = 3,
    kind = "flagged",
    question,
    detail,
    value,
    unit = "px",
    onNudge,
    onAccept,
    onSkipAll,
    children,
    style,
    ...rest
  }) {
    return /* @__PURE__ */ react_shim_default.createElement("section", { style: {
      background: "var(--paper-raised)",
      borderTop: "1px solid var(--rule)",
      padding: "var(--s-5) var(--gutter-compact) var(--s-7)",
      display: "flex",
      flexDirection: "column",
      gap: "var(--s-5)",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement("header", { style: { display: "flex", alignItems: "baseline", justifyContent: "space-between" } }, /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-caps)",
      textTransform: "uppercase",
      letterSpacing: "var(--tracking-caps)",
      color: kind === "gap" ? "var(--mark-gap)" : "var(--mark-flag)"
    } }, kind === "gap" ? "Gap" : "Uncertain seam"), /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-mono)",
      color: "var(--ink-faint)",
      fontVariantNumeric: "tabular-nums"
    } }, index, " of ", total)), children, /* @__PURE__ */ react_shim_default.createElement("div", { style: { display: "flex", flexDirection: "column", gap: "var(--s-2)" } }, /* @__PURE__ */ react_shim_default.createElement("h2", { style: {
      font: "var(--type-title3)",
      letterSpacing: "var(--tracking-title)",
      margin: 0
    } }, question), detail && /* @__PURE__ */ react_shim_default.createElement("p", { style: {
      font: "var(--type-footnote)",
      color: "var(--ink-muted)",
      margin: 0,
      maxWidth: "var(--measure)",
      textWrap: "pretty"
    } }, detail)), /* @__PURE__ */ react_shim_default.createElement("div", { style: { display: "flex", alignItems: "stretch", gap: "var(--s-3)" } }, /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick: () => onNudge && onNudge(-1),
        "aria-label": "Nudge up",
        style: {
          width: 52,
          borderRadius: "var(--radius-sm)",
          background: "var(--paper-sunk)",
          border: "1px solid var(--rule)",
          color: "var(--ink)",
          cursor: "pointer",
          display: "grid",
          placeItems: "center"
        }
      },
      /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "chevron.up", size: 20 })
    ), /* @__PURE__ */ react_shim_default.createElement(Button, { variant: "filled", size: "large", onClick: onAccept, style: { flexGrow: 1 } }, "Looks right"), /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick: () => onNudge && onNudge(1),
        "aria-label": "Nudge down",
        style: {
          width: 52,
          borderRadius: "var(--radius-sm)",
          background: "var(--paper-sunk)",
          border: "1px solid var(--rule)",
          color: "var(--ink)",
          cursor: "pointer",
          display: "grid",
          placeItems: "center"
        }
      },
      /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "chevron.down", size: 20 })
    )), /* @__PURE__ */ react_shim_default.createElement("div", { style: { display: "flex", alignItems: "center", justifyContent: "space-between" } }, value != null ? /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-mono)",
      color: "var(--ink-muted)",
      fontVariantNumeric: "tabular-nums"
    } }, "dy ", value > 0 ? "+" : "", value, " ", unit) : /* @__PURE__ */ react_shim_default.createElement("span", null), /* @__PURE__ */ react_shim_default.createElement(
      "button",
      {
        type: "button",
        onClick: onSkipAll,
        style: {
          background: "none",
          border: "none",
          padding: "var(--s-2) 0",
          font: "var(--type-footnote)",
          color: "var(--ink-muted)",
          cursor: "pointer"
        }
      },
      "Skip all"
    )));
  }

  // src/repair/StepperRow.jsx
  function StepperRow({
    label,
    value = 0,
    unit = "px",
    step = 1,
    min,
    max,
    hint,
    onChange,
    style,
    ...rest
  }) {
    const set = (d) => {
      let v = value + d * step;
      if (min != null) v = Math.max(min, v);
      if (max != null) v = Math.min(max, v);
      onChange && onChange(v);
    };
    const btn = {
      width: 44,
      height: 34,
      display: "grid",
      placeItems: "center",
      cursor: "pointer",
      background: "transparent",
      border: "none",
      color: "var(--accent)"
    };
    return /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      display: "flex",
      alignItems: "center",
      gap: "var(--s-4)",
      minHeight: "var(--hit-min)",
      padding: "var(--s-3) 0",
      borderBottom: "1px solid var(--rule-faint)",
      ...style
    }, ...rest }, /* @__PURE__ */ react_shim_default.createElement("div", { style: { flexGrow: 1, minWidth: 0 } }, /* @__PURE__ */ react_shim_default.createElement("div", { style: { font: "var(--type-body)" } }, label), hint && /* @__PURE__ */ react_shim_default.createElement("div", { style: { font: "var(--type-caption)", color: "var(--ink-faint)" } }, hint)), /* @__PURE__ */ react_shim_default.createElement("span", { style: {
      font: "var(--type-mono)",
      color: "var(--ink-muted)",
      fontVariantNumeric: "tabular-nums",
      minWidth: 68,
      textAlign: "right"
    } }, value, " ", unit), /* @__PURE__ */ react_shim_default.createElement("div", { style: {
      display: "flex",
      background: "var(--paper-sunk)",
      borderRadius: "var(--radius-sm)",
      border: "1px solid var(--rule)"
    } }, /* @__PURE__ */ react_shim_default.createElement("button", { type: "button", style: btn, onClick: () => set(-1), "aria-label": `Decrease ${label}` }, /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "minus", size: 16 })), /* @__PURE__ */ react_shim_default.createElement("span", { style: { width: 1, background: "var(--rule)" } }), /* @__PURE__ */ react_shim_default.createElement("button", { type: "button", style: btn, onClick: () => set(1), "aria-label": `Increase ${label}` }, /* @__PURE__ */ react_shim_default.createElement(Icon, { name: "plus", size: 16 }))));
  }
  return __toCommonJS(index_exports);
})();
