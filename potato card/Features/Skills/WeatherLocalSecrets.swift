import Foundation

enum WeatherLocalSecrets {
    private static let fileName = "WeatherSecrets"

    static var apiKey: String? {
        value(for: "QWeatherAPIKey")
    }

    static var apiHost: String? {
        value(for: "QWeatherAPIHost")
    }

    private static func value(for key: String) -> String? {
        guard
            let url = Bundle.main.url(forResource: fileName, withExtension: "plist"),
            let dictionary = NSDictionary(contentsOf: url) as? [String: Any],
            let value = dictionary[key] as? String
        else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
