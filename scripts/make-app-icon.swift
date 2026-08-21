#!/usr/bin/env swift
//
// Generates the Seamly app icon into Assets.xcassets/AppIcon.appiconset.
//
//   swift scripts/make-app-icon.swift            # from the repo root
//
// The mark is "Ruled, three uneven": a full-bleed ink field with three
// horizontal joins at UNEQUAL spacing, the middle one carrying --mark-flag (the
// uncertain seam). See design-system/components/marks/AppIcon.prompt.md.
//
// Colours are PARSED from design-system/tokens/colors.css, never hardcoded here,
// so the icon stays derivable from the design system. If a token moves, re-run
// this; if a token is missing, this fails loudly rather than guessing.
//
// DO NOT INVERT for dark. The field and the paper joins are identical in both
// appearances — only the middle join changes, because --mark-flag lifts in its
// dark scope. --icon-field/--icon-join are theme-stable for exactly this reason.
//
// No tinted asset is produced ON PURPOSE: iOS derives grayscale, and what
// carries is the value structure (dark field, light joins).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - geometry. Percentages are authoritative; the px table is the contract.

let side = 1024.0
let joinPct = 2.8
let joinYPct = [26.0, 47.0, 73.0]

/// The spec's @1024 column. y floors, height rounds — matching the published
/// table exactly, and keeping every edge on a whole pixel so the rules stay
/// crisp (the SVG source says shape-rendering="crispEdges" for the same reason).
let joinY = joinYPct.map { Int(($0 / 100.0 * side).rounded(.down)) }
let joinH = Int((joinPct / 100.0 * side).rounded())

// Self-check against the documented table. If someone edits the constants above,
// this is what tells them the docs no longer match.
precondition(joinY == [266, 481, 747], "geometry drifted from the spec: y = \(joinY), expected [266, 481, 747]")
precondition(joinH == 29, "geometry drifted from the spec: h = \(joinH), expected 29")

// MARK: - tokens

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let tokensURL = repoRoot.appendingPathComponent("design-system/tokens/colors.css")
let iconSetURL = repoRoot.appendingPathComponent("Seamly/Seamly/Assets.xcassets/AppIcon.appiconset")

guard let css = try? String(contentsOf: tokensURL, encoding: .utf8) else {
    fatalError("cannot read \(tokensURL.path) — run this from the repo root")
}

/// Splits the stylesheet into the `:root` block and the `[data-theme="dark"]`
/// block, so a token can be read per scope.
func scope(_ selector: String, in css: String) -> String {
    guard let start = css.range(of: selector) else {
        fatalError("no \(selector) block in colors.css")
    }
    guard let open = css.range(of: "{", range: start.upperBound..<css.endIndex),
          let close = css.range(of: "\n}", range: open.upperBound..<css.endIndex) else {
        fatalError("malformed \(selector) block in colors.css")
    }
    return String(css[open.upperBound..<close.lowerBound])
}

let rootScope = scope(":root", in: css)
let darkScope = scope("[data-theme=\"dark\"]", in: css)

/// Reads `--name: #rrggbb;` out of one scope. Only 6-digit hex is accepted —
/// the icon has no use for a gradient or an rgba(), and silently accepting one
/// would produce a black rectangle.
func hexToken(_ name: String, from scopeText: String, scopeLabel: String) -> CGColor {
    let pattern = "--\(name)\\s*:\\s*#([0-9a-fA-F]{6})\\s*;"
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: scopeText, range: NSRange(scopeText.startIndex..., in: scopeText)),
          let r = Range(m.range(at: 1), in: scopeText) else {
        fatalError("--\(name) not found as a 6-digit hex in \(scopeLabel) of colors.css")
    }
    let v = UInt32(scopeText[r], radix: 16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        Double((v >> 16) & 0xff) / 255,
        Double((v >> 8) & 0xff) / 255,
        Double(v & 0xff) / 255,
        1,
    ])!
}

// Theme-STABLE: read from :root for both appearances, deliberately.
let field = hexToken("icon-field", from: rootScope, scopeLabel: ":root")
let join = hexToken("icon-join", from: rootScope, scopeLabel: ":root")
// The ONE value that differs between appearances.
let accentLight = hexToken("mark-flag", from: rootScope, scopeLabel: ":root")
let accentDark = hexToken("mark-flag", from: darkScope, scopeLabel: "[data-theme=\"dark\"]")

// MARK: - draw

func render(accent: CGColor) -> CGImage {
    let px = Int(side)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create a \(px)×\(px) bitmap context")
    }
    // Every edge is already on a whole pixel, so antialiasing can only soften
    // the rules. Off, for the same reason the SVG uses crispEdges.
    ctx.setShouldAntialias(false)

    ctx.setFillColor(field)
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

    // Core Graphics is bottom-left origin; the spec's y is from the TOP.
    for (i, yTop) in joinY.enumerated() {
        ctx.setFillColor(i == 1 ? accent : join)
        ctx.fill(CGRect(x: 0, y: side - Double(yTop) - Double(joinH),
                        width: side, height: Double(joinH)))
    }

    guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
    return image
}

func writePNG(_ image: CGImage, named name: String) {
    let url = iconSetURL.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write into \(iconSetURL.path) — does the appiconset exist?")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    print("  \(name)  \(Int(side))×\(Int(side))")
}

var isDir: ObjCBool = false
guard FileManager.default.fileExists(atPath: iconSetURL.path, isDirectory: &isDir), isDir.boolValue else {
    fatalError("no appiconset at \(iconSetURL.path) — run this from the repo root")
}

print("Ruled, three uneven — joins at y \(joinY.map(String.init).joined(separator: "/")), h \(joinH)")
writePNG(render(accent: accentLight), named: "icon_light.png")
writePNG(render(accent: accentDark), named: "icon_dark.png")
print("No tinted asset: iOS derives grayscale from the value structure.")
