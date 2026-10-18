import Foundation
import Testing
@testable import KeyPace

@Suite("Game detection")
struct GameRulesTests {
    private let steamGame = "/Users/x/Library/Application Support/Steam/steamapps/common/Portal 2/Portal 2.app/Contents/MacOS/Portal 2"

    @Test("Games category and its subcategories count as games")
    func categories() {
        #expect(GameRules.isGameCategory("public.app-category.games"))
        #expect(GameRules.isGameCategory("public.app-category.action-games"))
        #expect(GameRules.isGameCategory("public.app-category.puzzle-games"))
        #expect(!GameRules.isGameCategory("public.app-category.productivity"))
        #expect(!GameRules.isGameCategory("public.app-category.developer-tools"))
        #expect(!GameRules.isGameCategory(nil))
    }

    @Test("Steam games are games, the Steam client is not")
    func steam() {
        let r = GameRules.extras
        #expect(r.isGame(bundleID: nil, processName: "Portal 2", executablePath: steamGame, category: nil))
        #expect(!r.isGame(bundleID: "com.valvesoftware.steam", processName: "steam_osx",
                          executablePath: "/Applications/Steam.app/Contents/MacOS/steam_osx", category: nil))
    }

    @Test("Minecraft through Prism Launcher is a game")
    func prism() {
        let java = "/Users/x/Library/Application Support/PrismLauncher/java/java-runtime-delta/jre.bundle/Contents/Home/bin/java"
        #expect(GameRules.extras.isGame(bundleID: nil, processName: "java", executablePath: java, category: nil))
        #expect(!GameRules.extras.isGame(bundleID: nil, processName: "java", executablePath: "/usr/bin/java", category: nil))
    }

    @Test("Block list wins over a games category")
    func blockWins() {
        #expect(!GameRules.extras.isGame(bundleID: "com.apple.Safari", processName: "Safari", executablePath: nil,
                                         category: "public.app-category.games"))
    }

    @Test("Ordinary apps are not games")
    func ordinaryApps() {
        let r = GameRules.extras
        #expect(!r.isGame(bundleID: "com.microsoft.VSCode", processName: "Electron",
                          executablePath: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
                          category: "public.app-category.developer-tools"))
        #expect(r.isGame(bundleID: "com.example.indie", processName: "Indie", executablePath: nil,
                         category: nil, supportsGameMode: true))
    }

    @Test("Game Mode personality plists are merged, with process names cut to 15 characters")
    func personality() throws {
        let plist: [String: Any] = ["Model": ["Policy": [
            "Allow": ["BundleIdentifiers": ["com.blizzard.heroesofthestorm"], "ProcessNames": ["RobloxPlayer"]],
            "Block": ["BundleIdentifiers": ["net.battle.app"], "ProcessNames": ["UE4EditorServic"]],
        ]]]
        var r = GameRules()
        r.merge(personality: try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))
        #expect(r.isGame(bundleID: "com.blizzard.heroesofthestorm", processName: nil, executablePath: nil, category: nil))
        #expect(r.isGame(bundleID: nil, processName: "RobloxPlayer", executablePath: nil, category: nil))
        #expect(!r.isGame(bundleID: "net.battle.app", processName: nil, executablePath: nil, category: "public.app-category.games"))
        #expect(!r.isGame(bundleID: nil, processName: "UE4EditorServices", executablePath: nil, category: "public.app-category.games"))
    }

    @Test("Apple's Game Mode database loads when present")
    func appleDatabase() {
        let r = GameRules.load()
        #expect(r.allowPartialPaths.contains("steamapps/common"))
        if FileManager.default.fileExists(atPath: GameRules.assetDir.path) {
            #expect(r.blockBundleIDs.contains("com.epicgames.EpicGamesLauncher"))
            #expect(r.isGame(bundleID: nil, processName: "RobloxPlayer", executablePath: nil, category: nil))
        }
    }
}
