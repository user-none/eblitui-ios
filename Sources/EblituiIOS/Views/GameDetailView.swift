import SwiftUI

/// Game detail view showing metadata and play buttons
public struct GameDetailView: View {
    @EnvironmentObject var appState: AppState
    let gameCRC: String

    @State private var artworkImage: UIImage?
    @State private var rdbInfo: RDBGameInfo?
    @State private var hasResumeState = false

    private var game: GameEntry? {
        appState.library.games[gameCRC]
    }

    public init(gameCRC: String) {
        self.gameCRC = gameCRC
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height

                ZStack {
                    Color.black.ignoresSafeArea()

                    if let game = game {
                        if isLandscape {
                            landscapeLayout(game: game)
                        } else {
                            portraitLayout(game: game)
                        }
                    } else {
                        Text("Game not found")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { appState.navigateToLibrary() }) {
                        Image(systemName: "chevron.left")
                        Text("Library")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadData()
        }
    }

    // MARK: - Layouts

    @ViewBuilder
    private func portraitLayout(game: GameEntry) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Artwork
                artworkView

                // Title (full No-Intro name)
                Text(game.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Play buttons
                playButtons

                // Metadata
                if rdbInfo != nil || !game.region.isEmpty {
                    metadataSection
                }

                Spacer(minLength: 50)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func landscapeLayout(game: GameEntry) -> some View {
        HStack(alignment: .top, spacing: 30) {
            // Left side - Artwork
            artworkView
                .padding(.leading, 40)

            // Right side - Title, buttons, metadata
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    Text(game.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    // Play buttons
                    playButtons

                    // Metadata
                    if rdbInfo != nil || !game.region.isEmpty {
                        metadataSection
                    }
                }
                .padding(.vertical)
            }
            .padding(.trailing, 40)
        }
        .padding(.top, 20)
    }

    // MARK: - Subviews

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))

            if let image = artworkImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
            } else {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: 300)
    }

    private var playButtons: some View {
        VStack(spacing: 12) {
            if hasResumeState {
                // Resume button (primary)
                Button(action: {
                    appState.launchGame(gameCRC: gameCRC, resume: true)
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                // Start fresh button (secondary)
                Button(action: {
                    appState.launchGame(gameCRC: gameCRC, resume: false)
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Start Fresh")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                // Play button
                Button(action: {
                    appState.launchGame(gameCRC: gameCRC, resume: false)
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: 300)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.headline)
                .foregroundColor(.white)

            VStack(spacing: 8) {
                if let info = rdbInfo {
                    if !info.developer.isEmpty {
                        MetadataRow(label: "Developer", value: info.developer)
                    }
                    if !info.publisher.isEmpty {
                        MetadataRow(label: "Publisher", value: info.publisher)
                    }
                    if !info.franchise.isEmpty {
                        MetadataRow(label: "Franchise", value: info.franchise)
                    }
                    if !info.genre.isEmpty {
                        MetadataRow(label: "Genre", value: info.genre)
                    }
                    if !info.esrbRating.isEmpty {
                        MetadataRow(label: "ESRB", value: info.esrbRating)
                    }
                    if info.releaseYear > 0 {
                        let releaseDate = info.releaseMonth > 0
                            ? "\(info.releaseMonth)/\(info.releaseYear)"
                            : "\(info.releaseYear)"
                        MetadataRow(label: "Release", value: releaseDate)
                    }
                }

                if let game = game, !game.region.isEmpty {
                    MetadataRow(label: "Region", value: regionDisplayName(game.region))
                }

                if let game = game, game.lastPlayed > 0 {
                    MetadataRow(label: "Last Played", value: formatLastPlayed(game.lastPlayed))
                }

                MetadataRow(label: "System", value: EmulatorBridge.systemInfo.consoleName)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func loadData() {
        // Load artwork
        let artPath = StoragePaths.artworkPath(for: gameCRC)
        if let image = UIImage(contentsOfFile: artPath) {
            artworkImage = image
        }

        // Load RDB info
        if let crc32 = UInt32(gameCRC, radix: 16) {
            rdbInfo = appState.lookupGame(crc32: crc32)
        }

        // Check for resume state
        let saveStateManager = SaveStateManager()
        saveStateManager.setGame(crc: gameCRC)
        hasResumeState = saveStateManager.hasResumeState()
    }

    private func regionDisplayName(_ region: String) -> String {
        switch region.lowercased() {
        case "us", "usa": return "USA"
        case "eu", "europe": return "Europe"
        case "jp", "japan": return "Japan"
        default: return region.uppercased()
        }
    }

    private func formatLastPlayed(_ timestamp: TimeInterval) -> String {
        if timestamp == 0 {
            return "Never"
        }

        let date = Date(timeIntervalSince1970: timestamp)
        let now = Date()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let formatter = DateFormatter()

        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }

        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

/// Metadata row component
struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(.white)
        }
    }
}
