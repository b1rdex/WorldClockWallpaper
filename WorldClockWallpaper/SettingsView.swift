import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var cityManager: CityManager
    @State private var showingAdd = false
    @State private var tick = Date()

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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tick = Date()
        }
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
        .frame(height: min(max(CGFloat(cityManager.cities.count) * 44 + 8, 44), 280)) // 44pt rows + 8pt padding, max 280pt
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
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let lookupService = CityLookupService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("City name (e.g. Tokyo, New York)", text: $query)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading)
                .onSubmit { addCity() }

            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") { isShowing = false }
                    .disabled(isLoading)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Add") { addCity() }
                        .keyboardShortcut(.return)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(12)
    }

    @MainActor
    private func addCity() {
        guard !isLoading else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let city = try await lookupService.lookup(trimmed)
                isLoading = false
                cityManager.add(city)
                isShowing = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
