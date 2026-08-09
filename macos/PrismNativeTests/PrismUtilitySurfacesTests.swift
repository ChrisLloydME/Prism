import Foundation
import XCTest

@MainActor
final class PrismUtilitySurfacesTests: XCTestCase {
    func testAboutMetadataKeepsBuildValuesOptionalAndRepositoryWebOnly() {
        let metadata = PrismAboutMetadata.fixture

        XCTAssertEqual(metadata.productName, "Prism")
        XCTAssertEqual(metadata.version, "9.9.9-fixture")
        XCTAssertEqual(metadata.repositoryURL?.scheme, "https")
        XCTAssertNotNil(metadata.commit)
        XCTAssertNotNil(metadata.buildDate)
        XCTAssertNotNil(metadata.channel)

        let unsafe = PrismAboutMetadata(
            productName: "Prism",
            version: "fixture",
            repositoryURL: URL(string: "file:///private/tmp/fixture"),
            copyright: "fixture",
            aboutText: "fixture",
            creditsText: "fixture",
            licenseText: "fixture"
        )
        XCTAssertNil(unsafe.repositoryURL)
    }

    func testNewsModelCoversSelectionCancellationRetryAndStaleResults() throws {
        var loadGenerations: [Int] = []
        var cancellationCount = 0
        let model = PrismNewsModel(
            onLoad: { loadGenerations.append($0) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.load())
        let firstGeneration = try XCTUnwrap(loadGenerations.first)
        XCTAssertEqual(model.state, .loading)
        XCTAssertTrue(model.apply(entries: [.fixture], generation: firstGeneration))
        XCTAssertTrue(model.selectEntry("news.fixture"))
        XCTAssertEqual(model.selectedEntry?.title, "Fixture News")

        XCTAssertTrue(model.load())
        let secondGeneration = try XCTUnwrap(loadGenerations.last)
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(model.apply(entries: [.fixture], generation: secondGeneration))

        XCTAssertTrue(model.load())
        let thirdGeneration = try XCTUnwrap(loadGenerations.last)
        XCTAssertTrue(model.apply(
            failure: PrismNewsFailure(localizationKey: "news.fixture.failure", diagnosticText: "fixture", retryable: true),
            generation: thirdGeneration
        ))
        XCTAssertTrue(model.retry())
        XCTAssertEqual(loadGenerations.count, 4)
        XCTAssertFalse(model.selectEntry("missing"))
    }

    func testUpdateModelPreservesTypedDecisionsAndGeneration() throws {
        var checkGenerations: [Int] = []
        var decisions: [PrismUpdateDecision] = []
        let model = PrismUpdateModel(
            onCheck: { checkGenerations.append($0) },
            onDecision: { decision, _ in decisions.append(decision) }
        )

        XCTAssertTrue(model.check())
        let generation = try XCTUnwrap(checkGenerations.first)
        XCTAssertFalse(model.applyNoUpdate(generation: generation + 1))
        XCTAssertTrue(model.apply(notice: .fixture, generation: generation))
        XCTAssertTrue(model.choose(.install))
        XCTAssertEqual(decisions, [.install])
        XCTAssertFalse(model.choose(.skipVersion))
    }

    func testProviderChoiceModelKeepsSkipAndConfirmSemantics() {
        var responses: [PrismProviderChoiceResponse] = []
        let model = PrismProviderChoiceModel(
            providers: [.modrinth, .curseForge],
            initialProvider: .curseForge,
            onDecision: { responses.append($0) }
        )

        model.tryOthers = true
        XCTAssertTrue(model.choose(.confirmAll))
        XCTAssertEqual(
            responses,
            [PrismProviderChoiceResponse(action: .confirmAll, provider: .curseForge, tryOthers: true)]
        )
        model.reset()
        XCTAssertTrue(model.choose(.skipAll))
        XCTAssertEqual(responses.last, PrismProviderChoiceResponse(action: .skipAll, provider: nil, tryOthers: true))

        let singleChoice = PrismProviderChoiceModel(
            providers: [.modrinth],
            singleChoice: true,
            allowSkipping: false
        )
        XCTAssertFalse(singleChoice.choose(.confirmAll))
        XCTAssertFalse(singleChoice.choose(.skipOne))
        XCTAssertTrue(singleChoice.choose(.confirmOne))
    }

    func testRecoveryMessageModelGuardsActionsAndCopiesFixtureDetails() throws {
        var decisions: [PrismRecoveryDecision] = []
        let model = PrismRecoveryMessageModel(onDecision: { decisions.append($0) })
        let detail = try XCTUnwrap(PrismRecoveryDetail(id: "url", label: "URL", value: "https://example.invalid/fixture"))
        model.present(PrismRecoveryMessage(
            titleKey: "recovery.fixture.title",
            messageKey: "recovery.fixture.message",
            diagnosticText: "fixture diagnostic",
            details: [detail],
            retryAvailable: true,
            editAvailable: false,
            partialChangesRolledBack: true
        ))

        XCTAssertTrue(model.copyDetails())
        XCTAssertFalse(model.choose(.edit))
        XCTAssertTrue(model.choose(.retry))
        XCTAssertEqual(decisions, [.retry])
        model.reset()
        XCTAssertEqual(model.state, .idle)
    }

    func testShortcutModelValidatesTargetsDestinationAndStaleResults() throws {
        var requests: [PrismShortcutCreationRequest] = []
        var generations: [Int] = []
        let model = PrismShortcutCreationModel(
            instanceIdentifier: "fixture.instance",
            instanceName: "Fixture Instance",
            worlds: [PrismShortcutWorld(id: "world.fixture", displayName: "Fixture World")],
            profiles: [PrismShortcutProfile(id: "profile.fixture", displayName: "Fixture Profile")],
            onCreate: { request, generation in
                requests.append(request)
                generations.append(generation)
            }
        )

        model.setLaunchTarget(.world)
        XCTAssertNotNil(model.validationMessage)
        model.setWorldID("world.fixture")
        model.draft.overrideAccount = true
        model.setProfileID("profile.fixture")
        model.setDestination(.other)
        XCTAssertNotNil(model.validationMessage)

        let originalURL = URL(fileURLWithPath: "/private/tmp/prism-native-m9-w1-fixture/original")
        let replacementURL = URL(fileURLWithPath: "/private/tmp/prism-native-m9-w1-fixture/replacement")
        let cancelledToken = try XCTUnwrap(model.beginOtherDestinationPanel())
        XCTAssertTrue(model.applyOtherDestinationPanelResult(nil, token: cancelledToken))
        XCTAssertNil(model.draft.destinationURL)
        let destinationToken = try XCTUnwrap(model.beginOtherDestinationPanel())
        XCTAssertTrue(model.applyOtherDestinationPanelResult(originalURL, token: destinationToken))
        XCTAssertEqual(model.draft.destinationURL, originalURL.standardizedFileURL)

        XCTAssertTrue(model.startCreate())
        let generation = try XCTUnwrap(generations.first)
        XCTAssertEqual(requests.first?.launchTarget, .world)
        XCTAssertEqual(requests.first?.destinationURL, originalURL.standardizedFileURL)
        XCTAssertTrue(model.apply(result: .succeeded(for: "fixture.instance"), generation: generation))
        XCTAssertEqual(model.state, .succeeded)

        model.reset()
        let staleToken = try XCTUnwrap(model.beginOtherDestinationPanel())
        model.setDestination(.desktop)
        XCTAssertFalse(model.applyOtherDestinationPanelResult(replacementURL, token: staleToken))
        XCTAssertNil(model.draft.destinationURL)
    }

    func testUtilitySurfacesUseSystemControlsAndKeepNativeBoundaryClean() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismUtilitySurfaces.swift"),
            encoding: .utf8
        )
        for requiredToken in [
            "PrismAboutMetadata",
            "PrismNewsModel",
            "PrismUpdateModel",
            "PrismProviderChoiceModel",
            "PrismRecoveryMessageModel",
            "PrismShortcutCreationModel",
            "TabView",
            "NavigationSplitView",
            "List(",
            "Form {",
            "LabeledContent",
            "ContentUnavailableView",
            "ProgressView",
            "PrismSystemSavePanel.present",
            "NSPasteboard.general",
            "keyboardShortcut(.defaultAction)",
            "keyboardShortcut(.cancelAction)",
            ".accessibilityIdentifier",
            "LocalizedStringKey"
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native utility API: \(requiredToken)")
        }
        for forbiddenToken in [
            "QWidget",
            "QDialog",
            "Qt",
            "std::",
            "URLSession",
            "Process(",
            "FileManager",
            "Canvas(",
            "draw(",
            "CGContext",
            "NSBezierPath",
            "CALayer"
        ] {
            XCTAssertFalse(source.contains(forbiddenToken), "Forbidden utility token: \(forbiddenToken)")
        }

