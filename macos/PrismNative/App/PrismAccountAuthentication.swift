import Foundation
import SwiftUI

enum PrismAccountAuthenticationAction: Int, Equatable, Sendable {
    case login
    case refresh

    init?(bridgeAction: PRAccountAuthenticationAction) {
        switch bridgeAction {
        case .login:
            self = .login
        case .refresh:
            self = .refresh
        @unknown default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .login:
            return "Sign In"
        case .refresh:
            return "Refresh Sign-In"
        }
    }

    var bridgeValue: PRAccountAuthenticationAction {
        switch self {
        case .login:
            return .login
        case .refresh:
            return .refresh
        }
    }
}

enum PrismAccountAuthenticationPhase: Int, Equatable, Sendable {
    case preparing
    case awaitingUser
    case authenticating
    case succeeded
    case failed
    case cancelled

    init?(bridgePhase: PRAccountAuthenticationPhase) {
        switch bridgePhase {
        case .preparing:
            self = .preparing
        case .awaitingUser:
            self = .awaitingUser
        case .authenticating:
            self = .authenticating
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        @unknown default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .preparing:
            return "Preparing sign-in"
        case .awaitingUser:
            return "Waiting for confirmation"
        case .authenticating:
            return "Finishing sign-in"
        case .succeeded:
            return "Sign-in complete"
        case .failed:
            return "Sign-in failed"
        case .cancelled:
            return "Sign-in cancelled"
        }
    }
}

struct PrismAccountAuthenticationProgress: Equatable, Sendable {
    let accountIdentifier: String
    let action: PrismAccountAuthenticationAction
    let phase: PrismAccountAuthenticationPhase
    let providerLabel: String
    let verificationURL: String?
    let localizationKey: String
    let diagnosticText: String?
    let expiresInSeconds: Int
    let canCancel: Bool
    let retryable: Bool
    let requiresUserAction: Bool

    init?(bridgeProgress: PRAccountAuthenticationProgress) {
        let identifier = bridgeProgress.accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = bridgeProgress.providerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = bridgeProgress.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              !provider.isEmpty,
              !key.isEmpty,
              let action = PrismAccountAuthenticationAction(bridgeAction: bridgeProgress.action),
              let phase = PrismAccountAuthenticationPhase(bridgePhase: bridgeProgress.phase),
              bridgeProgress.expiresInSeconds >= 0 else {
            return nil
        }

        let verification = bridgeProgress.verificationURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnostic = bridgeProgress.diagnosticText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountIdentifier = identifier
        self.action = action
        self.phase = phase
        self.providerLabel = provider
        self.verificationURL = verification?.isEmpty == false ? verification : nil
        self.localizationKey = key
        self.diagnosticText = diagnostic?.isEmpty == false ? diagnostic : nil
        self.expiresInSeconds = bridgeProgress.expiresInSeconds
        self.canCancel = bridgeProgress.canCancel
        self.retryable = bridgeProgress.retryable
        self.requiresUserAction = bridgeProgress.requiresUserAction
    }

    var isAwaitingUser: Bool {
        phase == .awaitingUser && requiresUserAction
    }
}

enum PrismAccountAuthenticationState: Equatable, Sendable {
    case idle
    case starting(generation: Int, accountIdentifier: String, action: PrismAccountAuthenticationAction)
    case running(PrismAccountAuthenticationProgress)
    case succeeded(PrismAccount?)
    case failed(PrismAccountFailure)
    case cancelled
}

@MainActor
final class PrismAccountAuthenticationModel: ObservableObject {
    @Published private(set) var state: PrismAccountAuthenticationState = .idle

