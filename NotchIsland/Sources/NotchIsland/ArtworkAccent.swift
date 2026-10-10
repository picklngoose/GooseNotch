import AppKit

struct AccentRGB: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

/// Picks a representative, vivid colour from album artwork.
enum ArtworkAccent {
    /// Shrinks the image, buckets pixels by hue weighted by how colourful and bright they are, and
    /// returns the winning bucket's average, adjusted to read well on a dark island. Returns nil
    /// for artwork with no real colour (greyscale covers), so callers keep their default.
    nonisolated static func dominant(from data: Data) -> AccentRGB? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 32
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        let bucketCount = 12
        var weight = [Double](repeating: 0, count: bucketCount)
        var sumR = [Double](repeating: 0, count: bucketCount)
        var sumG = [Double](repeating: 0, count: bucketCount)
        var sumB = [Double](repeating: 0, count: bucketCount)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[index + 3] > 128 else { continue }
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let delta = high - low
            let saturation = high == 0 ? 0 : delta / high
            // Skip near-black and near-grey pixels: they say nothing about the cover's colour.
            guard high > 0.2, saturation > 0.2 else { continue }

            var hue: Double
            if high == r { hue = (g - b) / delta }
            else if high == g { hue = 2 + (b - r) / delta }
            else { hue = 4 + (r - g) / delta }
            hue /= 6
            if hue < 0 { hue += 1 }

            let bucket = min(Int(hue * Double(bucketCount)), bucketCount - 1)
            let w = saturation * high
            weight[bucket] += w
            sumR[bucket] += r * w
            sumG[bucket] += g * w
            sumB[bucket] += b * w
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0.5 else {
            return nil
        }
        let base = NSColor(
            deviceRed: sumR[best] / weight[best],
            green: sumG[best] / weight[best],
            blue: sumB[best] / weight[best],
            alpha: 1
        )

        // Keep it soft rather than saturated, and light enough for small accents on a dark background.
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        let adjusted = NSColor(
            deviceHue: hue,
            saturation: min(max(saturation, 0.25), 0.6),
            brightness: min(max(brightness, 0.78), 0.95),
            alpha: 1
        )
        guard let rgb = adjusted.usingColorSpace(.deviceRGB) else { return nil }
        return AccentRGB(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}
