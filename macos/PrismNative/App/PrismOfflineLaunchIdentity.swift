import Foundation
import SwiftUI

enum PrismOfflineLaunchIdentityMode: Int, Equatable, Sendable {
    case offline
    case demo

    init?(bridgeMode: PROfflineLaunchIdentityMode) {
        switch bridgeMode {
        case .offline:
            self = .offline
        case .demo:
            self = .demo
        @unknown default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .offline:
            return "Offline"
        case .demo:
            return "Demo"
        }
    }

    var bridgeValue: PROfflineLaunchIdentityMode {
        switch self {
        case .offline:
            return .offline
        case .demo:
            return .demo
        }
    }
}

struct PrismOfflineLaunchIdentity: Equatable, Sendable {
    let mode: PrismOfflineLaunchIdentityMode
    let accountIdentifier: String?
    let name: String

    init?(bridgeIdentity: PROfflineLaunchIdentity) {
        guard let mode = PrismOfflineLaunchIdentityMode(bridgeMode: bridgeIdentity.mode),
              !bridgeIdentity.name.isEmpty else {
            return nil
        }

        self.mode = mode
        let identifier = bridgeIdentity.accountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountIdentifier = identifier?.isEmpty == false ? identifier : nil
        self.name = bridgeIdentity.name
    }

    init?(mode: PrismOfflineLaunchIdentityMode, accountIdentifier: String?, name: String) {
        guard !name.isEmpty else {
            return nil
        }

        self.mode = mode
        let identifier = accountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountIdentifier = identifier?.isEmpty == false ? identifier : nil
        self.name = name
    }

    static func fixture() -> PrismOfflineLaunchIdentity {
        PrismOfflineLaunchIdentity(
            mode: .offline,
            accountIdentifier: "account.fixture.offline",
            name: "Saved_Player"
        )!
    }
}

enum PrismOfflineLaunchIdentityValidation {
    static let legacyRuleDescription = "Use 3–16 English letters, numbers, or underscores."

    static func isValidLegacyName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard (3...16).contains(bytes.count) else {
            return false
        }

        return bytes.allSatisfy { byte in
            (65...90).contains(byte)
                || (97...122).contains(byte)
                || (48...57).contains(byte)
                || byte == 95
        }
    }
}

enum PrismOfflineLaunchIdentityOperation: Int, Equatable, Sendable {
    case load
    case save
}

struct PrismOfflineLaunchIdentityFailure: Equatable, Sendable {
    let operation: PrismOfflineLaunchIdentityOperation
    let localizationKey: String
    let diagnosticText: String?
    let recoveryAction: PrismInstanceDetailsRecoveryAction

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

enum PrismOfflineLaunchIdentityState: Equatable, Sendable {
    case idle
    case loading(generation: Int, fallbackName: String)
    case editing(confirmed: PrismOfflineLaunchIdentity, draftName: String, allowInvalidNames: Bool)
    case saving(
        generation: Int,
        confirmed: PrismOfflineLaunchIdentity,
        draftName: String,
        allowInvalidNames: Bool
    )
    case succeeded(PrismOfflineLaunchIdentity)
    case failed(
        failure: PrismOfflineLaunchIdentityFailure,
        confirmed: PrismOfflineLaunchIdentity?,
        draftName: String,
        allowInvalidNames: Bool
    )
    case cancelled(
        confirmed: PrismOfflineLaunchIdentity?,
        draftName: String,
        allowInvalidNames: Bool
    )
}

@MainActor
final class PrismOfflineLaunchIdentityModel: ObservableObject {
    @Published private(set) var state: PrismOfflineLaunchIdentityState = .idle

