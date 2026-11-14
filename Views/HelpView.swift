import SwiftUI

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
                .padding(7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(10)

                List(filtered, selection: $selection) { topic in
                    Label(topic.title, systemImage: topic.icon)
                        .tag(topic.id)
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Help")
        } detail: {
            if let selectedTopic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
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

                        ForEach(selectedTopic.sections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.heading).font(.headline)
                                ForEach(section.lines, id: \.self) { line in
                                    Text(line)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        if selectedTopic.id == "shortcuts" {
                            shortcuts
                        }

                        Divider()
                        HStack {
                            Link(
                                "Open README", destination: URL(string: "https://github.com/zheltukheen/lanfi#readme")!)
                            Link(
                                "Report an issue",
                                destination: URL(string: "https://github.com/zheltukheen/lanfi/issues")!)
                        }
                        .font(.caption)
                    }
                    .padding(22)
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
        .frame(minWidth: 760, minHeight: 560)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 5) {
            shortcut("⌘R", HelpContent.refresh)
            shortcut("⌘F", HelpContent.search)
            shortcut("⌘1…⌘7", HelpContent.switchPanel)
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
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(label).font(.caption)
        }
    }
}

struct HelpTopic: Identifiable {
    let id: String
    let title: String
    let summary: String
    let icon: String
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
    static var searchPlaceholder: String { isRussian ? "Поиск по справке" : "Search help" }
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
            id: "start", title: "Getting started", summary: "First scan, permissions and the main window.",
            icon: "sparkles",
            sections: [
                HelpSection(
                    "First launch",
                    [
                        "Allow Location Services so macOS can reveal SSIDs and BSSIDs. Without it, scanning still works but names and BSSID values may be hidden.",
                        "The main table shows nearby networks. Select a row to open Network Details; ⌘-click or ⇧-click selects several rows.",
                        "The bottom panel has Overview, Profile, Interfaces, Raw Data, Spectrum, History and Diagnostics.",
                    ]),
                HelpSection(
                    "What the score means",
                    [
                        "Quality combines signal, SNR, channel overlap, reported utilization and security posture.",
                        "Channel recommendations rank the quietest usable channel for each band, including DFS notes.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "scan", title: "Scanning & filters", summary: "Refresh, bands, search, sorting and grouping.",
            icon: "wifi",
            sections: [
                HelpSection(
                    "Scanning",
                    [
                        "⌘R refreshes immediately. The gear menu changes the scan interval, minimum signal and inactive-network expiry.",
                        "The 2.4/5/6 chips filter by band; the 7 chip filters Wi-Fi 7 (802.11be) networks.",
                    ]),
                HelpSection(
                    "Filters & sorting",
                    [
                        "Open the Filters sidebar from the toolbar or Display → Show Filters Sidebar.",
                        "Click a section title to expand it. Click several values to combine them; All clears that category. The sort popover controls sorting; the arrow button changes direction.",
                        "Grouping, signal units and column profiles live in Display.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "profile", title: "Profile & Interfaces",
            summary: "Per-network protocol blocks and all BSD interfaces.",
            icon: "square.stack.3d.up",
            sections: [
                HelpSection(
                    "Profile",
                    [
                        "Select one network to inspect seven blocks: Radio & PHY, Wi-Fi 7 & MLO, Security & trust, Spectrum & airtime, Roaming & mobility, Network format, Vendor & capabilities.",
                        "The block header states which network is selected. No row selected means the all-network overview.",
                    ]),
                HelpSection(
                    "Interfaces",
                    [
                        "Interfaces lists every BSD interface, including VPN tunnels, bridges, AWDL and loopback.",
                        "Inactive interfaces are collapsed. Active cards show addresses, MTU, speed, traffic and Wi-Fi association.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "toolkit", title: "Network Toolkit",
            summary: "The main window: grouped tools, search and live status.",
            icon: "square.grid.2x2",
            sections: [
                HelpSection(
                    "Finding a tool",
                    [
                        "The sidebar groups tools by Wi-Fi, Monitoring, Diagnostics, DNS & Domains and Network Tools. Type in Search tools to filter by name or description.",
                        "Unavailable tools stay visible with a Soon badge so the map of the toolkit stays honest.",
                    ]),
                HelpSection(
                    "Reading results",
                    [
                        "Every tool uses the same cards, metrics and status pills. Green means ready or healthy, orange needs attention, and a spinner means a probe is running.",
                        "Stop cancels a running probe without closing the screen. Copy exports the visible result to the clipboard.",
                    ]),
                HelpSection(
                    "Help",
                    [
                        "Press ⌘? or click the question mark in the toolbar to open this window. Settings → General has the same button."
                    ]),
            ]
        ),
        HelpTopic(
            id: "lan", title: "LAN Scanner & Device Shelf",
            summary: "What is on the network: names, models, services, ports and history.",
            icon: "desktopcomputer",
            sections: [
                HelpSection(
                    "What LanFi reads",
                    [
                        "ARP plus a fast ICMP sweep find addresses. Bonjour/mDNS TXT records, SSDP/UPnP descriptions and TCP banners supply the device's own name, manufacturer, model, firmware version, role and services. Reverse DNS adds host names.",
                        "This is why a device can be labelled even when you never typed its name: the device advertises the data itself.",
                    ]),
                HelpSection(
                    "Reading the inspector",
                    [
                        "Kind and Role answer what the device is. Manufacturer, Model and Version answer which one it is. IP, MAC, Network and Gateway answer where it is. Advertised services and open ports answer how it can be reached.",
                        "Detect versions reads banners from every open port and fills in the software running behind them.",
                    ]),
                HelpSection(
                    "Device Shelf",
                    [
                        "Every device is kept across scans with your alias, type, notes, availability, latency history and risk findings. New devices are flagged only when Guard this network is on.",
                        "Export CSV or JSON from the shelf menu. Names and notes survive rescans and DHCP changes.",
                    ]),
                HelpSection(
                    "If fields are empty",
                    [
                        "Most devices publish nothing. Allow Local Network access, scan again, and prefer a network where multicast (mDNS/SSDP) is not blocked by client isolation."
                    ]),
            ]
        ),
        HelpTopic(
            id: "monitor", title: "Network Monitor",
            summary: "How this Mac is connected: primary interface, addresses, router and routes.",
            icon: "waveform.path.ecg",
            sections: [
                HelpSection(
                    "Overview",
                    [
                        "The primary interface card shows the address, router, DNS, Wi-Fi and traffic that matter. Other active interfaces stay collapsed; open one to see MTU, speed, IPv6 and counters. Inactive interfaces are hidden under a disclosure."
                    ]),
                HelpSection(
                    "Routes",
                    [
                        "The Routes tab reads the IPv4 routing table. The default route for the primary interface is highlighted; Refresh re-reads netstat."
                    ]),
                HelpSection(
                    "Auto-refresh",
                    [
                        "Overview refreshes every eight seconds while Auto-refresh is on. Copy writes the full interface report to the clipboard."
                    ]),
            ]
        ),
        HelpTopic(
            id: "mcp", title: "MCP for AI agents",
            summary: "Connect Claude, Cursor or another MCP client to LanFi.",
            icon: "sparkles",
            sections: [
                HelpSection(
                    "How it works",
                    [
                        "The app publishes the live scan to ~/Library/Application Support/LanFi/mcp/latest-scan.json. The lanfi-cli mcp command serves that snapshot and the toolkit probes over stdio. No cloud, account or telemetry is involved."
                    ]),
                HelpSection(
                    "Setup",
                    [
                        "Build or install lanfi-cli, then add the command and args [\"mcp\"] to your client's MCP configuration. Settings → MCP copies a ready config and remembers the binary path."
                    ]),
                HelpSection(
                    "Tools",
                    [
                        "Agents can read scan summaries, analysis, protocols, channels, captures and spectrum traces; run ping, traceroute, MTR, port and path checks, DNS, WHOIS, GeoIP, TLS, subnet, interfaces, routes, LAN discovery, iperf3 and speed tests; and read the Device Shelf, uptime and diagnostics."
                    ]),
                HelpSection(
                    "Privacy",
                    [
                        "The server runs locally and reads files you already have. Turn off Publish the latest scan for MCP clients in Settings → MCP to stop writing the snapshot."
                    ]),
            ]
        ),
        HelpTopic(
            id: "charts", title: "Spectrum & History", summary: "RF charts and dynamic signal scaling.",
            icon: "waveform.path.ecg",
            sections: [
                HelpSection(
                    "Spectrum",
                    [
                        "Bars show occupied channel width; height is signal strength. Click a network to select it."
                    ]),
                HelpSection(
                    "History",
                    [
                        "History keeps the last three minutes of signal samples. Its Y axis auto-scales to the observed range; it no longer pins everything to the bottom."
                    ]),
            ]
        ),
        HelpTopic(
            id: "diagnostics", title: "Diagnostics", summary: "Health score, checks, monitoring and support bundles.",
            icon: "stethoscope",
            sections: [
                HelpSection(
                    "Reading the report",
                    [
                        "The health score summarises passed, warning and failed checks. Checks are grouped by link, network, DNS, internet, performance and security.",
                        "Recommendations appear in orange under a failing or warning check.",
                        "Monitoring reruns the checks every 60 seconds; the last 12 reports persist.",
                    ]),
                HelpSection(
                    "Support",
                    [
                        "Export Diagnostics Bundle from the report header or Settings → Diagnostics. It includes the report, history, interfaces, system version and local crash logs. No telemetry is sent."
                    ]),
            ]
        ),
        HelpTopic(
            id: "capture", title: "Live & offline capture",
            summary: "BPF captures, pcap/pcapng and monitor-mode limitations.",
            icon: "waveform.badge.magnifyingglass",
            sections: [
                HelpSection(
                    "Live capture",
                    [
                        "Tools → Live Capture. macOS asks for administrator authorization because BPF requires root.",
                        "Each capture has a unique file and a hard stop. Built-in Apple Wi-Fi adapters often expose monitor mode but deliver zero frames; use an external monitor-capable adapter for 802.11.",
                        "The synthetic PCAP export reconstructs beacons from visible networks and always works.",
                    ]),
                HelpSection(
                    "Offline analysis",
                    [
                        "Tools → Analyze Packet Capture reads pcap/pcapng with radiotap or bare 802.11. RAW IP and Ethernet captures are rejected because they contain no Wi-Fi beacons.",
                        "After a live capture, use Analyze capture to open the same file.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "survey", title: "Site Survey", summary: "Floor plans, samples, walls and PDF reports.",
            icon: "map",
            sections: [
                HelpSection(
                    "Recording",
                    [
                        "Import a floor plan, choose the network, then click to record RSSI. Each click is a sample.",
                        "Draw Wall requires two clicks. Walls attenuate samples whose path crosses them, and persist with the project.",
                        "Use + to create another floor project. Export PDF creates a report with the plan, heatmap, points and legend.",
                    ])
            ]
        ),
        HelpTopic(
            id: "remote", title: "Remote sensors", summary: "SSH scans from another Mac.",
            icon: "server.rack",
            sections: [
                HelpSection(
                    "Setup",
                    [
                        "Enable Remote Login on the sensor Mac and authorize your SSH key. Add the host, user, port and optional key in Tools → Remote Sensors.",
                        "Auto 60 s reruns the sensor scan. SSIDs may be redacted by the remote Mac's privacy settings.",
                    ])
            ]
        ),
        HelpTopic(
            id: "automation", title: "CLI & deep links", summary: "Automation and URL commands.",
            icon: "terminal",
            sections: [
                HelpSection(
                    "CLI",
                    [
                        "lanfi-cli summary scan.json [--json]",
                        "lanfi-cli protocols scan.json",
                        "lanfi-cli pcap capture.pcapng [--json]",
                        "lanfi-cli mcp   # MCP server for AI agents (see the MCP topic)",
                    ]),
                HelpSection(
                    "Deep links",
                    [
                        "lanfi://tab/interfaces · lanfi://tab/protocols · lanfi://search?q=AX55 · lanfi://diagnostics/run"
                    ]),
            ]
        ),
        HelpTopic(
            id: "shortcuts", title: "Keyboard shortcuts", summary: "Frequent commands.",
            icon: "keyboard",
            sections: [HelpSection("Keys", ["Use the shortcuts listed below."])]
        ),
        HelpTopic(
            id: "privacy", title: "Privacy & troubleshooting", summary: "Data storage, logs and ad-hoc builds.",
            icon: "lock.shield",
            sections: [
                HelpSection(
                    "Privacy",
                    [
                        "LanFi has no account, telemetry or cloud. Scan data stays in memory unless you save a session or survey.",
                        "Annotations, sessions, surveys, vendor overrides and crash logs live in ~/Library/Application Support/LanFi and ~/Library/Logs/LanFi.",
                    ]),
                HelpSection(
                    "Ad-hoc build",
                    [
                        "This build is ad-hoc signed because there is no Apple Developer account. On first launch, right-click LanFi.app → Open, or use Homebrew.",
                        "Settings → General contains the Homebrew command and release link.",
                    ]),
                HelpSection(
                    "If something is empty",
                    [
                        "Check Location Services for SSID/BSSID. Check the selected Wi-Fi interface in Settings → Wi-Fi.",
                        "If live monitor capture writes 0 frames, the built-in adapter does not support it; use an external adapter or synthetic PCAP.",
                    ]),
            ]
        ),
    ]

    private static let russian: [HelpTopic] = [
        HelpTopic(
            id: "start", title: "С чего начать", summary: "Первый скан, разрешения и главное окно.",
            icon: "sparkles",
            sections: [
                HelpSection(
                    "Первый запуск",
                    [
                        "Разрешите Location Services, чтобы macOS раскрыла SSID и BSSID. Без этого скан работает, но имена и BSSID могут быть скрыты.",
                        "Таблица показывает nearby-сети. Выберите строку для Network Details; ⌘-клик или ⇧-клик выделяет несколько.",
                        "Нижняя панель: Overview, Profile, Interfaces, Raw Data, Spectrum, History и Diagnostics.",
                    ]),
                HelpSection(
                    "Что означает оценка",
                    [
                        "Quality учитывает сигнал, SNR, перекрытие каналов, заявленную загрузку и security.",
                        "Рекомендации каналов ранжируют самый свободный канал для каждого диапазона с учётом DFS.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "scan", title: "Скан и фильтры", summary: "Обновление, диапазоны, поиск, сортировка и группировка.",
            icon: "wifi",
            sections: [
                HelpSection(
                    "Скан",
                    [
                        "⌘R обновляет сразу. Шестерёнка меняет интервал, минимальный сигнал и удаление неактивных сетей.",
                        "Чипы 2.4/5/6 фильтруют по диапазону; чип 7 — по Wi-Fi 7 (802.11be).",
                    ]),
                HelpSection(
                    "Фильтры и сортировка",
                    [
                        "Сайдбар Filters открывается из toolbar или Display → Show Filters Sidebar.",
                        "Клик по заголовку секции раскрывает её. Несколько значений в категории объединяются; All сбрасывает категорию. Поповер Sort by задаёт поле; стрелка — направление.",
                        "Группировка, единицы сигнала и профили колонок — в меню Display.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "profile", title: "Profile и интерфейсы", summary: "Блоки протоколов и все BSD-интерфейсы.",
            icon: "square.stack.3d.up",
            sections: [
                HelpSection(
                    "Profile",
                    [
                        "Выберите одну сеть, чтобы увидеть семь блоков: Radio & PHY, Wi-Fi 7 & MLO, Security & trust, Spectrum & airtime, Roaming & mobility, Network format, Vendor & capabilities.",
                        "В шапке указано, какая сеть выбрана. Без выбора показывается обзор всех сетей.",
                    ]),
                HelpSection(
                    "Interfaces",
                    [
                        "Interfaces перечисляет все BSD-интерфейсы, включая VPN, мосты, AWDL и loopback.",
                        "Неактивные интерфейсы свёрнуты. Активные карточки показывают адреса, MTU, скорость, трафик и Wi-Fi.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "toolkit", title: "Network Toolkit",
            summary: "Главное окно: сгруппированные инструменты, поиск и живой статус.",
            icon: "square.grid.2x2",
            sections: [
                HelpSection(
                    "Как найти инструмент",
                    [
                        "Сайдбар группирует инструменты по Wi-Fi, Monitoring, Diagnostics, DNS & Domains и Network Tools. Введите запрос в Search tools, чтобы фильтровать по названию или описанию.",
                        "Недоступные инструменты остаются видимыми с бейджем Soon, чтобы карта toolkit была честной.",
                    ]),
                HelpSection(
                    "Как читать результат",
                    [
                        "Все инструменты используют одинаковые карточки, метрики и статусы. Зелёный — готово или всё в порядке, оранжевый — требует внимания, спиннер — проба выполняется.",
                        "Stop отменяет запущенную пробу, не закрывая экран. Copy копирует видимый результат в буфер обмена.",
                    ]),
                HelpSection(
                    "Справка",
                    [
                        "Нажмите ⌘? или значок вопроса в toolbar, чтобы открыть это окно. Та же кнопка есть в Settings → General."
                    ]),
            ]
        ),
        HelpTopic(
            id: "lan", title: "LAN Scanner и Device Shelf",
            summary: "Что есть в сети: имена, модели, сервисы, порты и история.",
            icon: "desktopcomputer",
            sections: [
                HelpSection(
                    "Что читает LanFi",
                    [
                        "ARP и быстрый ICMP-свип находят адреса. Записи Bonjour/mDNS TXT, описания SSDP/UPnP и TCP-баннеры дают собственное имя устройства, производителя, модель, версию прошивки, роль и сервисы. Reverse DNS добавляет hostname.",
                        "Поэтому устройство подписывается, даже если вы никогда не вводили его имя: оно само сообщает эти данные в сеть.",
                    ]),
                HelpSection(
                    "Как читать инспектор",
                    [
                        "Kind и Role отвечают, что это за устройство. Manufacturer, Model и Version — какое именно. IP, MAC, Network и Gateway — где оно находится. Advertised services и открытые порты — как до него добраться.",
                        "Detect versions читает баннеры со всех открытых портов и показывает, какое ПО за ними работает.",
                    ]),
                HelpSection(
                    "Device Shelf",
                    [
                        "Каждое устройство сохраняется между сканами с вашим именем, типом, заметками, доступностью, историей задержек и рисками. Новые устройства отмечаются, только если включён Guard this network.",
                        "Export CSV или JSON — в меню полки. Имена и заметки переживают повторные сканы и смену адреса по DHCP.",
                    ]),
                HelpSection(
                    "Если поля пустые",
                    [
                        "Большинство устройств ничего о себе не публикуют. Разрешите Local Network access, повторите скан и используйте сеть, где multicast (mDNS/SSDP) не блокируется изоляцией клиентов."
                    ]),
            ]
        ),
        HelpTopic(
            id: "monitor", title: "Network Monitor",
            summary: "Как подключён этот Mac: основной интерфейс, адреса, роутер и маршруты.",
            icon: "waveform.path.ecg",
            sections: [
                HelpSection(
                    "Overview",
                    [
                        "Карточка основного интерфейса показывает главное: адрес, роутер, DNS, Wi-Fi и трафик. Остальные активные интерфейсы свёрнуты; раскройте нужный, чтобы увидеть MTU, скорость, IPv6 и счётчики. Неактивные интерфейсы спрятаны под disclosure."
                    ]),
                HelpSection(
                    "Routes",
                    [
                        "Вкладка Routes читает таблицу IPv4-маршрутов. Маршрут по умолчанию для основного интерфейса подсвечен; Refresh перечитывает netstat."
                    ]),
                HelpSection(
                    "Auto-refresh",
                    [
                        "Overview обновляется каждые восемь секунд, пока включён Auto-refresh. Copy копирует полный отчёт по интерфейсам в буфер обмена."
                    ]),
            ]
        ),
        HelpTopic(
            id: "mcp", title: "MCP для AI-агентов",
            summary: "Подключите Claude, Cursor или другой MCP-клиент к LanFi.",
            icon: "sparkles",
            sections: [
                HelpSection(
                    "Как это работает",
                    [
                        "Приложение публикует живой скан в ~/Library/Application Support/LanFi/mcp/latest-scan.json. Команда lanfi-cli mcp отдаёт этот снимок и пробы toolkit по stdio. Облака, аккаунта и телеметрии нет."
                    ]),
                HelpSection(
                    "Настройка",
                    [
                        "Соберите или установите lanfi-cli, затем добавьте command и args [\"mcp\"] в MCP-конфигурацию клиента. Settings → MCP копирует готовый конфиг и запоминает путь к бинарнику."
                    ]),
                HelpSection(
                    "Инструменты",
                    [
                        "Агенты читают сводку скана, анализ, протоколы, каналы, захваты и spectrum; запускают ping, traceroute, MTR, проверку портов и пути, DNS, WHOIS, GeoIP, TLS, subnet, interfaces, routes, LAN discovery, iperf3 и speed test; читают Device Shelf, uptime и diagnostics."
                    ]),
                HelpSection(
                    "Приватность",
                    [
                        "Сервер работает локально и читает файлы, которые уже есть на Mac. Отключите Publish the latest scan for MCP clients в Settings → MCP, чтобы перестать писать снимок."
                    ]),
            ]
        ),
        HelpTopic(
            id: "charts", title: "Spectrum и History", summary: "RF-графики и автомасштаб сигнала.",
            icon: "waveform.path.ecg",
            sections: [
                HelpSection(
                    "Spectrum",
                    [
                        "Ширина полосы показывает занятый канал, высота — уровень сигнала. Клик выбирает сеть."
                    ]),
                HelpSection(
                    "History",
                    [
                        "History хранит последние три минуты. Ось Y автоматически масштабируется под наблюдаемый диапазон, а не всегда -100…0."
                    ]),
            ]
        ),
        HelpTopic(
            id: "diagnostics", title: "Диагностика", summary: "Health score, проверки, мониторинг и support bundle.",
            icon: "stethoscope",
            sections: [
                HelpSection(
                    "Как читать отчёт",
                    [
                        "Health score суммирует passed/warning/failed. Проверки сгруппированы по link, network, DNS, internet, performance и security.",
                        "Рекомендации показываются оранжевым под проблемной проверкой.",
                        "Мониторинг повторяет проверки каждые 60 секунд; последние 12 отчётов сохраняются.",
                    ]),
                HelpSection(
                    "Поддержка",
                    [
                        "Export Diagnostics Bundle из шапки отчёта или Settings → Diagnostics. Внутри отчёт, история, интерфейсы, версия системы и локальные crash logs. Телеметрия не отправляется."
                    ]),
            ]
        ),
        HelpTopic(
            id: "capture", title: "Live и offline capture", summary: "BPF, pcap/pcapng и ограничения monitor mode.",
            icon: "waveform.badge.magnifyingglass",
            sections: [
                HelpSection(
                    "Live capture",
                    [
                        "Tools → Live Capture. macOS запросит администратора, потому что BPF требует root.",
                        "У каждого захвата уникальный файл и жёсткая остановка. Встроенные Apple Wi-Fi адаптеры часто заявляют monitor mode, но не отдают кадры; для 802.11 нужен внешний адаптер.",
                        "Synthetic PCAP export собирает beacon-кадры из видимых сетей и работает всегда.",
                    ]),
                HelpSection(
                    "Offline-анализ",
                    [
                        "Tools → Analyze Packet Capture читает pcap/pcapng с radiotap или bare 802.11. RAW IP и Ethernet отклоняются, потому что в них нет Wi-Fi beacon.",
                        "После live capture нажмите Analyze capture.",
                    ]),
            ]
        ),
        HelpTopic(
            id: "survey", title: "Site Survey", summary: "Планы, сэмплы, стены и PDF-отчёты.",
            icon: "map",
            sections: [
                HelpSection(
                    "Запись",
                    [
                        "Импортируйте план, выберите сеть и кликайте по плану для RSSI. Каждый клик — сэмпл.",
                        "Draw Wall требует два клика. Стены attenuate сэмплы на пересечении и сохраняются в проекте.",
                        "Кнопка + создаёт ещё один этаж. Export PDF формирует отчёт с планом, heatmap, точками и легендой.",
                    ])
            ]
        ),
        HelpTopic(
            id: "remote", title: "Remote sensors", summary: "SSH-скан с другого Mac.",
            icon: "server.rack",
            sections: [
                HelpSection(
                    "Настройка",
                    [
                        "Включите Remote Login на Mac-сенсоре и авторизуйте SSH-ключ. Добавьте host, user, port и ключ в Tools → Remote Sensors.",
                        "Auto 60 s перезапускает скан. Удалённый Mac может скрывать SSID из-за privacy settings.",
                    ])
            ]
        ),
        HelpTopic(
            id: "automation", title: "CLI и deep links", summary: "Автоматизация и URL-команды.",
            icon: "terminal",
            sections: [
                HelpSection(
                    "CLI",
                    [
                        "lanfi-cli summary scan.json [--json]",
                        "lanfi-cli protocols scan.json",
                        "lanfi-cli pcap capture.pcapng [--json]",
                        "lanfi-cli mcp   # MCP server for AI agents (see the MCP topic)",
                    ]),
                HelpSection(
                    "Deep links",
                    [
                        "lanfi://tab/interfaces · lanfi://tab/protocols · lanfi://search?q=AX55 · lanfi://diagnostics/run"
                    ]),
            ]
        ),
        HelpTopic(
            id: "shortcuts", title: "Горячие клавиши", summary: "Частые команды.",
            icon: "keyboard",
            sections: [HelpSection("Клавиши", ["Список ниже."])]
        ),
        HelpTopic(
            id: "privacy", title: "Приватность и проблемы", summary: "Данные, логи и ad-hoc сборка.",
            icon: "lock.shield",
            sections: [
                HelpSection(
                    "Приватность",
                    [
                        "Нет аккаунта, телеметрии и облака. Данные скана остаются в памяти, если не сохранить сессию или survey.",
                        "Аннотации, сессии, survey, vendor overrides и crash logs лежат в ~/Library/Application Support/LanFi и ~/Library/Logs/LanFi.",
                    ]),
                HelpSection(
                    "Ad-hoc сборка",
                    [
                        "Эта сборка ad-hoc signed, потому что нет Apple Developer аккаунта. При первом запуске right-click LanFi.app → Open или установите через Homebrew.",
                        "Settings → General содержит Homebrew-команду и ссылку на релизы.",
                    ]),
                HelpSection(
                    "Если пусто",
                    [
                        "Проверьте Location Services для SSID/BSSID и выбранный Wi-Fi интерфейс в Settings → Wi-Fi.",
                        "Если live monitor capture пишет 0 кадров, встроенный адаптер не поддерживает monitor mode; нужен внешний адаптер или synthetic PCAP.",
                    ]),
            ]
        ),
    ]
}
