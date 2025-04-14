import Foundation

struct StationPreferences: Codable {
    var fromStation: String
    var toStation: String
    var upcomingItemsCount: Int
    
    static let defaultPreferences = StationPreferences(
        fromStation: "3700",  // Default from station
        toStation: "2300",    // Default to station
        upcomingItemsCount: 3 // Default number of upcoming trains to show
    )
}

class PreferencesManager {
    static let shared = PreferencesManager()
    
    private let preferencesKey = "StationPreferences"
    private let userDefaults = UserDefaults.standard
    
    private init() {}
    
    var preferences: StationPreferences {
        get {
            guard let data = userDefaults.data(forKey: preferencesKey),
                  let preferences = try? JSONDecoder().decode(StationPreferences.self, from: data) else {
                return StationPreferences.defaultPreferences
            }
            return preferences
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: preferencesKey)
            }
        }
    }
    
    func savePreferences(fromStation: String, toStation: String, upcomingItemsCount: Int = 3) {
        preferences = StationPreferences(fromStation: fromStation, toStation: toStation, upcomingItemsCount: upcomingItemsCount)
    }
}

// Station data
struct Station: Identifiable, Hashable {
    let id: String
    let name: String
    
    // Default stations in case fetching fails
    static let defaultStations: [Station] = [
        Station(id: "3700", name: "Tel Aviv - Savidor Center"),
        Station(id: "2300", name: "Haifa - Hof HaCarmel"),
    ]
    
    // Static property to hold stations with thread-safe access
    private static var _allStations: [Station] = defaultStations
    private static let stationsQueue = DispatchQueue(label: "com.ilrailbar.stationsAccess")
    
    static var allStations: [Station] {
        stationsQueue.sync {
            return _allStations
        }
    }
    
    static func setStations(_ stations: [Station]) {
        stationsQueue.async {
            // Only replace if we have stations
            if !stations.isEmpty {
                _allStations = stations
            }
        }
    }
    
    static func findStation(byId id: String) -> Station? {
        return allStations.first { $0.id == id }
    }
    
    // Station data fetcher
    static func fetchStations(completion: @escaping ([Station]?) -> Void) {
        // First check if we have cached stations in UserDefaults
        if let cachedData = UserDefaults.standard.data(forKey: "cachedStationsData") {
            do {
                struct RemoteStation: Codable {
                    let id: String
                    let hebrew: String
                    let english: String?
                    let russian: String?
                    let arabic: String?
                    let image: String?
                }
                
                let remoteStations = try JSONDecoder().decode([RemoteStation].self, from: cachedData)
                let stations = remoteStations.map { 
                    Station(id: $0.id, name: $0.english ?? $0.hebrew) 
                }.sorted { $0.name < $1.name }
                
                if !stations.isEmpty {
                    logDebug("Using \(stations.count) stations from cache")
                    // Return cached stations immediately but still try to fetch fresh ones
                    setStations(stations)
                    NotificationCenter.default.post(name: .stationsLoaded, object: nil)
                    completion(stations)
                    
                    // Continue fetch for the latest data in the background
                }
            } catch {
                logError("Error decoding cached stations: \(error.localizedDescription)")
                // Continue with remote fetch
            }
        }
        
        // Fetch from primary source
        let primaryUrl = URL(string: "https://raw.githubusercontent.com/better-rail/app/main/ios/BetterRailWatch/stationsData.json")!
        
        fetchFromUrl(primaryUrl) { stations in
            if let stations = stations, !stations.isEmpty {
                completion(stations)
                return
            }
            
            // If primary source fails, use default stations
            logWarning("Using default stations as primary source failed")
            setStations(defaultStations)
            NotificationCenter.default.post(name: .stationsLoaded, object: nil)
            completion(defaultStations)
        }
    }
    
    private static func fetchFromUrl(_ url: URL, completion: @escaping ([Station]?) -> Void) {
        var request = URLRequest(url: url)
        request.addValue("ILrail-bar/1.0 macOS", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                logError("Error fetching stations from \(url.absoluteString): \(error?.localizedDescription ?? "HTTP \(statusCode)")")
                completion(nil)
                return
            }
                       
            do {
                struct RemoteStation: Codable {
                    let id: String
                    let hebrew: String
                    let english: String?
                    let russian: String?
                    let arabic: String?
                    let image: String?
                }
                
                // First try to decode as an array
                let remoteStations = try JSONDecoder().decode([RemoteStation].self, from: data)
                let stations = remoteStations.map { Station(id: $0.id, name: $0.english ?? $0.hebrew) }
                    .sorted { $0.name < $1.name } // Sort by name
                
                // Verify we got stations
                if stations.isEmpty {
                    logWarning("Warning: Received empty stations list from \(url.absoluteString)")
                    completion(nil)
                } else {
                    logDebug("Successfully loaded \(stations.count) stations from \(url.absoluteString)")
                    
                    // Cache the data for future use
                    UserDefaults.standard.set(data, forKey: "cachedStationsData")
                    
                    // Update the shared list and notify observers
                    setStations(stations)
                    NotificationCenter.default.post(name: .stationsLoaded, object: nil)
                    
                    completion(stations)
                }
            } catch {
                logError("Error decoding stations from \(url.absoluteString): \(error.localizedDescription)")
                
                // Try to decode the structure of the JSON to understand the format
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        logDebug("JSON is a dictionary with keys: \(json.keys)")
                        // Handle dictionary format if needed
                    } else if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                        logDebug("JSON is an array of dictionaries with \(json.count) items")
                        // Handle array format
                    } else {
                        logDebug("JSON is in an unknown format")
                    }
                } catch {
                    logError("Failed to parse JSON: \(error.localizedDescription)")
                }
                
                completion(nil)
            }
        }.resume()
    }
}

// Notification for station data loaded
extension Notification.Name {
    static let preferencesChanged = Notification.Name("com.ilrailbar.preferencesChanged")
    static let stationsLoaded = Notification.Name("com.ilrailbar.stationsLoaded")
}