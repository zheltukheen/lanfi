import CoreGraphics
import Foundation

/// Pure geometry for a compact, axis-free sparkline.
///
/// The menu-bar sparkline and the throughput card draw the same shape, so the
/// point maths lives here instead of inside a `Canvas` closure. Values are
/// clamped into the drawable rect and normalised against the window peak; a
/// flat or empty window still produces a stable baseline.
enum SparklineGeometry {
    /// Points in draw order. Empty when the rect cannot be drawn.
    static func points(values: [Double], in size: CGSize) -> [CGPoint] {
        guard size.width > 1, size.height > 1, !values.isEmpty else { return [] }
        let peak = max(values.max() ?? 0, 1)
        return values.enumerated().map { index, value in
            let x =
                values.count > 1
                ? CGFloat(index) / CGFloat(values.count - 1) * size.width
                : size.width
            let normalized = min(1, max(0, value / peak))
            return CGPoint(
                x: x,
                y: size.height - 1 - CGFloat(normalized) * (size.height - 2))
        }
    }

    /// Baseline for the no-samples state, inset by one point so the stroke is
    /// not clipped by the view bounds.
    static func baseline(in size: CGSize) -> (CGPoint, CGPoint)? {
        guard size.width > 1, size.height > 1 else { return nil }
        return (
            CGPoint(x: 0, y: size.height - 1),
            CGPoint(x: size.width, y: size.height - 1)
        )
    }
}
