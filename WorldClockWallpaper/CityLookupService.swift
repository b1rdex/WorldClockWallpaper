import CoreLocation

enum CityLookupError: LocalizedError, Equatable {
    case noResults
    case noLocation
    case noTimezone

    var errorDescription: String? {
        switch self {
        case .noResults:  return "City not found. Try a different spelling or add the country."
        case .noLocation: return "Could not determine coordinates for this city."
        case .noTimezone: return "Could not determine timezone for this city."
        }
    }
}

final class CityLookupService {
    private let geocoder = CLGeocoder()

    /// Geocodes `query` and returns a `City` with name, timezone, lat, and lon.
    /// Uses the first result from CLGeocoder. Throws `CityLookupError` on failure.
    func lookup(_ query: String) async throws -> City {
        let placemarks = try await geocoder.geocodeAddressString(query)
        guard let placemark = placemarks.first else { throw CityLookupError.noResults }
        guard let location = placemark.location   else { throw CityLookupError.noLocation }
        guard let tz = placemark.timeZone         else { throw CityLookupError.noTimezone }

        // Verify that the query is plausibly related to the returned placemark.
        // Build a set of candidate strings from the placemark's name fields.
        let candidates: [String?] = [
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
            placemark.country,
            placemark.name,
        ]
        let haystack = candidates
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        // Split the query into words and require at least one query word to appear
        // in the placemark haystack. This rejects completely unrelated fuzzy matches.
        let queryWords = query
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 3 }
        let hasMatch = queryWords.isEmpty || queryWords.contains { haystack.contains($0) }
        guard hasMatch else { throw CityLookupError.noResults }

        // Use city/town name if available, fall back to the placemark's name, then the query.
        let name = placemark.locality ?? placemark.name ?? query
        return City(
            name: name,
            timezone: tz.identifier,
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude
        )
    }
}
