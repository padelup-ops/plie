import SwiftUI

// MARK: - Le téléphone de Nina — chapitre 1 « Trouvé »
//
// Lundi 3 novembre, 8 h 12, TER Nantes–Le Croisic. Nina Perrin, 24 ans, n'a plus donné de nouvelles depuis vendredi soir.

enum NinaStory {
    static let story = PhoneStory(
        owner: "Nina",
        passcode: "1403",
        lockHints: [
            T("Le fond d'écran raconte quelque chose.", "The wallpaper is telling you something."),
            T("Regarde ce qui est écrit sous la photo du chat.", "Look at what's written under the cat's photo."),
            T("Une date : le jour, puis le mois. Quatre chiffres.", "A date: the day, then the month. Four digits.")
        ],
        wallpaper: .polaroidPixel,
        contacts: [
            Contact(id: "ines", name: "Inès", color: Color(red: 0.95, green: 0.45, blue: 0.55)),
            Contact(id: "maman", name: T("Maman", "Mom"), color: Color(red: 0.55, green: 0.6, blue: 0.95)),
            Contact(id: "h", name: "H ♡", color: Color(red: 0.5, green: 0.5, blue: 0.55)),
            Contact(id: "samir", name: "Samir Studio", color: Color(red: 0.3, green: 0.75, blue: 0.7)),
            Contact(id: "studio", name: "Studio Lumen 📷", color: Color(red: 0.95, green: 0.7, blue: 0.3))
        ],
        conversations: [
            Conversation(id: "ines", contact: "ines", history: [
                Message(id: "i1", thread: "ines", fromMe: false, text: T("Ce week-end on se fait le ciné ?", "Movie this weekend?"), time: T("Jeu. 19:02", "Thu 7:02 PM")),
                Message(id: "i2", thread: "ines", fromMe: true, text: T("Grave. Mais pas vendredi, j'ai un truc et je sais pas à quelle heure je finis", "Sure. But not Friday, I have a thing and I don't know when it ends"), time: T("Jeu. 19:10", "Thu 7:10 PM")),
                Message(id: "i3", thread: "ines", fromMe: false, text: T("Mystérieuse 👀", "Mysterious 👀"), time: T("Jeu. 19:11", "Thu 7:11 PM")),
                Message(id: "i4", thread: "ines", fromMe: true, text: T("Je t'expliquerai. Promis.", "I'll explain. Promise."), time: T("Jeu. 19:15", "Thu 7:15 PM")),
                Message(id: "i5", thread: "ines", fromMe: true, text: T("Tu pourrais garder Pixel quelques jours ? La clé est sous le pot de basilic", "Could you look after Pixel for a few days? The key is under the basil pot"), time: T("Ven. 17:52", "Fri 5:52 PM")),
                Message(id: "i6", thread: "ines", fromMe: false, text: T("Euh oui bien sûr. Tout va bien ?", "Uh, sure. Is everything ok?"), time: T("Ven. 17:58", "Fri 5:58 PM")),
                Message(id: "i7", thread: "ines", fromMe: true, text: T("Oui. Je t'aime fort.", "Yes. Love you lots."), time: T("Ven. 18:03", "Fri 6:03 PM")),
                Message(id: "i8", thread: "ines", fromMe: false, text: T("Nina ?", "Nina?"), time: T("Sam. 11:20", "Sat 11:20 AM")),
                Message(id: "i9", thread: "ines", fromMe: false, text: T("Pixel va bien, il a tout mangé. Toi tu réponds plus 😕", "Pixel is fine, he ate everything. You're not answering 😕"), time: T("Sam. 18:44", "Sat 6:44 PM")),
                Message(id: "i10", thread: "ines", fromMe: false, text: T("Ta mère m'a appelée. Elle est super inquiète.", "Your mom called me. She's really worried."), time: T("Dim. 10:05", "Sun 10:05 AM")),
                Message(id: "i11", thread: "ines", fromMe: false, text: T("Nina sérieux, appelle quelqu'un", "Nina seriously, call someone"), time: T("Dim. 22:31", "Sun 10:31 PM")),
                Message(id: "i12", thread: "ines", fromMe: false, text: T("T'es où ??", "Where are you??"), time: "07:58")
            ]),
            Conversation(id: "maman", contact: "maman", history: [
                Message(id: "m1", thread: "maman", fromMe: false, text: T("Tu viens dimanche ? Je fais le gâteau aux pommes", "Coming on Sunday? I'm making apple cake"), time: T("Jeu. 12:14", "Thu 12:14 PM")),
                Message(id: "m2", thread: "maman", fromMe: true, text: T("Pas ce dimanche maman. Je t'embrasse fort", "Not this Sunday mom. Big hugs"), time: T("Jeu. 12:40", "Thu 12:40 PM")),
                Message(id: "m3", thread: "maman", fromMe: false, text: T("Ma chérie, tu ne réponds pas ?", "Sweetheart, you're not answering?"), time: T("Sam. 16:02", "Sat 4:02 PM")),
                Message(id: "m4", thread: "maman", fromMe: false, text: T("Inès m'a appelée. Rappelle-moi s'il te plaît.", "Inès called me. Please call me back."), time: T("Dim. 09:47", "Sun 9:47 AM")),
                Message(id: "m5", thread: "maman", fromMe: false, text: T("Nina rappelle-moi, je t'en supplie", "Nina call me back, I'm begging you"), time: "07:30")
            ]),
            Conversation(id: "h", contact: "h", history: [
                Message(id: "h1", thread: "h", fromMe: false, text: T("Tu étais belle hier soir ❤", "You looked beautiful last night ❤"), time: "12/08"),
                Message(id: "h2", thread: "h", fromMe: true, text: "❤", time: "12/08"),
                Message(id: "h3", thread: "h", fromMe: false, text: T("Pourquoi tu parles encore à ce Samir ?", "Why are you still talking to that Samir?"), time: "02/09"),
                Message(id: "h4", thread: "h", fromMe: true, text: T("C'est mon collègue Hu. Arrête.", "He's my coworker. Stop."), time: "02/09"),
                Message(id: "h5", thread: "h", fromMe: true, text: T("J'ai besoin qu'on fasse une pause. Pour de vrai cette fois.", "I need us to take a break. For real this time."), time: "05/09"),
                Message(id: "h6", thread: "h", fromMe: false, text: T("Je comprends pas pourquoi tu me fais ça", "I don't understand why you're doing this to me"), time: "05/09"),
                Message(id: "h7", thread: "h", fromMe: false, text: T("Je suis passé devant le studio. Tu étais jolie aujourd'hui.", "I walked past the studio. You looked pretty today."), time: T("Jeu. 18:20", "Thu 6:20 PM")),
                Message(id: "h8", thread: "h", fromMe: false, text: T("Tu es où ce soir ?", "Where are you tonight?"), time: T("Ven. 21:40", "Fri 9:40 PM")),
                Message(id: "h9", thread: "h", fromMe: false, text: T("Réponds-moi.", "Answer me."), time: T("Sam. 01:12", "Sat 1:12 AM")),
                Message(id: "h10", thread: "h", fromMe: false, text: T("Je sais que tu lis.", "I know you're reading."), time: T("Sam. 01:13", "Sat 1:13 AM")),
                Message(id: "h11", thread: "h", fromMe: false, text: T("Bonne nuit ma belle ❤", "Good night beautiful ❤"), time: T("Dim. 23:59", "Sun 11:59 PM"))
            ]),
            Conversation(id: "samir", contact: "samir", history: [
                Message(id: "s1", thread: "samir", fromMe: false, text: T("Tu as les fichiers du mariage Rivière ?", "Do you have the Rivière wedding files?"), time: T("Mer. 10:02", "Wed 10:02 AM")),
                Message(id: "s2", thread: "samir", fromMe: true, text: T("Sur le serveur, dossier 2025-10 👍", "On the server, folder 2025-10 👍"), time: T("Mer. 10:05", "Wed 10:05 AM")),
                Message(id: "s3", thread: "samir", fromMe: true, text: T("Tu peux garder ce que je t'ai donné tout à l'heure ? Ne l'ouvre pas.", "Can you keep what I gave you earlier? Don't open it."), time: T("Ven. 16:31", "Fri 4:31 PM")),
                Message(id: "s4", thread: "samir", fromMe: false, text: T("Ok… tu me fais un peu peur là", "Ok… you're kind of scaring me"), time: T("Ven. 16:40", "Fri 4:40 PM")),
                Message(id: "s5", thread: "samir", fromMe: true, text: T("Je t'expliquerai. Merci Samir. Vraiment.", "I'll explain. Thank you Samir. Really."), time: T("Ven. 16:41", "Fri 4:41 PM")),
                Message(id: "s6", thread: "samir", fromMe: false, text: T("T'es pas venue ce matin, le boss demande. Ça va ?", "You didn't come in this morning, the boss is asking. You ok?"), time: "08:05")
            ]),
            Conversation(id: "studio", contact: "studio", history: [
                Message(id: "g1", thread: "studio", fromMe: false, text: T("Paul : shooting Brioches Lebrun déplacé à jeudi 9h", "Paul: Lebrun Bakery shoot moved to Thursday 9am"), time: T("Mar. 08:40", "Tue 8:40 AM")),
                Message(id: "g2", thread: "studio", fromMe: true, text: T("Je prends le 50mm et les deux softbox", "I'll take the 50mm and both softboxes"), time: T("Mar. 08:52", "Tue 8:52 AM")),
                Message(id: "g3", thread: "studio", fromMe: false, text: T("Samir : quelqu'un a encore mangé mes Petit Écolier 😤", "Samir: someone ate my cookies again 😤"), time: T("Mer. 15:10", "Wed 3:10 PM")),
                Message(id: "g4", thread: "studio", fromMe: true, text: T("Pixel. C'était Pixel.", "Pixel. It was Pixel."), time: T("Mer. 15:11", "Wed 3:11 PM")),
                Message(id: "g5", thread: "studio", fromMe: false, text: T("Paul : Nina tu es absente lundi ? Rien dans le planning", "Paul: Nina are you off on Monday? Nothing in the schedule"), time: T("Dim. 20:15", "Sun 8:15 PM"))
            ])
        ],
        photos: [
            PhotoItem(id: "p1", art: .polaroidPixel, date: T("14 mars 2023", "March 14, 2023"), place: "Nantes",
                      back: T("Pixel ♡ arrivé à la maison le 14/03", "Pixel ♡ came home on 14/03")),
            PhotoItem(id: "p2", art: .pixelSleeping, date: T("2 novembre 2025", "November 2, 2025"), place: "Nantes"),
            PhotoItem(id: "p3", art: .birthday, date: T("23 août 2025", "August 23, 2025"), place: "Nantes",
                      back: T("Les 25 ans d'Inès 🎈 — de gauche à droite : Samir, Inès, Hugo, moi", "Inès turns 25 🎈 — left to right: Samir, Inès, Hugo, me")),
            PhotoItem(id: "p4", art: .loireSunset, date: T("30 octobre 2025", "October 30, 2025"), place: T("Quai de la Fosse", "Quai de la Fosse")),
            PhotoItem(id: "p5", art: .studio, date: T("28 octobre 2025", "October 28, 2025"), place: "Studio Lumen"),
            PhotoItem(id: "p6", art: .coffee, date: T("27 octobre 2025", "October 27, 2025"), place: T("Café du Passage", "Café du Passage")),
            PhotoItem(id: "p7", art: .flowers, date: T("19 octobre 2025", "October 19, 2025"), place: T("Jardin des Plantes", "Jardin des Plantes")),
            PhotoItem(id: "p8", art: .catOnDesk, date: T("12 octobre 2025", "October 12, 2025"), place: "Nantes"),
            PhotoItem(id: "p9", art: .trainWindow, date: T("4 octobre 2025", "October 4, 2025"), place: T("Angers", "Angers"))
        ],
        notes: [
            Note(id: "n0", title: T("Si quelqu'un lit ça", "If someone reads this"),
                 body: T("""
                 Si tu as trouvé ce téléphone : ne réponds pas à H. Ne lui dis pas où tu es.

                 Je vais bien. Mais j'ai besoin de toi.

                 Tout est là-dedans, il faut juste chercher. Commence par mes photos.

                 — N.
                 """, """
                 If you found this phone: don't answer H. Don't tell him where you are.

                 I'm ok. But I need you.

                 Everything is in here, you just have to look. Start with my photos.

                 — N.
                 """), date: T("Ven. 19:48", "Fri 7:48 PM"), pinned: true, requires: "note_unlocked"),
            Note(id: "n1", title: T("Courses", "Groceries"),
                 body: T("- lait\n- croquettes Pixel (les bleues !)\n- piles AA\n- basilic", "- milk\n- Pixel's kibble (the blue ones!)\n- AA batteries\n- basil"), date: T("Mer.", "Wed")),
            Note(id: "n2", title: T("Vendredi", "Friday"),
                 body: T("Papiers ✔︎\nChargeur ✔︎\nClé → pot\n18h\nLe reste reste ici.", "Papers ✔︎\nCharger ✔︎\nKey → pot\n6pm\nEverything else stays here."), date: T("Jeu.", "Thu")),
            Note(id: "n3", title: T("Idées photos", "Photo ideas"),
                 body: T("- le pont Anne-de-Bretagne au lever du soleil\n- les grues jaunes de l'île de Nantes sous la pluie\n- Pixel dans un carton (classique)\n- portrait de maman dans son jardin", "- Anne-de-Bretagne bridge at sunrise\n- the yellow cranes of Île de Nantes in the rain\n- Pixel in a box (a classic)\n- portrait of mom in her garden"), date: "21/10"),
            Note(id: "n4", title: T("Pour moi", "For me"),
                 body: T("Code de l'album : mon chiffre porte-bonheur × le numéro de chez maman.\n(Comme ça je l'oublie jamais.)",
                         "Album code: my lucky number × mom's house number.\n(That way I never forget it.)"),
                 date: "06/09", requires: "ch2")
        ],
        voicemails: [
            Voicemail(id: "v1", contact: "maman", date: T("Dim. 19:42", "Sun 7:42 PM"), seconds: 38,
                      transcript: T("Nina, c'est maman. Je ne sais pas pourquoi tu ne réponds pas. Inès est passée voir Pixel, il va bien. Tu te souviens, quand tu étais petite, tu disais que le sept te portait bonheur ? J'ai allumé une bougie. Rappelle-moi, ma chérie. N'importe quand.",
                                    "Nina, it's mom. I don't know why you're not answering. Inès went to see Pixel, he's fine. Do you remember, when you were little, you used to say seven was your lucky number? I lit a candle. Call me back, sweetheart. Anytime.")),
            Voicemail(id: "v2", contact: "h", date: T("Sam. 02:13", "Sat 2:13 AM"), seconds: 21,
                      transcript: T("C'est moi. Je suis en bas de chez toi. La lumière est éteinte. Je veux juste parler. Rappelle-moi.",
                                    "It's me. I'm outside your place. The light is off. I just want to talk. Call me back.")),
            Voicemail(id: "v3", contact: "samir", date: T("Ven. 20:05", "Fri 8:05 PM"), seconds: 12,
                      transcript: T("Hé, c'est Samir. Je l'ai mis dans mon casier. Personne n'y touche. Prends soin de toi.",
                                    "Hey, it's Samir. I put it in my locker. Nobody touches it. Take care of yourself."))
        ],
        live: [
            LiveMessage(id: "l1", after: "unlocked", delay: 6, message: Message(id: "li1", thread: "ines", fromMe: false, text: T("…Nina ? Ton téléphone vient de se rallumer ?", "…Nina? Your phone just came back on?"), time: T("maintenant", "now"))),
            LiveMessage(id: "l2", after: "unlocked", delay: 14, message: Message(id: "li2", thread: "ines", fromMe: false, text: T("Si ce n'est pas Nina qui lit ça : qui êtes-vous ? Vous avez trouvé son téléphone ?", "If this isn't Nina reading: who are you? Did you find her phone?"), time: T("maintenant", "now")), sets: "ines_asks"),
            LiveMessage(id: "l3", after: "unlocked", delay: 30, message: Message(id: "lh1", thread: "h", fromMe: false, text: T("Nina ?", "Nina?"), time: T("maintenant", "now"))),
            LiveMessage(id: "l4", after: "unlocked", delay: 46, message: Message(id: "lh2", thread: "h", fromMe: false, text: T("Ton téléphone est allumé. Je le vois.", "Your phone is on. I can see it."), time: T("maintenant", "now"))),
            LiveMessage(id: "l5", after: "ines_told", delay: 4, message: Message(id: "li3", thread: "ines", fromMe: false, text: T("Merci. Merci. Elle a disparu depuis vendredi soir. La police dit qu'elle est majeure, qu'elle est peut-être partie d'elle-même.", "Thank you. Thank you. She's been missing since Friday night. The police say she's an adult, she may have left on her own."), time: T("maintenant", "now"))),
            LiveMessage(id: "l6", after: "ines_told", delay: 10, message: Message(id: "li4", thread: "ines", fromMe: false, text: T("Je peux vous demander un truc ? Dans ses contacts il y a un « H ». Il lui écrit tout le temps. Vous pouvez trouver qui c'est ?", "Can I ask you something? There's an \"H\" in her contacts. He texts her all the time. Can you find out who it is?"), time: T("maintenant", "now")), sets: "ask_h"),
            LiveMessage(id: "l7", after: "h_no_samir", delay: 3, message: Message(id: "li5", thread: "ines", fromMe: false, text: T("Non, Samir est dans ses contacts sous son nom. Regardez ses photos : elle écrit souvent les prénoms au dos.", "No, Samir is in her contacts under his name. Look at her photos: she often writes names on the back."), time: T("maintenant", "now"))),
            LiveMessage(id: "l8", after: "h_no_idea", delay: 3, message: Message(id: "li6", thread: "ines", fromMe: false, text: T("Regardez ses photos, s'il vous plaît. Elle écrit souvent les prénoms au dos.", "Please look at her photos. She often writes names on the back."), time: T("maintenant", "now"))),
            LiveMessage(id: "l9", after: "h_found", delay: 3, message: Message(id: "li7", thread: "ines", fromMe: false, text: T("Hugo. Son ex. Ils se sont séparés il y a deux mois.", "Hugo. Her ex. They broke up two months ago."), time: T("maintenant", "now"))),
            LiveMessage(id: "l10", after: "h_found", delay: 9, message: Message(id: "li8", thread: "ines", fromMe: false, text: T("Elle avait peur de lui ces derniers temps. Elle me l'a dit une fois, et puis plus rien.", "She was scared of him lately. She told me once, then nothing."), time: T("maintenant", "now"))),
            LiveMessage(id: "l11", after: "h_found", delay: 15, message: Message(id: "li9", thread: "ines", fromMe: false, text: T("Elle notait tout dans ses notes. Regardez, s'il vous plaît.", "She wrote everything down in her notes. Please look."), time: T("maintenant", "now")), sets: "note_unlocked"),
            LiveMessage(id: "l12", after: "h_found", delay: 22, message: Message(id: "lh3", thread: "h", fromMe: false, text: T("Qui a ton téléphone ?", "Who has your phone?"), time: T("maintenant", "now"))),
            // Chapitre 2 — Les photos
            LiveMessage(id: "c1", after: "ch2", delay: 5, message: Message(id: "c2i1", thread: "ines", fromMe: false, text: T("Vous avez lu ses notes ? Elle a laissé quelque chose ?", "Did you read her notes? Did she leave anything?"), time: T("maintenant", "now")), sets: "ines_note_ask"),
            LiveMessage(id: "c2", after: "note_told", delay: 4, message: Message(id: "c2i2", thread: "ines", fromMe: false, text: T("Elle va bien… J'ose pas y croire.", "She's ok… I can't believe it."), time: T("maintenant", "now"))),
            LiveMessage(id: "c3", after: "note_told", delay: 11, message: Message(id: "c2i3", thread: "ines", fromMe: false, text: T("Elle avait un album caché dans ses photos, elle me l'a montré une fois. Le code venait d'un truc avec sa mère, un chiffre porte-bonheur.", "She had a hidden album in her photos, she showed me once. The code came from something with her mom, a lucky number."), time: T("maintenant", "now")), sets: "album_hint"),
            LiveMessage(id: "c4", after: "album_open", delay: 8, message: Message(id: "c2h1", thread: "h", fromMe: false, text: T("Arrête de fouiller dans ses affaires.", "Stop going through her things."), time: T("maintenant", "now"))),
            LiveMessage(id: "c5", after: "car_told", delay: 4, message: Message(id: "c2i4", thread: "ines", fromMe: false, text: T("Hugo a une Clio grise. Je l'ai vue cent fois devant chez elle.", "Hugo drives a grey Clio. I've seen it outside her place a hundred times."), time: T("maintenant", "now"))),
            LiveMessage(id: "c6", after: "car_told", delay: 12, message: Message(id: "c2i5", thread: "ines", fromMe: false, text: T("Elle le prenait en photo. Pour avoir des preuves. Et elle ne m'a rien dit…", "She was taking photos of him. To have proof. And she never told me…"), time: T("maintenant", "now"))),
            LiveMessage(id: "c7", after: "car_told", delay: 22, message: Message(id: "c2s1", thread: "samir", fromMe: false, text: T("Nina ? C'est toi ? J'ai toujours ce que tu m'as donné. Dans mon casier, comme promis.", "Nina? Is that you? I still have what you gave me. In my locker, like I promised."), time: T("maintenant", "now"))),
            LiveMessage(id: "c8", after: "car_told", delay: 32, message: Message(id: "c2h2", thread: "h", fromMe: false, text: T("Je vais venir le chercher, ce téléphone.", "I'm coming to get that phone."), time: T("maintenant", "now")), sets: "ch2_done")
        ],
        replies: [
            ReplyChoice(id: "r1", thread: "ines", when: ["ines_asks"], until: "ines_told", text: T("Oui. Je l'ai trouvé sur un siège du TER, ce matin.", "Yes. I found it on a seat on the train this morning."), sets: "ines_told"),
            ReplyChoice(id: "r2", thread: "ines", when: ["ines_asks"], until: "ines_told", text: T("Je l'ai trouvé dans le train. Je veux aider.", "I found it on the train. I want to help."), sets: "ines_told"),
            ReplyChoice(id: "r3", thread: "ines", when: ["ask_h"], until: "h_found", text: T("C'est Samir, je crois.", "It's Samir, I think."), sets: "h_no_samir"),
            ReplyChoice(id: "r4", thread: "ines", when: ["ask_h"], until: "h_found", text: T("Aucune idée.", "No idea."), sets: "h_no_idea"),
            ReplyChoice(id: "r5", thread: "ines", when: ["ask_h", "seen_back_p3"], until: "h_found", text: T("C'est Hugo. Il est sur une photo d'anniversaire.", "It's Hugo. He's in a birthday photo."), sets: "h_found"),
            ReplyChoice(id: "r6", thread: "ines", when: ["ines_note_ask"], until: "note_told", text: T("Oui. Elle dit qu'elle va bien, de ne pas répondre à H, et de regarder ses photos.", "Yes. She says she's ok, not to answer H, and to look at her photos."), sets: "note_told"),
            ReplyChoice(id: "r7", thread: "ines", when: ["ines_note_ask"], until: "note_told", text: T("Elle dit qu'elle va bien.", "She says she's ok."), sets: "note_told"),
            ReplyChoice(id: "r8", thread: "ines", when: ["car_all"], until: "car_told", text: T("Dans son album caché, la même voiture grise revient sur chaque photo. Plaque GX-417-HL.", "In her hidden album, the same grey car is in every photo. Plate GX-417-HL."), sets: "car_told")
        ],
        lockNotifications: [
            Message(id: "ln1", thread: "ines", fromMe: false, text: T("T'es où ??", "Where are you??"), time: "07:58"),
            Message(id: "ln2", thread: "maman", fromMe: false, text: T("Nina rappelle-moi, je t'en supplie", "Nina call me back, I'm begging you"), time: "07:30"),
            Message(id: "ln3", thread: "samir", fromMe: false, text: T("T'es pas venue ce matin, le boss demande. Ça va ?", "You didn't come in this morning, the boss is asking. You ok?"), time: "08:05"),
            Message(id: "ln4", thread: "h", fromMe: false, text: T("Bonne nuit ma belle ❤", "Good night beautiful ❤"), time: T("hier", "yesterday"))
        ],
        events: [
            CalendarEvent(id: "e1", day: T("Mercredi 29 octobre", "Wednesday, October 29"), time: "17:30", title: T("Véto Pixel (vaccin)", "Vet for Pixel (shots)"), color: .green),
            CalendarEvent(id: "e2", day: T("Jeudi 30 octobre", "Thursday, October 30"), time: "09:00", title: T("Shooting Brioches Lebrun", "Lebrun Bakery shoot"), detail: T("Studio B. Prendre le 50 mm et les deux softbox.", "Studio B. Bring the 50mm and both softboxes."), color: .orange),
            CalendarEvent(id: "e3", day: T("Vendredi 31 octobre", "Friday, October 31"), time: "18:00", title: "R.",
                          detail: T("Papiers.\nRien d'autre.", "Papers.\nNothing else."), color: .purple),
            CalendarEvent(id: "e4", day: T("Dimanche 2 novembre", "Sunday, November 2"), time: "12:30", title: T("Déjeuner chez maman", "Lunch at mom's"),
                          detail: T("112 rue Saint-Aubin, Angers\n(gâteau aux pommes 🍎)", "112 rue Saint-Aubin, Angers\n(apple cake 🍎)"), color: .pink),
            CalendarEvent(id: "e5", day: T("Lundi 3 novembre", "Monday, November 3"), time: "09:00", title: T("Studio", "Studio"), color: .orange)
        ],
        hiddenAlbum: HiddenAlbum(
            title: T("Masqué", "Hidden"),
            code: "784",
            hints: [
                T("Écoute la messagerie : sa mère parle d'un chiffre porte-bonheur.", "Listen to the voicemails: her mom mentions a lucky number."),
                T("L'adresse de sa mère est dans l'agenda.", "Her mom's address is in the calendar."),
                T("7 × 112.", "7 × 112.")
            ],
            photos: [
                PhotoItem(id: "a1", art: .streetStudio, date: T("12 septembre 2025", "September 12, 2025"), place: T("Devant le studio", "Outside the studio"), car: CGPoint(x: 0.72, y: 0.8)),
                PhotoItem(id: "a2", art: .streetHome, date: T("27 septembre 2025", "September 27, 2025"), place: T("En bas de chez moi", "Outside my place"), car: CGPoint(x: 0.3, y: 0.82)),
                PhotoItem(id: "a3", art: .parkGate, date: T("11 octobre 2025", "October 11, 2025"), place: T("Jardin des Plantes", "Jardin des Plantes"), car: CGPoint(x: 0.78, y: 0.84)),
                PhotoItem(id: "a4", art: .station, date: T("24 octobre 2025", "October 24, 2025"), place: T("Gare de Nantes", "Nantes station"),
                          back: T("Encore lui. 24/10. Je garde tout.", "Him again. 24/10. I'm keeping everything."), car: CGPoint(x: 0.25, y: 0.83))
            ],
            plate: "GX-417-HL"
        ),
        chapters: [
            Chapter(title: T("Trouvé", "Found"), end: "read_n0",
                    endText: T("Nina savait que quelqu'un lirait sa note. Elle comptait sur toi.\nAu chapitre 2, son agenda s'ouvre, et un album caché attend dans ses photos.",
                               "Nina knew someone would read her note. She was counting on you.\nIn chapter 2, her calendar opens, and a hidden album is waiting in her photos."),
                    start: "unlocked"),
            Chapter(title: T("Les photos", "The photos"), end: "ch2_done",
                    endText: T("Nina photographiait Hugo depuis des semaines. Des preuves.\nEt maintenant, il sait que quelqu'un a son téléphone.\nLe chapitre 3 arrive bientôt.",
                               "Nina had been photographing Hugo for weeks. Proof.\nAnd now he knows someone has her phone.\nChapter 3 is coming soon."),
                    start: "ch2")
        ],
        freeChapters: 1
    )
}
