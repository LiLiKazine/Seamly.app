import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import StitchKit

@Suite struct BatchStitcherOrderStrategyTests {
    private static let names = ["20260718-225057", "20260718-225102", "20260718-225107"]

    private func load(_ name: String) throws -> CGImage {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Example")
        )
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func recoverOrInputOrderKeepsCleanRecoveredChainWithoutBadging() throws {
        // Input is bottom, top, middle; recovered scroll order is input slots 1, 2, 0.
        let images = try [Self.names[1], Self.names[2], Self.names[0]].map(load)

        let plan = try BatchStitcher().plan(images, strategy: .recoverOrInputOrder)

        #expect(plan.order == [1, 2, 0])
        #expect(plan.session.segmentBreaks.isEmpty)
        #expect(plan.session.orderAssumed == false)
    }

    @Test func recoverOrInputOrderFallsBackToInputOrderAndBadgesDisconnectedInput() throws {
        // The top and bottom screenshots do not overlap. Recovery cannot establish their relative
        // order, so the input order is the fallback, while the genuine discontinuity stays split.
        let images = try [Self.names[1], Self.names[2]].map(load)

        let plan = try BatchStitcher().plan(images, strategy: .recoverOrInputOrder)

        #expect(plan.order == [0, 1])
        #expect(plan.session.seams.isEmpty)
        #expect(plan.session.segmentBreaks.count == 1)
        #expect(plan.session.orderAssumed)
    }

    @Test func recoverOrInputOrderDiscardsNonIdentityPartialRecoveryBeforeFallingBack() throws {
        let source = makeScrollSource(width: 120, height: 1_200)
        let top = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 300)))
        let middle = try #require(source.cropping(to: CGRect(x: 0, y: 140, width: 120, height: 300)))
        let disconnected = try #require(
            source.cropping(to: CGRect(x: 0, y: 900, width: 120, height: 300))
        )
        // The overlapping pair is deliberately reversed; the disconnected tail makes recovery
        // incomplete. This ensures identity below can only come from the fallback.
        let images = [middle, top, disconnected]
        let stitcher = BatchStitcher()

        let recovered = try stitcher.plan(images, strategy: .recover)
        #expect(recovered.order == [1, 0, 2])
        #expect(recovered.order != Array(images.indices))
        #expect(!recovered.session.segmentBreaks.isEmpty)
        #expect(recovered.session.orderAssumed == false)

        let fallback = try stitcher.plan(images, strategy: .recoverOrInputOrder)
        #expect(fallback.order == [0, 1, 2])
        #expect(fallback.session.segmentBreaks.map(\.afterKeyframeIndex) == [0, 1])
        #expect(fallback.session.orderAssumed)
    }

    @Test func inputOrderTrustsChronologyWithoutBadging() throws {
        let images = try [Self.names[2], Self.names[0], Self.names[1]].map(load)

        let plan = try BatchStitcher().plan(images, strategy: .inputOrder)

        #expect(plan.order == [0, 1, 2])
        #expect(plan.session.segmentBreaks.isEmpty)
        #expect(plan.session.orderAssumed == false)
    }

    @Test func strategyAPIKeepsExistingPlanningSemantics() throws {
        let images = try Self.names.map(load)
        let identity = Array(images.indices)
        let stitcher = BatchStitcher()

        let recovered = try stitcher.plan(images)
        let recoveredByStrategy = try stitcher.plan(images, strategy: .recover)
        #expect(recoveredByStrategy.order == recovered.order)
        #expect(recoveredByStrategy.session.seams == recovered.session.seams)
        #expect(recoveredByStrategy.session.segmentBreaks == recovered.session.segmentBreaks)
        #expect(recoveredByStrategy.session.contentBands == recovered.session.contentBands)
        #expect(recoveredByStrategy.session.orderAssumed == false)

        let assumed = try stitcher.plan(images, assumingOrder: identity)
        let inputByStrategy = try stitcher.plan(images, strategy: .inputOrder)
        #expect(inputByStrategy.order == assumed.order)
        #expect(inputByStrategy.session.seams == assumed.session.seams)
        #expect(inputByStrategy.session.segmentBreaks == assumed.session.segmentBreaks)
        #expect(inputByStrategy.session.contentBands == assumed.session.contentBands)
        #expect(inputByStrategy.session.orderAssumed == false)
    }

    private func makeScrollSource(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let value = 60.0 + Double(y) * (120.0 / Double(height))
                    + 50 * sin(Double(x) * 0.35)
                    + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                let byte = UInt8(max(0, min(255, value)))
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = byte
                pixels[offset + 1] = byte
                pixels[offset + 2] = byte
                pixels[offset + 3] = 255
            }
        }
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
