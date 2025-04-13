import Foundation

class NetworkManager {
    private let apiKey = "4b0d355121fe4e0bb3d86e902efe9f20"
    private let baseURL = "https://israelrail.azurefd.net/rjpa-prod/api/v1/timetable/searchTrainLuzForDateTime"
    
    private let languageId = "Hebrew"
    private let scheduleType = "1"
    private let systemType = "2"
    
    enum NetworkError: Error {
        case invalidURL
        case noData
        case decodingError
        case serverError(String)
    }
    
    func fetchTrainSchedule(completion: @escaping (Result<[TrainSchedule], Error>) -> Void) {
        // Get current date and time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let currentDate = dateFormatter.string(from: Date())
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let currentTime = timeFormatter.string(from: Date())
        
        // Get station preferences
        let preferences = PreferencesManager.shared.preferences
        
        // Log preferences to check station IDs
        logInfo("Fetching trains from \(preferences.fromStation) to \(preferences.toStation)")
        
        // Construct URL with query parameters
        var components = URLComponents(string: baseURL)
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
        request.addValue(apiKey, forHTTPHeaderField: "ocp-apim-subscription-key")
        
        URLSession.shared.dataTask(with: request) { data, response, error in            
            if let error = error {
                completion(.failure(error))
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
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    
                    // Create a more flexible date formatter that can handle the API format
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                    
                    // Try different date formats with explicit time zone (Israel Standard Time)
                    let dateFormatter = DateFormatter()
                    dateFormatter.timeZone = TimeZone(identifier: "Asia/Jerusalem") ?? TimeZone.current
                    
                    // Try with the standard format
                    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    if let date = dateFormatter.date(from: dateString) {
                        return date
                    }
                    
                    // Try with additional formats that might be returned by the API
                    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
                    if let date = dateFormatter.date(from: dateString) {
                        return date
                    }
                    
                    // Try without the 'T' separator which might be used in some cases
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    if let date = dateFormatter.date(from: dateString) {
                        return date
                    }
                    
                    // Log the problematic date string to help with debugging
                    logWarning("Failed to parse date string: \(dateString)")
                    
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: decoder.codingPath,
                                              debugDescription: "Date string does not match any expected format: \(dateString)")
                    )
                }
                
                let response = try decoder.decode(APIResponse.self, from: data)
                
                // Extract all trains from all travels
                var trainSchedules: [TrainSchedule] = []
                
                for travel in response.result.travels {
                    for trainData in travel.trains {
                        // Convert the train number to string properly
                        let trainNumberString = String(describing: trainData.trainNumber)
                        
                        // Only add trains that match our origin station filter
                        // Checking if the orignStation (fromStationName) matches our preferences
                        if trainData.fromStationName == preferences.fromStation && 
                           trainData.toStationName == preferences.toStation {                            
                            let schedule = TrainSchedule(
                                trainNumber: trainNumberString,
                                departureTime: trainData.departureTime,
                                arrivalTime: trainData.arrivalTime,
                                platform: trainData.platform,
                                fromStationName: trainData.fromStationName ?? preferences.fromStation,
                                toStationName: trainData.toStationName ?? preferences.toStation
                            )
                            trainSchedules.append(schedule)
                        }
                    }
                }
                
                // Get current date with proper time zone handling
                let now = Date()
                logDebug("Current date: \(now)")
                               
                // Filter out trains that have already departed with 1-minute buffer
                // Sometimes API time and local time can be slightly off
                let upcomingTrains = trainSchedules.filter { 
                    $0.departureTime.timeIntervalSince(now) > -60 // Allow trains departing within the last minute
                }
                
                // Sort the filtered trains by departure time
                let sortedTrains = upcomingTrains.sorted { $0.departureTime < $1.departureTime }
                
                // Debug info for the first few trains after sorting
                logInfo("Sorted upcoming trains:")
                for (index, train) in sortedTrains.enumerated() {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let departureString = formatter.string(from: train.departureTime)
                    logDebug("Train \(index): #\(train.trainNumber), from: \(train.fromStationName), to: \(train.toStationName), departs at \(departureString)")
                }
                
                completion(.success(sortedTrains))
            } catch {
                logError("Decoding error: \(error)")
                completion(.failure(NetworkError.decodingError))
            }
        }.resume()
    }
}