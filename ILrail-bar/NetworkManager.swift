import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    
    private let apiKey = "4b0d355121fe4e0bb3d86e902efe9f20"
    private let apiBaseURL = "https://israelrail.azurefd.net"    
    private var timetableBaseURL: String { return apiBaseURL + "/rjpa-prod/api/v1/timetable/searchTrainLuzForDateTime" }
    private var stationsBaseURL: String { return apiBaseURL + "/common/api/v1/stations" }
    private let madeUpUserAgent = "ILrail-bar/1.0 macOS"
    
    private let languageId = "Hebrew"
    private let scheduleType = "1"
    private let systemType = "2"
    
    enum NetworkError: Error {
        case invalidURL
        case noData
        case decodingError
        case serverError(String)
        case cacheError
    }
    
    private struct CacheKeys {
        static let stationsData = "cachedStationsData"
        static let timetablePrefix = "cachedTimetableData_"
    }
    
    // Generic cache manager function
    // Stored in ~/Library/Containers/il.co.liar.ILrail-bar/Data/Library/Preferences/il.co.liar.ILrail-bar.plist
    private func cacheData(_ data: Data, forKey key: String) {
        let cacheBundle: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "data": data
        ]
        UserDefaults.standard.set(cacheBundle, forKey: key)
        logDebug("Data cached successfully with key: \(key)")
    }
    
    // Generic cache retrieval function
    private func getCachedData(forKey key: String) -> (data: Data, ageInMinutes: Int)? {
        if let cachedBundle = UserDefaults.standard.dictionary(forKey: key),
           let cachedData = cachedBundle["data"] as? Data,
           let timestamp = cachedBundle["timestamp"] as? TimeInterval {
            let cacheAge = Date().timeIntervalSince1970 - timestamp
            let minutes = Int(cacheAge / 60)
            return (cachedData, minutes)
        }
        return nil
    }
    
    // Function to get timetable cache key
    private func getTimetableCacheKey(fromStation: String, toStation: String) -> String {
        return "\(CacheKeys.timetablePrefix)\(fromStation)_\(toStation)"
    }
    
    func fetchStations(completion: @escaping (Result<[RemoteStation], NetworkError>) -> Void) {
        guard var components = URLComponents(string: stationsBaseURL) else {
            completion(.failure(.invalidURL))
            return
        }
        
        components.queryItems = [
            URLQueryItem(name: "languageId", value: "English"),
            URLQueryItem(name: "systemType", value: systemType)
        ]
        
        guard let url = components.url else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue(madeUpUserAgent, forHTTPHeaderField: "User-Agent")
        request.addValue(apiKey, forHTTPHeaderField: "ocp-apim-subscription-key")
        
        // Define a function to process station data
        let processStationData = { (data: Data) -> [RemoteStation] in
            do {
                let response = try JSONDecoder().decode(StationResponse.self, from: data)
                return response.result
            } catch {
                logError("Error decoding stations: \(error.localizedDescription)")
                
                // Try to decode the structure of the JSON to understand the format
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        logDebug("JSON is a dictionary with keys: \(json.keys)")
                    } else if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                        logDebug("JSON is an array of dictionaries with \(json.count) items")
                    } else {
                        logDebug("JSON is in an unknown format")
                    }
                } catch {
                    logError("Failed to parse JSON: \(error.localizedDescription)")
                }
                
                throw NetworkError.decodingError
            }
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                logError("Error fetching stations: \(error.localizedDescription)")
                
                // Try to use cached data if available
                if let cachedDataInfo = self.getCachedData(forKey: CacheKeys.stationsData) {
                    do {
                        let stations = try processStationData(cachedDataInfo.data)
                        logInfo("Using cached stations data from \(cachedDataInfo.ageInMinutes) minutes ago")
                        completion(.success(stations))
                    } catch {
                        completion(.failure(.cacheError))
                    }
                } else {
                    completion(.failure(.serverError(error.localizedDescription)))
                }
                return
            }
            
            guard let data = data else {
                completion(.failure(.noData))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                completion(.failure(.serverError(errorMessage)))
                return
            }
            
            do {
                let stations = try processStationData(data)
                
                // Cache the data for future use
                self.cacheData(data, forKey: CacheKeys.stationsData)
                
                completion(.success(stations))
            } catch {
                completion(.failure(.decodingError))
            }
        }.resume()
    }
    
    func fetchTrainSchedule(completion: @escaping (Result<[TrainSchedule], Error>) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let currentDate = dateFormatter.string(from: Date())
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let currentTime = timeFormatter.string(from: Date())
        
        let preferences = PreferencesManager.shared.preferences
        
        logInfo("Fetching trains from \(preferences.fromStation) to \(preferences.toStation)")
        
        var components = URLComponents(string: timetableBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "fromStation", value: preferences.fromStation),
            URLQueryItem(name: "toStation", value: preferences.toStation),
            URLQueryItem(name: "date", value: currentDate),
            URLQueryItem(name: "hour", value: currentTime),
            URLQueryItem(name: "scheduleType", value: scheduleType),
            URLQueryItem(name: "systemType", value: systemType),
            URLQueryItem(name: "languageId", value: languageId)
        ]
        
        guard let url = components?.url else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue(madeUpUserAgent, forHTTPHeaderField: "User-Agent")
        request.addValue(apiKey, forHTTPHeaderField: "ocp-apim-subscription-key")
        
        // Generate a cache key based on from/to stations
        let cacheKey = getTimetableCacheKey(fromStation: preferences.fromStation, toStation: preferences.toStation)
        
        // Create a function to process API response data
        let processData = { (data: Data, isFromCache: Bool, cacheAgeMinutes: Int?) -> [TrainSchedule] in
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    
                    if let date = DateFormatters.parseDateFormats(dateString) {
                        return date
                    }
                    
                    // If we reach here, none of our formats worked
                    logWarning("Failed to parse date string: \(dateString)")
                    
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: decoder.codingPath,
                                              debugDescription: "Date string does not match any expected format: \(dateString)")
                    )
                }
                
                let response = try decoder.decode(APIResponse.self, from: data)
                let now = Date()
                var trainSchedules: [TrainSchedule] = []
                
                for travel in response.result.travels {
                    // The number of changes is the number of trains in this travel minus 1
                    // If there's just one train, there are 0 changes
                    let trainChanges = travel.trains.count - 1
                    
                    // For multi-train journeys, we only need to add the first train segment
                    // with information about the entire journey
                    if let firstTrainData = travel.trains.first {
                        let trainNumberString = String(describing: firstTrainData.trainNumber)
                        let allTrainNumbers = travel.trains.map { String(describing: $0.trainNumber) }
                        
                        // We want to show the first train of each travel, with the overall journey time
                        // Instead of checking that both stations match, we'll check the overall journey details
                        // This handles train changes correctly
                        let schedule = TrainSchedule(
                            trainNumber: trainNumberString,
                            departureTime: firstTrainData.departureTime,
                            arrivalTime: travel.trains.last?.arrivalTime ?? firstTrainData.arrivalTime, // Use the final arrival time for the complete journey
                            platform: firstTrainData.platform,
                            fromStationName: firstTrainData.fromStationName ?? preferences.fromStation,
                            toStationName: travel.trains.last?.toStationName ?? firstTrainData.toStationName ?? preferences.toStation,
                            trainChanges: trainChanges,
                            allTrainNumbers: allTrainNumbers,
                            isFromCache: isFromCache,
                            cacheAgeMinutes: cacheAgeMinutes
                        )
                        trainSchedules.append(schedule)
                    }
                }
                
                // Filter out trains that have already departed with 1-minute buffer
                // Also filter out trains that would depart before the user can walk to the station
                // And filter out trains with more changes than the max allowed
                let walkTimeDurationSec = TimeInterval(preferences.walkTimeDurationMin * 60)
                let upcomingTrains = trainSchedules.filter { 
                    // First check if this train has too many changes
                    if preferences.maxTrainChanges != -1 && $0.trainChanges > preferences.maxTrainChanges {
                        return false
                    }
                    
                    // Then check if the train is still relevant based on timing
                    let timeUntilDeparture = $0.departureTime.timeIntervalSince(now)
                    if preferences.walkTimeDurationMin > 0 {
                        return timeUntilDeparture > walkTimeDurationSec
                    } else {
                        return timeUntilDeparture > -60 // Allow trains departing within the last minute
                    }
                }
                
                // Sort the filtered trains by departure time
                let sortedTrains = upcomingTrains.sorted { $0.departureTime < $1.departureTime }
                
                logDebug("Sorted upcoming trains:")
                for (_, train) in sortedTrains.enumerated() {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let departureString = formatter.string(from: train.departureTime)
                    logDebug("Train #\(train.trainNumber): from: \(train.fromStationName), to: \(train.toStationName), departs at \(departureString)")
                }
                
                return sortedTrains
            } catch {
                logError("Decoding error: \(error)")
                throw NetworkError.decodingError
            }
        }
        
        // Try to use cached data first, especially if offline
        URLSession.shared.dataTask(with: request) { data, response, error in            
            if let error = error {
                logWarning("Network error: \(error.localizedDescription). Attempting to use cached data.")
                
                // Try to use cached data instead
                if let cachedDataInfo = self.getCachedData(forKey: cacheKey) {
                    do {
                        let cachedTrains = try processData(cachedDataInfo.data, true, cachedDataInfo.ageInMinutes)
                        logInfo("Using cached timetable data from \(cachedDataInfo.ageInMinutes) minutes ago")
                        completion(.success(cachedTrains))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                completion(.failure(NetworkError.noData))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                completion(.failure(NetworkError.serverError(errorMessage)))
                return
            }
            
            // Process the fresh data from the network
            do {
                let sortedTrains = try processData(data, false, nil)
                // Cache the data for future use
                self.cacheData(data, forKey: cacheKey)
                completion(.success(sortedTrains))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
