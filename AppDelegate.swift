import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var trainScheduleTimer: Timer?
    private let networkManager = NetworkManager()
    private var preferencesWindow: NSWindow?
    private var preferencesControls: [String: NSPopUpButton]?
    private var aboutWindow: NSWindow?
    
    // Constants
    private let appRefreshInterval: TimeInterval = 300 // 5 minutes
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fetch station data as soon as the app starts
        fetchStationData()
        
        setupMenuBar()
        fetchTrainSchedule()
        
        // Set up a timer to refresh the train schedule every 5 minutes
        trainScheduleTimer = Timer.scheduledTimer(timeInterval: appRefreshInterval, target: self, selector: #selector(fetchTrainSchedule), userInfo: nil, repeats: true)
        
        // Listen for preferences changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .preferencesChanged,
            object: nil
        )
    }
    
    private func fetchStationData() {
        Station.fetchStations { stations in
            DispatchQueue.main.async {
                if let stations = stations {
                    // Update the stations
                    Station.setStations(stations)
                    
                    // Notify that stations have been loaded
                    NotificationCenter.default.post(name: .stationsLoaded, object: nil)
                    
                    logInfo("Loaded \(stations.count) stations from remote source")
                } else {
                    logWarning("Failed to load stations, using default stations")
                }
            }
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Use a train icon with better styling
            let tramImage = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Train")
            tramImage?.isTemplate = true  // Ensures proper appearance in dark/light modes
            button.image = tramImage
            
            // Add loading message with a styled appearance
            button.attributedTitle = NSAttributedString(
                string: " Loading...",
                attributes: [
                    NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor,
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                ]
            )
        }
        
        // Create menu with better visual organization
        menu = NSMenu()
        
        // Add a separator at the top of the menu
        menu.addItem(NSMenuItem.separator())
        
        // Add preferences menu item with direct action block instead of selector
        let prefsItem = NSMenuItem(title: "Preferences...", action: nil, keyEquivalent: ",")
        prefsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Preferences")
        prefsItem.target = self
        // Set action separately after configuration
        prefsItem.action = #selector(showPreferences(_:))
        menu.addItem(prefsItem)
        
        // Add refresh item with icon
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(fetchTrainSchedule), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add about item with icon
        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        // Add a separator before the quit item
        menu.addItem(NSMenuItem.separator())
        
        // Add quit item with icon
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func showPreferences(_ sender: Any?) {
        // If a preferences window already exists, just bring it to front
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            // Add more debugging - print window position
            if let screenFrame = NSScreen.main?.frame {
                let windowFrame = window.frame
                logDebug("Main screen: \(screenFrame)")
                logDebug("Window frame: \(windowFrame)")
            }
            return
        }
        
        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        // Explicitly position window on the main screen
        if let mainScreen = NSScreen.main {
            let screenFrame = mainScreen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
            logDebug("Positioning window at x:\(x), y:\(y) on screen: \(screenFrame)")
        } else {
            window.center()
            logWarning("No main screen found, using default center()")
        }
        
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        window.delegate = self  // Set self as the window delegate
        window.level = .floating  // Try to make it appear above other windows
        
        // Create and set the SwiftUI view as content
        let preferencesView = PreferencesView(window: window)
        let hostingView = NSHostingView(rootView: preferencesView)
        window.contentView = hostingView
        
        // Make the app active and show the window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        // Store reference to prevent deallocation
        preferencesWindow = window
        
        // Debug: verify window is created
        logDebug("Preferences window created and should be visible now")
        
        // Additional debugging - print window position
        let windowFrame = window.frame
        logDebug("Window frame after positioning: \(windowFrame)")
    }
    
    @objc func savePreferences(_ sender: NSButton) {
        // Access controls from the stored property
        guard let controls = preferencesControls,
              let fromPopup = controls["fromPopup"],
              let toPopup = controls["toPopup"] else {
            logError("Error: Could not access controls")
            return
        }
        
        // Get the selected station IDs
        let selectedFromIndex = fromPopup.indexOfSelectedItem
        let selectedToIndex = toPopup.indexOfSelectedItem
        
        if selectedFromIndex >= 0 && selectedFromIndex < Station.allStations.count &&
           selectedToIndex >= 0 && selectedToIndex < Station.allStations.count {
            
            let fromStation = Station.allStations[selectedFromIndex]
            let toStation = Station.allStations[selectedToIndex]
            
            // Save preferences
            PreferencesManager.shared.savePreferences(
                fromStation: fromStation.id,
                toStation: toStation.id
            )
            
            // Notify that preferences changed
            NotificationCenter.default.post(name: .preferencesChanged, object: nil)
            
            logInfo("Saved preferences: from=\(fromStation.name) to=\(toStation.name)")
        }
        
        // Close the window
        sender.window?.close()
    }
    
    @objc private func preferencesChanged() {
        // Reload train schedule when preferences change
        fetchTrainSchedule()
    }
    
    @objc private func fetchTrainSchedule() {
        networkManager.fetchTrainSchedule { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let trainSchedules):
                    if !trainSchedules.isEmpty {
                        // Pass all train schedules to the update method
                        self.updateMenuBarWithTrains(trainSchedules)
                    } else {
                        self.updateMenuBarWithError("No trains found")
                    }
                case .failure(let error):
                    self.updateMenuBarWithError(error.localizedDescription)
                }
            }
        }
    }
    
    private func updateMenuBarWithNextTrain(_ train: TrainSchedule) {
        // Keep track of important menu items
        let importantItems = menu.items.filter { item in
            return item.title == "Preferences..." || 
                   item.title == "Refresh" || 
                   item.title == "About" ||
                   item.title == "Quit" ||
                   item.isSeparatorItem
        }
        
        // Clear all items
        menu.removeAllItems()
        
        // Add separator at the top
        menu.addItem(NSMenuItem.separator())
        
        // Add train information
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        // Calculate time until departure
        let timeUntilDeparture = train.departureTime.timeIntervalSinceNow / 60 // in minutes
        
        // Add train info item
        let trainNumber = train.trainNumber.isEmpty ? "" : " (Train #\(train.trainNumber))"
        let trainInfoItem = NSMenuItem(
            title: "Next train: \(formatter.string(from: train.departureTime)) → \(formatter.string(from: train.arrivalTime))\(trainNumber)",
            action: nil, 
            keyEquivalent: ""
        )
        menu.addItem(trainInfoItem)
        
        // Add a separator before the control items
        menu.addItem(NSMenuItem.separator())
        
        // Restore important menu items
        for item in importantItems {
            if item.title == "Preferences..." || item.title == "Refresh" || item.title == "About" || item.title == "Quit" {
                // Make sure our About menu item always has its action and target set
                if item.title == "About" {
                    item.action = #selector(showAbout(_:))
                    item.target = self
                }
                menu.addItem(item)
            } else if item.isSeparatorItem && menu.items.last?.title != nil {
                // Add separators only between items, not after another separator
                menu.addItem(NSMenuItem.separator())
            }
        }
        
        // Set status bar title with color based on time until departure
        if let button = statusItem.button {
            let departureTimeString = formatter.string(from: train.departureTime)
            
            // Set color based on time until departure
            if timeUntilDeparture < 15 {
                // Less than 15 minutes - use red
                button.attributedTitle = NSAttributedString(
                    string: " " + departureTimeString,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.systemRed]
                )
            } else if timeUntilDeparture < 30 {
                // Less than 30 minutes - use orange
                button.attributedTitle = NSAttributedString(
                    string: " " + departureTimeString,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.systemOrange]
                )
            } else {
                // More than 30 minutes - use default system color
                button.attributedTitle = NSAttributedString(
                    string: " " + departureTimeString,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
                )
            }
        }
    }
    
    private func updateMenuBarWithTrains(_ trainSchedules: [TrainSchedule]) {
        // Keep track of important menu items
        let importantItems = menu.items.filter { item in
            return item.title == "Preferences..." || 
                   item.title == "Refresh" || 
                   item.title == "About" ||
                   item.title == "Quit" ||
                   item.isSeparatorItem
        }
        
        // Clear all items
        menu.removeAllItems()
        
        // Add separator at the top
        menu.addItem(NSMenuItem.separator())
        
        // Add train information
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        // Get the first train for the status bar display
        let firstTrain = trainSchedules[0]
        let timeUntilDeparture = firstTrain.departureTime.timeIntervalSinceNow / 60 // in minutes
        
        // Display the next train
        let firstTrainNumber = firstTrain.trainNumber.isEmpty ? "" : " (Train #\(firstTrain.trainNumber))"
        let firstTrainInfoItem = NSMenuItem(
            title: "Next train: \(formatter.string(from: firstTrain.departureTime)) → \(formatter.string(from: firstTrain.arrivalTime))\(firstTrainNumber)",
            action: nil, 
            keyEquivalent: ""
        )
        menu.addItem(firstTrainInfoItem)
        
        // Add up to 3 additional trains
        let maxTrainsToShow = min(4, trainSchedules.count) // Show up to 4 trains total (1 + 3 additional)
        
        if trainSchedules.count > 1 {
            // Add a separator before upcoming trains
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Upcoming trains:", action: nil, keyEquivalent: ""))
            
            for i in 1..<maxTrainsToShow {
                let train = trainSchedules[i]
                let trainNumber = train.trainNumber.isEmpty ? "" : " (Train #\(train.trainNumber))"
                let trainInfoItem = NSMenuItem(
                    title: "\(formatter.string(from: train.departureTime)) → \(formatter.string(from: train.arrivalTime))\(trainNumber)",
                    action: nil, 
                    keyEquivalent: ""
                )
                menu.addItem(trainInfoItem)
            }
        }
        
        // Add a separator before the control items
        menu.addItem(NSMenuItem.separator())
        
        // Restore important menu items
        for item in importantItems {
            if item.title == "Preferences..." || item.title == "Refresh" || item.title == "About" || item.title == "Quit" {
                // Make sure our About menu item always has its action and target set
                if item.title == "About" {
                    item.action = #selector(showAbout(_:))
                    item.target = self
                }
                menu.addItem(item)
            } else if item.isSeparatorItem && menu.items.last?.title != nil {
                // Add separators only between items, not after another separator
                menu.addItem(NSMenuItem.separator())
            }
        }
        
        // Set status bar title with color based on time until departure
        if let button = statusItem.button {
            let departureTimeString = formatter.string(from: firstTrain.departureTime)
            
            // Set color based on time until departure
            if timeUntilDeparture < 15 {
                // Less than 15 minutes - use red
                button.attributedTitle = NSAttributedString(
                    string: " " + departureTimeString,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.systemRed]
                )
            } else if timeUntilDeparture < 30 {
                // Less than 30 minutes - use orange
                button.attributedTitle = NSAttributedString(
                    string: " " + departureTimeString,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.systemOrange]
                )
            } else {
                // More than 30 minutes - use default system color
                button.attributedTitle = NSAttributedString(
                    string: " " + departureTimeString,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
                )
            }
        }
    }
    
    private func updateMenuBarWithError(_ message: String) {
        // Keep track of important menu items
        let importantItems = menu.items.filter { item in
            return item.title == "Preferences..." || 
                   item.title == "Refresh" || 
                   item.title == "About" ||
                   item.title == "Quit" ||
                   item.isSeparatorItem
        }
        
        // Clear all items
        menu.removeAllItems()
        
        // Add separator at the top
        menu.addItem(NSMenuItem.separator())
        
        // Add error information
        let errorItem = NSMenuItem(title: "Error: " + message, action: nil, keyEquivalent: "")
        menu.addItem(errorItem)
        
        // Add a retry option
        let retryItem = NSMenuItem(title: "Retry connection", action: #selector(fetchTrainSchedule), keyEquivalent: "")
        retryItem.target = self
        menu.addItem(retryItem)
        
        // Add a separator before the control items
        menu.addItem(NSMenuItem.separator())
        
        // Restore important menu items
        for item in importantItems {
            if item.title == "Preferences..." || item.title == "Refresh" || item.title == "About" || item.title == "Quit" {
                // Make sure our About menu item always has its action and target set
                if item.title == "About" {
                    item.action = #selector(showAbout(_:))
                    item.target = self
                }
                menu.addItem(item)
            } else if item.isSeparatorItem && menu.items.last?.title != nil {
                // Add separators only between items, not after another separator
                menu.addItem(NSMenuItem.separator())
            }
        }
        
        // Update status bar with error indicator
        if let button = statusItem.button {
            button.title = " Error"
            
            // Use red color for the error indication
            button.attributedTitle = NSAttributedString(
                string: " Error",
                attributes: [NSAttributedString.Key.foregroundColor: NSColor.systemRed]
            )
        }
    }
    
    @objc func showAbout(_ sender: Any?) {      
        // If an about window already exists, just bring it to front
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a new window for the About dialog
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 350),  // Increased height for the image
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "About"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self  // Set self as the window delegate
        window.level = .floating  // Try to make it appear above other windows
        
        // Create and set the SwiftUI view as content
        let aboutView = AboutView(window: window)
        let hostingView = NSHostingView(rootView: aboutView)
        window.contentView = hostingView
        
        // Make the app active and show the window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        // Store reference to prevent deallocation
        aboutWindow = window
    }
    
    @objc func openGitHub() {
        // Replace with your actual GitHub URL
        if let url = URL(string: "https://github.com/danny") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func openLinkedIn() {
        // Replace with your actual LinkedIn URL
        if let url = URL(string: "https://linkedin.com/in/danny") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // If our preferences window is closing, clear the reference
        if let closingWindow = notification.object as? NSWindow,
           closingWindow === preferencesWindow {
            // Ensure the window is completely released
            preferencesWindow = nil
            preferencesControls = nil
        }
        
        // If our about window is closing, clear the reference
        if let closingWindow = notification.object as? NSWindow,
           closingWindow === aboutWindow {
            // Ensure the window is completely released
            aboutWindow = nil
        }
    }
        
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showPreferences(_:)) || 
           menuItem.action == #selector(showAbout(_:)) {
            return true
        }
        return true
    }
}

// A simple SwiftUI view for the About dialog
struct AboutView: View {
    let window: NSWindow
    
    var body: some View {
        VStack(spacing: 10) {
            // Static tram.fill icon
            Image(systemName: "tram.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
            
            Text("A Menubar app for Israel Railways train schedules")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 30) {
                Button(action: {
                    if let url = URL(string: "https://github.com/drehelis") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Github")
                        .font(.headline)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    if let url = URL(string: "https://linkedin.com/in/drehelis") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("LinkedIn")
                        .font(.headline)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 10)
            
            Spacer()
        }
        .padding()
        .frame(width: 350, height: 200)
    }
}