import AppKit
import SwiftUI

/// Task-oriented help: each topic answers one "how do I…" question and ships
/// one short caption that says what to look at on that screen.
struct HelpView: View {
    @State private var selection: String
    @State private var query = ""

    private let topics: [HelpTopic]

    init() {
        let content = HelpContent.current
        topics = content
        _selection = State(initialValue: content.first?.id ?? "")
    }

    private var filtered: [HelpTopic] {
        guard !query.isEmpty else { return topics }
        let needle = query.lowercased()
        return topics.filter {
            $0.title.lowercased().contains(needle)
                || $0.summary.lowercased().contains(needle)
                || $0.sections.contains { section in
                    section.heading.lowercased().contains(needle)
                        || section.lines.contains { $0.lowercased().contains(needle) }
                }
        }
    }

    private var selectedTopic: HelpTopic? {
        topics.first { $0.id == selection } ?? filtered.first
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(HelpContent.searchPlaceholder, text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(DesignToken.Spacing.small)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: DesignToken.Radius.control))
                .padding(DesignToken.Spacing.compact)

                List(filtered, selection: $selection) { topic in
                    Label(topic.title, systemImage: topic.icon)
                        .tag(topic.id)
                }
                .listStyle(.sidebar)
            }
            .navigationTitle(HelpContent.sidebarTitle)
        } detail: {
            if let selectedTopic {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                        HStack(spacing: DesignToken.Spacing.compact) {
                            Image(systemName: selectedTopic.icon)
                                .font(.system(size: 24))
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedTopic.title).font(.title2.bold())
                                Text(selectedTopic.summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        topicBanner(selectedTopic)

                        ForEach(selectedTopic.sections) { section in
                            VStack(alignment: .leading, spacing: DesignToken.Spacing.tight) {
                                Text(section.heading).font(.headline)
                                ForEach(section.lines, id: \.self) { line in
                                    Text(line)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        if selectedTopic.id == "settings" {
                            shortcuts
                        }

                        Divider()
                        HStack {
                            Link(
                                "Open README",
                                destination: URL(string: "https://github.com/zheltukheen/lanfi#readme")!)
                            Link(
                                "Report an issue",
                                destination: URL(string: "https://github.com/zheltukheen/lanfi/issues")!)
                        }
                        .font(.caption)
                    }
                    .padding(DesignToken.Spacing.section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(selectedTopic.title)
            } else {
                Text("Select a topic")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 290)
        .frame(minWidth: 860, minHeight: 620)
    }

    /// A symbol banner instead of a screenshot: the help text must not ship
    /// pictures of anyone's network, SSIDs, addresses or device names.
    private func topicBanner(_ topic: HelpTopic) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.tight) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignToken.Radius.card)
                    .fill(Color.accentColor.opacity(0.10))
                Image(systemName: topic.icon)
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(.accentColor)
            }
            .frame(height: 110)
            Text(topic.screenshotCaption)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Keyboard shortcuts").font(.headline)
            shortcut("⌘R", HelpContent.refresh)
            shortcut("⌘F", HelpContent.search)
            shortcut("⌘1…⌘9", HelpContent.switchPanel)
            shortcut("⌘⇧P", HelpContent.liveCapture)
            shortcut("⌘⇧D", HelpContent.diagnostics)
            shortcut("⌘⇧M", HelpContent.survey)
            shortcut("⌘,", HelpContent.settings)
            shortcut("⌘?", HelpContent.help)
        }
    }

    private func shortcut(_ key: String, _ label: String) -> some View {
        HStack {
            Text(key)
                .font(.caption.monospaced().bold())
                .padding(.horizontal, DesignToken.Spacing.small)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: DesignToken.Radius.badge))
            Text(label).font(.caption)
        }
    }
}

struct HelpTopic: Identifiable {
    let id: String
    let title: String
    let summary: String
    let icon: String
    /// Caption shown under the topic's symbol banner.
    let screenshotCaption: String
    let sections: [HelpSection]
}

struct HelpSection: Identifiable {
    let id: String
    let heading: String
    let lines: [String]

    init(_ heading: String, _ lines: [String]) {
        self.id = heading
        self.heading = heading
        self.lines = lines
    }
}

