import Foundation

/// Un emoji proposé dans la barre pour certains mots, comme le clavier d'Apple (« sad » → 😢, « merci » → 🙏).
/// Une courte liste choisie à la main (anglais et français) : seulement des mots clairs, pour ne pas encombrer la barre.
enum KBEmojiSuggest {
    private static let map: [String: String] = {
        let pairs: [(String, String)] = [
            // Anglais
            ("love", "❤️"), ("heart", "❤️"), ("sad", "😢"), ("cry", "😭"), ("crying", "😭"), ("happy", "😊"), ("smile", "😊"),
            ("lol", "😂"), ("haha", "😂"), ("hahaha", "😂"), ("lmao", "🤣"), ("laugh", "😂"), ("funny", "😂"), ("angry", "😠"), ("mad", "😡"),
            ("fire", "🔥"), ("lit", "🔥"), ("cool", "😎"), ("party", "🎉"), ("birthday", "🎂"), ("congrats", "🎉"), ("congratulations", "🎉"),
            ("thanks", "🙏"), ("thank", "🙏"), ("please", "🙏"), ("pray", "🙏"), ("ok", "👌"), ("okay", "👌"), ("yes", "👍"), ("no", "👎"),
            ("kiss", "😘"), ("hug", "🤗"), ("hugs", "🤗"), ("sleep", "😴"), ("sleepy", "😴"), ("tired", "😩"), ("sick", "🤒"),
            ("money", "💰"), ("coffee", "☕️"), ("beer", "🍺"), ("wine", "🍷"), ("pizza", "🍕"), ("cake", "🎂"), ("dog", "🐶"), ("cat", "🐱"),
            ("sun", "☀️"), ("sunny", "☀️"), ("rain", "🌧️"), ("snow", "❄️"), ("car", "🚗"), ("plane", "✈️"), ("home", "🏠"), ("house", "🏠"),
            ("wow", "😮"), ("omg", "😱"), ("think", "🤔"), ("thinking", "🤔"), ("idea", "💡"), ("music", "🎵"), ("gym", "💪"), ("strong", "💪"),
            ("win", "🏆"), ("winner", "🏆"), ("cheers", "🥂"), ("hello", "👋"), ("hi", "👋"), ("hey", "👋"), ("bye", "👋"), ("great", "👍"),
            ("perfect", "👌"), ("nice", "👍"), ("clap", "👏"), ("bravo", "👏"), ("christmas", "🎄"), ("gift", "🎁"), ("present", "🎁"),
            ("flower", "🌸"), ("flowers", "💐"), ("rose", "🌹"), ("star", "⭐️"), ("moon", "🌙"), ("eyes", "👀"), ("scared", "😱"),
            ("sorry", "😔"), ("oops", "🙈"), ("crazy", "🤪"), ("devil", "😈"), ("angel", "😇"), ("ghost", "👻"), ("skull", "💀"), ("dead", "💀"),
            ("poop", "💩"), ("check", "✅"), ("done", "✅"), ("warning", "⚠️"), ("rocket", "🚀"), ("beach", "🏖️"), ("soccer", "⚽️"),
            ("football", "🏈"), ("basketball", "🏀"), ("tennis", "🎾"), ("game", "🎮"), ("phone", "📱"), ("computer", "💻"), ("book", "📖"),
            ("time", "⏰"), ("hungry", "😋"), ("yummy", "😋"), ("delicious", "😋"), ("food", "🍽️"), ("wink", "😉"), ("cute", "🥰"),
            ("baby", "👶"), ("family", "👪"), ("work", "💼"), ("muscle", "💪"), ("hot", "🥵"), ("cold", "🥶"), ("rainbow", "🌈"),
            ("hundred", "💯"), ("100", "💯"), ("shh", "🤫"), ("nerd", "🤓"), ("broken", "💔"), ("heartbroken", "💔"), ("blush", "😊"),
            ("upset", "😞"), ("disappointed", "😞"), ("bored", "🥱"), ("excited", "🤩"), ("amazing", "🤩"), ("awesome", "🤩"), ("good", "👍"),
            ("night", "🌙"), ("morning", "☀️"), ("tea", "🍵"), ("burger", "🍔"), ("fries", "🍟"), ("ice", "🧊"), ("snowman", "☃️"),
            ("halloween", "🎃"), ("pumpkin", "🎃"), ("balloon", "🎈"), ("trophy", "🏆"), ("medal", "🥇"), ("run", "🏃"), ("running", "🏃"),
            ("dance", "💃"), ("dancing", "💃"), ("sing", "🎤"), ("movie", "🎬"), ("camera", "📷"), ("photo", "📷"), ("key", "🔑"), ("lock", "🔒"),
            ("brain", "🧠"), ("smart", "🧠"), ("wave", "👋"), ("peace", "✌️"), ("fingers", "🤞"), ("luck", "🍀"), ("lucky", "🍀"),
            // Français
            ("amour", "❤️"), ("coeur", "❤️"), ("cœur", "❤️"), ("triste", "😢"), ("pleure", "😭"), ("pleurer", "😭"), ("content", "😊"),
            ("contente", "😊"), ("heureux", "😊"), ("heureuse", "😊"), ("sourire", "😊"), ("mdr", "😂"), ("ptdr", "🤣"), ("rire", "😂"),
            ("drole", "😂"), ("drôle", "😂"), ("colere", "😠"), ("colère", "😠"), ("enerve", "😡"), ("énervé", "😡"), ("énervée", "😡"),
            ("feu", "🔥"), ("fete", "🎉"), ("fête", "🎉"), ("anniversaire", "🎂"), ("bravo", "👏"), ("felicitations", "🎉"), ("félicitations", "🎉"),
            ("merci", "🙏"), ("stp", "🙏"), ("svp", "🙏"), ("bisou", "😘"), ("bisous", "😘"), ("calin", "🤗"), ("câlin", "🤗"), ("dodo", "😴"),
            ("fatigue", "😩"), ("fatigué", "😩"), ("fatiguée", "😩"), ("malade", "🤒"), ("argent", "💰"), ("cafe", "☕️"), ("café", "☕️"),
            ("biere", "🍺"), ("bière", "🍺"), ("vin", "🍷"), ("gateau", "🎂"), ("gâteau", "🎂"), ("chien", "🐶"), ("chat", "🐱"),
            ("soleil", "☀️"), ("pluie", "🌧️"), ("neige", "❄️"), ("voiture", "🚗"), ("avion", "✈️"), ("maison", "🏠"), ("ouf", "😮‍💨"),
            ("noel", "🎄"), ("noël", "🎄"), ("cadeau", "🎁"), ("fleur", "🌸"), ("fleurs", "💐"), ("etoile", "⭐️"), ("étoile", "⭐️"),
            ("peur", "😱"), ("desole", "😔"), ("désolé", "😔"), ("désolée", "😔"), ("oups", "🙈"), ("chut", "🤫"), ("fou", "🤪"), ("folle", "🤪"),
            ("ange", "😇"), ("diable", "😈"), ("parfait", "👌"), ("genial", "🤩"), ("génial", "🤩"), ("super", "👍"), ("top", "👍"),
            ("oui", "👍"), ("non", "👎"), ("salut", "👋"), ("bonjour", "👋"), ("coucou", "👋"), ("faim", "😋"), ("miam", "😋"),
            ("manger", "🍽️"), ("bebe", "👶"), ("bébé", "👶"), ("famille", "👪"), ("travail", "💼"), ("boulot", "💼"), ("sport", "💪"),
            ("foot", "⚽️"), ("musique", "🎵"), ("idee", "💡"), ("idée", "💡"), ("fort", "💪"), ("champion", "🏆"), ("gagne", "🏆"),
            ("gagné", "🏆"), ("chaud", "🥵"), ("froid", "🥶"), ("nuit", "🌙"), ("lune", "🌙"), ("plage", "🏖️"), ("vacances", "🏖️"),
            ("fusee", "🚀"), ("fusée", "🚀"), ("livre", "📖"), ("telephone", "📱"), ("téléphone", "📱"), ("ordi", "💻"), ("ordinateur", "💻"),
            ("cle", "🔑"), ("clé", "🔑"), ("cerveau", "🧠"), ("chance", "🍀"), ("danse", "💃"), ("film", "🎬"), ("photo", "📷"),
            ("pizza", "🍕"), ("burger", "🍔"), ("the", "🍵"), ("thé", "🍵"), ("yeux", "👀"), ("brisé", "💔"), ("ennui", "🥱"),
            ("trop", "😍"), ("magnifique", "😍"), ("beau", "😍"), ("belle", "😍"), ("adore", "😍"), ("jadore", "😍"), ("j’adore", "😍"),
            ("j'adore", "😍"), ("bonne", "👍"), ("pouce", "👍"), ("ok", "👌"), ("daccord", "👌"), ("d’accord", "👌"), ("d'accord", "👌"),
        ]
        var m: [String: String] = [:]
        for (k, v) in pairs where m[k] == nil { m[k] = v }
        // « the » et « trop » sont trop courants en anglais / français pour un emoji : retirés.
        m["the"] = nil
        m["trop"] = nil
        m["bonne"] = nil
        return m
    }()

    /// L'emoji pour ce mot (sans tenir compte des majuscules), ou rien.
    static func emoji(for word: String) -> String? {
        let w = word.lowercased()
        guard w.count >= 2 else { return nil }
        return map[w]
    }
}
