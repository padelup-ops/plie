// swift-tools-version:5.9
// Le cœur d'émulation Game Boy de RetroFold : SameBoy (Lior Halphon, licence Expat/MIT), compilé sans débogueur,
// triche ni retour en arrière. Les sources de SameBoy et ses ROM de démarrage libres sont ajoutées avant la
// compilation par retrofold/tools/fetch_sameboy.sh (version fixée). Les joueurs chargent leurs propres jeux.
import PackageDescription

let package = Package(
    name: "GBCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "GBCore", targets: ["GBCore"])],
    targets: [
        .target(
            name: "GBCore",
            path: "Sources/GBCore",
            exclude: ["Core/LICENSE"],
            cSettings: [
                .define("GB_INTERNAL"),
                .define("GB_DISABLE_DEBUGGER"),
                .define("GB_DISABLE_CHEATS"),
                .define("GB_DISABLE_CHEAT_SEARCH"),
                .define("GB_DISABLE_REWIND"),
                .define("_GNU_SOURCE"),
                .define("GB_VERSION", to: "\"1.0\""),
                .define("GB_COPYRIGHT_YEAR", to: "\"2026\""),
                .headerSearchPath("Core"),
            ]
        ),
    ],
    cLanguageStandard: .gnu11
)
