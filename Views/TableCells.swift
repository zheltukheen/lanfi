import AppKit

enum TableCellStyle {
    case standard
    case secondary
}

final class WiFiTableCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("WiFiTextCell")

    private let textFieldLabel: NSTextField = {
        let tf = NSTextField()
        tf.isEditable = false
        tf.isBordered = false
        tf.drawsBackground = false
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        addSubview(textFieldLabel)
        textField = textFieldLabel

        NSLayoutConstraint.activate([
            textFieldLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textFieldLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            textFieldLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    func configure(
        text: String,
        isConnected: Bool,
        alignment: NSTextAlignment,
        highlightConnected: Bool,
        style: TableCellStyle = .standard
    ) {
        textFieldLabel.stringValue = text
        textFieldLabel.toolTip = text
        textFieldLabel.alignment = alignment

        let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let baseColor = (style == .secondary) ? NSColor.secondaryLabelColor : NSColor.labelColor
        textFieldLabel.font = baseFont
        textFieldLabel.textColor = baseColor

        if highlightConnected && isConnected {
            textFieldLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            textFieldLabel.textColor = NSColor.systemBlue
        }
    }
}

final class DisclosureTableCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("DisclosureCell")

    private let disclosureButton: NSButton = {
        let button = NSButton()
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .disclosure
        button.title = ""
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let textFieldLabel: NSTextField = {
        let tf = NSTextField()
        tf.isEditable = false
        tf.isBordered = false
        tf.drawsBackground = false
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private var onToggle: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        addSubview(disclosureButton)
        addSubview(textFieldLabel)
        textField = textFieldLabel

        disclosureButton.target = self
        disclosureButton.action = #selector(toggleDisclosure)

        NSLayoutConstraint.activate([
            disclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            disclosureButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            disclosureButton.widthAnchor.constraint(equalToConstant: 14),
            disclosureButton.heightAnchor.constraint(equalToConstant: 14),
            textFieldLabel.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 6),
            textFieldLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textFieldLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    func configure(title: String, isExpanded: Bool, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        textFieldLabel.stringValue = title
        textFieldLabel.toolTip = title
        disclosureButton.state = isExpanded ? .on : .off
    }

    @objc private func toggleDisclosure() {
        onToggle?()
    }
}

final class PaddedHeaderCell: NSTableHeaderCell {
    private let horizontalPadding: CGFloat = 10

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        var size = super.cellSize(forBounds: rect)
        size.width += horizontalPadding * 2
        return size
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let base = super.titleRect(forBounds: rect)
        return base.insetBy(dx: horizontalPadding, dy: 0)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
}

final class GroupTableCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("GroupCell")

    private let titleLabel: NSTextField = {
        let label = NSTextField()
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = NSColor.secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let countLabel: NSTextField = {
        let label = NSTextField()
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = NSColor.tertiaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(titleLabel)
        addSubview(countLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(group: NetworkGroup) {
        titleLabel.stringValue = "\(group.title.uppercased())   \(group.subtitle)"
        countLabel.stringValue = "\(group.networkCount)"
        toolTip = "\(group.title) — \(group.subtitle)"
    }
}
