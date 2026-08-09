import AppKit
import Foundation
import XCTest

@MainActor
final class PrismContentRenderingTests: XCTestCase {
    func testQRCodeContentUsesFixturePayloadAndBoundedImageSize() {
        let image = PrismQRCodeContent.image(for: "https://login.invalid/verify?code=fixture")

        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width, PrismQRCodeContent.defaultPointSize)
        XCTAssertEqual(image?.size.height, PrismQRCodeContent.defaultPointSize)
        XCTAssertGreaterThan(image?.representations.first?.pixelsWide ?? 0, 0)
        XCTAssertGreaterThan(image?.representations.first?.pixelsHigh ?? 0, 0)
        XCTAssertNil(PrismQRCodeContent.image(for: "   "))
        XCTAssertNil(PrismQRCodeContent.image(for: String(repeating: "x", count: PrismQRCodeContent.maximumPayloadBytes + 1)))
        XCTAssertEqual(
            PrismQRCodeContent.image(for: "fixture", pointSize: 1)?.size.width,
            PrismQRCodeContent.minimumPointSize
        )
        XCTAssertEqual(
            PrismQRCodeContent.image(for: "fixture", pointSize: 10_000)?.size.width,
            PrismQRCodeContent.maximumPointSize
        )
    }

    func testNativeContentPathsUseSystemPresentationAndNoCustomControlDrawing() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let contentSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismContentRendering.swift"),
            encoding: .utf8
        )
        for requiredToken in [
            "CIFilter.qrCodeGenerator()",
            "CIContext()",
            "NSImage(",
            "Image(nsImage:",
            "ContentUnavailableView",
            ".accessibilityLabel",
            ".accessibilityValue",
            ".accessibilityIdentifier(\"prism.settings.accounts.authentication-qr\")"
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing QR content contract: \(requiredToken)")
        }
        for forbiddenToken in [
            "Canvas(",
            "CGContext",
            "NSBezierPath",
            "QPainter",
            "QOpenGL",
            "CatPainter",
            "drawRect",
            "paintEvent"
        ] {
            XCTAssertFalse(contentSource.contains(forbiddenToken), "Forbidden content-rendering token: \(forbiddenToken)")
        }

        let authenticationSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismAccountSettings.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(authenticationSource.contains("PrismQRCodeContentView(payload: verificationURL)"))
        XCTAssertTrue(authenticationSource.contains(".textSelection(.enabled)"))
        XCTAssertTrue(authenticationSource.contains("prism.settings.accounts.authentication-verification"))

        let screenshotsSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/ContentView.swift"),
            encoding: .utf8
        )
        for requiredToken in [
            "Table(model.visibleScreenshots, selection:",
            "Button(\"Open\", systemImage:",
            "Button(\"Copy Image\", systemImage:",
            "ContentUnavailableView(",
            "prism.instance-screenshots.empty-state"
        ] {
            XCTAssertTrue(screenshotsSource.contains(requiredToken), "Missing system screenshot representation: \(requiredToken)")
        }
        XCTAssertFalse(screenshotsSource.contains("QPainter"))
        XCTAssertFalse(screenshotsSource.contains("Canvas("))

        let bridgeModelsSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/Bridge/PrismBridgeModels.h"),
            encoding: .utf8
        )
        XCTAssertTrue(bridgeModelsSource.contains("image bytes remain a system action"))
    }
}
