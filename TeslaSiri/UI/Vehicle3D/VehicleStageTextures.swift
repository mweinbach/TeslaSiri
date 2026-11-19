import CoreGraphics
import RealityKit
import UIKit

/// Procedural textures for the 3D stage: fallback contact shadow, the driving road pool,
/// lane dashes, and a soft-edged planned-path ribbon. Each is an opaque grayscale mask
/// (white = fully visible) used as an opacity texture so a material tint supplies color.
@MainActor
enum VehicleStageTextures {
    /// Fallback soft contact shadow when a vehicle build lacks a bundled `FloorMask.r8`.
    static let contactShadow: TextureResource? = radial(size: 256, stops: [
        (0.0, 0.72), (0.45, 0.48), (0.76, 0.14), (1.0, 0)
    ])

    /// Road surface pool: opaque in the middle, dissolving smoothly to nothing at the edges.
    static let roadPool: TextureResource? = radial(size: 512, stops: [
        (0.0, 1), (0.40, 0.92), (0.68, 0.42), (1.0, 0)
    ])

    /// Lane-line dash with feathered ends so dashes glide smoothly rather than pop.
    static let dash: TextureResource? = linear(width: 8, height: 64, horizontal: false, stops: [
        (0.0, 0), (0.14, 1), (0.86, 1), (1.0, 0)
    ])

    /// Soft-edged horizontal beam mask for the Autopilot/FSD planned-path ribbon.
    static let pathRibbon: TextureResource? = linear(width: 64, height: 8, horizontal: true, stops: [
        (0.0, 0), (0.18, 0.75), (0.5, 1), (0.82, 0.75), (1.0, 0)
    ])

    private static func radial(size: Int, stops: [(CGFloat, CGFloat)]) -> TextureResource? {
        draw(width: size, height: size) { context in
            let colors = stops.map { CGColor(gray: $0.1, alpha: 1) } as CFArray
            let locations = stops.map(\.0)
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations) else { return }
            let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size) / 2, options: [])
        }
    }

    private static func linear(width: Int, height: Int, horizontal: Bool, stops: [(CGFloat, CGFloat)]) -> TextureResource? {
        draw(width: width, height: height) { context in
            let colors = stops.map { CGColor(gray: $0.1, alpha: 1) } as CFArray
            let locations = stops.map(\.0)
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations) else { return }
            let end = horizontal ? CGPoint(x: CGFloat(width), y: 0) : CGPoint(x: 0, y: CGFloat(height))
            context.drawLinearGradient(gradient, start: .zero, end: end, options: [])
        }
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> TextureResource? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        body(context)
        guard let image = context.makeImage() else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .raw))
    }
}

extension UnlitMaterial {
    /// Unlit, alpha-blended material whose shape comes from a procedural opacity mask.
    /// The color's own alpha scales the mask.
    @MainActor
    static func stageSprite(_ mask: TextureResource?, color: UIColor) -> UnlitMaterial {
        let alpha = color.cgColor.alpha
        var material = UnlitMaterial(color: color.withAlphaComponent(1))
        if let mask {
            material.blending = .transparent(opacity: .init(scale: Float(alpha), texture: .init(mask)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: Float(alpha)))
        }
        material.faceCulling = .none
        return material
    }
}
