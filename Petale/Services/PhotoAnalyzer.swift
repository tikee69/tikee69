import CoreGraphics
import ImageIO
import Photos
import UIKit
import Vision

/// Analyse une photo avec l'IA d'Apple, directement sur l'iPhone.
enum PhotoAnalyzer {
    static let analysisSize: CGFloat = 512

    static func analyze(id: String) async -> PhotoAnalysis? {
        let options = LibraryScanner.fetchOptions()
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options).firstObject else {
            return nil
        }
        guard let loaded = await loadImage(for: asset) else { return nil }
        if Task.isCancelled { return nil }
        return analyze(cgImage: loaded.0, orientation: loaded.1)
    }

    // MARK: Chargement de l'image

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    static func loadImage(for asset: PHAsset) async -> (CGImage, CGImagePropertyOrientation)? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true   // photos stockées sur iCloud
        options.isSynchronous = false
        options.version = .current

        let once = ResumeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<(CGImage, CGImagePropertyOrientation)?, Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: analysisSize, height: analysisSize),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                guard once.claim() else { return }
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                if let cg = image.cgImage {
                    continuation.resume(returning: (cg, CGImagePropertyOrientation(image.imageOrientation)))
                } else {
                    // Image sans CGImage (rare) : on la redessine.
                    let renderer = UIGraphicsImageRenderer(size: image.size)
                    let redrawn = renderer.image { _ in image.draw(at: .zero) }
                    if let cg = redrawn.cgImage {
                        continuation.resume(returning: (cg, .up))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    // MARK: Analyse

    static func analyze(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> PhotoAnalysis? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        // 1. Empreinte (indispensable)
        let featureRequest = VNGenerateImageFeaturePrintRequest()
        do {
            try handler.perform([featureRequest])
        } catch {
            return nil
        }
        guard let observation = featureRequest.results?.first,
              let rawVector = vector(from: observation), !rawVector.isEmpty
        else { return nil }
        let vector = VectorMath.normalized(rawVector)

        // 2. Ce qu'il y a sur la photo
        var labels: [String] = []
        let classifyRequest = VNClassifyImageRequest()
        if (try? handler.perform([classifyRequest])) != nil {
            let observations = classifyRequest.results ?? []
            labels = observations
                .filter { obs in
                    obs.hasPrecisionRecallCurve
                        ? obs.hasMinimumRecall(0.01, forPrecision: 0.9)
                        : obs.confidence > 0.6
                }
                .prefix(10)
                .map(\.identifier)
        }

        // 3. Esthétique et photo « utilitaire »
        var aesthetic: Float?
        var isUtility = false
        let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
        if (try? handler.perform([aestheticsRequest])) != nil, let result = aestheticsRequest.results?.first {
            aesthetic = result.overallScore
            isUtility = result.isUtility
        }

        // 4. Qualité des visages (yeux fermés, flou de bougé…)
        var faceQuality: Float?
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        if (try? handler.perform([faceRequest])) != nil {
            let qualities = (faceRequest.results ?? []).compactMap { obs in obs.faceCaptureQuality.map { Float(truncating: $0 as NSNumber) } }
            if !qualities.isEmpty {
                faceQuality = qualities.reduce(0, +) / Float(qualities.count)
            }
        }

        // 5. Netteté et exposition (calcul maison sur les pixels)
        let stats = pixelStatistics(cgImage)

        return PhotoAnalysis(
            version: PhotoAnalysis.currentVersion,
            vectorData: VectorMath.data(from: vector),
            aesthetic: aesthetic,
            isUtility: isUtility,
            sharpness: stats.sharpness,
            exposure: stats.exposure,
            faceQuality: faceQuality,
            labels: labels
        )
    }

    private static func vector(from observation: VNFeaturePrintObservation) -> [Float]? {
        let data = observation.data
        switch observation.elementType {
        case .float:
            return VectorMath.vector(from: data)
        case .double:
            let count = data.count / MemoryLayout<Double>.size
            var doubles = [Double](repeating: 0, count: count)
            doubles.withUnsafeMutableBytes { dest in
                _ = data.copyBytes(to: dest, count: count * MemoryLayout<Double>.size)
            }
            return doubles.map { Float($0) }
        default:
            return nil
        }
    }

    /// Netteté (variance du laplacien) et qualité d'exposition (histogramme).
    static func pixelStatistics(_ image: CGImage) -> (sharpness: Float, exposure: Float) {
        let maxSide = 256.0
        let scale = min(1.0, maxSide / Double(max(image.width, image.height, 1)))
        let width = max(8, Int(Double(image.width) * scale))
        let height = max(8, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height)

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return (0, 0.5) }

        // Laplacien
        var sum = 0.0, sumSquares = 0.0, count = 0.0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let i = row + x
                let center = Int(pixels[i]) * 4
                let lap = center - Int(pixels[i - 1]) - Int(pixels[i + 1]) - Int(pixels[i - width]) - Int(pixels[i + width])
                let v = Double(lap)
                sum += v
                sumSquares += v * v
                count += 1
            }
        }
        let mean = count > 0 ? sum / count : 0
        let variance = count > 0 ? max(0, sumSquares / count - mean * mean) : 0

        // Exposition
        var lumSum = 0.0, dark = 0.0, bright = 0.0
        for p in pixels {
            lumSum += Double(p)
            if p < 16 { dark += 1 }
            if p > 240 { bright += 1 }
        }
        let n = Double(pixels.count)
        let meanLum = lumSum / n
        let penalty = abs(meanLum - 118) / 118 * 0.6 + (dark / n) * 1.2 + (bright / n) * 1.2
        let exposure = max(0, min(1, 1 - penalty))

        return (Float(variance), Float(exposure))
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
