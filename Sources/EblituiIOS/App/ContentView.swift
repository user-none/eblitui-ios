import SwiftUI

/// Main content view that routes between app screens
public struct ContentView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        switch appState.currentScreen {
        case .library:
            LibraryView()
        case .settings:
            SettingsView()
        case .detail(let gameCRC):
            GameDetailView(gameCRC: gameCRC)
        case .gameplay(let gameCRC, let resume):
            GameplayView(gameCRC: gameCRC, resume: resume)
        }
    }
}
