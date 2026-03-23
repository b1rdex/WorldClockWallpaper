import XCTest
@testable import WorldClockWallpaper

final class CityManagerTests: XCTestCase {
    var sut: CityManager!
    let testKey = "test_cities_key"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
        sut = CityManager(storageKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        sut = nil
        super.tearDown()
    }

    func test_defaultCities_areNotEmpty() {
        XCTAssertFalse(sut.cities.isEmpty)
    }

    func test_addCity_appendsToList() {
        let initial = sut.cities.count
        sut.add(City(name: "Paris", timezone: "Europe/Paris", lat: 48.85, lon: 2.35))
        XCTAssertEqual(sut.cities.count, initial + 1)
    }

    func test_removeCity_removesFromList() {
        let city = City(name: "Paris", timezone: "Europe/Paris", lat: 48.85, lon: 2.35)
        sut.add(city)
        sut.remove(id: city.id)
        XCTAssertFalse(sut.cities.contains(where: { $0.id == city.id }))
    }

    func test_persistAndReload() {
        let city = City(name: "Sydney", timezone: "Australia/Sydney", lat: -33.87, lon: 151.21)
        sut.add(city)
        let reloaded = CityManager(storageKey: testKey)
        XCTAssertTrue(reloaded.cities.contains(where: { $0.id == city.id }))
    }

    func test_moveCity_changesOrder() {
        // Start with default cities; move the first to position 2
        let nameAtZero = sut.cities[0].name
        sut.move(fromOffsets: IndexSet([0]), toOffset: 2)
        XCTAssertNotEqual(sut.cities[0].name, nameAtZero)
        XCTAssertEqual(sut.cities[1].name, nameAtZero)
    }
}
