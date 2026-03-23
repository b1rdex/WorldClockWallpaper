import XCTest
@testable import WorldClockWallpaper

final class CityTests: XCTestCase {

    func test_codableRoundTrip() throws {
        let city = City(name: "Moscow", timezone: "Europe/Moscow", lat: 55.75, lon: 37.62)
        let data = try JSONEncoder().encode(city)
        let decoded = try JSONDecoder().decode(City.self, from: data)
        XCTAssertEqual(decoded.name, "Moscow")
        XCTAssertEqual(decoded.timezone, "Europe/Moscow")
        XCTAssertEqual(decoded.lat, 55.75)
        XCTAssertEqual(decoded.lon, 37.62)
    }

    func test_localTime_returnsNonEmptyString() {
        let city = City(name: "Tokyo", timezone: "Asia/Tokyo", lat: 35.68, lon: 139.69)
        XCTAssertFalse(city.localTimeString.isEmpty)
    }

    func test_unknownTimezone_doesNotCrash() {
        let city = City(name: "Nowhere", timezone: "Invalid/Zone", lat: 0, lon: 0)
        XCTAssertFalse(city.localTimeString.isEmpty)
    }
}
