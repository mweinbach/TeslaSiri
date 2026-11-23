import CoreGraphics
import Foundation
import RealityKit

@MainActor enum StudioPaint {
    /// Environment BRDF of the recovered GLES2 material, in its native color domain.
    nonisolated static func response(rgb: SIMD3<Float>, metallic m: Float, roughness r: Float,
                                     cosine v: Float) -> (specular: SIMD3<Float>, diffuse: SIMD3<Float>) {
        let f0 = SIMD3<Float>(repeating: 0.04 * (1 - m)) + rgb * m
        let f90 = simd_max(f0, SIMD3(repeating: 1 - r))
        let f = f0 + (f90 - f0) * pow(1 - v, 5)
        let x = 1 - r, a = min(x * x, pow(2, -9.28 * v)) * x + 0.0425 - 0.0275 * r
        let specular = f * (1.04 - 0.572 * r - 1.04 * a) + SIMD3(repeating: 0.022 * r - 0.04 + 1.04 * a)
        return (specular, (SIMD3<Float>(repeating: 1) - f) * rgb * (1 - m))
    }

    /// Two 512-texel BRDF tables, not a texture of the painted car. The graph
    /// retains each mesh's own occlusion, view vector and live reflections.
    static func weights(rgb:SIMD3<Float>,metallic m:Float,roughness r:Float) throws -> (TextureResource,TextureResource) {
        var spec=[UInt8](),diff=[UInt8]()
        func encoded(_ v:Float)->UInt8 {
            let t=min(1,max(0,v)),s=t<=0.0031308 ? 12.92*t : 1.055*pow(t,1/2.4)-0.055
            return UInt8(clamping:Int((255*s).rounded()))
        }
        for i in 0..<512 {
            let weight = response(rgb: rgb, metallic: m, roughness: r, cosine: (Float(i) + 0.5) / 512)
            for k in 0..<3 {spec.append(encoded(weight.specular[k]));diff.append(encoded(weight.diffuse[k]))}
            spec.append(255);diff.append(255)
        }
        func texture(_ data:[UInt8]) throws -> TextureResource {
            let image=CGImage(width:512,height:1,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:2048,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:.init(rawValue:CGImageAlphaInfo.noneSkipLast.rawValue),
                provider:CGDataProvider(data:Data(data) as CFData)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
            return try TextureResource(image: image, options: .init(semantic: .color))
        }
        return try (texture(spec),texture(diff))
    }
}
