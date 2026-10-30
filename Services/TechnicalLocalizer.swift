import Foundation

/// Localizes generated technical strings (details/values) while leaving SSIDs,
/// BSSIDs, vendor names and numeric measurements untouched.
enum TechnicalLocalizer {
    private static let replacements: [(String, String)] = [
        ("Not advertised", "Не заявлено"),
        ("Not exposed by CoreWLAN", "Не предоставляется CoreWLAN"),
        ("No active association", "Нет активного подключения"),
        ("Noise floor unavailable", "Уровень шума недоступен"),
        ("Location permission may be required to read RSSI", "Для RSSI может потребоваться доступ к геолокации"),
        ("Unknown", "Неизвестно"),
        ("Required", "Требуется"),
        ("Not required", "Не требуется"),
        ("Enabled", "Включено"),
        ("Disabled", "Выключено"),
        ("Supported", "Поддерживается"),
        ("Not supported", "Не поддерживается"),
        ("Secured", "Защищённая"),
        ("Hidden", "Скрытая"),
        ("Broadcast", "Широковещательная"),
        ("Infrastructure", "Инфраструктура"),
        ("Client", "Клиент"),
        ("Mesh", "Mesh"),
        ("DFS channel", "DFS-канал"),
        ("Noise", "Шум"),
        ("Signal", "Сигнал"),
        ("Channel", "Канал"),
        ("address(es)", "адрес(ов)"),
        ("overlapping APs", "перекрывающихся AP"),
        ("co-channel", "совмещённый канал"),
        ("Congestion", "Загруженность"),
        ("Clean", "Свободный"),
        ("Busy", "Занятый"),
        ("Excellent", "Отлично"),
        ("Good", "Хорошо"),
        ("Fair", "Средне"),
        ("Poor", "Плохо"),
        ("Recommended channel", "Рекомендуемый канал"),
        ("Not reported", "Не сообщается"),
        ("Reported", "Сообщается"),
        ("None decoded", "Не декодировано"),
        ("decoded", "декодировано"),
        ("bytes", "байт"),
        ("MHz", "МГц"),
        ("dBm", "дБм"),
        ("ms", "мс"),
        ("channel width", "ширина канала"),
        ("link set", "набор линков"),
        ("monitor capture", "monitor-захват"),
        ("MLO groups", "MLO-группы"),
        ("Offline packet analysis", "Офлайн-анализ пакетов"),
        ("offline capture analysis", "офлайн-анализ захвата"),
        ("Wi-Fi link", "Wi-Fi линк"),
        ("gateway", "шлюз"),
        ("latency", "задержка"),
        ("captive portal", "captive portal"),
        ("internet access", "доступ в интернет"),
        ("No diagnostics run", "Диагностика не запускалась"),
        ("All checks passed", "Все проверки пройдены"),
        ("failed", "ошибок"),
        ("warning", "предупреждений"),
        ("passed", "пройдено"),
    ]

    static func localize(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        var result = value
        for (english, russian) in replacements where result.contains(english) {
            result = result.replacingOccurrences(of: english, with: russian)
        }
        return result
    }
}
