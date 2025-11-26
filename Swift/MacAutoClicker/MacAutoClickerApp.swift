import SwiftUI

@main
struct MacAutoClickerApp: App {
    @StateObject private var viewModel = ClickerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.titleBar)
    }
}
