import AppKit

/// Paints the signal and quality bars beside their numbers.
///
/// Only those two columns may use it; see the product rule on
/// `TableMicroVisual`. Drawing is a single `NSBezierPath` fill per cell, so
/// scrolling stays cheap.
final class TableMicroVisualView: NSView {
    private var shape: TableMicroVisual.Shape = .bar(fraction: 0)
    private var tint: MicroVisualTint = .warning

    override var isFlipped: Bool { true }

    func configure(visual: TableMicroVisual?) {
        guard let visual else {
            isHidden = true
            return
        }
        isHidden = false
        shape = visual.shape
        tint = visual.tint
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let color = Self.color(for: tint) else { return }
        switch shape {
        case .bar(let fraction):
            let trackRect = bounds
            guard trackRect.height > 1, trackRect.width > 1 else { return }
            NSBezierPath(
                roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2
            ).applyFill(color.withAlphaComponent(0.16))

            let width = max(0, min(1, fraction)) * trackRect.width
            guard width > 1.5 else { return }
            let fillRect = NSRect(
                x: trackRect.minX, y: trackRect.minY, width: width, height: trackRect.height)
            NSBezierPath(
                roundedRect: fillRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2
            ).applyFill(color.withAlphaComponent(0.7))
        }
    }

    static func color(for tint: MicroVisualTint) -> NSColor? {
        switch tint {
        case .ok: return .systemGreen
        case .warning: return .systemOrange
        case .danger: return .systemRed
        }
    }
}

extension NSBezierPath {
    fileprivate func applyFill(_ color: NSColor) {
        color.setFill()
        fill()
    }
}

enum TableCellStyle {
    case standard
    case secondary
}

final class WiFiTableCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("WiFiTextCell")

    private var edgeConstraint: NSLayoutConstraint?
    private var iconConstraint: NSLayoutConstraint?

    private let vendorIcon: NSImageView = {
        let view = NSImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.imageScaling = .scaleProportionallyDown
        view.isHidden = true
        return view
    }()

    private let textFieldLabel: NSTextField = {
        let tf = NSTextField()
        tf.isEditable = false
        tf.isSelectable = true
        tf.isBordered = false
        tf.drawsBackground = false
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let microVisualView: TableMicroVisualView = {
        let view = TableMicroVisualView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    /// Bar sits in its own gutter to the left of the number, never under it.
    private var barConstraints: [NSLayoutConstraint] = []
    private var textAfterBarConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        addSubview(vendorIcon)
        addSubview(microVisualView)
        addSubview(textFieldLabel)
        textField = textFieldLabel

        edgeConstraint = textFieldLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        iconConstraint = textFieldLabel.leadingAnchor.constraint(equalTo: vendorIcon.trailingAnchor, constant: 5)
        textAfterBarConstraint = textFieldLabel.leadingAnchor.constraint(
            equalTo: microVisualView.trailingAnchor, constant: 6)
        barConstraints = [
            microVisualView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            microVisualView.widthAnchor.constraint(equalToConstant: 34),
            microVisualView.heightAnchor.constraint(equalToConstant: 6),
            microVisualView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        // The bar keeps its own gutter at all times; only its leading text rule
        // is toggled. Leaving it unconstrained while hidden would make the cell
        // layout ambiguous.
        NSLayoutConstraint.activate(barConstraints)
        NSLayoutConstraint.activate([
            vendorIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            vendorIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            vendorIcon.widthAnchor.constraint(equalToConstant: 15),
            vendorIcon.heightAnchor.constraint(equalToConstant: 15),
            textFieldLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            edgeConstraint!,
            textFieldLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    func configure(
        text: String,
        isConnected: Bool,
        alignment: NSTextAlignment,
        highlightConnected: Bool,
        style: TableCellStyle = .standard,
        vendor: String? = nil,
        visual: TableMicroVisual? = nil,
        fontSize: CGFloat = NSFont.systemFontSize
    ) {
        if visual == nil, let symbol = VendorIconProvider.symbol(for: vendor) {
            vendorIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: vendor)
            vendorIcon.contentTintColor = .secondaryLabelColor
            vendorIcon.isHidden = false
        } else {
            vendorIcon.isHidden = true
        }
        textFieldLabel.stringValue = text
        textFieldLabel.toolTip = text
        textFieldLabel.setAccessibilityLabel(text)
        textFieldLabel.alignment = alignment

        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let baseColor = (style == .secondary) ? NSColor.secondaryLabelColor : NSColor.labelColor
        textFieldLabel.font = baseFont
        textFieldLabel.textColor = baseColor

        if highlightConnected && isConnected {
            textFieldLabel.font = NSFont.boldSystemFont(ofSize: fontSize)
            textFieldLabel.textColor = NSColor.systemBlue
        }

        apply(visual: visual)
    }

    /// Exactly one leading rule is active at a time so a reused cell never
    /// accumulates conflicting constraints.
    private func apply(visual: TableMicroVisual?) {
        microVisualView.configure(visual: visual)
        guard visual != nil else {
            textAfterBarConstraint?.isActive = false
            if vendorIcon.isHidden {
                iconConstraint?.isActive = false
                edgeConstraint?.isActive = true
            } else {
                edgeConstraint?.isActive = false
                iconConstraint?.isActive = true
            }
            return
        }
        edgeConstraint?.isActive = false
        iconConstraint?.isActive = false
        textAfterBarConstraint?.isActive = true
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

final class TintedRowView: NSTableRowView {
    var tint: NSColor?

    override func drawBackground(in dirtyRect: NSRect) {
        if let tint {
            let alpha: CGFloat =
                NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.26 : 0.20
            tint.withAlphaComponent(alpha).setFill()
            dirtyRect.fill()
        }
        super.drawBackground(in: dirtyRect)
    }
}
