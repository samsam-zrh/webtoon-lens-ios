import CoreGraphics
import Foundation

public struct BrowserSourceSnapshotPlan: Sendable {
    public let region: NormalizedRect
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(anchor: BrowserImageAnchor, visibleRegion: NormalizedRect) throws {
        guard anchor.isValid, visibleRegion.isInsideImage,
              let width = anchor.pixelWidth, let height = anchor.pixelHeight else {
            throw BrowserCaptureError.invalidViewport
        }
        let gridWidth = anchor.rasterWidth ?? min(1600, width)
        let gridHeight = anchor.rasterHeight ?? max(1, Int((Double(height) * Double(gridWidth) / Double(width)).rounded()))
        let left = max(0, Int(ceil((visibleRegion.minX - anchor.bounds.minX) / anchor.bounds.width * Double(gridWidth))))
        let top = max(0, Int(ceil((visibleRegion.minY - anchor.bounds.minY) / anchor.bounds.height * Double(gridHeight))))
        let right = min(gridWidth, Int(floor((visibleRegion.maxX - anchor.bounds.minX) / anchor.bounds.width * Double(gridWidth))))
        let bottom = min(gridHeight, Int(floor((visibleRegion.maxY - anchor.bounds.minY) / anchor.bounds.height * Double(gridHeight))))
        guard right - left >= 12, right - left <= 1600, bottom - top >= 12, (right - left) * (bottom - top) <= 4_000_000 else {
            throw BrowserCaptureError.invalidViewport
        }
        pixelWidth = right - left
        pixelHeight = bottom - top
        let projected = BrowserImageCoordinates.viewportRect(image: NormalizedRect(
            x: Double(left) / Double(gridWidth), y: Double(top) / Double(gridHeight),
            width: Double(pixelWidth) / Double(gridWidth), height: Double(pixelHeight) / Double(gridHeight)
        ), anchor: anchor)
        guard projected.minX >= -0.00000001, projected.minY >= -0.00000001,
              projected.maxX <= 1.00000001, projected.maxY <= 1.00000001 else { throw BrowserCaptureError.invalidViewport }
        let x = max(0, projected.minX), y = max(0, projected.minY)
        region = NormalizedRect(x: x, y: y, width: min(1, projected.maxX) - x, height: min(1, projected.maxY) - y)
    }
}
