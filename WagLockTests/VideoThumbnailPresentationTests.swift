import SwiftUI
import UIKit
import XCTest
@testable import WagLock

@MainActor
final class VideoThumbnailPresentationTests: XCTestCase {
    func testPortraitLandscapeAndSquarePreserveTheirPixelProportions() throws {
        for size in [CGSize(width: 90, height: 160), CGSize(width: 160, height: 90), CGSize(width: 100, height: 100)] {
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            let bounds = try renderedRedBounds(image)
            XCTAssertEqual(bounds.width / bounds.height, size.width / size.height, accuracy: 0.025)
            XCTAssertEqual(bounds.midX, 60, accuracy: 1)
            XCTAssertEqual(bounds.midY, 60, accuracy: 1)
            XCTAssertEqual(max(bounds.width, bounds.height), 120, accuracy: 1)
        }
    }

    func testImageOrientationIsAppliedBeforeFitting() throws {
        let size = CGSize(width: 90, height: 160)
        let original = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let rotated = UIImage(cgImage: try XCTUnwrap(original.cgImage), scale: 1, orientation: .right)
        let bounds = try renderedRedBounds(rotated)
        XCTAssertGreaterThan(bounds.width, bounds.height)
        XCTAssertEqual(bounds.width / bounds.height, 160.0 / 90.0, accuracy: 0.025)
    }

    private func renderedRedBounds(_ image: UIImage) throws -> CGRect {
        let renderer = ImageRenderer(content: VideoThumbnailImage(image: image).frame(width: 120, height: 120))
        renderer.scale = 1
        let output = try XCTUnwrap(renderer.uiImage?.cgImage)
        let width = output.width
        let height = output.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(output, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var xs: [Int] = []
        var ys: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if pixels[offset] > 180 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80 {
                    xs.append(x); ys.append(y)
                }
            }
        }
        let minX = try XCTUnwrap(xs.min())
        let maxX = try XCTUnwrap(xs.max())
        let minY = try XCTUnwrap(ys.min())
        let maxY = try XCTUnwrap(ys.max())
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
