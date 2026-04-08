import Foundation

/// Manages the optional 6-digit PIN that protects access to Luma settings.
/// The PIN is stored in the Keychain under the "com.nox.luma.pin" key.
@MainActor
final class PINManager: ObservableObject {

    static let shared = PINManager()

    private let keychainKey = "com.nox.luma.pin"

    /// True if the user has set a PIN.
    @Published private(set) var hasPIN: Bool = false

    private init() {
        hasPIN = (try? KeychainManager.load(key: keychainKey)) != nil
    }

    // MARK: - PIN Operations

    /// Saves a new 6-digit PIN to the Keychain.
    func setPIN(_ pin: String) throws {
        guard pin.count == 6, pin.allSatisfy({ $0.isNumber }) else {
            throw PINError.invalidPINFormat
        }
        try KeychainManager.save(key: keychainKey, string: pin)
        hasPIN = true
    }

    /// Returns true if the provided PIN matches the stored PIN.
    func validatePIN(_ enteredPIN: String) -> Bool {
        guard let storedPIN = try? KeychainManager.loadString(key: keychainKey) else {
            return false
        }
        return enteredPIN == storedPIN
    }

    /// Removes the PIN (user can access settings without PIN after this).
    func clearPIN() throws {
        try KeychainManager.delete(key: keychainKey)
        hasPIN = false
    }

    // MARK: - Errors

    enum PINError: Error, LocalizedError {
        case invalidPINFormat

        var errorDescription: String? {
            "PIN must be exactly 6 digits."
        }
    }
}
