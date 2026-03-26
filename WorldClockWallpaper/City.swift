import Foundation

struct City: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var timezone: String   // IANA timezone id, e.g. "Europe/Moscow"
    var lat: Double
    var lon: Double

    init(id: UUID = UUID(), name: String, timezone: String, lat: Double, lon: Double) {
        self.id = id
        self.name = name
        self.timezone = timezone
        self.lat = lat
        self.lon = lon
    }

    /// Current time in this city's timezone, formatted using the system locale
    var localTimeString: String {
        City.timeFormatter.timeZone = TimeZone(identifier: timezone) ?? .current
        return City.timeFormatter.string(from: Date())
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}
