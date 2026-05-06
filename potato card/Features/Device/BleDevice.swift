import CoreGraphics
import Foundation

struct BleDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let rawDevice: [AnyHashable: Any]
    let profile: EInkDeviceProfile
    let batteryPercent: Int?
    let batteryVoltage: Double?
    let batterySource: String?

    init(rawDevice: [AnyHashable: Any]) {
        self.rawDevice = rawDevice

        let rawName = rawDevice["name"] as? String
        let rawMac = rawDevice["mac"] as? String
        let rawMacAddress = rawDevice["macAddress"] as? String
        let rawAddress = rawDevice["address"] as? String

        // SDK 回调里常用 `macAddress` 保存设备编号，必须和 `mac` 一起纳入识别。
        let normalizedName = BleDevice.normalizedString(rawName)
        let normalizedMac = BleDevice.normalizedString(rawMac)
        let normalizedMacAddress = BleDevice.normalizedString(rawMacAddress)
        let normalizedAddress = BleDevice.normalizedString(rawAddress)

        self.name = normalizedName ?? normalizedMacAddress ?? normalizedMac ?? "未知设备"
        self.address = normalizedMacAddress ?? normalizedMac ?? normalizedAddress ?? ""
        self.id = normalizedMacAddress ?? normalizedMac ?? normalizedAddress ?? self.name
        // 设备型号表依赖 NEMR 编号，蓝牙名是 PICKSMART 时也要优先用编号匹配。
        let profileLookupName = normalizedMacAddress ?? normalizedMac ?? normalizedName ?? self.name
        self.profile = EInkDeviceProfile.profile(for: profileLookupName)
        let parsedPercent = BleDevice.parseBatteryPercent(from: rawDevice)
        let parsedVoltage = BleDevice.parseBatteryVoltage(from: rawDevice)
        self.batteryPercent = parsedPercent?.value
        self.batteryVoltage = parsedVoltage?.value
        self.batterySource = parsedPercent?.source ?? parsedVoltage?.source
    }

    static func == (lhs: BleDevice, rhs: BleDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var targetSnapshot: WeatherTargetDeviceSnapshot {
        WeatherTargetDeviceSnapshot(device: self)
    }

    var sdkTransferDevice: [AnyHashable: Any] {
        var device = rawDevice.filter { _, value in
            !(value is NSNull)
        }

        let stableName = name.isEmpty ? id : name
        let stableAddress = address.isEmpty ? id : address

        device["name"] = BleDevice.normalizedString(device["name"] as? String) ?? stableName
        device["mac"] = BleDevice.normalizedString(device["mac"] as? String) ?? stableAddress
        device["macAddress"] = BleDevice.normalizedString(device["macAddress"] as? String) ?? stableAddress
        device["address"] = BleDevice.normalizedString(device["address"] as? String) ?? stableAddress

        return device
    }

    var debugSummary: String {
        let batteryText = batteryPercent.map { "\($0)%" } ?? batteryVoltage.map { String(format: "%.1fV", $0) } ?? "nil"
        return "name=\(name), address=\(address.isEmpty ? "<empty>" : address), id=\(id), battery=\(batteryText), batterySource=\(batterySource ?? "nil"), profile=\(profile.name) \(profile.displaySize), raw=\(debugRawSummary)"
    }

    var batteryStatus: BatteryStatus? {
        if let batteryPercent {
            return BatteryStatus(text: "\(batteryPercent)%", fillPercent: batteryPercent, level: .percent(batteryPercent))
        }

        if let batteryVoltage {
            let fillPercent = Self.estimatedBatteryPercent(fromVoltage: batteryVoltage)
            return BatteryStatus(text: String(format: "%.1fV", batteryVoltage), fillPercent: fillPercent, level: .voltage(batteryVoltage))
        }

        return nil
    }

    private var debugRawSummary: String {
        let keys = rawDevice.keys
            .map { String(describing: $0) }
            .sorted()

        let pairs = keys.map { key in
            let value = rawDevice.first { String(describing: $0.key) == key }?.value
            return "\(key)=\(String(describing: value))"
        }

        return "{\(pairs.joined(separator: ", "))}"
    }

    private static func parseBatteryPercent(from rawDevice: [AnyHashable: Any]) -> (value: Int, source: String)? {
        let preferredKeys = ["power", "bettery", "battery", "batteryLevel", "electricity", "batteryPercent"]

        for key in preferredKeys {
            guard let rawValue = rawDevice[key] else { continue }
            if let percent = normalizedBatteryPercent(from: rawValue) {
                return (percent, key)
            }
        }

        return nil
    }

    private static func parseBatteryVoltage(from rawDevice: [AnyHashable: Any]) -> (value: Double, source: String)? {
        let preferredKeys = ["powerLevel", "voltage", "batteryVoltage", "batteryVolt", "vbat"]

        for key in preferredKeys {
            guard let rawValue = rawDevice[key] else { continue }
            if let voltage = normalizedBatteryVoltage(from: rawValue) {
                return (voltage, key)
            }
        }

        return nil
    }

    // 统一清洗字符串，避免 Optional 包装值或空串参与设备识别。
    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        return trimmedValue
    }

    private static func normalizedBatteryPercent(from rawValue: Any) -> Int? {
        let normalizedString: String?
        let value: Double?

        if let number = rawValue as? NSNumber {
            normalizedString = nil
            value = number.doubleValue
        } else if let string = rawValue as? String {
            normalizedString = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            value = Double(normalizedString ?? "")
        } else {
            normalizedString = nil
            value = nil
        }

        guard let value else { return nil }

        let percent = value <= 1 ? value * 100 : value
        guard percent >= 0, percent <= 100 else { return nil }

        return Int(percent.rounded())
    }

    private static func normalizedBatteryVoltage(from rawValue: Any) -> Double? {
        let value: Double?

        if let number = rawValue as? NSNumber {
            value = number.doubleValue
        } else if let string = rawValue as? String {
            let normalizedString = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "V", with: "")
                .replacingOccurrences(of: "v", with: "")
            value = Double(normalizedString)
        } else {
            value = nil
        }

        guard let value else { return nil }

        let voltage = value > 10 ? value / 10 : value
        guard voltage >= 1.5, voltage <= 5.5 else { return nil }

        return voltage
    }

    private static func estimatedBatteryPercent(fromVoltage voltage: Double) -> Int {
        let normalized = (voltage - 2.4) / (3.3 - 2.4)
        return Int((min(max(normalized, 0), 1) * 100).rounded())
    }
}