private enum HelpContent {
    static let isRussian = Locale.current.language.languageCode?.identifier == "ru"
    static var searchPlaceholder: String { isRussian ? "Поиск по задачам" : "Search tasks" }
    static var sidebarTitle: String { isRussian ? "Что нужно сделать" : "What do you want to do?" }
    static var refresh: String { isRussian ? "Обновить скан" : "Refresh scan" }
    static var search: String { isRussian ? "Поиск сетей" : "Search networks" }
    static var switchPanel: String { isRussian ? "Переключить нижнюю панель" : "Switch bottom panel" }
    static var liveCapture: String { isRussian ? "Живой захват" : "Live capture" }
    static var diagnostics: String { isRussian ? "Диагностика" : "Diagnostics" }
    static var survey: String { isRussian ? "Site Survey" : "Site Survey" }
    static var settings: String { isRussian ? "Настройки" : "Settings" }
    static var help: String { isRussian ? "Открыть справку" : "Open help" }

    static var current: [HelpTopic] {
        isRussian ? russian : english
    }

    private static let english: [HelpTopic] = [
        HelpTopic(
            id: "first-scan",
            title: "Run your first scan",
            summary: "Grant access, pick a scan mode and read the network list.",
            icon: "sparkles",
            screenshotCaption:
                "The Wi-Fi Analyzer: table and inspector above, All Bands chart below.",
            sections: [
                HelpSection(
                    "1. Allow Wi-Fi names",
                    [
                        "Click Allow Access when macOS asks for Location. LanFi uses it only so macOS reveals SSIDs and BSSIDs; without it scans still run but names stay hidden.",
                        "Settings → Wi-Fi chooses the interface when the Mac has more than one radio. The toolbar shows which one is scanning.",
                        "Press ⌘R to scan immediately. The gear menu sets the interval, minimum signal and when inactive networks disappear.",
                    ]),
                HelpSection(
                    "2. Pick a scan mode",
                    [
                        "Active is the normal macOS scan: fast, but 6 GHz standard-power and non-PSC access points can be missing.",
                        "Passive listens in monitor mode on every supported channel. It needs one administrator authorization and finds beacon-only and non-PSC 6 GHz networks.",
                        "Directed listens only on the channels you choose. Use it to check one 6 GHz channel or to work around Apple N1 hardware that cannot hop channels reliably.",
                    ]),
                HelpSection(
                    "3. Read the results",
                    [
                        "The table lists every network; select a row to see radio, security, roaming and vendor details in the inspector. Click the marker on the All Bands chart to select a network there.",
                        "The ? button above the All Bands chart explains every mark in the chart.",
                        "Band chips, the signal threshold, grouping and search narrow the list. Display → Columns controls which table columns appear.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "connections",
            title: "See what this Mac is connecting to",
            summary: "List the TCP connections and listening sockets per process.",
            icon: "arrow.left.arrow.right",
            screenshotCaption:
                "Connections: per-process TCP endpoints, filterable by process, address or PID.",
            sections: [
                HelpSection(
                    "Open the list",
                    [
                        "Network Tools → Connections. Refresh re-reads the table; Include listening sockets adds servers waiting for clients.",
                        "The filter matches process name, address or PID. The counts at the top summarise connections, processes and listeners.",
                    ]),
                HelpSection(
                    "Read a row",
                    [
                        "Process and PID tell you who owns the socket. Local and Remote are the two endpoints, and State is the TCP state — ESTABLISHED is an open session, LISTEN waits for a client.",
                        "Sort by remote endpoint to spot unexpected destinations, or filter by one app to see everything it talks to.",
                    ]),
                HelpSection(
                    "Privacy",
                    [
                        "The list comes from a read-only lsof snapshot taken on this Mac. Nothing is uploaded or stored."
                    ]),
            ]
        ),
        HelpTopic(
            id: "diagnose",
            title: "Diagnose a slow or broken connection",
            summary: "Run the health checks, follow the path and drill into one hop.",
            icon: "stethoscope",
            screenshotCaption:
                "Internet Check: health verdict, the Mac → router → internet → DNS → web path and per-check details.",
            sections: [
                HelpSection(
                    "Run a check",
                    [
                        "Diagnostics → Internet Check. Quick checks link, gateway, DNS and web; Full adds latency and more probes.",
                        "Monitor every 60 s repeats the run and keeps the last 12 reports. Copy puts the visible report on the clipboard.",
                    ]),
                HelpSection(
                    "Read the path",
                    [
                        "The strip shows This Mac → Router → Internet → DNS → Web. A green segment works, amber is slow or partial, red failed.",
                        "Open Details for the numbers behind each step, including latency and packet loss. Orange recommendations say what to try next.",
                    ]),
                HelpSection(
                    "Go deeper",
                    [
                        "Ping and Traceroute/MTR test latency and the route hop by hop. DNS Lookup and DNS Propagation check resolution, Speed Test measures throughput, and SSL Certificate inspects the TLS chain.",
                        "Export Diagnostics Bundle from the report header when you want to share the state of the connection.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "coverage",
            title: "Measure Wi-Fi coverage",
            summary: "Record RSSI samples on a floor plan and turn them into a heatmap.",
            icon: "map",
            screenshotCaption:
                "Site Survey: floor-plan canvas, coverage summary, sample tools and the RSSI legend.",
            sections: [
                HelpSection(
                    "Record samples",
                    [
                        "Wi-Fi → Site Survey. Import a floor plan or start a blank metre grid, then choose the network you are measuring.",
                        "Click each spot you want to record. Draw Wall takes two clicks; walls attenuate samples whose path crosses them and stay with the project. + adds another floor.",
                        "Samples can also carry GPS coordinates, and a GPX track can be imported or exported from the Map tab.",
                    ]),
                HelpSection(
                    "Read the heatmap",
                    [
                        "Colour runs from red at −90 dBm to green at −40 dBm. Cool areas are strong; red or empty areas are where clients will struggle.",
                        "Survey planning estimates how many access points the space needs and where to put them, and tracks which planned spots are still unsampled.",
                        "Export PDF creates a report with the plan, heatmap, points and legend.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "process-traffic",
            title: "Find the app using your bandwidth",
            summary: "See per-process download and upload rates without leaving the Mac.",
            icon: "chart.bar.xaxis",
            screenshotCaption:
                "Process Traffic is opt-in: rates appear only after you enable the read-only sampler.",
            sections: [
                HelpSection(
                    "Turn it on",
                    [
                        "Network Tools → Process Traffic, then enable the toggle. LanFi runs Apple's read-only nettop twice a second apart and keeps only process names, PIDs and byte deltas in memory.",
                        "Switch it off and the rates disappear immediately.",
                    ]),
                HelpSection(
                    "Read the list",
                    [
                        "Rows show the process, its PID and the download and upload rate over the sample window. Sort by rate to find the top talker.",
                        "The menu-bar meter shows the same totals for the whole Mac; open it for a live sparkline and the connected link.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "settings",
            title: "Set up, update and automate",
            summary: "Preferences, updates, automation and what to do when a screen is empty.",
            icon: "gearshape",
            screenshotCaption:
                "Settings → General: appearance and density, startup, updates and menu-bar options.",
            sections: [
                HelpSection(
                    "Settings",
                    [
                        "Appearance controls theme, table density, high contrast and the colour-blind-safe palette. Startup sets the login item, scan on launch and the refresh interval.",
                        "Updates use Sparkle; Check Now and Release Notes live in the Updates card. Menu Bar picks the label, metric and throughput unit.",
                        "Settings → Wi-Fi chooses the radio, Diagnostics keeps the bundle options, and MCP controls the AI-agent snapshot.",
                    ]),
                HelpSection(
                    "Automation",
                    [
                        "MCP: the app publishes the live scan and lanfi-cli mcp serves it to Claude, Cursor or another MCP client over stdio. Settings → MCP copies a ready configuration.",
                        "CLI: lanfi-cli summary scan.json, protocols, pcap and mcp. Deep links: lanfi://tab/interfaces · lanfi://search?q=AX55 · lanfi://diagnostics/run.",
                    ]),
                HelpSection(
                    "If a screen is empty",
                    [
                        "Check Location Services for SSID/BSSID and the selected interface in Settings → Wi-Fi.",
                        "If monitor capture writes zero frames, the built-in adapter does not deliver them; use an external monitor-capable adapter.",
                        "This build is ad-hoc signed: on first launch use right-click → Open, or install with Homebrew. LanFi has no account, telemetry or cloud; scan data stays on this Mac.",
                    ]),
            ]
        ),
    ]

    private static let russian: [HelpTopic] = [
        HelpTopic(
            id: "first-scan",
            title: "Запустить первый скан",
            summary: "Выдать доступ, выбрать режим и прочитать список сетей.",
            icon: "sparkles",
            screenshotCaption:
                "Анализатор Wi-Fi: таблица и инспектор сверху, график All Bands снизу.",
            sections: [
                HelpSection(
                    "1. Разрешите имена Wi-Fi",
                    [
                        "Нажмите «Разрешить доступ», когда macOS спросит Location. LanFi использует его только для того, чтобы macOS раскрыла SSID и BSSID; без разрешения скан работает, но имена скрыты.",
                        "Settings → Wi-Fi выбирает интерфейс, если в Mac несколько радио. В toolbar видно, каким идёт скан.",
                        "⌘R запускает скан сразу. Шестерёнка задаёт интервал, минимальный сигнал и удаление неактивных сетей.",
                    ]),
                HelpSection(
                    "2. Выберите режим скана",
                    [
                        "Active — обычный скан macOS: быстрый, но 6 GHz standard-power и non-PSC точки могут отсутствовать.",
                        "Passive слушает в monitor mode на всех поддерживаемых каналах. Нужна одна авторизация администратора; находит beacon-only и non-PSC 6 GHz сети.",
                        "Directed слушает только выбранные каналы. Удобно проверить один канал 6 GHz или обойти ограничение Apple N1, который ненадёжно переключает каналы.",
                    ]),
                HelpSection(
                    "3. Прочитайте результат",
                    [
                        "Таблица перечисляет сети; выберите строку, чтобы увидеть radio, security, roaming и vendor в инспекторе. Клик по полосе на графике All Bands тоже выбирает сеть.",
                        "Кнопка ? над графиком All Bands объясняет каждое обозначение.",
                        "Чипы диапазонов, порог сигнала, группировка и поиск сужают список. Display → Columns управляет колонками.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "connections",
            title: "Узнать, куда подключается Mac",
            summary: "TCP-соединения и слушающие сокеты по процессам.",
            icon: "arrow.left.arrow.right",
            screenshotCaption:
                "Connections: TCP-эндпоинты по процессам с фильтром по имени, адресу или PID.",
            sections: [
                HelpSection(
                    "Откройте список",
                    [
                        "Network Tools → Connections. Refresh перечитывает таблицу; Include listening sockets добавляет серверы, ожидающие клиентов.",
                        "Фильтр ищет по имени процесса, адресу или PID. Счётчики сверху показывают соединения, процессы и слушателей.",
                    ]),
                HelpSection(
                    "Как читать строку",
                    [
                        "Process и PID — кто владеет сокетом. Local и Remote — два эндпоинта, State — состояние TCP: ESTABLISHED означает открытую сессию, LISTEN — ожидание клиента.",
                        "Сортируйте по удалённому адресу, чтобы заметить неожиданные направления, или отфильтруйте одно приложение.",
                    ]),
                HelpSection(
                    "Приватность",
                    [
                        "Список строится из read-only снимка lsof на этом Mac. Ничего не отправляется и не сохраняется."
                    ]),
            ]
        ),
        HelpTopic(
            id: "diagnose",
            title: "Найти причину медленного интернета",
            summary: "Проверки здоровья, путь до интернета и разбор одного участка.",
            icon: "stethoscope",
            screenshotCaption:
                "Internet Check: вердикт, путь Mac → роутер → интернет → DNS → web и детали проверок.",
            sections: [
                HelpSection(
                    "Запустите проверку",
                    [
                        "Diagnostics → Internet Check. Quick проверяет link, gateway, DNS и web; Full добавляет задержку и больше проб.",
                        "Monitor every 60 s повторяет прогон и хранит последние 12 отчётов. Copy копирует отчёт в буфер.",
                    ]),
                HelpSection(
                    "Прочитайте путь",
                    [
                        "Полоса показывает This Mac → Router → Internet → DNS → Web. Зелёный участок работает, оранжевый медленный или частичный, красный — ошибка.",
                        "В Details — цифры по каждому шагу, включая задержку и потери. Оранжевые рекомендации подсказывают следующий шаг.",
                    ]),
                HelpSection(
                    "Копните глубже",
                    [
                        "Ping и Traceroute/MTR проверяют задержку и маршрут по хопам. DNS Lookup и DNS Propagation — резолвинг, Speed Test — скорость, SSL Certificate — цепочку TLS.",
                        "Export Diagnostics Bundle в шапке отчёта сохраняет состояние соединения для передачи.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "coverage",
            title: "Измерить покрытие Wi-Fi",
            summary: "Записать RSSI на плане помещения и получить heatmap.",
            icon: "map",
            screenshotCaption:
                "Site Survey: план помещения, сводка покрытия, инструменты сэмплов и легенда RSSI.",
            sections: [
                HelpSection(
                    "Запишите сэмплы",
                    [
                        "Wi-Fi → Site Survey. Импортируйте план или начните с пустой метровой сетки, затем выберите измеряемую сеть.",
                        "Кликайте по точкам, где нужен замер. Draw Wall требует два клика; стены ослабляют сэмплы на пересечении и сохраняются в проекте. + добавляет этаж.",
                        "Сэмплы могут нести GPS-координаты, а GPX-трек импортируется и экспортируется на вкладке Map.",
                    ]),
                HelpSection(
                    "Прочитайте heatmap",
                    [
                        "Цвет от красного при −90 dBm до зелёного при −40 dBm. Холодные зоны сильные; красные и пустые — там клиентам будет тяжело.",
                        "Survey planning оценивает число точек доступа и их расстановку и отмечает, какие запланированные места ещё не замерены.",
                        "Export PDF создаёт отчёт с планом, heatmap, точками и легендой.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "process-traffic",
            title: "Найти приложение, съедающее трафик",
            summary: "Скорость скачивания и отдачи по процессам, без выхода в сеть.",
            icon: "chart.bar.xaxis",
            screenshotCaption:
                "Process Traffic включается вручную: цифры появляются после включения read-only сэмплера.",
            sections: [
                HelpSection(
                    "Включите",
                    [
                        "Network Tools → Process Traffic, затем включите тумблер. LanFi запускает read-only nettop дважды с интервалом в секунду и держит в памяти только имена, PID и дельты байт.",
                        "Выключите — цифры сразу исчезают.",
                    ]),
                HelpSection(
                    "Как читать",
                    [
                        "В строках — процесс, PID и скорость скачивания/отдачи за окно замера. Сортировка по скорости показывает главного потребителя.",
                        "Menu-bar meter показывает те же итоги по всему Mac; откройте его для sparkline и данных подключения.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "settings",
            title: "Настроить, обновить и автоматизировать",
            summary: "Настройки, обновления, автоматизация и что делать, если экран пуст.",
            icon: "gearshape",
            screenshotCaption:
                "Settings → General: внешний вид и плотность, запуск, обновления и меню-бар.",
            sections: [
                HelpSection(
                    "Настройки",
                    [
                        "Appearance управляет темой, плотностью таблиц, высокой контрастностью и colour-blind палитрой. Startup задаёт login item, скан при запуске и интервал.",
                        "Обновления идут через Sparkle; Check Now и Release Notes — в карточке Updates. Menu Bar задаёт подпись, метрику и единицы скорости.",
                        "Settings → Wi-Fi выбирает радио, Diagnostics хранит опции bundle, MCP управляет снимком для AI-агентов.",
                    ]),
                HelpSection(
                    "Автоматизация",
                    [
                        "MCP: приложение публикует живой скан, а lanfi-cli mcp отдаёт его Claude, Cursor или другому MCP-клиенту по stdio. Settings → MCP копирует готовый конфиг.",
                        "CLI: lanfi-cli summary scan.json, protocols, pcap и mcp. Deep links: lanfi://tab/interfaces · lanfi://search?q=AX55 · lanfi://diagnostics/run.",
                    ]),
                HelpSection(
                    "Если экран пуст",
                    [
                        "Проверьте Location Services для SSID/BSSID и выбранный интерфейс в Settings → Wi-Fi.",
                        "Если monitor capture пишет 0 кадров, встроенный адаптер их не отдаёт; нужен внешний адаптер с monitor mode.",
                        "Сборка ad-hoc signed: при первом запуске right-click → Open или установка через Homebrew. Аккаунта, телеметрии и облака нет; данные скана остаются на Mac.",
                    ]),
            ]
        ),
    ]
}
