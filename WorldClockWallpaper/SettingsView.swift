import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var cityManager: CityManager
    @State private var showingAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("World Clock Wallpaper")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            cityListView

            Divider()
            footerView
        }
        .frame(width: 300)
    }

    private var cityListView: some View {
        List {
            ForEach(cityManager.cities) { city in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(city.name).font(.body)
                        Text(city.timezone).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(city.localTimeString).foregroundColor(.secondary)
                    Button(action: { cityManager.remove(id: city.id) }) {
                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onMove { cityManager.move(fromOffsets: $0, toOffset: $1) }
        }
        .frame(height: min(CGFloat(cityManager.cities.count) * 44 + 8, 280))
    }

    private var footerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingAdd {
                AddCityForm(cityManager: cityManager, isShowing: $showingAdd)
            } else {
                Button(action: { showingAdd = true }) {
                    Label("Add City", systemImage: "plus")
                }
                .padding(12)
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else  { try SMAppService.mainApp.unregister() }
                        } catch {
                            print("Login item error: \(error)")
                        }
                    }
                ))
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct AddCityForm: View {
    @ObservedObject var cityManager: CityManager
    @Binding var isShowing: Bool
    @State private var name = ""
    @State private var timezone = ""
    @State private var lat = ""
    @State private var lon = ""

    var body: some View {
        VStack(spacing: 6) {
            TextField("City name (e.g. Paris)", text: $name)
            TextField("Timezone (e.g. Europe/Paris)", text: $timezone)
            HStack {
                TextField("Latitude", text: $lat)
                TextField("Longitude", text: $lon)
            }
            HStack {
                Button("Cancel") { isShowing = false }
                Spacer()
                Button("Add") {
                    cityManager.add(City(
                        name: name,
                        timezone: timezone,
                        lat: Double(lat) ?? 0,
                        lon: Double(lon) ?? 0
                    ))
                    isShowing = false
                }
                .disabled(name.isEmpty || timezone.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(12)
        .textFieldStyle(.roundedBorder)
    }
}
