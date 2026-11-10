import SwiftUI

// MARK: - Surfaces

struct ToolkitCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

struct ToolkitSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

// MARK: - Status

enum ToolkitTone {
    case neutral
    case good
    case warning
    case bad
    case running

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        case .running: return .accentColor
        }
    }
}

struct ToolkitStatusPill: View {
    let text: String
    let tone: ToolkitTone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tone.color.opacity(0.10), in: Capsule())
    }
}

struct ToolkitStateDot: View {
    let state: PortState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }

    private var color: Color {
        switch state {
        case .open: return .green
        case .closed: return .red
        case .filtered: return .orange
        }
    }
}

// MARK: - Metrics

struct ToolkitMetric: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty and error

struct ToolkitEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.4))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}

struct ToolkitErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Badges

struct ToolkitTypeBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            .foregroundColor(color)
    }
}

enum ToolkitTypeColor {
    static func color(for type: DNSRecordType) -> Color {
        switch type {
        case .a: return .blue
        case .aaaa: return .cyan
        case .cname: return .purple
        case .mx: return .pink
        case .txt: return .orange
        case .ns: return .green
        case .soa: return .red
        case .srv: return .indigo
        case .caa: return .brown
        case .ptr: return .teal
        }
    }
}

// MARK: - Formatting

enum ToolkitFormat {
    static func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms", value)
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "—" }
        return value.formatted(date: .abbreviated, time: .omitted)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        return formatter.string(fromByteCount: value)
    }
}