    private let onAuthenticate: ((String, PrismAccountAuthenticationAction, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private let bridge: PRPrismBridge?
    private var authenticationToken: PRBridgeObservationToken?
    private var generation = 0
    private var lastRequest: (accountIdentifier: String, action: PrismAccountAuthenticationAction)?

    init(
        bridge: PRPrismBridge? = nil,
        onAuthenticate: ((String, PrismAccountAuthenticationAction, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.onAuthenticate = onAuthenticate
        self.onCancel = onCancel
        self.bridge = bridge
    }

    var isRunning: Bool {
        switch state {
        case .starting, .running:
            return true
        case .idle, .succeeded, .failed, .cancelled:
            return false
        }
    }

    var isCancellable: Bool {
        switch state {
        case .starting:
            return true
        case .running(let progress):
            return progress.canCancel
        case .idle, .succeeded, .failed, .cancelled:
            return false
        }
    }

    var currentProgress: PrismAccountAuthenticationProgress? {
        guard case .running(let progress) = state else {
            return nil
        }
        return progress
    }

    var authenticationFailure: PrismAccountFailure? {
        guard case .failed(let failure) = state else {
            return nil
        }
        return failure
    }

    var canRetry: Bool {
        authenticationFailure?.isRetryAvailable == true
    }

    var currentGeneration: Int {
        generation
    }

    @discardableResult
    func start(accountIdentifier: String, action: PrismAccountAuthenticationAction = .login) -> Bool {
        let normalizedIdentifier = accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty, !isRunning else {
            return false
        }

        generation += 1
        let activeGeneration = generation
        lastRequest = (normalizedIdentifier, action)
        state = .starting(generation: activeGeneration, accountIdentifier: normalizedIdentifier, action: action)
        if let bridge {
            authenticationToken?.cancel()
            authenticationToken = bridge.authenticateAccount(
                withIdentifier: normalizedIdentifier,
                action: action.bridgeValue,
                progress: { [weak self] progress in
                    _ = self?.apply(progress: progress, generation: activeGeneration)
                },
                completion: { [weak self] result, error in
                    self?.authenticationToken = nil
                    if let result {
                        _ = self?.apply(result: result, generation: activeGeneration)
                    } else if let error {
                        _ = self?.apply(error: error, generation: activeGeneration)
                    }
                }
            )
            if authenticationToken == nil {
                state = .failed(
                    Self.failure(
                        key: "accounts.authentication.unavailable",
                        diagnostic: nil,
                        retryable: true
                    )
                )
                return false
            }
            return true
        }

        guard let onAuthenticate else {
            state = .failed(
                Self.failure(
                    key: "accounts.authentication.unavailable",
                    diagnostic: "The native authentication adapter is not connected.",
                    retryable: true
                )
            )
            return false
        }
        onAuthenticate(normalizedIdentifier, action, activeGeneration)
        return true
    }

    @discardableResult
    func apply(progress: PRAccountAuthenticationProgress, generation resultGeneration: Int? = nil) -> Bool {
        guard let request = lastRequest,
              let mapped = PrismAccountAuthenticationProgress(bridgeProgress: progress),
              mapped.accountIdentifier == request.accountIdentifier,
              mapped.action == request.action,
              (resultGeneration ?? generation) == generation else {
            return false
        }

        switch progress.outcome {
        case .inProgress:
            state = .running(mapped)
        case .succeeded:
            state = .succeeded(nil)
        case .failed, .rejected:
            state = .failed(
                Self.failure(key: mapped.localizationKey, diagnostic: mapped.diagnosticText, retryable: mapped.retryable)
            )
        case .cancelled:
            state = .cancelled
        @unknown default:
            state = .failed(Self.failure(key: "accounts.authentication.unknownOutcome", diagnostic: nil, retryable: true))
            return false
        }
        return true
    }

    @discardableResult
    func apply(result: PRAccountAuthenticationResult, generation resultGeneration: Int? = nil) -> Bool {
        guard let request = lastRequest, (resultGeneration ?? generation) == generation else {
            return false
        }
        switch result.outcome {
        case .succeeded:
            guard let account = result.account,
                  let mapped = PrismAccount(bridgeAccount: account),
                  mapped.id == request.accountIdentifier,
                  mapped.type == .microsoft,
                  mapped.state == .online,
                  mapped.isSelectable else {
                state = .failed(Self.failure(key: "accounts.authentication.invalidResult", diagnostic: nil, retryable: true))
                return false
            }
            state = .succeeded(mapped)
        case .failed, .rejected:
            state = .failed(
                Self.failure(
                    key: result.localizationKey,
                    diagnostic: result.diagnosticText,
                    retryable: result.retryable
                )
            )
        case .cancelled:
            state = .cancelled
        case .inProgress:
            return false
        @unknown default:
            state = .failed(Self.failure(key: "accounts.authentication.unknownOutcome", diagnostic: nil, retryable: true))
            return false
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation resultGeneration: Int? = nil) -> Bool {
        guard lastRequest != nil,
              (resultGeneration ?? generation) == generation,
              !error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        state = .failed(
            Self.failure(
                key: error.localizationKey,
                diagnostic: error.diagnosticText,
                retryable: error.recoveryKind == .retry
            )
        )
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard isCancellable else {
            return false
        }
        generation += 1
        authenticationToken?.cancel()
        authenticationToken = nil
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard canRetry, let request = lastRequest else {
            return false
        }
        return start(accountIdentifier: request.accountIdentifier, action: request.action)
    }

    func reset() {
        generation += 1
        authenticationToken?.cancel()
        authenticationToken = nil
        state = .idle
    }

    private static func failure(key: String, diagnostic: String?, retryable: Bool) -> PrismAccountFailure {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return PrismAccountFailure(
            localizationKey: normalizedKey.isEmpty ? "accounts.authentication.failed" : normalizedKey,
            diagnosticText: diagnostic,
            recoveryAction: retryable ? .retry : .none
        )
    }
}
