import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Generates bounded QR content for the authentication verification URL.
///
/// This is content rendering only: system controls, text, and accessibility
/// semantics remain in the surrounding SwiftUI surface.
enum PrismQRCodeContent {
    static let defaultPointSize: CGFloat = 220
    static let minimumPointSize: CGFloat = 96
    static let maximumPointSize: CGFloat = 512
    static let maximumPayloadBytes = 2_048

    static func image(for payload: String, pointSize: CGFloat = defaultPointSize) -> NSImage? {
        let normalizedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPayload.isEmpty,
              let message = normalizedPayload.data(using: .utf8),
              message.count <= maximumPayloadBytes,
              pointSize.isFinite,
              pointSize > 0 else {
            return nil
        }

        let displayPointSize = min(max(pointSize, minimumPointSize), maximumPointSize)
        let generator = CIFilter.qrCodeGenerator()
        generator.message = message
        generator.correctionLevel = "M"
        guard let generatedImage = generator.outputImage else {
            return nil
        }

        let sourceExtent = generatedImage.extent.integral
        guard sourceExtent.width > 0, sourceExtent.height > 0 else {
            return nil
        }

        let scale = Float(max(1, floor(displayPointSize / max(sourceExtent.width, sourceExtent.height))))
        let scaleFilter = CIFilter.lanczosScaleTransform()
        scaleFilter.inputImage = generatedImage
        scaleFilter.scale = scale
        scaleFilter.aspectRatio = 1
        guard let scaledImage = scaleFilter.outputImage,
              let renderedImage = CIContext().createCGImage(scaledImage, from: scaledImage.extent.integral) else {
            return nil
        }

        return NSImage(
            cgImage: renderedImage,
            size: NSSize(width: displayPointSize, height: displayPointSize)
        )
    }
}

struct PrismQRCodeContentView: View {
    let payload: String

    private var image: NSImage? {
        PrismQRCodeContent.image(for: payload)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: PrismQRCodeContent.defaultPointSize,
                        height: PrismQRCodeContent.defaultPointSize
                    )
                    .background(Color.white)
                    .accessibilityLabel(Text("Sign-In QR Code"))
                    .accessibilityValue(Text("Scan this code to continue sign-in. The verification URL is also shown as text."))
                    .accessibilityIdentifier("prism.settings.accounts.authentication-qr")
            } else {
                ContentUnavailableView(
                    "QR Code Unavailable",
                    systemImage: "qrcode",
                    description: Text("Use the verification URL and code shown below.")
                )
                .accessibilityIdentifier("prism.settings.accounts.authentication-qr-unavailable")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
