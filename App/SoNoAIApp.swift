import SwiftUI
import SoNoCore

@main
struct SoNoAIApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: "vi_VN"))
                .environment(\.calendar, VietnameseDate.calendar)
                .environment(\.timeZone, VietnameseDate.calendar.timeZone)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .tint(.teal)
                .task { await model.open() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { model.lockIfEnabled() }
                }
        }
    }
}
