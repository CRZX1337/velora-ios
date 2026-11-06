import SwiftUI

@main
struct SpeedometerApp: App {
    var body: some Scene {
        WindowGroup {
            SpeedometerView()
                .environmentObject(LocationService.shared)
                .environmentObject(TripSession.shared)
                .environmentObject(DemoMode.shared)
        }
    }
}