        let commandSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismCommands.swift"),
            encoding: .utf8
        )
        for requiredToken in [
            "openWindow(id: \"prism.about\")",
            "openWindow(id: \"prism.news\")",
            "openWindow(id: \"prism.updates\")",
            "openWindow(id: \"prism.create-shortcut\")",
            "CommandGroup(replacing: .appInfo)"
        ] {
            XCTAssertTrue(commandSource.contains(requiredToken), "Missing utility command routing: \(requiredToken)")
        }
        XCTAssertFalse(commandSource.contains("QMessageBox"))

        let appSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismNativeApp.swift"),
            encoding: .utf8
        )
        for requiredToken in [
            "Window(\"About Prism\", id: \"prism.about\")",
            "Window(\"News\", id: \"prism.news\")",
            "Window(\"Check for Updates\", id: \"prism.updates\")",
            "Window(\"Create Shortcut\", id: \"prism.create-shortcut\")",
            "PrismShortcutCreationModel"
        ] {
            XCTAssertTrue(appSource.contains(requiredToken), "Missing utility window registration: \(requiredToken)")
        }

        let commandModelSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismCommandModel.swift"),
            encoding: .utf8
        )
        for requiredToken in ["case news", "case checkForUpdates", "case createShortcut", "requiresSelection: true"] {
            XCTAssertTrue(commandModelSource.contains(requiredToken), "Missing utility command contract: \(requiredToken)")
        }
    }
}
