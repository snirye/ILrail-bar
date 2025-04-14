import Foundation

struct TrainSchedule {
    let trainNumber: String
    let departureTime: Date
    let arrivalTime: Date
    let platform: String?
    let fromStationName: String
    let toStationName: String
    let trainChanges: Int
    let allTrainNumbers: [String] // Added to store all train IDs in a journey
}