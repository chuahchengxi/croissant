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
    let blinkToggle: String
    let blinkCaption: String
    let notificationsToggle: String
    let notificationsCaption: String
    let notificationsFDANote: String
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
        blinkToggle: "Blink animation",
        blinkCaption: "The buddy blinks now and then, and shuts its eyes while napping. Turn this off to leave the face exactly as drawn.",
        notificationsToggle: "Show notifications above the buddy",
        notificationsCaption: "When another app posts a notification, the buddy startles and holds it up on a pixel banner for a few seconds. Notices from Croissaint itself always show.",
        notificationsFDANote: "Reading notifications from other apps needs Full Disk Access.",
        companionSection: "Companion",
        activeNow: "Buddy is out and about",
        keywords: ["pet", "buddy", "pokemon", "companion", "tamagotchi", "desktop",
                   "notification", "notifications", "banner", "alert"]
    )

    static let ptBR = DesktopPetFeatureStrings(
        pageTitle: "Mascote da Mesa",
        hubDescription: "Um companheiro de bolso que passeia pela sua mesa, com aparições selvagens para capturar",
        showOnDesktopToggle: "Mostrar mascote na mesa",
        showOnDesktopCaption: "O mascote caminha pela parte inferior da tela, tira cochilos no canto quando cansado e reage a cliques. Arraste-o para onde quiser.",
        blinkToggle: "Animação de piscar",
        blinkCaption: "O mascote pisca de vez em quando e fecha os olhos durante o cochilo. Desative para manter o rosto exatamente como desenhado.",
        notificationsToggle: "Mostrar notificações acima do mascote",
        notificationsCaption: "Quando outro app envia uma notificação, o mascote se assusta e a exibe por alguns segundos em um balão de pixels. Avisos do próprio Croissaint sempre aparecem.",
        notificationsFDANote: "Ler notificações de outros apps exige Acesso Total ao Disco.",
        companionSection: "Companheiro",
        activeNow: "O mascote está passeando",
        keywords: ["mascote", "companheiro", "pokemon", "bicho",
                   "notificação", "notificacao", "notificações", "aviso"]
    )

    static let tr = DesktopPetFeatureStrings(
        pageTitle: "Masaüstü Dostu",
        hubDescription: "Masaüstünüzde dolaşan, yakalanmak için ortaya çıkan yabancılarla dolu cepli bir dost",
        showOnDesktopToggle: "Dostu masaüstünde göster",
        showOnDesktopCaption: "Dost ekranınızın altında dolaşır, yorulduğunda bir köşede şekerleme yapar ve tıklamalara tepki verir. İstediğiniz yere sürükleyin.",
        blinkToggle: "Göz kırpma animasyonu",
        blinkCaption: "Dost ara sıra göz kırpar ve şekerleme yaparken gözlerini kapatır. Yüzü çizildiği gibi bırakmak için kapatın.",
        notificationsToggle: "Bildirimleri dostun üstünde göster",
        notificationsCaption: "Başka bir uygulama bildirim gönderdiğinde dost irkilir ve bildirimi birkaç saniye boyunca piksel bir afişte tutar. Croissaint'in kendi uyarıları her zaman görünür.",
        notificationsFDANote: "Diğer uygulamaların bildirimlerini okumak Tam Disk Erişimi gerektirir.",
        companionSection: "Yoldaş",
        activeNow: "Dost şu anda geziniyor",
        keywords: ["dost", "masaüstü", "pokemon", "evcil",
                   "bildirim", "bildirimler", "uyarı"]
    )

    static let ru = DesktopPetFeatureStrings(
        pageTitle: "Питомец на рабочем столе",
        hubDescription: "Карманный друг, который бродит по рабочему столу, и дикие покемоны, которых можно ловить",
        showOnDesktopToggle: "Показывать питомца на рабочем столе",
        showOnDesktopCaption: "Питомец гуляет вдоль нижнего края экрана, дремлет в углу, когда устал, и реагирует на щелчки. Перетащите его куда угодно.",
        blinkToggle: "Анимация моргания",
        blinkCaption: "Питомец время от времени моргает и закрывает глаза во время сна. Отключите, чтобы оставить мордочку такой, как нарисована.",
        notificationsToggle: "Показывать уведомления над питомцем",
        notificationsCaption: "Когда другое приложение присылает уведомление, питомец вздрагивает и несколько секунд держит его на пиксельной табличке. Сообщения самого Croissaint показываются всегда.",
        notificationsFDANote: "Чтение уведомлений других приложений требует полного доступа к диску.",
        companionSection: "Спутник",
        activeNow: "Питомец сейчас гуляет",
        keywords: ["питомец", "друг", "покемон", "спутник",
                   "уведомление", "уведомления", "оповещение"]
    )

    static let es = DesktopPetFeatureStrings(
        pageTitle: "Mascota de escritorio",
        hubDescription: "Un compañero de bolsillo que pasea por tu escritorio, con apariciones salvajes que atrapar",
        showOnDesktopToggle: "Mostrar la mascota en el escritorio",
        showOnDesktopCaption: "La mascota camina por el borde inferior de la pantalla, se echa una siesta en una esquina cuando está cansada y reacciona a los clics. Arrástrala donde quieras.",
        blinkToggle: "Animación de parpadeo",
        blinkCaption: "La mascota parpadea de vez en cuando y cierra los ojos durante la siesta. Desactívalo para dejar la cara exactamente como está dibujada.",
        notificationsToggle: "Mostrar notificaciones sobre la mascota",
        notificationsCaption: "Cuando otra app envía una notificación, la mascota se sobresalta y la sostiene unos segundos en un cartel de píxeles. Los avisos del propio Croissaint siempre aparecen.",
        notificationsFDANote: "Leer notificaciones de otras apps requiere Acceso Total al Disco.",
        companionSection: "Compañero",
        activeNow: "La mascota está paseando",
        keywords: ["mascota", "compañero", "pokemon", "escritorio",
                   "notificación", "notificacion", "notificaciones", "aviso"]
    )

    static let de = DesktopPetFeatureStrings(
        pageTitle: "Desktop-Haustier",
        hubDescription: "Ein Taschenfreund, der über deinen Desktop wandert — mit wilden Spawns zum Fangen",
        showOnDesktopToggle: "Freund auf dem Desktop zeigen",
        showOnDesktopCaption: "Der Freund läuft am unteren Bildschirmrand entlang, macht müde in einer Ecke ein Nickerchen und reagiert auf Klicks. Ziehe ihn beliebig hin.",
        blinkToggle: "Blinzel-Animation",
        blinkCaption: "Der Freund blinzelt ab und zu und schließt beim Nickerchen die Augen. Ausschalten, um das Gesicht genau wie gezeichnet zu lassen.",
        notificationsToggle: "Mitteilungen über dem Freund zeigen",
        notificationsCaption: "Wenn eine andere App eine Mitteilung schickt, erschrickt der Freund und hält sie ein paar Sekunden auf einem Pixel-Banner hoch. Hinweise von Croissaint selbst erscheinen immer.",
        notificationsFDANote: "Mitteilungen anderer Apps zu lesen erfordert vollen Festplattenzugriff.",
        companionSection: "Begleiter",
        activeNow: "Der Freund ist unterwegs",
        keywords: ["haustier", "freund", "pokemon", "begleiter", "desktop",
                   "mitteilung", "mitteilungen", "benachrichtigung", "hinweis"]
    )

    static let fr = DesktopPetFeatureStrings(
        pageTitle: "Compagnon de bureau",
        hubDescription: "Un compagnon de poche qui se promène sur votre bureau, avec des apparitions sauvages à capturer",
        showOnDesktopToggle: "Afficher le compagnon sur le bureau",
        showOnDesktopCaption: "Le compagnon marche le long du bas de l'écran, fait une sieste dans un coin quand il est fatigué et réagit aux clics. Faites-le glisser où vous voulez.",
        blinkToggle: "Animation de clignement",
        blinkCaption: "Le compagnon cligne des yeux de temps en temps et les ferme pendant la sieste. Désactivez pour laisser le visage exactement tel quel.",
        notificationsToggle: "Afficher les notifications au-dessus du compagnon",
        notificationsCaption: "Quand une autre app envoie une notification, le compagnon sursaute et la brandit quelques secondes sur une bannière en pixels. Les avis de Croissaint s'affichent toujours.",
        notificationsFDANote: "Lire les notifications des autres apps nécessite l'accès complet au disque.",
        companionSection: "Compagnon",
        activeNow: "Le compagnon est en promenade",
        keywords: ["compagnon", "animal", "pokemon", "bureau",
                   "notification", "notifications", "bannière", "alerte"]
    )

    static let it = DesktopPetFeatureStrings(
        pageTitle: "Animale da tavolo",
        hubDescription: "Un compagno tascabile che vaghi per il tavolo, con incontri selvatici da catturare",
        showOnDesktopToggle: "Mostra il compagno sul tavolo",
        showOnDesktopCaption: "Il compagno cammina lungo il bordo inferiore dello schermo, sonnecchia in un angolo quando è stanco e reagisce ai clic. Trascinalo dove vuoi.",
        blinkToggle: "Animazione del battito di ciglia",
        blinkCaption: "Il compagno sbatte le palpebre di tanto in tanto e chiude gli occhi durante il pisolino. Disattiva per lasciare il viso esattamente come disegnato.",
        notificationsToggle: "Mostra le notifiche sopra il compagno",
        notificationsCaption: "Quando un'altra app invia una notifica, il compagno sobbalza e la regge per qualche secondo su un cartello a pixel. Gli avvisi di Croissaint compaiono sempre.",
        notificationsFDANote: "Leggere le notifiche di altre app richiede l'accesso completo al disco.",
        companionSection: "Compagno",
        activeNow: "Il compagno è in giro",
        keywords: ["animale", "compagno", "pokemon", "tavolo",
                   "notifica", "notifiche", "avviso"]
    )

    static let ja = DesktopPetFeatureStrings(
        pageTitle: "デスクトップペット",
        hubDescription: "デスクトップを歩き回るポケットの相棒。野生の出現も捕まえられます",
        showOnDesktopToggle: "相棒をデスクトップに表示",
        showOnDesktopCaption: "相棒は画面の下端を歩き、疲れると隅で昼寝し、クリックに反応します。好きな場所へドラッグできます。",
        blinkToggle: "まばたきアニメーション",
        blinkCaption: "相棒は時々まばたきし、昼寝中は目を閉じます。オフにすると顔は描かれたままになります。",
        notificationsToggle: "通知を相棒の上に表示",
        notificationsCaption: "他のアプリが通知を出すと、相棒が驚いてピクセルの看板に数秒間かかげます。Croissaint 自身のお知らせは常に表示されます。",
        notificationsFDANote: "他のアプリの通知を読むにはフルディスクアクセスが必要です。",
        companionSection: "相棒",
        activeNow: "相棒が散歩中です",
        keywords: ["ペット", "相棒", "ポケモン", "デスクトップ",
                   "通知", "お知らせ", "バナー"]
    )

    static let ko = DesktopPetFeatureStrings(
        pageTitle: "바탕화면 펫",
        hubDescription: "바탕화면을 돌아다니는 주머니 속 친구, 야생 포켓몬도 잡을 수 있습니다",
        showOnDesktopToggle: "바탕화면에 친구 표시",
        showOnDesktopCaption: "친구는 화면 아래쪽을 걷고, 피곤하면 구석에서 낮잠을 자며, 클릭에 반응합니다. 원하는 곳으로 드래그하세요.",
        blinkToggle: "눈 깜빡임 애니메이션",
        blinkCaption: "친구는 가끔 눈을 깜빡이고 낮잠 중에는 눈을 감습니다. 끄면 얼굴이 그려진 그대로 유지됩니다.",
        notificationsToggle: "알림을 친구 위에 표시",
        notificationsCaption: "다른 앱이 알림을 보내면 친구가 깜짝 놀라 픽셀 간판에 몇 초 동안 들어 올립니다. Croissaint 자체 알림은 항상 표시됩니다.",
        notificationsFDANote: "다른 앱의 알림을 읽으려면 전체 디스크 접근 권한이 필요합니다.",
        companionSection: "친구",
        activeNow: "친구가 산책 중입니다",
        keywords: ["펫", "친구", "포켓몬", "바탕화면",
                   "알림", "알림 배너", "배너"]
    )

    static let zhHans = DesktopPetFeatureStrings(
        pageTitle: "桌面伙伴",
        hubDescription: "一只在桌面上闲逛的口袋伙伴，还有野生宝可梦等你捕捉",
        showOnDesktopToggle: "在桌面上显示伙伴",
        showOnDesktopCaption: "伙伴会沿着屏幕底部散步，累了就在角落打盹，还会回应点击。可以把它拖到任意位置。",
        blinkToggle: "眨眼动画",
        blinkCaption: "伙伴会偶尔眨眼，打盹时会闭上眼睛。关闭后面部保持原画不变。",
        notificationsToggle: "在伙伴上方显示通知",
        notificationsCaption: "其他 App 发来通知时，伙伴会吓一跳，并用像素横幅举着它几秒钟。Croissaint 自己的提示始终会显示。",
        notificationsFDANote: "读取其他 App 的通知需要完全磁盘访问权限。",
        companionSection: "伙伴",
        activeNow: "伙伴正在散步",
        keywords: ["宠物", "伙伴", "宝可梦", "口袋妖怪", "桌面",
                   "通知", "提醒", "横幅"]
    )

    static let zhTW = DesktopPetFeatureStrings(
        pageTitle: "桌面夥伴",
        hubDescription: "一隻在桌面上閒晃的口袋夥伴，還有野生寶可夢等你捕捉",
        showOnDesktopToggle: "在桌面上顯示夥伴",
        showOnDesktopCaption: "夥伴會沿著螢幕底部散步，累了就在角落打盹，也會回應點擊。可以把它拖到任意位置。",
        blinkToggle: "眨眼動畫",
        blinkCaption: "夥伴會偶爾眨眼，打盹時會閉上眼睛。關閉後面部保持原畫不變。",
        notificationsToggle: "在夥伴上方顯示通知",
        notificationsCaption: "其他 App 傳來通知時，夥伴會嚇一跳，並用像素橫幅舉著它幾秒鐘。Croissaint 自己的提示一律會顯示。",
        notificationsFDANote: "讀取其他 App 的通知需要完全取用磁碟權限。",
        companionSection: "夥伴",
        activeNow: "夥伴正在散步",
        keywords: ["寵物", "夥伴", "寶可夢", "神奇寶貝", "桌面",
                   "通知", "提醒", "橫幅"]
    )

    static let zhHK = DesktopPetFeatureStrings(
        pageTitle: "桌面夥伴",
        hubDescription: "一隻喺桌面上周圍行嘅口袋夥伴，仲有野生寶可夢等你捕捉",
        showOnDesktopToggle: "喺桌面顯示夥伴",
        showOnDesktopCaption: "夥伴會沿螢幕底邊散步，攰嘅時候就會喺角落度瞌眼瞓，仲會回應撳一下。可以將佢拖去任何位置。",
        blinkToggle: "眨眼動畫",
        blinkCaption: "夥伴會間中眨吓眼，瞌眼瞓嘅時候會閉埋眼。關閉之後個樣就保持原畫唔變。",
        notificationsToggle: "喺夥伴上面顯示通知",
        notificationsCaption: "第個 App 傳通知過嚟嘅時候，夥伴會嚇一跳，仲會用像素橫額舉住佢幾秒。Croissaint 自己嘅提示就一定會顯示。",
        notificationsFDANote: "讀取其他 App 嘅通知需要完全取用磁碟權限。",
        companionSection: "夥伴",
        activeNow: "夥伴正在散步",
        keywords: ["寵物", "夥伴", "寶可夢", "神奇寶貝", "桌面",
                   "通知", "提醒", "橫幅"]
    )
}
