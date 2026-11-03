import Foundation
import Vision
import UIKit
import CoreImage.CIFilterBuiltins
import SoNoCore

struct AppleHandwritingOCR: HandwritingOCRService {
    func recognize(_ image: Data) async throws -> String {
        guard image.count <= 20_000_000 else { throw LedgerError.invalid("Ảnh vượt 20 MB.") }
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            let languages = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = languages.contains("vi-VN") ? ["vi-VN", "en-US"].filter(languages.contains) : ["en-US"].filter(languages.contains)
            let handler = VNImageRequestHandler(data: image, options: [:])
            try handler.perform([request]); try Task.checkCancellation()
            let lines = (request.results ?? []).sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.015 { return $0.boundingBox.midY > $1.boundingBox.midY }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            return lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

enum ImagePreparation {
    static func prepare(_ data: Data, rotate: Bool = false, enhance: Bool = false) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard data.count <= 20_000_000, let source = CIImage(data: data, options: [.applyOrientationProperty: true]),
                  source.extent.width * source.extent.height <= 60_000_000 else { throw LedgerError.invalid("Ảnh không hợp lệ hoặc quá lớn.") }
            var image = source
            if rotate { image = image.oriented(.right) }
            if enhance {
                let controls = CIFilter.colorControls(); controls.inputImage = image; controls.contrast = 1.2; controls.saturation = 0
                image = controls.outputImage ?? image
                let sharpen = CIFilter.sharpenLuminance(); sharpen.inputImage = image; sharpen.sharpness = 0.5
                image = sharpen.outputImage ?? image
            }
            let scale = min(1, 2400 / max(image.extent.width, image.extent.height))
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let context = CIContext(options: [.cacheIntermediates: false])
            guard let cgImage = context.createCGImage(image, from: image.extent), let output = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) else { throw LedgerError.invalid("Không xử lý được ảnh.") }
            return output
        }.value
    }
}