struct BatteryStatus: Equatable, Hashable {
    enum Level: Equatable, Hashable {
        case percent(Int)
        case voltage(Double)
    }

    let text: String
    let fillPercent: Int
    let level: Level
}

struct EInkDeviceProfile: Equatable {
    static let fallback = EInkDeviceProfile(
        name: "未知型号",
        pixelSize: CGSize(width: 400, height: 600),
        colorMode: .sixColor,
        isFallback: true
    )

    let name: String
    let pixelSize: CGSize
    let colorMode: EInkColorMode
    let isFallback: Bool

    var displaySize: String {
        "\(Int(pixelSize.width)) x \(Int(pixelSize.height))"
    }

    static func profile(for deviceName: String) -> EInkDeviceProfile {
        switch deviceName {
        case "NEMR92128526":
            return EInkDeviceProfile(name: "2.1 寸", pixelSize: CGSize(width: 250, height: 128), colorMode: .monochrome, isFallback: false)
        case "NEMR92957953", "NEMR92984868":
            return EInkDeviceProfile(name: "2.9 寸黑白红", pixelSize: CGSize(width: 296, height: 128), colorMode: .blackWhiteRed, isFallback: false)
        case "NEMR99833123":
            return EInkDeviceProfile(name: "10.2 寸", pixelSize: CGSize(width: 960, height: 640), colorMode: .monochrome, isFallback: false)
        case "NEMR99836136":
            return EInkDeviceProfile(name: "4.0 寸", pixelSize: CGSize(width: 528, height: 768), colorMode: .blackWhiteRedYellow, isFallback: false)
        default:
            return fallback
        }
    }
}

enum EInkColorMode: String, Codable, Equatable {
    case monochrome
    case blackWhiteRed
    case blackWhiteRedYellow
    case sixColor
}
