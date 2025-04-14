import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @State private var selectedFromStation: String
    @State private var selectedToStation: String
    @State private var upcomingItemsCount: Int
    @State private var launchAtLogin: Bool
    @State private var isPresented: Bool = true
    @State private var stations: [Station] = Station.allStations
    @State private var isLoading: Bool = false
    
    // Reference to the window so we can close it manually
    var window: NSWindow?
    
    init(window: NSWindow? = nil) {
        let preferences = PreferencesManager.shared.preferences
        _selectedFromStation = State(initialValue: preferences.fromStation)
        _selectedToStation = State(initialValue: preferences.toStation)
        _upcomingItemsCount = State(initialValue: preferences.upcomingItemsCount)
        _launchAtLogin = State(initialValue: preferences.launchAtLogin)
        self.window = window
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            
            if isLoading {
                ProgressView("Loading stations...")
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 20) {
                    HStack(alignment: .center) {
                        Text("Launch at Login")
                            .frame(width: 105, alignment: .leading)
                        
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .padding(.leading, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    HStack(alignment: .center) {
                        Text("From Station")
                            .frame(width: 100, alignment: .leading)
                        
                        Picker("", selection: $selectedFromStation) {
                            ForEach(stations) { station in
                                Text("\(station.name)").tag(station.id)
                            }
                        }
                        .pickerStyle(PopUpButtonPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                    
                    HStack(alignment: .center) {
                        Text("To Station")
                            .frame(width: 100, alignment: .leading)
                        
                        Picker("", selection: $selectedToStation) {
                            ForEach(stations) { station in
                                Text("\(station.name)").tag(station.id)
                            }
                        }
                        .pickerStyle(PopUpButtonPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                    
                    HStack(alignment: .center) {
                        Text("Upcoming Items")
                            .frame(width: 100, alignment: .leading)
                        
                        // Replace the regular Stepper with a custom layout that aligns the number with the stepper buttons
                        HStack(spacing: 5) {
                            Text("\(upcomingItemsCount)")
                                .frame(minWidth: 20, alignment: .trailing)
                            Stepper("", value: $upcomingItemsCount, in: 1...10)
                                .labelsHidden()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Bottom buttons with consistent spacing
            HStack(spacing: 20) {
                Button("Cancel") {
                    closeWindow()
                }
                .buttonStyle(.bordered)
                .frame(width: 100)
                
                Button("Save") {
                    // Save preferences
                    PreferencesManager.shared.savePreferences(
                        fromStation: selectedFromStation,
                        toStation: selectedToStation,
                        upcomingItemsCount: upcomingItemsCount,
                        launchAtLogin: launchAtLogin
                    )
                    
                    // Configure launch at login
                    updateLaunchAtLogin(launchAtLogin)
                    
                    // Notify the app to refresh train schedules with new preferences
                    NotificationCenter.default.post(name: .preferencesChanged, object: nil)
                    
                    closeWindow()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 100)
                .disabled(isLoading)
            }
            .frame(maxWidth: .infinity)  // This ensures the HStack takes the full width
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 250) // Adjusted height since we removed the title
        .onAppear {
            loadStations()
        }
    }
    
    private func loadStations() {
        // Only show loading if we have default stations
        if stations.count <= 5 {
            isLoading = true
        }
        
        // Update stations when view appears
        stations = Station.allStations
        
        // Setup notification observer for stations loaded
        NotificationCenter.default.addObserver(
            forName: .stationsLoaded,
            object: nil,
            queue: .main
        ) { _ in
            // Update stations when loaded from remote
            self.stations = Station.allStations
            self.isLoading = false
            
            // Check if currently selected stations still exist in the new data
            if !self.stations.contains(where: { $0.id == self.selectedFromStation }) {
                self.selectedFromStation = Station.defaultStations.first?.id ?? ""
            }
            if !self.stations.contains(where: { $0.id == self.selectedToStation }) {
                self.selectedToStation = Station.defaultStations.last?.id ?? ""
            }
        }
        
        // Actively fetch stations if needed
        if stations.count <= 5 {
            Station.fetchStations { fetchedStations in
                DispatchQueue.main.async {
                    if let fetchedStations = fetchedStations, !fetchedStations.isEmpty {
                        Station.setStations(fetchedStations)
                        self.stations = fetchedStations
                        self.isLoading = false
                        
                        // Notify that stations have been loaded
                        NotificationCenter.default.post(name: .stationsLoaded, object: nil)
                    } else {
                        // If fetch failed, use default stations and hide loading
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    private func closeWindow() {
        window?.close()
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logInfo("Launch at login enabled")

            } else {
                try SMAppService.mainApp.unregister()
                logInfo("Launch at login disabled")
            }
        } catch {
            logError("Failed to \(enabled ? "register" : "unregister") launch at login: \(error.localizedDescription)")
        }
    }
}

// Custom button style that works on older macOS versions
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}