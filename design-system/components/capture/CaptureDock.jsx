import React from "react";
import { Icon } from "../foundation/Icon.jsx";

/* Return-home IA: the capture affordance is PERMANENTLY present, never a toolbar
   icon. Docked at the bottom, in thumb reach, with the two import paths flanking
   it so the hero is unmistakable but the alternatives cost one tap.
   Capped width — a 1024pt-wide button on iPad is absurd.

   `unavailable`: when live capture cannot work on the device (an iPad app on a
   Mac; ReplayKit reporting itself unavailable), the hero's slot carries this
   sentence instead of the Record button. A Record button with nothing behind it
   swallows the tap in silence, and App Review read that silence as functionality
   hidden from them (guideline 5.6). The import buttons stay either side of the
   sentence because they are exactly what it tells the user to use. */
export function CaptureDock({ onRecord, onVideo, onPhotos, recording = false,
                             unavailable = null, style, ...rest }) {
  const side = {
    width: 52, height: 52, flex: "none", display: "grid", placeItems: "center",
    background: "var(--paper-raised)", border: "1px solid var(--rule)",
    borderRadius: "var(--radius-sm)", color: "var(--ink)", cursor: "pointer",
  };
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "var(--s-4)",
      maxWidth: "var(--column-max)", margin: "0 auto", width: "100%", ...style }} {...rest}>
      <button type="button" onClick={onVideo} aria-label="From a screen recording" style={side}>
        <Icon name="film" size={20} />
      </button>
      {unavailable ? (
        <p style={{ flexGrow: 1, margin: 0, minHeight: 52, display: "flex",
          alignItems: "center", justifyContent: "center", textAlign: "center",
          font: "var(--type-footnote)", color: "var(--ink-muted)" }}>
          {unavailable}
        </p>
      ) : (
        <button type="button" onClick={onRecord}
          style={{ flexGrow: 1, height: 52, display: "flex", alignItems: "center",
            justifyContent: "center", gap: "var(--s-3)", cursor: "pointer",
            borderRadius: "var(--radius-sm)", border: "1px solid transparent",
            background: recording ? "var(--mark-rec)" : "var(--accent)",
            color: "var(--ink-inverse)", font: "var(--type-headline)" }}>
          <Icon name="record.circle" size={20} strokeWidth={1.8} />
          {recording ? "Recording" : "Record"}
        </button>
      )}
      <button type="button" onClick={onPhotos} aria-label="From screenshots" style={side}>
        <Icon name="photo.on.rectangle" size={20} />
      </button>
    </div>
  );
}