    private let onLoad: ((PrismOfflineLaunchIdentityMode, String?, String, Int) -> Void)?
    private let onSave: ((PrismOfflineLaunchIdentityMode, String?, String, Bool, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private let bridge: PRPrismBridge?
    private var loadToken: PRBridgeObservationToken?
    private var saveToken: PRBridgeObservationToken?
    private var generation = 0
    private var lastLoadRequest: (mode: PrismOfflineLaunchIdentityMode, accountIdentifier: String?, fallbackName: String)?
    private var lastSaveRequest: (mode: PrismOfflineLaunchIdentityMode, accountIdentifier: String?, name: String, allowInvalidNames: Bool)?

    init(
        initialIdentity: PrismOfflineLaunchIdentity? = nil,
        bridge: PRPrismBridge? = nil,
        onLoad: ((PrismOfflineLaunchIdentityMode, String?, String, Int) -> Void)? = nil,
        onSave: ((PrismOfflineLaunchIdentityMode, String?, String, Bool, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.onLoad = onLoad
        self.onSave = onSave
        self.onCancel = onCancel
        self.bridge = bridge
        if let initialIdentity {
            state = .editing(confirmed: initialIdentity, draftName: initialIdentity.name, allowInvalidNames: false)
        }
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    var isSaving: Bool {
        if case .saving = state {
            return true
        }
        return false
    }

    var isBusy: Bool {
        isLoading || isSaving
    }

    var confirmedIdentity: PrismOfflineLaunchIdentity? {
        switch state {
        case .editing(let confirmed, _, _), .saving(_, let confirmed, _, _):
            return confirmed
        case .succeeded(let identity):
            return identity
        case .failed(_, let confirmed, _, _), .cancelled(let confirmed, _, _):
            return confirmed
        case .idle, .loading:
            return nil
        }
    }

    var draftName: String {
        switch state {
        case .loading(_, let fallbackName):
            return fallbackName
        case .editing(_, let draftName, _), .saving(_, _, let draftName, _), .failed(_, _, let draftName, _),
                .cancelled(_, let draftName, _):
            return draftName
        case .succeeded(let identity):
            return identity.name
        case .idle:
            return ""
        }
    }

    var allowInvalidNames: Bool {
        switch state {
        case .editing(_, _, let allowInvalidNames), .saving(_, _, _, let allowInvalidNames),
                .failed(_, _, _, let allowInvalidNames), .cancelled(_, _, let allowInvalidNames):
            return allowInvalidNames
        case .idle, .loading, .succeeded:
            return false
        }
    }

    var nameIsValid: Bool {
        !draftName.isEmpty && PrismOfflineLaunchIdentityValidation.isValidLegacyName(draftName)
    }

    var canSave: Bool {
        if case .editing = state {
            return !draftName.isEmpty && (allowInvalidNames || nameIsValid)
        }
        return false
    }

    var failure: PrismOfflineLaunchIdentityFailure? {
        guard case .failed(let failure, _, _, _) = state else {
            return nil
        }
        return failure
    }

    var canRetry: Bool {
        failure?.isRetryAvailable == true
    }

    var currentGeneration: Int {
        generation
    }

    @discardableResult
    func load(
        mode: PrismOfflineLaunchIdentityMode = .offline,
        accountIdentifier: String?,
        fallbackName: String
    ) -> Bool {
        guard !fallbackName.isEmpty, !isBusy else {
            return false
        }

        let normalizedIdentifier = Self.normalizeIdentifier(accountIdentifier)
        generation += 1
        let activeGeneration = generation
        lastLoadRequest = (mode, normalizedIdentifier, fallbackName)
        state = .loading(generation: activeGeneration, fallbackName: fallbackName)
        if let bridge {
            loadToken?.cancel()
            loadToken = bridge.loadOfflineLaunchIdentity(
                with: mode.bridgeValue,
                accountIdentifier: normalizedIdentifier,
                fallbackName: fallbackName
            ) { [weak self] result, error in
                self?.loadToken = nil
                if let result {
                    _ = self?.apply(loadResult: result, generation: activeGeneration)
                } else if let error {
                    _ = self?.apply(error: error, generation: activeGeneration)
                }
            }
            if loadToken == nil {
                state = .failed(
                    failure: Self.failure(
                        operation: .load,
                        key: "accounts.offlineIdentity.unavailable",
                        diagnostic: nil,
                        retryable: true
                    ),
                    confirmed: nil,
                    draftName: fallbackName,
                    allowInvalidNames: false
                )
                return false
            }
            return true
        }

        guard let onLoad else {
            state = .failed(
                failure: Self.failure(
                    operation: .load,
                    key: "accounts.offlineIdentity.unavailable",
                    diagnostic: "The native offline identity adapter is not connected.",
                    retryable: true
                ),
                confirmed: nil,
                draftName: fallbackName,
                allowInvalidNames: false
            )
            return false
        }

        onLoad(mode, normalizedIdentifier, fallbackName, activeGeneration)
        return true
    }

    @discardableResult
    func updateDraftName(_ name: String) -> Bool {
        guard case .editing(let confirmed, _, let allowInvalidNames) = state else {
            guard case .failed(_, let confirmed, _, let failedAllowInvalidNames) = state, let confirmed else {
                return false
            }
            state = .editing(confirmed: confirmed, draftName: name, allowInvalidNames: failedAllowInvalidNames)
            return true
        }
        state = .editing(confirmed: confirmed, draftName: name, allowInvalidNames: allowInvalidNames)
        return true
    }

    @discardableResult
    func updateAllowInvalidNames(_ allowInvalidNames: Bool) -> Bool {
        guard case .editing(let confirmed, let draftName, _) = state else {
            return false
        }
        state = .editing(confirmed: confirmed, draftName: draftName, allowInvalidNames: allowInvalidNames)
        return true
    }

    @discardableResult
    func beginEditing() -> Bool {
        switch state {
        case .succeeded(let identity):
            state = .editing(confirmed: identity, draftName: identity.name, allowInvalidNames: false)
            return true
        case .failed(_, let confirmed, let draftName, let allowInvalidNames),
                .cancelled(let confirmed, let draftName, let allowInvalidNames):
            guard let confirmed else {
                return false
            }
            state = .editing(confirmed: confirmed, draftName: draftName, allowInvalidNames: allowInvalidNames)
            return true
        case .idle, .loading, .editing, .saving:
            return false
        }
    }

    @discardableResult
    func save() -> Bool {
        guard case .editing(let confirmed, let draftName, let allowInvalidNames) = state,
              !draftName.isEmpty,
              allowInvalidNames || PrismOfflineLaunchIdentityValidation.isValidLegacyName(draftName) else {
            return false
        }

        let mode = confirmed.mode
        let accountIdentifier = confirmed.accountIdentifier
        generation += 1
        let activeGeneration = generation
        lastSaveRequest = (mode, accountIdentifier, draftName, allowInvalidNames)
        state = .saving(
            generation: activeGeneration,
            confirmed: confirmed,
            draftName: draftName,
            allowInvalidNames: allowInvalidNames
        )
        if let bridge {
            saveToken?.cancel()
            saveToken = bridge.updateOfflineLaunchIdentity(
                with: mode.bridgeValue,
                accountIdentifier: accountIdentifier,
                name: draftName,
                allowInvalidName: allowInvalidNames
            ) { [weak self] result, error in
                self?.saveToken = nil
                if let result {
                    _ = self?.apply(updateResult: result, generation: activeGeneration)
                } else if let error {
                    _ = self?.apply(error: error, generation: activeGeneration)
                }
            }
            if saveToken == nil {
                state = .failed(
                    failure: Self.failure(
                        operation: .save,
                        key: "accounts.offlineIdentity.unavailable",
                        diagnostic: nil,
                        retryable: true
                    ),
                    confirmed: confirmed,
                    draftName: draftName,
                    allowInvalidNames: allowInvalidNames
                )
                return false
            }
            return true
        }

        guard let onSave else {
            state = .failed(
                failure: Self.failure(
                    operation: .save,
                    key: "accounts.offlineIdentity.unavailable",
                    diagnostic: "The native offline identity adapter is not connected.",
                    retryable: true
                ),
                confirmed: confirmed,
                draftName: draftName,
                allowInvalidNames: allowInvalidNames
            )
            return false
        }

        onSave(mode, accountIdentifier, draftName, allowInvalidNames, activeGeneration)
        return true
    }

    @discardableResult
    func apply(loadResult: PROfflineLaunchIdentityLoadResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .loading(let activeGeneration, let fallbackName) = state,
              (resultGeneration ?? activeGeneration) == activeGeneration,
              let request = lastLoadRequest else {
            return false
        }

        switch loadResult.outcome {
        case .succeeded:
            guard let identity = loadResult.identity,
                  let mapped = PrismOfflineLaunchIdentity(bridgeIdentity: identity),
                  mapped.mode == request.mode,
                  mapped.accountIdentifier == request.accountIdentifier else {
                state = .failed(
                    failure: Self.failure(
                        operation: .load,
                        key: "accounts.offlineIdentity.invalidResult",
                        diagnostic: nil,
                        retryable: true
                    ),
                    confirmed: nil,
                    draftName: fallbackName,
                    allowInvalidNames: false
                )
                return false
            }
            state = .editing(confirmed: mapped, draftName: mapped.name, allowInvalidNames: false)
        case .failed, .rejected:
            state = .failed(
                failure: Self.failure(
                    operation: .load,
                    key: loadResult.localizationKey,
                    diagnostic: loadResult.diagnosticText,
                    retryable: loadResult.retryable
                ),
                confirmed: nil,
                draftName: fallbackName,
                allowInvalidNames: false
            )
        case .cancelled:
            state = .cancelled(confirmed: nil, draftName: fallbackName, allowInvalidNames: false)
        @unknown default:
            state = .failed(
                failure: Self.failure(
                    operation: .load,
                    key: "accounts.offlineIdentity.unknownOutcome",
                    diagnostic: nil,
                    retryable: true
                ),
                confirmed: nil,
                draftName: fallbackName,
                allowInvalidNames: false
            )
            return false
        }
        return true
    }

    @discardableResult
    func apply(updateResult: PROfflineLaunchIdentityUpdateResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .saving(let activeGeneration, let confirmed, let draftName, let allowInvalidNames) = state,
              (resultGeneration ?? activeGeneration) == activeGeneration else {
            return false
        }

        switch updateResult.outcome {
        case .succeeded:
            guard let identity = updateResult.identity,
                  let mapped = PrismOfflineLaunchIdentity(bridgeIdentity: identity),
                  mapped.mode == confirmed.mode,
                  mapped.accountIdentifier == confirmed.accountIdentifier,
                  mapped.name == draftName else {
                state = .failed(
                    failure: Self.failure(
                        operation: .save,
                        key: "accounts.offlineIdentity.invalidResult",
                        diagnostic: nil,
                        retryable: true
                    ),
                    confirmed: confirmed,
                    draftName: draftName,
                    allowInvalidNames: allowInvalidNames
                )
                return false
            }
            state = .succeeded(mapped)
        case .invalidName, .failed, .rejected:
            state = .failed(
                failure: Self.failure(
                    operation: .save,
                    key: updateResult.localizationKey,
                    diagnostic: updateResult.diagnosticText,
                    retryable: updateResult.retryable
                ),
                confirmed: confirmed,
                draftName: draftName,
                allowInvalidNames: allowInvalidNames
            )
        case .cancelled:
            state = .cancelled(confirmed: confirmed, draftName: draftName, allowInvalidNames: allowInvalidNames)
        @unknown default:
            state = .failed(
                failure: Self.failure(
                    operation: .save,
                    key: "accounts.offlineIdentity.unknownOutcome",
                    diagnostic: nil,
                    retryable: true
                ),
                confirmed: confirmed,
                draftName: draftName,
                allowInvalidNames: allowInvalidNames
            )
            return false
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation resultGeneration: Int? = nil) -> Bool {
        guard !error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch state {
        case .loading(let activeGeneration, let fallbackName):
            guard (resultGeneration ?? activeGeneration) == activeGeneration else {
                return false
            }
            state = .failed(
                failure: Self.failure(
                    operation: .load,
                    key: error.localizationKey,
                    diagnostic: error.diagnosticText,
                    retryable: error.recoveryKind == .retry
                ),
                confirmed: nil,
                draftName: fallbackName,
                allowInvalidNames: false
            )
        case .saving(let activeGeneration, let confirmed, let draftName, let allowInvalidNames):
            guard (resultGeneration ?? activeGeneration) == activeGeneration else {
                return false
            }
            state = .failed(
                failure: Self.failure(
                    operation: .save,
                    key: error.localizationKey,
                    diagnostic: error.diagnosticText,
                    retryable: error.recoveryKind == .retry
                ),
                confirmed: confirmed,
                draftName: draftName,
                allowInvalidNames: allowInvalidNames
            )
        default:
            return false
        }
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        switch state {
        case .loading(_, let fallbackName):
            generation += 1
            loadToken?.cancel()
            loadToken = nil
            onCancel?()
            state = .cancelled(confirmed: nil, draftName: fallbackName, allowInvalidNames: false)
            return true
        case .saving(_, let confirmed, let draftName, let allowInvalidNames):
            generation += 1
            saveToken?.cancel()
            saveToken = nil
            onCancel?()
            state = .cancelled(confirmed: confirmed, draftName: draftName, allowInvalidNames: allowInvalidNames)
            return true
        case .editing(let confirmed, _, _):
            state = .cancelled(confirmed: confirmed, draftName: confirmed.name, allowInvalidNames: false)
            return true
        case .idle, .succeeded, .failed, .cancelled:
            return false
        }
    }

    @discardableResult
    func retry() -> Bool {
        guard case .failed(let failure, let confirmed, let draftName, let allowInvalidNames) = state,
              failure.isRetryAvailable else {
            return false
        }

        switch failure.operation {
        case .load:
            guard let request = lastLoadRequest else {
                return false
            }
            return load(
                mode: request.mode,
                accountIdentifier: request.accountIdentifier,
                fallbackName: request.fallbackName
            )
        case .save:
            guard let confirmed else {
                return false
            }
            state = .editing(confirmed: confirmed, draftName: draftName, allowInvalidNames: allowInvalidNames)
            return save()
        }
    }

    func reset() {
        generation += 1
        loadToken?.cancel()
        loadToken = nil
        saveToken?.cancel()
        saveToken = nil
        lastLoadRequest = nil
        lastSaveRequest = nil
        state = .idle
    }

    private static func normalizeIdentifier(_ identifier: String?) -> String? {
        let normalized = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private static func failure(
        operation: PrismOfflineLaunchIdentityOperation,
        key: String,
        diagnostic: String?,
        retryable: Bool
    ) -> PrismOfflineLaunchIdentityFailure {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return PrismOfflineLaunchIdentityFailure(
            operation: operation,
            localizationKey: normalizedKey.isEmpty ? "accounts.offlineIdentity.failed" : normalizedKey,
            diagnosticText: diagnostic,
            recoveryAction: retryable ? .retry : .none
        )
    }
}
