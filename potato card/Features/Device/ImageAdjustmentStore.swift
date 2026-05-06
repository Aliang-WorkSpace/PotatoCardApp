import CoreGraphics
import Foundation

struct ImageAdjustmentStore {
    private let keyPrefix = "imageManualAdjustment."
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadAdjustment(sourceID: String, targetSize: CGSize) -> EInkManualAdjustment? {
        guard
            let data = userDefaults.data(forKey: key(sourceID: sourceID, targetSize: targetSize)),
            let adjustment = try? decoder.decode(EInkManualAdjustment.self, from: data)
        else {
            return nil
        }

        return adjustment
    }

    func save(_ adjustment: EInkManualAdjustment, sourceID: String, targetSize: CGSize) {
        guard let data = try? encoder.encode(adjustment) else { return }
        userDefaults.set(data, forKey: key(sourceID: sourceID, targetSize: targetSize))
    }

    private func key(sourceID: String, targetSize: CGSize) -> String {
        let sizeKey = "\(Int(targetSize.width.rounded()))x\(Int(targetSize.height.rounded()))"
        return keyPrefix + sanitized(sourceID) + "." + sizeKey
    }

    private func sanitized(_ value: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? "unknown-source" : sanitized
    }
}
