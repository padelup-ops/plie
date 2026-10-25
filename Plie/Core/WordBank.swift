import SwiftUI

// MARK: - Mots à faire deviner
//
// Thèmes et mots (français, anglais) utilisés par DESSINE-MOI.

enum WordTheme: Int, CaseIterable, Identifiable {
    case animals, jobs, objects, food, mime, places

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .animals: return L("Animaux")
        case .jobs: return L("Métiers")
        case .objects: return L("Objets")
        case .food: return L("À manger")
        case .mime: return L("À mimer")
        case .places: return L("Lieux")
        }
    }

    var symbol: String {
        switch self {
        case .animals: return "pawprint.fill"
        case .jobs: return "stethoscope"
        case .objects: return "umbrella.fill"
        case .food: return "fork.knife"
        case .mime: return "figure.dance"
        case .places: return "mountain.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .animals: return Color(hex: 0x8BDB4F)
        case .jobs: return Color(hex: 0x5CC8FF)
        case .objects: return Color(hex: 0xFFC53D)
        case .food: return Color(hex: 0xFF8A5C)
        case .mime: return Color(hex: 0xC59BFF)
        case .places: return Color(hex: 0x2FD08C)
        }
    }

    /// Les mots, en français et en anglais.
    var words: [(String, String)] {
        switch self {
        case .animals:
            return [("Chat", "Cat"), ("Chien", "Dog"), ("Éléphant", "Elephant"), ("Girafe", "Giraffe"), ("Lion", "Lion"),
                    ("Pingouin", "Penguin"), ("Kangourou", "Kangaroo"), ("Crocodile", "Crocodile"), ("Singe", "Monkey"),
                    ("Serpent", "Snake"), ("Lapin", "Rabbit"), ("Cheval", "Horse"), ("Vache", "Cow"), ("Cochon", "Pig"),
                    ("Poule", "Chicken"), ("Requin", "Shark"), ("Dauphin", "Dolphin"), ("Baleine", "Whale"),
                    ("Papillon", "Butterfly"), ("Abeille", "Bee"), ("Araignée", "Spider"), ("Escargot", "Snail"),
                    ("Grenouille", "Frog"), ("Hibou", "Owl"), ("Perroquet", "Parrot"), ("Tortue", "Turtle"),
                    ("Zèbre", "Zebra"), ("Ours", "Bear"), ("Loup", "Wolf"), ("Renard", "Fox")]
        case .jobs:
            return [("Pompier", "Firefighter"), ("Médecin", "Doctor"), ("Cuisinier", "Cook"), ("Pilote d'avion", "Pilot"),
                    ("Astronaute", "Astronaut"), ("Policier", "Police officer"), ("Boulanger", "Baker"), ("Coiffeur", "Hairdresser"),
                    ("Dentiste", "Dentist"), ("Jardinier", "Gardener"), ("Magicien", "Magician"), ("Chanteur", "Singer"),
                    ("Photographe", "Photographer"), ("Professeur", "Teacher"), ("Facteur", "Mail carrier"),
                    ("Vétérinaire", "Vet"), ("Pêcheur", "Fisherman"), ("Peintre", "Painter"), ("Plombier", "Plumber"),
                    ("Danseuse", "Dancer"), ("Clown", "Clown"), ("Pirate", "Pirate"), ("Chevalier", "Knight"),
                    ("Détective", "Detective"), ("Footballeur", "Soccer player")]
        case .objects:
            return [("Parapluie", "Umbrella"), ("Brosse à dents", "Toothbrush"), ("Téléphone", "Phone"), ("Guitare", "Guitar"),
                    ("Ballon", "Ball"), ("Ciseaux", "Scissors"), ("Lunettes", "Glasses"), ("Chaussette", "Sock"),
                    ("Lampe", "Lamp"), ("Horloge", "Clock"), ("Clé", "Key"), ("Bougie", "Candle"), ("Vélo", "Bike"),
                    ("Valise", "Suitcase"), ("Appareil photo", "Camera"), ("Marteau", "Hammer"), ("Échelle", "Ladder"),
                    ("Fourchette", "Fork"), ("Oreiller", "Pillow"), ("Miroir", "Mirror"), ("Trompette", "Trumpet"),
                    ("Cerf-volant", "Kite"), ("Montre", "Watch"), ("Peigne", "Comb"), ("Boussole", "Compass")]
        case .food:
            return [("Pizza", "Pizza"), ("Banane", "Banana"), ("Glace", "Ice cream"), ("Croissant", "Croissant"),
                    ("Spaghettis", "Spaghetti"), ("Fromage", "Cheese"), ("Carotte", "Carrot"), ("Pomme", "Apple"),
                    ("Chocolat", "Chocolate"), ("Gâteau", "Cake"), ("Frites", "Fries"), ("Sandwich", "Sandwich"),
                    ("Soupe", "Soup"), ("Crêpe", "Pancake"), ("Tomate", "Tomato"), ("Fraise", "Strawberry"),
                    ("Pastèque", "Watermelon"), ("Pop-corn", "Popcorn"), ("Œuf", "Egg"), ("Pain", "Bread"),
                    ("Citron", "Lemon"), ("Sushi", "Sushi"), ("Hamburger", "Burger"), ("Bonbon", "Candy"), ("Yaourt", "Yogurt")]
        case .mime:
            return [("Nager", "Swimming"), ("Dormir", "Sleeping"), ("Danser", "Dancing"), ("Éternuer", "Sneezing"),
                    ("Se brosser les dents", "Brushing your teeth"), ("Faire du vélo", "Riding a bike"), ("Conduire", "Driving"),
                    ("Cuisiner", "Cooking"), ("Jongler", "Juggling"), ("Pêcher", "Fishing"), ("Skier", "Skiing"),
                    ("Boxer", "Boxing"), ("Applaudir", "Clapping"), ("Pleurer", "Crying"), ("Rire", "Laughing"),
                    ("Courir", "Running"), ("Sauter à la corde", "Jumping rope"), ("Se maquiller", "Putting on makeup"),
                    ("Jouer de la guitare", "Playing guitar"), ("Peindre un mur", "Painting a wall"), ("Lire un livre", "Reading a book"),
                    ("Téléphoner", "Making a phone call"), ("Tricoter", "Knitting"), ("Surfer", "Surfing"), ("Marcher sur la Lune", "Walking on the Moon")]
        case .places:
            return [("Plage", "Beach"), ("Montagne", "Mountain"), ("École", "School"), ("Hôpital", "Hospital"),
                    ("Piscine", "Swimming pool"), ("Cinéma", "Movie theater"), ("Forêt", "Forest"), ("Désert", "Desert"),
                    ("Aéroport", "Airport"), ("Zoo", "Zoo"), ("Château", "Castle"), ("Bibliothèque", "Library"),
                    ("Boulangerie", "Bakery"), ("Supermarché", "Supermarket"), ("Île", "Island"), ("Volcan", "Volcano"),
                    ("Gare", "Train station"), ("Musée", "Museum"), ("Cirque", "Circus"), ("Ferme", "Farm")]
        }
    }
}
