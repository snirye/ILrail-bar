import Foundation

/// Helper struct to provide standardized date formatters throughout the app
struct DateFormatters {
    /// Formatter for displaying time in 24-hour format (HH:mm)
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    /// Formatter for date in ISO format (yyyy-MM-dd)
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    /// Helper function to format travel time between two dates
    static func formatTravelTime(from departureTime: Date, to arrivalTime: Date) -> String {
        let travelTimeInMinutes = Int(arrivalTime.timeIntervalSince(departureTime) / 60)
        
        if travelTimeInMinutes >= 60 {
            let hours = travelTimeInMinutes / 60
            let minutes = travelTimeInMinutes % 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        } else {
            return "\(travelTimeInMinutes)m"
        }
    }
}