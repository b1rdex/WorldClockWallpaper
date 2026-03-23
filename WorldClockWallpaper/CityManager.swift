import Foundation
import Combine
import SwiftUI

final class CityManager: ObservableObject {
    @Published private(set) var cities: [City]
    private let storageKey: String

    init(storageKey: String = "saved_cities") {
        self.storageKey = storageKey
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([City].self, from: data) {
            cities = saved
        } else {
            cities = CityManager.defaults
        }
    }

    func add(_ city: City) {
        cities.append(city)
        persist()
    }

    func remove(id: UUID) {
        cities.removeAll { $0.id == id }
        persist()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        cities.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cities) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static let defaults: [City] = [
        City(name: "Moscow",    timezone: "Europe/Moscow",       lat: 55.75,  lon:  37.62),
        City(name: "New York",  timezone: "America/New_York",    lat: 40.71,  lon: -74.01),
        City(name: "London",    timezone: "Europe/London",       lat: 51.51,  lon:  -0.13),
        City(name: "Tokyo",     timezone: "Asia/Tokyo",          lat: 35.68,  lon: 139.69),
        City(name: "Dubai",     timezone: "Asia/Dubai",          lat: 25.20,  lon:  55.27),
    ]
}
