import Foundation

enum ProjectedContentType: String, Codable, Equatable {
    case weather
    case album
    case gallery
    case todo
    case unknown

    var title: String {
        switch self {
        case .weather:
            return "天气"
        case .album:
            return "专辑"
        case .gallery:
            return "图库"
        case .todo:
            return "待办"
        case .unknown:
            return "未知"
        }
    }
}

struct ProjectedContentRecord: Codable, Equatable {
    let deviceID: String
    let type: ProjectedContentType
    let updatedAt: Date
}

struct ProjectedContentStore {
    private let keyPrefix = "projectedContentRecord."
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadRecord(for deviceID: String) -> ProjectedContentRecord? {
        guard
            let data = userDefaults.data(forKey: key(for: deviceID)),
            let record = try? decoder.decode(ProjectedContentRecord.self, from: data)
        else {
            return nil
        }

        return record
    }

    func save(type: ProjectedContentType, for deviceID: String) {
        let record = ProjectedContentRecord(deviceID: deviceID, type: type, updatedAt: Date())
        guard let data = try? encoder.encode(record) else { return }
        userDefaults.set(data, forKey: key(for: deviceID))
    }

    private func key(for deviceID: String) -> String {
        keyPrefix + sanitizedDeviceID(deviceID)
    }

    private func sanitizedDeviceID(_ deviceID: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = deviceID.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? "unknown-device" : sanitized
    }
}
