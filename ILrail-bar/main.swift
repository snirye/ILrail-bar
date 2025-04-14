// This file serves as the entry point for the application
import Cocoa

// Create a shared application instance
let app = NSApplication.shared

// Set up the app delegate
let appDelegate = AppDelegate()
app.delegate = appDelegate

// This is critical for a menubar-only app - it prevents 
// the app from showing in the dock regardless of Info.plist settings
NSApp.setActivationPolicy(.accessory)

// Run the application
app.run()