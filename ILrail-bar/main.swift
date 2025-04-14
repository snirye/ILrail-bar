// This file serves as the entry point for the application
import Cocoa

// Create a shared application instance
let app = NSApplication.shared

// Set up the app delegate
let appDelegate = AppDelegate()
app.delegate = appDelegate

// Run the application
app.run()