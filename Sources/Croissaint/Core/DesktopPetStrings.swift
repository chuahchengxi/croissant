// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// Strings for the Desktop Pet feature. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file. The buddy's in-panel game text stays
/// English on purpose — it is flavor content, not chrome.
struct DesktopPetFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let showOnDesktopToggle: String
    let showOnDesktopCaption: String
    let companionSection: String
    let activeNow: String
    let keywords: [String]
}

extension FeatureStrings {
    static func desktopPet(_ language: AppLanguage) -> DesktopPetFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension DesktopPetFeatureStrings {
    static let enUS = DesktopPetFeatureStrings(
        pageTitle: "Desktop Pet",
        hubDescription: "A pocket buddy that wanders your desktop, with wild spawns to catch",
        showOnDesktopToggle: "Show buddy on desktop",
        showOnDesktopCaption: "The buddy walks along the bottom of your screen, naps in a corner when tired, and reacts to clicks. Drag it anywhere you like.",
        companionSection: "Companion",
        activeNow: "Buddy is out and about",
        keywords: ["pet", "buddy", "pokemon", "companion", "tamagotchi", "desktop"]
    )

    static let ptBR = DesktopPetFeatureStrings(
        pageTitle: "Mascote da Mesa",
        hubDescription: "Um companheiro de bolso que passeia pela sua mesa, com aparições selvagens para capturar",
        showOnDesktopToggle: "Mostrar mascote na mesa",
        showOnDesktopCaption: "O mascote caminha pela parte inferior da tela, tira cochilos no canto quando cansado e reage a cliques. Arraste-o para onde quiser.",
        companionSection: "Companheiro",
        activeNow: "O mascote está passeando",
        keywords: ["mascote", "companheiro", "pokemon", "bicho"]
    )

    static let tr = DesktopPetFeatureStrings(
        pageTitle: "Masaüstü Dostu",
        hubDescription: "Masaüstünüzde dolaşan, yakalanmak için ortaya çıkan yabancılarla dolu cepli bir dost",
        showOnDesktopToggle: "Dostu masaüstünde göster",
        showOnDesktopCaption: "Dost ekranınızın altında dolaşır, yorulduğunda bir köşede şekerleme yapar ve tıklamalara tepki verir. İstediğiniz yere sürükleyin.",
        companionSection: "Yoldaş",
        activeNow: "Dost şu anda geziniyor",
        keywords: ["dost", "masaüstü", "pokemon", "evcil"]
    )

    static let ru = DesktopPetFeatureStrings(
        pageTitle: "Питомец на рабочем столе",
        hubDescription: "Карманный друг, который бродит по рабочему столу, и дикие покемоны, которых можно ловить",
        showOnDesktopToggle: "Показывать питомца на рабочем столе",
        showOnDesktopCaption: "Питомец гуляет вдоль нижнего края экрана, дремлет в углу, когда устал, и реагирует на щелчки. Перетащите его куда угодно.",
        companionSection: "Спутник",
        activeNow: "Питомец сейчас гуляет",
        keywords: ["питомец", "друг", "покемон", "спутник"]
    )

    static let es = DesktopPetFeatureStrings(
        pageTitle: "Mascota de escritorio",
        hubDescription: "Un compañero de bolsillo que pasea por tu escritorio, con apariciones salvajes que atrapar",
        showOnDesktopToggle: "Mostrar la mascota en el escritorio",
        showOnDesktopCaption: "La mascota camina por el borde inferior de la pantalla, se echa una siesta en una esquina cuando está cansada y reacciona a los clics. Arrástrala donde quieras.",
        companionSection: "Compañero",
        activeNow: "La mascota está paseando",
        keywords: ["mascota", "compañero", "pokemon", "escritorio"]
    )

    static let de = DesktopPetFeatureStrings(
        pageTitle: "Desktop-Haustier",
        hubDescription: "Ein Taschenfreund, der über deinen Desktop wandert — mit wilden Spawns zum Fangen",
        showOnDesktopToggle: "Freund auf dem Desktop zeigen",
        showOnDesktopCaption: "Der Freund läuft am unteren Bildschirmrand entlang, macht müde in einer Ecke ein Nickerchen und reagiert auf Klicks. Ziehe ihn beliebig hin.",
        companionSection: "Begleiter",
        activeNow: "Der Freund ist unterwegs",
        keywords: ["haustier", "freund", "pokemon", "begleiter", "desktop"]
    )

    static let fr = DesktopPetFeatureStrings(
        pageTitle: "Compagnon de bureau",
        hubDescription: "Un compagnon de poche qui se promène sur votre bureau, avec des apparitions sauvages à capturer",
        showOnDesktopToggle: "Afficher le compagnon sur le bureau",
        showOnDesktopCaption: "Le compagnon marche le long du bas de l'écran, fait une sieste dans un coin quand il est fatigué et réagit aux clics. Faites-le glisser où vous voulez.",
        companionSection: "Compagnon",
        activeNow: "Le compagnon est en promenade",
        keywords: ["compagnon", "animal", "pokemon", "bureau"]
    )

    static let it = DesktopPetFeatureStrings(
        pageTitle: "Animale da tavolo",
        hubDescription: "Un compagno tascabile che vaghi per il tavolo, con incontri selvatici da catturare",
        showOnDesktopToggle: "Mostra il compagno sul tavolo",
        showOnDesktopCaption: "Il compagno cammina lungo il bordo inferiore dello schermo, sonnecchia in un angolo quando è stanco e reagisce ai clic. Trascinalo dove vuoi.",
        companionSection: "Compagno",
        activeNow: "Il compagno è in giro",
        keywords: ["animale", "compagno", "pokemon", "tavolo"]
    )

    static let ja = DesktopPetFeatureStrings(
        pageTitle: "デスクトップペット",
        hubDescription: "デスクトップを歩き回るポケットの相棒。野生の出現も捕まえられます",
        showOnDesktopToggle: "相棒をデスクトップに表示",
        showOnDesktopCaption: "相棒は画面の下端を歩き、疲れると隅で昼寝し、クリックに反応します。好きな場所へドラッグできます。",
        companionSection: "相棒",
        activeNow: "相棒が散歩中です",
        keywords: ["ペット", "相棒", "ポケモン", "デスクトップ"]
    )

    static let ko = DesktopPetFeatureStrings(
        pageTitle: "바탕화면 펫",
        hubDescription: "바탕화면을 돌아다니는 주머니 속 친구, 야생 포켓몬도 잡을 수 있습니다",
        showOnDesktopToggle: "바탕화면에 친구 표시",
        showOnDesktopCaption: "친구는 화면 아래쪽을 걷고, 피곤하면 구석에서 낮잠을 자며, 클릭에 반응합니다. 원하는 곳으로 드래그하세요.",
        companionSection: "친구",
        activeNow: "친구가 산책 중입니다",
        keywords: ["펫", "친구", "포켓몬", "바탕화면"]
    )

    static let zhHans = DesktopPetFeatureStrings(
        pageTitle: "桌面伙伴",
        hubDescription: "一只在桌面上闲逛的口袋伙伴，还有野生宝可梦等你捕捉",
        showOnDesktopToggle: "在桌面上显示伙伴",
        showOnDesktopCaption: "伙伴会沿着屏幕底部散步，累了就在角落打盹，还会回应点击。可以把它拖到任意位置。",
        companionSection: "伙伴",
        activeNow: "伙伴正在散步",
        keywords: ["宠物", "伙伴", "宝可梦", "口袋妖怪", "桌面"]
    )

    static let zhTW = DesktopPetFeatureStrings(
        pageTitle: "桌面夥伴",
        hubDescription: "一隻在桌面上閒晃的口袋夥伴，還有野生寶可夢等你捕捉",
        showOnDesktopToggle: "在桌面上顯示夥伴",
        showOnDesktopCaption: "夥伴會沿著螢幕底部散步，累了就在角落打盹，也會回應點擊。可以把它拖到任意位置。",
        companionSection: "夥伴",
        activeNow: "夥伴正在散步",
        keywords: ["寵物", "夥伴", "寶可夢", "神奇寶貝", "桌面"]
    )

    static let zhHK = DesktopPetFeatureStrings(
        pageTitle: "桌面夥伴",
        hubDescription: "一隻喺桌面上周圍行嘅口袋夥伴，仲有野生寶可夢等你捕捉",
        showOnDesktopToggle: "喺桌面顯示夥伴",
        showOnDesktopCaption: "夥伴會沿螢幕底邊散步，攰嘅時候就會喺角落度瞌眼瞓，仲會回應撳一下。可以將佢拖去任何位置。",
        companionSection: "夥伴",
        activeNow: "夥伴正在散步",
        keywords: ["寵物", "夥伴", "寶可夢", "神奇寶貝", "桌面"]
    )
}
