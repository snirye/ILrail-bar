import SwiftUI

struct PreferencesView: View {
    @State private var selectedFromStation: String
    @State private var selectedToStation: String
    @State private var isPresented: Bool = true
    @State private var stations: [Station] = Station.allStations
    @State private var isLoading: Bool = false
    
    // Reference to the window so we can close it manually
    var window: NSWindow?
    
    init(window: NSWindow? = nil) {
        let preferences = PreferencesManager.shared.preferences
        _selectedFromStation = State(initialValue: preferences.fromStation)
        _selectedToStation = State(initialValue: preferences.toStation)
        self.window = window
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Train Schedule Preferences")
                .font(.headline)
                .padding(.top)
            
            if isLoading {
                ProgressView("Loading stations...")
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("From Station", selection: $selectedFromStation) {
                        ForEach(stations) { station in
                            Text("\(station.name)").tag(station.id)
                        }
                    }
                    .pickerStyle(PopUpButtonPickerStyle())
                    .frame(maxWidth: .infinity)
                    
                    Picker("To Station", selection: $selectedToStation) {
                        ForEach(stations) { station in
                            Text("\(station.name)").tag(station.id)
                        }
                    }
                    .pickerStyle(PopUpButtonPickerStyle())
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
            }
            
            HStack {
                Button("Cancel") {
                    closeWindow()
                }
                
                Button("Save") {
                    PreferencesManager.shared.savePreferences(
                        fromStation: selectedFromStation,
                        toStation: selectedToStation
                    )
                    
                    // Notify the app to refresh train schedules with new preferences
                    NotificationCenter.default.post(name: .preferencesChanged, object: nil)
                    
                    closeWindow()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLoading)
            }
            .padding(.bottom)
        }
        .frame(width: 400, height: 250)
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