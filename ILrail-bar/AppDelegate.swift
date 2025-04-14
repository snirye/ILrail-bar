import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var trainScheduleTimer: Timer?
    private let networkManager = NetworkManager()
    private var preferencesWindow: NSWindow?
    private var aboutWindow: NSWindow?
    
    // Constants
    private let appRefreshInterval: TimeInterval = 300 // 5 minutes
    
    // MARK: - Window Management Helper
    
    private func createAndShowWindow(
        size: NSSize,
        title: String,
        styleMask: NSWindow.StyleMask,
        center: Bool = false,
        view: NSView,
        storeIn windowRef: inout NSWindow?
    ) {
        // If a window already exists, just bring it to front
        if let window = windowRef {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        
        // Set self as the window delegate to handle close events
        window.delegate = self
        
        // Set the content view
        window.contentView = view
        
        // Store reference to prevent deallocation
        windowRef = window
        
        // Make the window visible and active
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        logDebug("\(title) window created and should be visible now")
    }
    
    // MARK: - Menu Management Helper
    
    private func rebuildMenu(withTrainsOrError: Bool, errorItems: [NSMenuItem]? = nil, trainItems: [NSMenuItem]? = nil) {
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
        
        // Add train information or error items
        if withTrainsOrError {
            if let trainItems = trainItems {
                trainItems.forEach { menu.addItem($0) }
            } else if let errorItems = errorItems {
                errorItems.forEach { menu.addItem($0) }
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
    }
    
    // This method is called before applicationDidFinishLaunching
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set activation policy as early as possible
        NSApp.setActivationPolicy(.accessory)
    }
    
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
    
    // Handle when user attempts to open the app again while it's already running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Ensure activation policy is still .accessory
        NSApp.setActivationPolicy(.accessory)
        
        #if DEBUG
        // In debug mode, don't show any window when app is reopened to prevent double-opening in Xcode
        logDebug("App reopened in DEBUG mode - skipping window display")
        return true
        #else
        // Show about window when app is reopened
        showAbout(nil)
        return true
        #endif
    }
    
    private func fetchStationData() {
        Station.fetchStations { stations in
            DispatchQueue.main.async {
                if let stations = stations {
                    // Update the stations
                    Station.setStations(stations)
                    
                    // Notify that stations have been loaded
                    NotificationCenter.default.post(name: .stationsLoaded, object: nil)

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
        // Create a new hosting view with an instance of PreferencesView
        // Pass nil for the window as we'll set it properly after creating it
        let preferencesView = PreferencesView()
        let hostingView = NSHostingView(rootView: preferencesView)
        
        createAndShowWindow(
            size: NSSize(width: 400, height: 250),
            title: "Preferences",
            styleMask: [.titled, .closable, .miniaturizable],
            view: hostingView,
            storeIn: &preferencesWindow
        )
        
        // Now update the view with the correct window reference if needed
        if let window = preferencesWindow {
            // Access the underlying PreferencesView and update its window property
            let updatedView = PreferencesView(window: window)
            hostingView.rootView = updatedView
        }
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
    
    // Helper function to format travel time
    private func formatTravelTime(from departureTime: Date, to arrivalTime: Date) -> String {
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
    
    // Helper functions to create small-sized attributed text and append it
    private func createSmallText(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ])
    }

    private func appendSmallText(_ smallText: String, to attributedString: NSMutableAttributedString) {
        attributedString.append(createSmallText(smallText))
    }

    private func updateMenuBarWithTrains(_ trainSchedules: [TrainSchedule]) {
        // Create train menu items
        var trainItems: [NSMenuItem] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        // Get the first train for the status bar display
        let firstTrain = trainSchedules[0]
        let timeUntilDeparture = firstTrain.departureTime.timeIntervalSinceNow / 60 // in minutes
        
        // Display the next train
        let travelTime = formatTravelTime(from: firstTrain.departureTime, to: firstTrain.arrivalTime)
        let firstTrainTitle = "Next: \(formatter.string(from: firstTrain.departureTime)) → \(formatter.string(from: firstTrain.arrivalTime)) (\(firstTrain.trainChanges))"
        
        // Create an attributed string for the first train info
        let firstTrainAttrString = NSMutableAttributedString(string: firstTrainTitle)
        
        appendSmallText(" [\(travelTime)]", to: firstTrainAttrString)
        
        if firstTrain.trainChanges > 0 && !firstTrain.allTrainNumbers.isEmpty {
            let trainNumbersString = firstTrain.allTrainNumbers.map { "#\($0)" }.joined(separator: ", ")
            appendSmallText(" (\(trainNumbersString))", to: firstTrainAttrString)
        } else if !firstTrain.trainNumber.isEmpty {
            appendSmallText(" (#\(firstTrain.trainNumber))", to: firstTrainAttrString)
        }
        
        let firstTrainInfoItem = NSMenuItem(
            title: "",
            action: nil, 
            keyEquivalent: ""
        )
        firstTrainInfoItem.attributedTitle = firstTrainAttrString
        trainItems.append(firstTrainInfoItem)
        
        // Add up to the configured number of additional trains
        let preferences = PreferencesManager.shared.preferences
        let totalTrainsToShow = preferences.upcomingItemsCount + 1 // First train + additional trains
        let maxTrainsToShow = min(totalTrainsToShow, trainSchedules.count)
        
        if trainSchedules.count > 1 {
            trainItems.append(NSMenuItem.separator())
            trainItems.append(NSMenuItem(title: "Upcoming:", action: nil, keyEquivalent: ""))
            
            for i in 1..<maxTrainsToShow {
                let train = trainSchedules[i]
                
                // Create the basic train info title
                let travelTime = formatTravelTime(from: train.departureTime, to: train.arrivalTime)
                let trainBaseTitle = "\(formatter.string(from: train.departureTime)) → \(formatter.string(from: train.arrivalTime)) (\(train.trainChanges))"
                let trainAttrString = NSMutableAttributedString(string: trainBaseTitle)
                
                appendSmallText(" [\(travelTime)]", to: trainAttrString)
                
                if train.trainChanges > 0 && !train.allTrainNumbers.isEmpty {
                    let trainNumbersString = train.allTrainNumbers.map { "#\($0)" }.joined(separator: ", ")
                    appendSmallText(" (\(trainNumbersString))", to: trainAttrString)
                } else if !train.trainNumber.isEmpty {
                    appendSmallText(" (#\(train.trainNumber))", to: trainAttrString)
                }
                
                let trainInfoItem = NSMenuItem(
                    title: "",
                    action: nil, 
                    keyEquivalent: ""
                )
                trainInfoItem.attributedTitle = trainAttrString
                trainItems.append(trainInfoItem)
            }
        }
        
        // Use the helper method to rebuild the menu
        rebuildMenu(withTrainsOrError: true, trainItems: trainItems)
        
        // Set status bar title with color based on time until departure
        if let button = statusItem.button {
            let departureTimeString = formatter.string(from: firstTrain.departureTime)
            
            if timeUntilDeparture < 15 {
                // Less than 15 minutes - use red
                button.attributedTitle = NSAttributedString(
                    string: " " + departureTimeString,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.systemRed]
                )
            } else if timeUntilDeparture < 30 {
                // Less than 30 minutes - use blue
                button.attributedTitle = NSAttributedString(
                    string: " " + departureTimeString,
                    attributes: [NSAttributedString.Key.foregroundColor: NSColor.systemBlue]
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
        // Create error menu items
        var errorItems: [NSMenuItem] = []
        
        // Add error information
        let errorItem = NSMenuItem(title: "Error: " + message, action: nil, keyEquivalent: "")
        errorItems.append(errorItem)
        
        // Add a retry option
        let retryItem = NSMenuItem(title: "Retry connection", action: #selector(fetchTrainSchedule), keyEquivalent: "")
        retryItem.target = self
        errorItems.append(retryItem)
        
        // Use the helper method to rebuild the menu
        rebuildMenu(withTrainsOrError: true, errorItems: errorItems)
        
        // Update status bar with error indicator
        if let button = statusItem.button {
            // Use red color for the error indication
            button.attributedTitle = NSAttributedString(
                string: " Error",
                attributes: [NSAttributedString.Key.foregroundColor: NSColor.systemRed]
            )
        }
    }
    
    @objc func showAbout(_ sender: Any?) {      
        let aboutView = AboutView(window: aboutWindow ?? NSWindow())
        let hostingView = NSHostingView(rootView: aboutView)
        createAndShowWindow(
            size: NSSize(width: 350, height: 350),
            title: "About",
            styleMask: [.titled, .closable],
            center: true,
            view: hostingView,
            storeIn: &aboutWindow
        )
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // If our preferences window is closing, clear the reference
        if let closingWindow = notification.object as? NSWindow,
           closingWindow === preferencesWindow {
            // Ensure the window is completely released
            preferencesWindow = nil
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
            Image(systemName: "tram.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
            
            GroupBox(label: 
                Text("Legend:")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 5) {
                        Text("Red")
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                        Text("- Train departing in less than 15 minutes")
                    }
                    
                    HStack(spacing: 5) {
                        Text("Blue")
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                        Text("- Train departing in less than 30 minutes")
                    }
                    
                    HStack(spacing: 5) {
                        Text("Default")
                            .fontWeight(.medium)
                        Text("- Train departing in 30+ minutes")
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack(spacing: 5) {
                        Text("(0)")
                            .fontWeight(.medium)
                        Text("- No train changes required")
                    }
                    
                    HStack(spacing: 5) {
                        Text("(1+)")
                            .fontWeight(.medium)
                        Text("- Train changes required")
                    }
                }
                .padding(8)
            }
            .padding(.horizontal, 4)
            
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
        .frame(width: 350, height: 400)
    }
}
