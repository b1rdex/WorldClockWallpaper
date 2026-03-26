import Foundation
import Combine

final class CityManager: ObservableObject {
    @Published private(set) var cities: [City]
    private let storageKey: String

    init(storageKey: String = "saved_cities_v2") {
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

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cities) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static let defaults: [City] = [
        City(name: "Anchorage",    timezone: "America/Anchorage",                  lat:  61.22, lon: -149.90),
        City(name: "Los Angeles",  timezone: "America/Los_Angeles",                lat:  34.05, lon: -118.24),
        City(name: "New York",     timezone: "America/New_York",                   lat:  40.71, lon:  -74.01),
        City(name: "Bogotá",       timezone: "America/Bogota",                     lat:   4.71, lon:  -74.07),
        City(name: "São Paulo",    timezone: "America/Sao_Paulo",                  lat: -23.55, lon:  -46.63),
        City(name: "Buenos Aires", timezone: "America/Argentina/Buenos_Aires",     lat: -34.60, lon:  -58.38),
        City(name: "Berlin",       timezone: "Europe/Berlin",                      lat:  52.52, lon:   13.40),
        City(name: "Tel Aviv",     timezone: "Asia/Jerusalem",                     lat:  32.08, lon:   34.78),
        City(name: "Moscow",       timezone: "Europe/Moscow",                      lat:  55.75, lon:   37.62),
        City(name: "Novosibirsk",  timezone: "Asia/Novosibirsk",                   lat:  54.99, lon:   82.90),
        City(name: "Nairobi",      timezone: "Africa/Nairobi",                     lat:  -1.29, lon:   36.82),
        City(name: "Lagos",        timezone: "Africa/Lagos",                       lat:   6.52, lon:    3.38),
        City(name: "Bangkok",      timezone: "Asia/Bangkok",                       lat:  13.75, lon:  100.52),
        City(name: "Ulaanbaatar",  timezone: "Asia/Ulaanbaatar",                   lat:  47.91, lon:  106.88),
        City(name: "Vladivostok",  timezone: "Asia/Vladivostok",                   lat:  43.12, lon:  131.89),
        City(name: "Beijing",      timezone: "Asia/Shanghai",                      lat:  39.91, lon:  116.39),
        City(name: "Tokyo",        timezone: "Asia/Tokyo",                         lat:  35.69, lon:  139.69),
        City(name: "Petropavlovsk", timezone: "Asia/Kamchatka",                    lat:  53.01, lon:  158.65),
        City(name: "Sydney",       timezone: "Australia/Sydney",                   lat: -33.87, lon:  151.21),
    ]
}
