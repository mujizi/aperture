import AppKit
import CFNetwork
import Darwin
import QuartzCore
import WebKit

private let apertureURL = URL(string: "http://127.0.0.1:4317/?surface=companion")!
private let reviewURL = URL(string: "http://127.0.0.1:4317/api/review/current")!
private let monitoringURL = URL(string: "http://127.0.0.1:4317/api/monitoring")!
private let focusURL = URL(string: "http://127.0.0.1:4317/api/focus")!
private let languageURL = URL(string: "http://127.0.0.1:4317/api/language")!
private let promptURL = URL(string: "http://127.0.0.1:4317/api/prompt")!
private let configURL = URL(string: "http://127.0.0.1:4317/api/config")!
private let configSecretURL = URL(string: "http://127.0.0.1:4317/api/config/secret")!
private let modelsURL = URL(string: "http://127.0.0.1:4317/api/models")!
private let modelTestURL = URL(string: "http://127.0.0.1:4317/api/config/test")!
private let inboxSeenURL = URL(string: "http://127.0.0.1:4317/api/inbox/seen")!
private let healthURL = URL(string: "http://127.0.0.1:4317/api/health")!
private let defaultExpandedSize = NSSize(width: 343, height: 726)
private let languageChangedNotification = Notification.Name(
    "ApertureLanguageChanged"
)

private enum AppLanguage: String, Codable {
    case cn
    case en

    var isEnglish: Bool { self == .en }

    func text(_ cn: String, _ en: String) -> String {
        isEnglish ? en : cn
    }
}

private struct ReviewEnvelope: Decodable {
    let review: ReviewSummary?
    let monitoring: MonitoringSummary?
    let focus: FocusSummary?
    let language: LanguageSummary?
    let prompt: PromptSummary?
    let inbox: InboxSummary?
}

private struct MonitoringSummary: Decodable {
    let enabled: Bool
}

private struct FocusSummary: Decodable {
    let level: Double
}

private struct LanguageSummary: Decodable {
    let value: AppLanguage
}

private struct LanguageUpdateEnvelope: Decodable {
    let language: LanguageSummary
    let prompt: PromptSummary
}

private struct PromptSummary: Decodable {
    let value: String
}

private struct InboxSummary: Decodable {
    let unreadCount: Int
}

private struct InboxEnvelope: Decodable {
    let inbox: InboxSummary
}

private struct ReviewSummary: Decodable {
    let id: String
    let projectName: String?
}

private struct ConfigEnvelope: Decodable {
    let openRouter: OpenRouterSummary
}

private struct OpenRouterSummary: Decodable {
    let enabled: Bool
    let provider: String?
    let model: String?
    let apiKeyConfigured: Bool?
}

private struct ConfigSecretEnvelope: Decodable {
    let provider: String
    let model: String?
    let apiKey: String
}

private struct ModelListEnvelope: Decodable {
    let models: [ModelOption]
}

private struct ModelOption: Decodable {
    let id: String
    let name: String
    let contextLength: Int
    let isFree: Bool
}

private struct ModelTestEnvelope: Decodable {
    let ok: Bool
    let model: String
    let latencyMs: Int
}

private struct APIErrorEnvelope: Decodable {
    let error: String
}

private struct HealthEnvelope: Decodable {
    let ok: Bool
    let service: String
    let capabilities: [String]?
}

private struct AttentionState {
    let reviewID: String?
    let unreadCount: Int
    let connected: Bool
}

private struct ProjectFilterOption {
    let key: String?
    let name: String
    let path: String?
    let unreadCount: Int
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectableWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

private final class DragHeaderView: NSView {
    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let mouseDownLocation,
            let windowOriginAtMouseDown
        else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: windowOriginAtMouseDown.x + current.x - mouseDownLocation.x,
            y: windowOriginAtMouseDown.y + current.y - mouseDownLocation.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
    }
}

private final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?

    init(symbol: String, label: String) {
        super.init(frame: .zero)
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        toolTip = label
        target = self
        action = #selector(invoke)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        actionHandler?()
    }
}

private final class ProjectPickerRowView: NSView {
    private let check = NSTextField(labelWithString: "✓")
    private let name = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let button = NSButton(frame: .zero)
    var actionHandler: (() -> Void)?

    init(option: ProjectFilterOption, selected: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            : NSColor.clear.cgColor

        check.translatesAutoresizingMaskIntoConstraints = false
        check.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        check.textColor = .controlAccentColor
        check.stringValue = selected ? "✓" : ""
        addSubview(check)

        name.translatesAutoresizingMaskIntoConstraints = false
        name.font = NSFont.systemFont(ofSize: 14, weight: selected ? .medium : .regular)
        name.lineBreakMode = .byTruncatingTail
        name.toolTip = option.path ?? option.name
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(name)
        name.stringValue = option.name

        count.translatesAutoresizingMaskIntoConstraints = false
        count.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        count.alignment = .right
        count.textColor = NSColor(
            calibratedRed: 0.28,
            green: 0.72,
            blue: 0.49,
            alpha: 1
        )
        count.stringValue = option.unreadCount == 0
            ? ""
            : String(option.unreadCount)
        count.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(count)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.target = self
        button.action = #selector(selectRow)
        button.toolTip = option.path ?? option.name
        addSubview(button)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 14),
            name.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 4),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 8),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func selectRow() {
        actionHandler?()
    }
}

private final class ProjectPickerEmptyView: NSView {
    init(language: AppLanguage) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: language.text(
            "没有匹配项目",
            "No matching projects"
        ))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabelColor
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 26),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ProjectPickerViewController: NSViewController, NSSearchFieldDelegate {
    private let language: AppLanguage
    private let options: [ProjectFilterOption]
    private let selectedKey: String?
    private let searchField = NSSearchField(frame: .zero)
    private let rows = NSStackView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let onSelect: (String?) -> Void
    private let onResize: (NSSize) -> Void
    private var documentHeightConstraint: NSLayoutConstraint?

    init(
        language: AppLanguage,
        options: [ProjectFilterOption],
        selectedKey: String?,
        onSelect: @escaping (String?) -> Void,
        onResize: @escaping (NSSize) -> Void
    ) {
        self.language = language
        self.options = options
        self.selectedKey = selectedKey
        self.onSelect = onSelect
        self.onResize = onResize
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.contentSize(rowCount: options.count)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: preferredContentSize))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        view = root

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = language.text("搜索项目…", "Search projects…")
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .regular
        searchField.delegate = self
        root.addSubview(searchField)

        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.distribution = .fill
        rows.spacing = 1

        let document = NSView(frame: .zero)
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)
        documentHeightConstraint = document.heightAnchor.constraint(
            equalToConstant: CGFloat(max(options.count, 1) * 33)
        )
        documentHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rows.topAnchor.constraint(equalTo: document.topAnchor),
            rows.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = document
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        rebuildRows(query: "")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    func controlTextDidChange(_ obj: Notification) {
        rebuildRows(query: searchField.stringValue)
    }

    private func rebuildRows(query: String) {
        rows.arrangedSubviews.forEach {
            rows.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        let filtered = options.filter { option in
            needle.isEmpty ||
                option.name.localizedLowercase.contains(needle) ||
                (option.path?.localizedLowercase.contains(needle) ?? false)
        }
        let visibleRowCount = max(filtered.count, 1)
        documentHeightConstraint?.constant = CGFloat(visibleRowCount * 33)
        let nextSize = Self.contentSize(rowCount: visibleRowCount)
        preferredContentSize = nextSize
        onResize(nextSize)
        if filtered.isEmpty {
            let empty = ProjectPickerEmptyView(language: language)
            rows.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            return
        }
        for option in filtered {
            let row = ProjectPickerRowView(
                option: option,
                selected: option.key == selectedKey
            )
            row.actionHandler = { [weak self] in
                self?.onSelect(option.key)
            }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    private static func contentSize(rowCount: Int) -> NSSize {
        let visibleRows = min(max(rowCount, 1), 8)
        return NSSize(
            width: 240,
            height: CGFloat(47 + visibleRows * 33)
        )
    }
}

private final class FocusSliderCell: NSSliderCell {
    var activeColor = NSColor.labelColor
    var inactiveColor = NSColor.separatorColor
    var knobColor = NSColor.controlBackgroundColor
    var knobBorderColor = NSColor.separatorColor

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let knobWidth = max(14, knobRect(flipped: flipped).width)
        let trackRect = NSRect(
            x: rect.minX + knobWidth / 2,
            y: rect.midY - 1.5,
            width: max(0, rect.width - knobWidth),
            height: 3
        )
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5)
        inactiveColor.setFill()
        track.fill()

        let range = maxValue - minValue
        let progress = range > 0 ? (doubleValue - minValue) / range : 0
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: trackRect.width * CGFloat(min(1, max(0, progress))),
            height: trackRect.height
        )
        guard fillRect.width > 0 else { return }
        activeColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let diameter: CGFloat = 14
        let circleRect = NSRect(
            x: knobRect.midX - diameter / 2,
            y: knobRect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let circle = NSBezierPath(ovalIn: circleRect)
        knobColor.setFill()
        circle.fill()

        knobBorderColor.setStroke()
        circle.lineWidth = 1
        circle.stroke()
    }
}

private final class FocusSlider: NSSlider {
    private let minimalCell = FocusSliderCell()
    private(set) var isUserInteracting = false

    var activeColor: NSColor {
        get { minimalCell.activeColor }
        set { minimalCell.activeColor = newValue; needsDisplay = true }
    }

    var inactiveColor: NSColor {
        get { minimalCell.inactiveColor }
        set { minimalCell.inactiveColor = newValue; needsDisplay = true }
    }

    var knobColor: NSColor {
        get { minimalCell.knobColor }
        set { minimalCell.knobColor = newValue; needsDisplay = true }
    }

    var knobBorderColor: NSColor {
        get { minimalCell.knobBorderColor }
        set { minimalCell.knobBorderColor = newValue; needsDisplay = true }
    }

    init(value: Double, minValue: Double, maxValue: Double) {
        super.init(frame: .zero)
        cell = minimalCell
        self.minValue = minValue
        self.maxValue = maxValue
        doubleValue = value
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        isUserInteracting = true
        super.mouseDown(with: event)
        isUserInteracting = false
    }
}

private final class ApertureMarkView: NSView {
    var actionHandler: (() -> Void)?
    var connected = true {
        didSet { needsDisplay = true }
    }
    var isDark = true {
        didSet { needsDisplay = true }
    }
    var focusLevel: CGFloat = 0.62 {
        didSet {
            focusLevel = min(1, max(0, focusLevel))
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 29, height: 29)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        actionHandler?()
    }

    override func accessibilityPerformPress() -> Bool {
        actionHandler?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Self.render(
            in: bounds,
            connected: connected,
            focusLevel: focusLevel,
            isDark: isDark
        )
    }

    fileprivate static func render(
        in bounds: NSRect,
        connected: Bool,
        focusLevel: CGFloat,
        isDark: Bool
    ) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let size = min(bounds.width, bounds.height)
        let lensRect = NSRect(
            x: bounds.midX - size / 2,
            y: bounds.midY - size / 2,
            width: size,
            height: size
        )
        let lens = NSBezierPath(ovalIn: lensRect)
        let lensColor = isDark
            ? NSColor(
                calibratedRed: 0.060,
                green: 0.086,
                blue: 0.091,
                alpha: 1
            )
            : NSColor(
                calibratedRed: 0.900,
                green: 0.890,
                blue: 0.850,
                alpha: 1
            )
        lensColor.setFill()
        lens.fill()
        lens.addClip()

        context.saveGState()
        context.setShouldAntialias(false)
        context.translateBy(x: bounds.midX, y: bounds.midY)
        let radius = size * 0.47
        let apertureOpenness = 1 - focusLevel
        let inner = 0.045 + apertureOpenness * 0.38
        let darkBlades = [
            NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.21, alpha: 1),
            NSColor(calibratedRed: 0.18, green: 0.27, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.23, green: 0.32, blue: 0.31, alpha: 1),
            NSColor(calibratedRed: 0.15, green: 0.22, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.25, green: 0.34, blue: 0.31, alpha: 1),
            NSColor(calibratedRed: 0.14, green: 0.19, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.29, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.26, alpha: 1)
        ]
        let lightBlades = [
            NSColor(calibratedRed: 0.63, green: 0.69, blue: 0.68, alpha: 1),
            NSColor(calibratedRed: 0.72, green: 0.76, blue: 0.73, alpha: 1),
            NSColor(calibratedRed: 0.58, green: 0.65, blue: 0.65, alpha: 1),
            NSColor(calibratedRed: 0.77, green: 0.78, blue: 0.73, alpha: 1),
            NSColor(calibratedRed: 0.66, green: 0.71, blue: 0.68, alpha: 1),
            NSColor(calibratedRed: 0.54, green: 0.61, blue: 0.62, alpha: 1),
            NSColor(calibratedRed: 0.71, green: 0.74, blue: 0.70, alpha: 1),
            NSColor(calibratedRed: 0.60, green: 0.66, blue: 0.65, alpha: 1)
        ]
        let bladeColors = isDark ? darkBlades : lightBlades
        for index in 0..<8 {
            let angle = CGFloat(index) * (.pi * 2 / 8)
            func point(_ fraction: CGFloat, _ offset: CGFloat) -> NSPoint {
                let value = angle + offset
                return NSPoint(
                    x: cos(value) * radius * fraction,
                    y: sin(value) * radius * fraction
                )
            }
            let blade = NSBezierPath()
            blade.move(to: point(inner, -0.14))
            blade.line(to: point(0.98, -0.72))
            blade.line(to: point(1.0, 0.13))
            blade.line(to: point(inner + 0.14, 0.78))
            blade.close()
            bladeColors[index]
                .withAlphaComponent(connected ? 1 : 0.55)
                .setFill()
            blade.fill()
        }

        NSColor(
            calibratedWhite: 1,
            alpha: connected ? 1 : 0.58
        ).setFill()
        let opening = radius * (0.055 + apertureOpenness * 0.39)
        NSBezierPath(
            ovalIn: NSRect(
                x: -opening,
                y: -opening,
                width: opening * 2,
                height: opening * 2
            )
        ).fill()
        context.restoreGState()
    }
}

private final class ApertureCatMarkView: NSView {
    private static let spriteSheet: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "ApertureCatSprite",
            withExtension: "png"
        ) else { return nil }
        let image = NSImage(contentsOf: url)
        image?.isTemplate = false
        return image
    }()
    private static let subjectRect = NSRect(
        x: 5,
        y: 396,
        width: 44,
        height: 42
    )

    var actionHandler: (() -> Void)?
    var connected = true {
        didSet { needsDisplay = true }
    }
    var isDark = true {
        didSet { needsDisplay = true }
    }
    var focusLevel: CGFloat = 0.62 {
        didSet {
            focusLevel = min(1, max(0, focusLevel))
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 29, height: 29)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        actionHandler?()
    }

    override func accessibilityPerformPress() -> Bool {
        actionHandler?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let spriteSheet = Self.spriteSheet else {
            ApertureMarkView.render(
                in: bounds,
                connected: connected,
                focusLevel: focusLevel,
                isDark: isDark
            )
            return
        }

        let available = bounds.insetBy(dx: 2, dy: 2)
        let scale = min(
            available.width / Self.subjectRect.width,
            available.height / Self.subjectRect.height
        )
        let targetSize = NSSize(
            width: Self.subjectRect.width * scale,
            height: Self.subjectRect.height * scale
        )
        let targetRect = NSRect(
            x: available.midX - targetSize.width / 2 - 0.5,
            y: available.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        let context = NSGraphicsContext.current
        let previousInterpolation = context?.imageInterpolation
        context?.imageInterpolation = .none
        spriteSheet.draw(
            in: targetRect,
            from: Self.subjectRect,
            operation: .sourceOver,
            fraction: connected ? 1 : 0.58,
            respectFlipped: true,
            hints: nil
        )
        if let previousInterpolation {
            context?.imageInterpolation = previousInterpolation
        }
    }
}

private final class SettingsViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "设置")
    private let languageLabel = NSTextField(labelWithString: "语言")
    private let languageControl = NSSegmentedControl(
        labels: ["中文", "English"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let focusLabel = NSTextField(labelWithString: "聚焦")
    private let focusSlider = FocusSlider(value: 0.62, minValue: 0, maxValue: 1)
    private let appearanceLabel = NSTextField(labelWithString: "外观")
    private let appearanceControl = NSSegmentedControl(
        labels: ["", ""],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let sizeLabel = NSTextField(labelWithString: "字号")
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let providerLabel = NSTextField(labelWithString: "Provider")
    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let keyLabel = NSTextField(labelWithString: "API Key")
    // Keep the API key obscured without presenting an NSSecureTextField to
    // Password AutoFill. macOS treats every NSSecureTextField as a login
    // password, even when its content type is unset, and shows "Passwords…".
    private let secureKeyField: NSTextField = {
        let field = NSTextField(frame: .zero)
        field.cell = NSSecureTextFieldCell(textCell: "")
        field.contentType = nil
        field.isAutomaticTextCompletionEnabled = false
        return field
    }()
    private let visibleKeyField = NSTextField(frame: .zero)
    private let keyVisibilityButton = ActionButton(
        symbol: "eye",
        label: "显示或隐藏 API Key"
    )
    private let modelLabel = NSTextField(labelWithString: "模型")
    private let modelCombo = NSComboBox(frame: .zero)
    private let refreshModelsButton = ActionButton(
        symbol: "arrow.clockwise",
        label: "拉取模型列表"
    )
    private let freeModelsButton = ActionButton(
        symbol: "gift",
        label: "只看免费模型"
    )
    private let testModelButton = ActionButton(
        symbol: "bolt.horizontal.circle",
        label: "测试模型"
    )
    private let saveModelButton = ActionButton(
        symbol: "checkmark",
        label: "保存模型配置"
    )
    private let modelStatus = NSTextField(labelWithString: "")
    private var sizeChoices: [(Int, String)] {
        language.isEnglish
            ? [(16, "16 · Compact"), (18, "18 · Comfortable"),
               (20, "20 · Large"), (22, "22 · Extra large"), (24, "24 · Largest")]
            : [(16, "16 · 紧凑"), (18, "18 · 舒适"),
               (20, "20 · 大"), (22, "22 · 特大"), (24, "24 · 最大")]
    }
    private var language: AppLanguage
    private var isDark: Bool
    private var readerSize: Int
    private var showsKey = false
    private var apiKeyConfigured = false
    private var allModels: [ModelOption] = []
    private var showsFreeModelsOnly = false
    private var isLoadingModels = false
    private var focusHandler: ((Double) -> Void)?
    private var themeHandler: ((Bool) -> Void)?
    private var sizeHandler: ((Int) -> Void)?
    private var languageHandler: ((AppLanguage) -> Void)?

    init(
        focusLevel: Double,
        isDark: Bool,
        readerSize: Int,
        language: AppLanguage,
        onFocusChanged: @escaping (Double) -> Void,
        onThemeChanged: @escaping (Bool) -> Void,
        onSizeChanged: @escaping (Int) -> Void,
        onLanguageChanged: @escaping (AppLanguage) -> Void
    ) {
        self.isDark = isDark
        self.readerSize = readerSize
        self.language = language
        super.init(nibName: nil, bundle: nil)
        focusSlider.doubleValue = min(1, max(0, focusLevel))
        focusHandler = onFocusChanged
        themeHandler = onThemeChanged
        sizeHandler = onSizeChanged
        languageHandler = onLanguageChanged
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 410))
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        view = root

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        root.addSubview(titleLabel)

        let labels = [
            languageLabel,
            focusLabel,
            appearanceLabel,
            sizeLabel,
            providerLabel,
            keyLabel,
            modelLabel
        ]
        for label in labels {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            root.addSubview(label)
        }

        languageControl.translatesAutoresizingMaskIntoConstraints = false
        languageControl.controlSize = .regular
        languageControl.segmentStyle = .rounded
        languageControl.selectedSegment = language == .en ? 1 : 0
        languageControl.target = self
        languageControl.action = #selector(changeLanguage)
        root.addSubview(languageControl)
        focusSlider.translatesAutoresizingMaskIntoConstraints = false
        focusSlider.controlSize = .regular
        focusSlider.isContinuous = true
        focusSlider.focusRingType = .none
        focusSlider.toolTip = "向左保留更多细节，向右只看核心信息"
        focusSlider.setAccessibilityLabel("聚焦度")
        focusSlider.target = self
        focusSlider.action = #selector(changeFocus)
        root.addSubview(focusSlider)

        appearanceControl.translatesAutoresizingMaskIntoConstraints = false
        appearanceControl.controlSize = .regular
        appearanceControl.segmentStyle = .rounded
        appearanceControl.setImage(
            NSImage(systemSymbolName: "sun.max", accessibilityDescription: "亮色"),
            forSegment: 0
        )
        appearanceControl.setImage(
            NSImage(systemSymbolName: "moon", accessibilityDescription: "暗色"),
            forSegment: 1
        )
        appearanceControl.setWidth(36, forSegment: 0)
        appearanceControl.setWidth(36, forSegment: 1)
        appearanceControl.target = self
        appearanceControl.action = #selector(changeAppearance)
        root.addSubview(appearanceControl)

        sizePopup.translatesAutoresizingMaskIntoConstraints = false
        sizePopup.controlSize = .regular
        sizePopup.font = NSFont.systemFont(ofSize: 13)
        sizePopup.addItems(withTitles: sizeChoices.map { $0.1 })
        if let index = sizeChoices.firstIndex(where: { $0.0 == readerSize }) {
            sizePopup.selectItem(at: index)
        }
        sizePopup.target = self
        sizePopup.action = #selector(changeSize)
        root.addSubview(sizePopup)

        providerPopup.translatesAutoresizingMaskIntoConstraints = false
        providerPopup.controlSize = .regular
        providerPopup.font = NSFont.systemFont(ofSize: 13)
        providerPopup.addItem(withTitle: "OpenRouter")
        root.addSubview(providerPopup)

        for field in [secureKeyField, visibleKeyField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.controlSize = .regular
            field.font = NSFont.systemFont(ofSize: 13)
            field.placeholderString = "填写 Key"
            root.addSubview(field)
        }
        visibleKeyField.isHidden = true

        keyVisibilityButton.translatesAutoresizingMaskIntoConstraints = false
        keyVisibilityButton.actionHandler = { [weak self] in
            self?.toggleKeyVisibility()
        }
        root.addSubview(keyVisibilityButton)

        modelCombo.translatesAutoresizingMaskIntoConstraints = false
        modelCombo.controlSize = .regular
        modelCombo.font = NSFont.systemFont(ofSize: 13)
        modelCombo.isEditable = true
        modelCombo.completes = true
        modelCombo.placeholderString = "选择或输入模型名称"
        root.addSubview(modelCombo)

        for button in [
            refreshModelsButton,
            freeModelsButton,
            testModelButton,
            saveModelButton
        ] {
            button.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(button)
        }
        refreshModelsButton.actionHandler = { [weak self] in self?.fetchModels() }
        freeModelsButton.actionHandler = { [weak self] in self?.toggleFreeModels() }
        testModelButton.actionHandler = { [weak self] in self?.testModel() }
        saveModelButton.actionHandler = { [weak self] in self?.saveModelConfig() }

        modelStatus.translatesAutoresizingMaskIntoConstraints = false
        modelStatus.font = NSFont.systemFont(ofSize: 12)
        modelStatus.lineBreakMode = .byWordWrapping
        modelStatus.maximumNumberOfLines = 2
        root.addSubview(modelStatus)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            languageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            languageLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            languageControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            languageControl.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),
            languageControl.widthAnchor.constraint(equalToConstant: 166),

            focusLabel.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 24),
            focusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            focusSlider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 94),
            focusSlider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            focusSlider.centerYAnchor.constraint(equalTo: focusLabel.centerYAnchor),

            appearanceLabel.topAnchor.constraint(equalTo: focusLabel.bottomAnchor, constant: 24),
            appearanceLabel.leadingAnchor.constraint(equalTo: focusLabel.leadingAnchor),
            appearanceControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            appearanceControl.centerYAnchor.constraint(equalTo: appearanceLabel.centerYAnchor),

            sizeLabel.topAnchor.constraint(equalTo: appearanceLabel.bottomAnchor, constant: 24),
            sizeLabel.leadingAnchor.constraint(equalTo: focusLabel.leadingAnchor),
            sizePopup.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            sizePopup.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            sizePopup.widthAnchor.constraint(equalToConstant: 166),

            providerLabel.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 32),
            providerLabel.leadingAnchor.constraint(equalTo: focusLabel.leadingAnchor),
            providerPopup.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 94),
            providerPopup.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            providerPopup.centerYAnchor.constraint(equalTo: providerLabel.centerYAnchor),

            keyLabel.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 26),
            keyLabel.leadingAnchor.constraint(equalTo: focusLabel.leadingAnchor),
            secureKeyField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 94),
            secureKeyField.trailingAnchor.constraint(equalTo: keyVisibilityButton.leadingAnchor, constant: -7),
            secureKeyField.centerYAnchor.constraint(equalTo: keyLabel.centerYAnchor),
            visibleKeyField.leadingAnchor.constraint(equalTo: secureKeyField.leadingAnchor),
            visibleKeyField.trailingAnchor.constraint(equalTo: secureKeyField.trailingAnchor),
            visibleKeyField.centerYAnchor.constraint(equalTo: secureKeyField.centerYAnchor),
            keyVisibilityButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            keyVisibilityButton.centerYAnchor.constraint(equalTo: keyLabel.centerYAnchor),
            keyVisibilityButton.widthAnchor.constraint(equalToConstant: 28),
            keyVisibilityButton.heightAnchor.constraint(equalToConstant: 28),

            modelLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 26),
            modelLabel.leadingAnchor.constraint(equalTo: focusLabel.leadingAnchor),
            modelCombo.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 94),
            modelCombo.trailingAnchor.constraint(equalTo: refreshModelsButton.leadingAnchor, constant: -7),
            modelCombo.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            refreshModelsButton.trailingAnchor.constraint(equalTo: freeModelsButton.leadingAnchor, constant: -2),
            freeModelsButton.trailingAnchor.constraint(equalTo: testModelButton.leadingAnchor, constant: -2),
            testModelButton.trailingAnchor.constraint(equalTo: saveModelButton.leadingAnchor, constant: -2),
            saveModelButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            refreshModelsButton.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            freeModelsButton.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            testModelButton.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            saveModelButton.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            refreshModelsButton.widthAnchor.constraint(equalToConstant: 28),
            freeModelsButton.widthAnchor.constraint(equalToConstant: 28),
            testModelButton.widthAnchor.constraint(equalToConstant: 28),
            saveModelButton.widthAnchor.constraint(equalToConstant: 28),
            refreshModelsButton.heightAnchor.constraint(equalToConstant: 28),
            freeModelsButton.heightAnchor.constraint(equalToConstant: 28),
            testModelButton.heightAnchor.constraint(equalToConstant: 28),
            saveModelButton.heightAnchor.constraint(equalToConstant: 28),

            modelStatus.topAnchor.constraint(equalTo: modelCombo.bottomAnchor, constant: 9),
            modelStatus.leadingAnchor.constraint(equalTo: modelCombo.leadingAnchor),
            modelStatus.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            modelStatus.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
        ])

        applyTheme()
        applyLanguage()
        loadModelConfig()
    }

    func setFocus(level: Double) {
        guard !focusSlider.isUserInteracting else { return }
        focusSlider.doubleValue = min(1, max(0, level))
    }

    func setTheme(isDark: Bool) {
        self.isDark = isDark
        applyTheme()
    }

    func setReaderSize(_ value: Int) {
        readerSize = value
        if let index = sizeChoices.firstIndex(where: { $0.0 == value }) {
            sizePopup.selectItem(at: index)
        }
    }

    func setLanguage(_ value: AppLanguage) {
        guard language != value else { return }
        language = value
        languageControl.selectedSegment = value == .en ? 1 : 0
        applyLanguage()
    }

    @objc private func changeFocus() {
        focusHandler?(focusSlider.doubleValue)
    }

    @objc private func changeLanguage() {
        language = languageControl.selectedSegment == 1 ? .en : .cn
        applyLanguage()
        languageHandler?(language)
    }

    @objc private func changeAppearance() {
        isDark = appearanceControl.selectedSegment == 1
        applyTheme()
        themeHandler?(isDark)
    }

    @objc private func changeSize() {
        let index = max(0, sizePopup.indexOfSelectedItem)
        readerSize = sizeChoices[index].0
        sizeHandler?(readerSize)
    }

    private func currentKey() -> String {
        (showsKey ? visibleKeyField.stringValue : secureKeyField.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleKeyVisibility() {
        let value = currentKey()
        showsKey.toggle()
        secureKeyField.stringValue = value
        visibleKeyField.stringValue = value
        secureKeyField.isHidden = showsKey
        visibleKeyField.isHidden = !showsKey
        keyVisibilityButton.image = NSImage(
            systemSymbolName: showsKey ? "eye.slash" : "eye",
            accessibilityDescription: "显示或隐藏 API Key"
        )
        view.window?.makeFirstResponder(
            showsKey ? visibleKeyField : secureKeyField
        )
    }

    private func requestBody() -> [String: String] {
        var body = [
            "provider": "openrouter",
            "model": modelCombo.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ]
        let key = currentKey()
        if !key.isEmpty { body["apiKey"] = key }
        return body
    }

    private func loadModelConfig() {
        var request = URLRequest(url: configSecretURL)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard
                let self,
                let data,
                let config = try? JSONDecoder().decode(
                    ConfigSecretEnvelope.self,
                    from: data
                )
            else { return }
            DispatchQueue.main.async {
                self.modelCombo.stringValue = config.model ?? ""
                self.secureKeyField.stringValue = config.apiKey
                self.visibleKeyField.stringValue = config.apiKey
                self.apiKeyConfigured = !config.apiKey.isEmpty
                self.updateKeyPlaceholder()
                self.fetchModels()
            }
        }.resume()
    }

    private func fetchModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        refreshModelsButton.isEnabled = false
        freeModelsButton.isEnabled = false
        setModelStatus(language.text("正在拉取模型…", "Loading models…"), success: nil)
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadRevalidatingCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard
                let data,
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode),
                let payload = try? JSONDecoder().decode(
                    ModelListEnvelope.self,
                    from: data
                )
            else {
                DispatchQueue.main.async { self.finishLoadingModels() }
                self.showAPIError(
                    data,
                    fallback: self.language.text("模型列表拉取失败", "Could not load models"),
                    error: error
                )
                return
            }
            DispatchQueue.main.async {
                self.finishLoadingModels()
                self.allModels = payload.models
                self.applyModelFilter()
            }
        }.resume()
    }

    private func finishLoadingModels() {
        isLoadingModels = false
        refreshModelsButton.isEnabled = true
        freeModelsButton.isEnabled = true
    }

    private func toggleFreeModels() {
        showsFreeModelsOnly.toggle()
        updateFreeModelsButton()
        if allModels.isEmpty {
            fetchModels()
            return
        }
        applyModelFilter()
    }

    private func applyModelFilter() {
        let selected = modelCombo.stringValue
        let models = showsFreeModelsOnly
            ? allModels.filter(\.isFree)
            : allModels
        modelCombo.removeAllItems()
        modelCombo.addItems(withObjectValues: models.map(\.id))
        modelCombo.stringValue = selected

        if showsFreeModelsOnly {
            setModelStatus(
                language.text(
                    "免费模型 \(models.count) 个 · 共 \(allModels.count) 个",
                    "\(models.count) free · \(allModels.count) total"
                ),
                success: true
            )
        } else {
            setModelStatus(
                language.text(
                    "已载入 \(allModels.count) 个模型",
                    "Loaded \(allModels.count) models"
                ),
                success: true
            )
        }
    }

    private func updateFreeModelsButton() {
        let label = showsFreeModelsOnly
            ? language.text("显示所有模型", "Show all models")
            : language.text("只看免费模型", "Show free models only")
        freeModelsButton.toolTip = label
        freeModelsButton.image = NSImage(
            systemSymbolName: showsFreeModelsOnly ? "gift.fill" : "gift",
            accessibilityDescription: label
        )
        freeModelsButton.setAccessibilityLabel(label)
        freeModelsButton.setAccessibilityValue(
            language.text(
                showsFreeModelsOnly ? "已开启" : "已关闭",
                showsFreeModelsOnly ? "On" : "Off"
            )
        )
        let accent = isDark
            ? NSColor(calibratedRed: 0.92, green: 0.70, blue: 0.29, alpha: 1)
            : NSColor(calibratedRed: 0.65, green: 0.43, blue: 0.04, alpha: 1)
        freeModelsButton.contentTintColor = showsFreeModelsOnly
            ? accent
            : (isDark
                ? NSColor(calibratedWhite: 0.72, alpha: 1)
                : NSColor(calibratedWhite: 0.36, alpha: 1))
        freeModelsButton.layer?.cornerRadius = 7
        freeModelsButton.layer?.backgroundColor = showsFreeModelsOnly
            ? accent.withAlphaComponent(0.12).cgColor
            : NSColor.clear.cgColor
    }

    private func testModel() {
        guard !modelCombo.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            setModelStatus(language.text("请先选择模型", "Select a model first"), success: false)
            return
        }
        setModelStatus(language.text("正在测试模型…", "Testing model…"), success: nil)
        postJSON(url: modelTestURL, body: requestBody()) { [weak self] data, response in
            guard let self else { return }
            guard
                let data,
                let response,
                (200..<300).contains(response.statusCode),
                let payload = try? JSONDecoder().decode(
                    ModelTestEnvelope.self,
                    from: data
                ),
                payload.ok
            else {
                self.showAPIError(
                    data,
                    fallback: self.language.text("模型测试失败", "Model test failed")
                )
                return
            }
            DispatchQueue.main.async {
                self.setModelStatus(
                    self.language.text(
                        "可用 · \(payload.latencyMs) ms",
                        "Available · \(payload.latencyMs) ms"
                    ),
                    success: true
                )
            }
        }
    }

    private func saveModelConfig() {
        guard !modelCombo.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            setModelStatus(language.text("请先选择模型", "Select a model first"), success: false)
            return
        }
        setModelStatus(language.text("正在保存…", "Saving…"), success: nil)
        postJSON(url: configURL, body: requestBody()) { [weak self] data, response in
            guard let self else { return }
            guard
                let response,
                (200..<300).contains(response.statusCode)
            else {
                self.showAPIError(
                    data,
                    fallback: self.language.text("模型配置保存失败", "Could not save model settings")
                )
                return
            }
            DispatchQueue.main.async {
                self.apiKeyConfigured =
                    self.apiKeyConfigured || !self.currentKey().isEmpty
                self.updateKeyPlaceholder()
                self.setModelStatus(
                    self.language.text("配置已保存", "Settings saved"),
                    success: true
                )
            }
        }
    }

    private func postJSON(
        url: URL,
        body: [String: String],
        completion: @escaping (Data?, HTTPURLResponse?) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            completion(data, response as? HTTPURLResponse)
        }.resume()
    }

    private func showAPIError(
        _ data: Data?,
        fallback: String,
        error: Error? = nil
    ) {
        let message = data.flatMap {
            try? JSONDecoder().decode(APIErrorEnvelope.self, from: $0).error
        } ?? error.map {
            language.text(
                "网络请求失败：\($0.localizedDescription)",
                "Network request failed: \($0.localizedDescription)"
            )
        } ?? fallback
        DispatchQueue.main.async {
            self.setModelStatus(message, success: false)
        }
    }

    private func updateKeyPlaceholder() {
        let placeholder = apiKeyConfigured
            ? language.text("已保存；输入可替换", "Saved; enter a value to replace")
            : language.text("填写 Key", "Enter key")
        secureKeyField.placeholderString = placeholder
        visibleKeyField.placeholderString = placeholder
    }

    private func setModelStatus(_ value: String, success: Bool?) {
        modelStatus.stringValue = value
        modelStatus.textColor = {
            guard let success else {
                return isDark
                    ? NSColor(calibratedWhite: 0.58, alpha: 1)
                    : NSColor(calibratedWhite: 0.43, alpha: 1)
            }
            return success
                ? NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.44, alpha: 1)
                : NSColor(calibratedRed: 0.84, green: 0.34, blue: 0.30, alpha: 1)
        }()
    }

    private func applyTheme() {
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        appearanceControl.selectedSegment = isDark ? 1 : 0
        let text = isDark
            ? NSColor(calibratedWhite: 0.90, alpha: 1)
            : NSColor(calibratedWhite: 0.18, alpha: 1)
        view.layer?.backgroundColor = (
            isDark
                ? NSColor(
                    calibratedRed: 0.075,
                    green: 0.088,
                    blue: 0.100,
                    alpha: 0.98
                )
                : NSColor(calibratedWhite: 0.985, alpha: 0.98)
        ).cgColor
        for label in [
            titleLabel,
            languageLabel,
            focusLabel,
            appearanceLabel,
            sizeLabel,
            providerLabel,
            keyLabel,
            modelLabel
        ] {
            label.textColor = text
        }
        focusSlider.activeColor = isDark
            ? NSColor(calibratedWhite: 0.84, alpha: 1)
            : NSColor(calibratedWhite: 0.24, alpha: 1)
        focusSlider.inactiveColor = isDark
            ? NSColor(calibratedWhite: 0.28, alpha: 0.72)
            : NSColor(calibratedWhite: 0.86, alpha: 1)
        focusSlider.knobColor = isDark
            ? NSColor(calibratedWhite: 0.88, alpha: 1)
            : NSColor.white
        focusSlider.knobBorderColor = isDark
            ? NSColor(calibratedWhite: 0.42, alpha: 1)
            : NSColor(calibratedWhite: 0.60, alpha: 1)
        let tint = isDark
            ? NSColor(calibratedWhite: 0.72, alpha: 1)
            : NSColor(calibratedWhite: 0.36, alpha: 1)
        for button in [
            keyVisibilityButton,
            refreshModelsButton,
            freeModelsButton,
            testModelButton,
            saveModelButton
        ] {
            button.contentTintColor = tint
        }
        updateFreeModelsButton()
        if !modelStatus.stringValue.isEmpty {
            setModelStatus(modelStatus.stringValue, success: nil)
        }
    }

    private func applyLanguage() {
        titleLabel.stringValue = language.text("设置", "Settings")
        languageLabel.stringValue = language.text("语言", "Language")
        focusLabel.stringValue = language.text("聚焦", "Focus")
        appearanceLabel.stringValue = language.text("外观", "Appearance")
        sizeLabel.stringValue = language.text("字号", "Text size")
        modelLabel.stringValue = language.text("模型", "Model")
        focusSlider.toolTip = language.text(
            "向左保留更多细节，向右只看核心信息",
            "Move left for more detail, right for only the essentials"
        )
        focusSlider.setAccessibilityLabel(language.text("聚焦度", "Focus level"))
        appearanceControl.setImage(
            NSImage(
                systemSymbolName: "sun.max",
                accessibilityDescription: language.text("亮色", "Light")
            ),
            forSegment: 0
        )
        appearanceControl.setImage(
            NSImage(
                systemSymbolName: "moon",
                accessibilityDescription: language.text("暗色", "Dark")
            ),
            forSegment: 1
        )
        let keyVisibilityLabel = language.text("显示或隐藏 API Key", "Show or hide API key")
        keyVisibilityButton.toolTip = keyVisibilityLabel
        keyVisibilityButton.image = NSImage(
            systemSymbolName: showsKey ? "eye.slash" : "eye",
            accessibilityDescription: keyVisibilityLabel
        )
        let refreshLabel = language.text("拉取模型列表", "Refresh model list")
        refreshModelsButton.toolTip = refreshLabel
        refreshModelsButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: refreshLabel
        )
        updateFreeModelsButton()
        let testLabel = language.text("测试模型", "Test model")
        testModelButton.toolTip = testLabel
        testModelButton.image = NSImage(
            systemSymbolName: "bolt.horizontal.circle",
            accessibilityDescription: testLabel
        )
        let saveModelLabel = language.text("保存模型配置", "Save model settings")
        saveModelButton.toolTip = saveModelLabel
        saveModelButton.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: saveModelLabel
        )
        modelCombo.placeholderString = language.text("选择或输入模型名称", "Select or enter a model")
        sizePopup.removeAllItems()
        sizePopup.addItems(withTitles: sizeChoices.map { $0.1 })
        if let index = sizeChoices.firstIndex(where: { $0.0 == readerSize }) {
            sizePopup.selectItem(at: index)
        }
        updateKeyPlaceholder()
        if allModels.isEmpty {
            modelStatus.stringValue = ""
        } else {
            applyModelFilter()
        }
    }
}

private struct ResizeEdges: OptionSet {
    let rawValue: Int

    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let top = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)
}

private final class ResizeHandleView: NSView {
    private let edges: ResizeEdges
    private var startMouse: NSPoint?
    private var startFrame: NSRect?

    init(edges: ResizeEdges) {
        self.edges = edges
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor())
    }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startFrame = window?.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let startMouse,
            let startFrame
        else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startMouse.x
        let dy = current.y - startMouse.y
        var frame = startFrame

        if edges.contains(.left) {
            frame.origin.x += dx
            frame.size.width -= dx
        }
        if edges.contains(.right) {
            frame.size.width += dx
        }
        if edges.contains(.bottom) {
            frame.origin.y += dy
            frame.size.height -= dy
        }
        if edges.contains(.top) {
            frame.size.height += dy
        }

        let minimum = window.minSize
        if frame.width < minimum.width {
            if edges.contains(.left) {
                frame.origin.x = startFrame.maxX - minimum.width
            }
            frame.size.width = minimum.width
        }
        if frame.height < minimum.height {
            if edges.contains(.bottom) {
                frame.origin.y = startFrame.maxY - minimum.height
            }
            frame.size.height = minimum.height
        }
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        startMouse = nil
        startFrame = nil
    }

    private func cursor() -> NSCursor {
        let horizontal =
            edges.contains(.left) || edges.contains(.right)
        let vertical =
            edges.contains(.top) || edges.contains(.bottom)
        if horizontal && vertical {
            let rising =
                (edges.contains(.left) && edges.contains(.top)) ||
                (edges.contains(.right) && edges.contains(.bottom))
            let symbol = rising
                ? "arrow.up.left.and.arrow.down.right"
                : "arrow.up.right.and.arrow.down.left"
            if let image = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: "调整窗口大小"
            ) {
                image.size = NSSize(width: 16, height: 16)
                return NSCursor(
                    image: image,
                    hotSpot: NSPoint(x: 8, y: 8)
                )
            }
        }
        return horizontal ? .resizeLeftRight : .resizeUpDown
    }
}

private final class ExpandedContainerView: NSVisualEffectView {
    private let mark = ApertureCatMarkView(frame: .zero)
    private let badge = NSTextField(labelWithString: "0")
    private let projectLabel = NSTextField(labelWithString: "")
    private let projectFilterButton = ActionButton(
        symbol: "chevron.down",
        label: "筛选项目"
    )
    private let header = DragHeaderView(frame: .zero)
    private let separator = NSView(frame: .zero)
    private let monitoringSwitch = NSSwitch(frame: .zero)
    private let settingsButton = ActionButton(
        symbol: "gearshape",
        label: "打开设置"
    )
    private var activeResizeEdges: ResizeEdges = []
    private var resizeStartMouse: NSPoint?
    private var resizeStartFrame: NSRect?
    private var monitoringHandler: ((Bool) -> Void)?
    private var focusHandler: ((Double) -> Void)?
    private var themeHandler: ((Bool) -> Void)?
    private var sizeHandler: ((Int) -> Void)?
    private var promptHandler: ((String) -> Void)?
    private var settingsToggleHandler: (() -> Void)?
    private var projectFilterHandler: ((NSView) -> Void)?
    private var currentFocus = 0.62
    private var currentIsDark: Bool
    private var currentReaderSize: Int
    private var currentPrompt = ""
    private var currentProjectFilterName: String?
    private var language: AppLanguage = .cn

    init(
        webView: WKWebView,
        isDark: Bool,
        readerSize: Int,
        onToggleMonitoring: @escaping (Bool) -> Void,
        onFocusChanged: @escaping (Double) -> Void,
        onThemeChanged: @escaping (Bool) -> Void,
        onSizeChanged: @escaping (Int) -> Void,
        onPromptChanged: @escaping (String) -> Void,
        onToggleSettings: @escaping () -> Void,
        onShowProjectFilter: @escaping (NSView) -> Void,
        onCollapse: @escaping () -> Void
    ) {
        currentIsDark = isDark
        currentReaderSize = readerSize
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        header.translatesAutoresizingMaskIntoConstraints = false
        header.wantsLayer = true

        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.actionHandler = onCollapse
        mark.toolTip = "收起为图标"
        mark.setAccessibilityElement(true)
        mark.setAccessibilityRole(.button)
        mark.setAccessibilityLabel("收起 Aperture")
        header.addSubview(mark)

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.alignment = .center
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        badge.isHidden = true
        badge.setAccessibilityLabel("未读结果")
        header.addSubview(badge)

        projectFilterHandler = onShowProjectFilter
        projectLabel.translatesAutoresizingMaskIntoConstraints = false
        projectLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        projectLabel.lineBreakMode = .byTruncatingTail
        projectLabel.maximumNumberOfLines = 1
        projectLabel.isHidden = true
        projectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        projectLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        projectLabel.setAccessibilityLabel("当前项目")
        header.addSubview(projectLabel)

        projectFilterButton.translatesAutoresizingMaskIntoConstraints = false
        projectFilterButton.actionHandler = { [weak self] in
            guard let self else { return }
            self.projectFilterHandler?(self.projectFilterButton)
        }
        projectFilterButton.setAccessibilityLabel("筛选项目")
        header.addSubview(projectFilterButton)

        monitoringHandler = onToggleMonitoring
        monitoringSwitch.translatesAutoresizingMaskIntoConstraints = false
        monitoringSwitch.controlSize = .mini
        monitoringSwitch.state = .on
        monitoringSwitch.toolTip = "监控所有 Codex 回答"
        monitoringSwitch.setAccessibilityLabel("监控 Codex 回答")
        monitoringSwitch.target = self
        monitoringSwitch.action = #selector(toggleMonitoring)
        header.addSubview(monitoringSwitch)

        focusHandler = onFocusChanged
        themeHandler = onThemeChanged
        sizeHandler = onSizeChanged
        promptHandler = onPromptChanged
        settingsToggleHandler = onToggleSettings
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.actionHandler = { [weak self] in
            self?.settingsToggleHandler?()
        }
        header.addSubview(settingsButton)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        header.addSubview(separator)

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(webView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 54),

            mark.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 15),
            mark.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 29),
            mark.heightAnchor.constraint(equalToConstant: 29),

            badge.topAnchor.constraint(equalTo: mark.topAnchor, constant: -4),
            badge.trailingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 6),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
            badge.heightAnchor.constraint(equalToConstant: 13),

            projectLabel.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10),
            projectLabel.centerYAnchor.constraint(equalTo: mark.centerYAnchor),

            projectFilterButton.leadingAnchor.constraint(equalTo: projectLabel.trailingAnchor, constant: 1),
            projectFilterButton.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            projectFilterButton.trailingAnchor.constraint(
                lessThanOrEqualTo: monitoringSwitch.leadingAnchor,
                constant: -12
            ),
            projectFilterButton.widthAnchor.constraint(equalToConstant: 22),
            projectFilterButton.heightAnchor.constraint(equalToConstant: 28),

            monitoringSwitch.trailingAnchor.constraint(
                equalTo: settingsButton.leadingAnchor,
                constant: -8
            ),
            monitoringSwitch.centerYAnchor.constraint(equalTo: mark.centerYAnchor),

            settingsButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            settingsButton.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 30),
            settingsButton.heightAnchor.constraint(equalToConstant: 30),

            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        update(state: AttentionState(
            reviewID: nil,
            unreadCount: 0,
            connected: false
        ))
        setTheme(isDark: isDark)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let edge: CGFloat = 14
        let corner: CGFloat = 22
        addCursorRect(
            NSRect(x: 0, y: corner, width: edge, height: bounds.height - corner * 2),
            cursor: .resizeLeftRight
        )
        addCursorRect(
            NSRect(x: bounds.width - edge, y: corner, width: edge, height: bounds.height - corner * 2),
            cursor: .resizeLeftRight
        )
        addCursorRect(
            NSRect(x: corner, y: bounds.height - edge, width: bounds.width - corner * 2, height: edge),
            cursor: .resizeUpDown
        )
        addCursorRect(
            NSRect(x: corner, y: 0, width: bounds.width - corner * 2, height: edge),
            cursor: .resizeUpDown
        )
        for (rect, edges) in [
            (NSRect(x: 0, y: bounds.height - corner, width: corner, height: corner), ResizeEdges([.top, .left])),
            (NSRect(x: bounds.width - corner, y: bounds.height - corner, width: corner, height: corner), ResizeEdges([.top, .right])),
            (NSRect(x: 0, y: 0, width: corner, height: corner), ResizeEdges([.bottom, .left])),
            (NSRect(x: bounds.width - corner, y: 0, width: corner, height: corner), ResizeEdges([.bottom, .right]))
        ] {
            addCursorRect(rect, cursor: resizeCursor(for: edges))
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let edges = resizeEdges(at: point)
        if !edges.isEmpty {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let edges = resizeEdges(at: point)
        guard !edges.isEmpty else {
            super.mouseDown(with: event)
            return
        }
        activeResizeEdges = edges
        resizeStartMouse = window?.convertPoint(
            toScreen: event.locationInWindow
        )
        resizeStartFrame = window?.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard !activeResizeEdges.isEmpty else {
            super.mouseDragged(with: event)
            return
        }
        guard let window else { return }
        applyResize(at: window.convertPoint(
            toScreen: event.locationInWindow
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if !activeResizeEdges.isEmpty {
            if let window {
                applyResize(at: window.convertPoint(
                    toScreen: event.locationInWindow
                ))
            }
        }
        activeResizeEdges = []
        resizeStartMouse = nil
        resizeStartFrame = nil
    }

    private func applyResize(at current: NSPoint) {
        guard
            let window,
            let resizeStartMouse,
            let resizeStartFrame
        else { return }
        let dx = current.x - resizeStartMouse.x
        let dy = current.y - resizeStartMouse.y
        var frame = resizeStartFrame

        if activeResizeEdges.contains(.left) {
            frame.origin.x += dx
            frame.size.width -= dx
        }
        if activeResizeEdges.contains(.right) {
            frame.size.width += dx
        }
        if activeResizeEdges.contains(.bottom) {
            frame.origin.y += dy
            frame.size.height -= dy
        }
        if activeResizeEdges.contains(.top) {
            frame.size.height += dy
        }

        let minimum = window.minSize
        if frame.width < minimum.width {
            if activeResizeEdges.contains(.left) {
                frame.origin.x = resizeStartFrame.maxX - minimum.width
            }
            frame.size.width = minimum.width
        }
        if frame.height < minimum.height {
            if activeResizeEdges.contains(.bottom) {
                frame.origin.y = resizeStartFrame.maxY - minimum.height
            }
            frame.size.height = minimum.height
        }
        window.setFrame(frame, display: true)
    }

    private func resizeEdges(at point: NSPoint) -> ResizeEdges {
        let edge: CGFloat = 14
        let corner: CGFloat = 22
        let nearLeft = point.x <= edge
        let nearRight = point.x >= bounds.maxX - edge
        let nearBottom = point.y <= edge
        let nearTop = point.y >= bounds.maxY - edge

        if point.x <= corner, point.y >= bounds.maxY - corner {
            return [.top, .left]
        }
        if point.x >= bounds.maxX - corner,
           point.y >= bounds.maxY - corner {
            return [.top, .right]
        }
        if point.x <= corner, point.y <= corner {
            return [.bottom, .left]
        }
        if point.x >= bounds.maxX - corner, point.y <= corner {
            return [.bottom, .right]
        }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        return []
    }

    private func resizeCursor(for edges: ResizeEdges) -> NSCursor {
        let rising =
            (edges.contains(.left) && edges.contains(.top)) ||
            (edges.contains(.right) && edges.contains(.bottom))
        let symbol = rising
            ? "arrow.up.left.and.arrow.down.right"
            : "arrow.up.right.and.arrow.down.left"
        guard let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "调整窗口大小"
        ) else {
            return .resizeLeftRight
        }
        image.size = NSSize(width: 16, height: 16)
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }

    func update(state: AttentionState) {
        mark.connected = state.connected
        badge.stringValue =
            state.unreadCount > 99 ? "99+" : String(state.unreadCount)
        badge.isHidden = state.unreadCount == 0
        badge.setAccessibilityValue(String(state.unreadCount))
        monitoringSwitch.isEnabled = state.connected
    }

    func setMonitoring(enabled: Bool, connected: Bool) {
        monitoringSwitch.state = enabled ? .on : .off
        monitoringSwitch.isEnabled = connected
    }

    func setFocus(level: Double) {
        currentFocus = min(1, max(0, level))
        mark.focusLevel = CGFloat(currentFocus)
    }

    func setPrompt(_ value: String) {
        currentPrompt = value
    }

    func setLanguage(_ value: AppLanguage) {
        language = value
        settingsButton.toolTip = value.text("打开设置", "Open settings")
        mark.toolTip = value.text("收起为图标", "Collapse to icon")
        mark.setAccessibilityLabel(value.text("收起 Aperture", "Collapse Aperture"))
        badge.setAccessibilityLabel(value.text("未读结果", "Unread results"))
        projectLabel.setAccessibilityLabel(value.text("当前项目", "Current project"))
        updateProjectFilterAppearance()
        monitoringSwitch.toolTip = value.text(
            "监控所有 Codex 回答",
            "Monitor all Codex responses"
        )
        monitoringSwitch.setAccessibilityLabel(value.text(
            "监控 Codex 回答",
            "Monitor Codex responses"
        ))
    }

    func setDisplayedProjectName(_ value: String?) {
        let name = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        projectLabel.stringValue = name
        projectLabel.toolTip = name.isEmpty ? nil : name
        projectLabel.isHidden = name.isEmpty
    }

    func setProjectFilterName(_ value: String?) {
        currentProjectFilterName = value
        updateProjectFilterAppearance()
    }

    private func updateProjectFilterAppearance() {
        let active = currentProjectFilterName != nil
        projectFilterButton.toolTip = currentProjectFilterName.map {
            language.text("筛选：\($0)", "Filter: \($0)")
        } ?? language.text("筛选：全部项目", "Filter: All projects")
        projectFilterButton.contentTintColor = active
            ? (currentIsDark
                ? NSColor(calibratedRed: 0.91, green: 0.70, blue: 0.30, alpha: 1)
                : NSColor(calibratedRed: 0.65, green: 0.43, blue: 0.04, alpha: 1))
            : (currentIsDark
                ? NSColor(calibratedWhite: 0.58, alpha: 1)
                : NSColor(calibratedWhite: 0.36, alpha: 1))
    }

    func setReaderSize(_ value: Int) {
        currentReaderSize = value
    }

    @objc private func toggleMonitoring() {
        monitoringHandler?(monitoringSwitch.state == .on)
    }

    func setTheme(isDark: Bool) {
        currentIsDark = isDark
        mark.isDark = isDark
        appearance = NSAppearance(
            named: isDark ? .darkAqua : .aqua
        )
        material = isDark ? .hudWindow : .contentBackground
        header.layer?.backgroundColor = (
            isDark
                ? NSColor(
                    calibratedRed: 0.045,
                    green: 0.055,
                    blue: 0.066,
                    alpha: 0.76
                )
                : NSColor(calibratedWhite: 0.985, alpha: 0.96)
        ).cgColor
        separator.layer?.backgroundColor = (
            isDark
                ? NSColor(calibratedWhite: 0.16, alpha: 1)
                : NSColor(calibratedWhite: 0.88, alpha: 1)
        ).cgColor
        let tint = isDark
            ? NSColor(calibratedWhite: 0.58, alpha: 1)
            : NSColor(calibratedWhite: 0.36, alpha: 1)
        projectLabel.textColor = isDark
            ? NSColor(calibratedWhite: 0.72, alpha: 1)
            : NSColor(calibratedWhite: 0.28, alpha: 1)
        badge.textColor = isDark
            ? NSColor(calibratedRed: 0.36, green: 0.88, blue: 0.62, alpha: 1)
            : NSColor(calibratedRed: 0.10, green: 0.58, blue: 0.34, alpha: 1)
        settingsButton.contentTintColor = tint
        updateProjectFilterAppearance()
    }
}

private final class BubbleView: NSView {
    private static let spriteFrameSize: CGFloat = 64
    private static let spriteColumns = 8
    private static let spriteRows = 7
    private static let spriteFrameCount = 56
    private static let animationFrameInterval: TimeInterval = 0.05
    // The 2.8-second sprite loop plus this rest produces a new observation
    // roughly every 6.5-8 seconds without feeling mechanically periodic.
    private static let idleRestDelayRange: ClosedRange<TimeInterval> = 3.7...5.2
    private static let spriteSheet: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "ApertureCatSprite",
            withExtension: "png"
        ) else { return nil }
        let image = NSImage(contentsOf: url)
        image?.isTemplate = false
        return image
    }()

    private let badge = NSButton(title: "0", target: nil, action: nil)
    private var bubbleConnected = false
    private var bubbleFocus: CGFloat = 0.62
    private var bubbleIsDark = true
    private var animationFrame = 0
    private var animationTimer: Timer?
    private var idleAnimationTimer: Timer?
    private var idleAnimationEnabled = false
    private var lastUnreadCount = 0
    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var didDrag = false
    private var language: AppLanguage = .cn
    private var projectFilterName: String?

    var onOpen: (() -> Void)?
    var onFilter: ((NSView) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
        layer?.borderWidth = 0
        layer?.backgroundColor = NSColor.clear.cgColor

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.alignment = .center
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        badge.isBordered = false
        badge.bezelStyle = .regularSquare
        badge.focusRingType = .none
        badge.contentTintColor = NSColor(
            calibratedRed: 0.28,
            green: 0.78,
            blue: 0.52,
            alpha: 1
        )
        badge.target = self
        badge.action = #selector(openProjectFilter)
        addSubview(badge)

        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
            badge.heightAnchor.constraint(equalToConstant: 13)
        ])

        toolTip = "Aperture · 点击展开，拖动可移动图标"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("展开 Aperture")
        setAccessibilityHelp("点击展开注意力侧边栏，拖动可移动猫咪图标")
        update(state: AttentionState(
            reviewID: nil,
            unreadCount: 0,
            connected: false
        ))
        setTheme(isDark: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
        idleAnimationTimer?.invalidate()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let spriteSheet = Self.spriteSheet {
            let column = animationFrame % Self.spriteColumns
            let row = animationFrame / Self.spriteColumns
            let sourceRect = NSRect(
                x: CGFloat(column) * Self.spriteFrameSize,
                y: CGFloat(Self.spriteRows - row - 1) * Self.spriteFrameSize,
                width: Self.spriteFrameSize,
                height: Self.spriteFrameSize
            )
            let context = NSGraphicsContext.current
            let previousInterpolation = context?.imageInterpolation
            context?.imageInterpolation = .none
            spriteSheet.draw(
                in: bounds,
                from: sourceRect,
                operation: .sourceOver,
                fraction: bubbleConnected ? 1 : 0.58,
                respectFlipped: true,
                hints: nil
            )
            if let previousInterpolation {
                context?.imageInterpolation = previousInterpolation
            }
            return
        }

        let diameter = max(0, min(bounds.width, bounds.height) - 14)
        ApertureMarkView.render(
            in: NSRect(
                x: (bounds.width - diameter) / 2,
                y: (bounds.height - diameter) / 2,
                width: diameter,
                height: diameter
            ),
            connected: bubbleConnected,
            focusLevel: bubbleFocus,
            isDark: bubbleIsDark
        )
    }

    func update(state: AttentionState, animateIncrease: Bool = true) {
        let shouldAnimate =
            animateIncrease && state.connected && state.unreadCount > lastUnreadCount
        lastUnreadCount = state.unreadCount
        bubbleConnected = state.connected
        needsDisplay = true
        badge.title =
            state.unreadCount > 99 ? "99+" : String(state.unreadCount)
        badge.isHidden = state.unreadCount == 0
        if !state.connected {
            stopFocusAnimation()
            cancelIdleAnimation()
        } else if shouldAnimate {
            playFocusAnimation()
        } else {
            scheduleIdleAnimationIfNeeded()
        }
    }

    func setIdleAnimationEnabled(_ enabled: Bool) {
        idleAnimationEnabled = enabled
        if enabled {
            scheduleIdleAnimationIfNeeded()
        } else {
            cancelIdleAnimation()
            stopFocusAnimation()
        }
    }

    func playFocusAnimation() {
        cancelIdleAnimation()
        guard
            window != nil,
            bubbleConnected,
            Self.spriteSheet != nil,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }
        stopFocusAnimation()
        animationFrame = 0
        needsDisplay = true
        let timer = Timer(
            timeInterval: Self.animationFrameInterval,
            repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.animationFrame += 1
            if self.animationFrame >= Self.spriteFrameCount {
                timer.invalidate()
                self.animationTimer = nil
                self.animationFrame = 0
                self.scheduleIdleAnimationIfNeeded()
            }
            self.needsDisplay = true
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleIdleAnimationIfNeeded() {
        guard
            idleAnimationEnabled,
            idleAnimationTimer == nil,
            animationTimer == nil,
            window != nil,
            bubbleConnected,
            Self.spriteSheet != nil,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }
        let delay = TimeInterval.random(in: Self.idleRestDelayRange)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.idleAnimationTimer = nil
            self.playFocusAnimation()
        }
        idleAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelIdleAnimation() {
        idleAnimationTimer?.invalidate()
        idleAnimationTimer = nil
    }

    private func stopFocusAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrame = 0
        needsDisplay = true
    }

    func setFocus(level: Double) {
        bubbleFocus = CGFloat(min(1, max(0, level)))
        needsDisplay = true
    }

    func setLanguage(_ value: AppLanguage) {
        language = value
        updateToolTip()
        setAccessibilityLabel(value.text("展开 Aperture", "Expand Aperture"))
        setAccessibilityHelp(value.text(
            "点击展开注意力侧边栏，拖动可移动猫咪图标",
            "Click to expand the attention sidebar; drag to move the cat icon"
        ))
    }

    func setTheme(isDark: Bool) {
        bubbleIsDark = isDark
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        badge.contentTintColor = isDark
            ? NSColor(calibratedRed: 0.36, green: 0.88, blue: 0.62, alpha: 1)
            : NSColor(calibratedRed: 0.10, green: 0.58, blue: 0.34, alpha: 1)
        needsDisplay = true
    }

    func setProjectFilterName(_ value: String?) {
        projectFilterName = value
        updateToolTip()
    }

    private func updateToolTip() {
        if let projectFilterName {
            toolTip = language.text(
                "\(projectFilterName) · 点击展开，点击数字筛选项目",
                "\(projectFilterName) · Click to expand; click the count to filter"
            )
            badge.toolTip = language.text(
                "\(projectFilterName) · 点击筛选项目",
                "\(projectFilterName) · Click to filter projects"
            )
        } else {
            toolTip = language.text(
                "Aperture · 点击展开，右键筛选项目",
                "Aperture · Click to expand; right-click to filter projects"
            )
            badge.toolTip = language.text(
                "点击筛选项目",
                "Click to filter projects"
            )
        }
    }

    @objc private func openProjectFilter() {
        onFilter?(badge)
    }

    override func mouseDown(with event: NSEvent) {
        cancelIdleAnimation()
        stopFocusAnimation()
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        didDrag = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelIdleAnimation()
            stopFocusAnimation()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDragged(with event: NSEvent) {
        guard
            let down = mouseDownLocation,
            let origin = windowOriginAtMouseDown,
            let window
        else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - down.x, y: current.y - down.y)
        if abs(delta.x) + abs(delta.y) > 3 {
            didDrag = true
        }
        window.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onOpen?()
        } else {
            scheduleIdleAnimationIfNeeded()
        }
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onFilter?(self)
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen?()
        return true
    }
}

private final class AttentionPanelController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    private let panel: FloatingPanel
    private let webView: WKWebView
    private let expandedView: ExpandedContainerView
    private let bubbleView: BubbleView
    private var isDark: Bool
    private var readerSize = 18
    private var monitoringEnabled = true
    private var focusLevel = 0.62
    private var language: AppLanguage = .cn
    private var customPrompt = ""
    private var focusWorkItem: DispatchWorkItem?
    private var focusRevision = 0
    private var pendingFocusRevision: Int?
    private var resizeSaveWorkItem: DispatchWorkItem?
    private var monitorTimer: Timer?
    private var isExpanded = true
    private var hasBaseline = false
    private var latestReviewID: String?
    private var displayedReviewID: String?
    private var acknowledgedReviewIDs = Set<String>()
    private var pendingSeenReviewIDs = Set<String>()
    private var seenReviewQueue: [String] = []
    private var isMarkingReviewSeen = false
    private var state = AttentionState(
        reviewID: nil,
        unreadCount: 0,
        connected: false
    )
    private var lastWebLoad = Date.distantPast
    private var expandedSize = defaultExpandedSize
    private var settingsPanel: FloatingPanel?
    private var settingsController: SettingsViewController?
    private var isPositioningSettings = false
    private var projectOptions: [ProjectFilterOption] = []
    private var selectedProjectKey: String?
    private var globalUnreadCount = 0
    private var projectPopover: NSPopover?

    override init() {
        let storedTheme = UserDefaults.standard.object(
            forKey: "apertureThemeDark"
        ) as? Bool
        let initialIsDark = storedTheme ?? true
        isDark = initialIsDark
        let storedReaderSize = UserDefaults.standard.integer(
            forKey: "apertureReaderSize"
        )
        let initialReaderSize =
            [16, 18, 20, 22, 24].contains(storedReaderSize)
                ? storedReaderSize
                : 18
        readerSize = initialReaderSize
        let storedProjectFilterKey = UserDefaults.standard.string(
            forKey: "apertureProjectFilterKey"
        )
        selectedProjectKey = storedProjectFilterKey
        let storedWidth = UserDefaults.standard.double(
            forKey: "apertureExpandedWidth"
        )
        let storedHeight = UserDefaults.standard.double(
            forKey: "apertureExpandedHeight"
        )
        if storedWidth >= 320, storedHeight >= 360 {
            expandedSize = NSSize(width: storedWidth, height: storedHeight)
        }

        let projectFilterLiteral: String = {
            guard
                let storedProjectFilterKey,
                let data = try? JSONEncoder().encode(storedProjectFilterKey)
            else { return "null" }
            return String(data: data, encoding: .utf8) ?? "null"
        }()
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: """
            document.documentElement.dataset.theme = '\(initialIsDark ? "dark" : "light")';
            document.documentElement.style.setProperty(
                '--reader-size',
                '\(initialReaderSize)px'
            );
            window.__APERTURE_PROJECT_FILTER__ = \(projectFilterLiteral);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()
        webView = SelectableWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")

        bubbleView = BubbleView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: defaultExpandedSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        var collapseHandler: (() -> Void)?
        var themeHandler: ((Bool) -> Void)?
        var sizeHandler: ((Int) -> Void)?
        var monitoringHandler: ((Bool) -> Void)?
        var focusHandler: ((Double) -> Void)?
        var promptHandler: ((String) -> Void)?
        var settingsHandler: (() -> Void)?
        var projectFilterHandler: ((NSView) -> Void)?
        expandedView = ExpandedContainerView(
            webView: webView,
            isDark: initialIsDark,
            readerSize: initialReaderSize,
            onToggleMonitoring: { enabled in monitoringHandler?(enabled) },
            onFocusChanged: { level in focusHandler?(level) },
            onThemeChanged: { isDark in themeHandler?(isDark) },
            onSizeChanged: { value in sizeHandler?(value) },
            onPromptChanged: { value in promptHandler?(value) },
            onToggleSettings: { settingsHandler?() },
            onShowProjectFilter: { anchor in projectFilterHandler?(anchor) },
            onCollapse: { collapseHandler?() }
        )
        super.init()

        collapseHandler = { [weak self] in self?.collapse() }
        themeHandler = { [weak self] isDark in self?.setTheme(isDark: isDark) }
        sizeHandler = { [weak self] value in self?.setReaderSize(value) }
        monitoringHandler = { [weak self] enabled in
            self?.updateMonitoring(enabled: enabled)
        }
        focusHandler = { [weak self] level in
            self?.updateFocus(level: level)
        }
        promptHandler = { [weak self] value in
            self?.updatePrompt(value)
        }
        settingsHandler = { [weak self] in self?.toggleSettings() }
        projectFilterHandler = { [weak self] anchor in
            self?.showProjectPicker(relativeTo: anchor)
        }
        contentController.add(self, name: "aperture")
        webView.navigationDelegate = self
        bubbleView.onOpen = { [weak self] in self?.expand() }
        bubbleView.onFilter = { [weak self] anchor in
            self?.showProjectPicker(relativeTo: anchor)
        }
        bubbleView.setTheme(isDark: initialIsDark)

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 320, height: 360)
        panel.delegate = self
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.animationBehavior = .utilityWindow
        panel.contentView = expandedView
        panel.setFrame(expandedFrame(), display: false)
        updateProjectScopeLabels()
    }

    deinit {
        projectPopover?.close()
        closeSettings()
        monitorTimer?.invalidate()
        focusWorkItem?.cancel()
        resizeSaveWorkItem?.cancel()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "aperture"
        )
    }

    func start() {
        panel.orderFrontRegardless()
        loadWebView(force: true)
        DaemonBootstrap.ensureRunning { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self?.loadWebView(force: true)
                self?.refresh()
            }
        }
        refresh()
        monitorTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(refresh),
            userInfo: nil,
            repeats: true
        )
        if let timer = monitorTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func toggle() {
        isExpanded ? collapse() : expand()
    }

    func show() {
        panel.orderFrontRegardless()
        settingsPanel?.orderFrontRegardless()
    }

    private func toggleSettings() {
        if settingsPanel != nil {
            closeSettings()
            return
        }

        let controller = SettingsViewController(
            focusLevel: focusLevel,
            isDark: isDark,
            readerSize: readerSize,
            language: language,
            onFocusChanged: { [weak self] level in
                self?.updateFocus(level: level)
            },
            onThemeChanged: { [weak self] isDark in
                self?.setTheme(isDark: isDark)
            },
            onSizeChanged: { [weak self] value in
                self?.setReaderSize(value)
            },
            onLanguageChanged: { [weak self] value in
                self?.updateLanguage(value)
            }
        )
        let settings = FloatingPanel(
            contentRect: settingsFrame(),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        settings.level = .floating
        settings.isOpaque = false
        settings.backgroundColor = .clear
        settings.hasShadow = true
        settings.hidesOnDeactivate = false
        settings.isReleasedWhenClosed = false
        settings.collectionBehavior = panel.collectionBehavior
        settings.animationBehavior = .utilityWindow
        settings.contentViewController = controller
        settings.alphaValue = 0
        settingsPanel = settings
        settingsController = controller
        panel.addChildWindow(settings, ordered: .above)
        positionSettingsPanel()
        settings.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            settings.animator().alphaValue = 1
        }
    }

    private func showProjectPicker(relativeTo anchor: NSView) {
        projectPopover?.close()
        let allProjects = ProjectFilterOption(
            key: nil,
            name: language.text("全部项目", "All projects"),
            path: nil,
            unreadCount: globalUnreadCount
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = ProjectPickerViewController(
            language: language,
            options: [allProjects] + projectOptions,
            selectedKey: selectedProjectKey,
            onSelect: { [weak self, weak popover] key in
                popover?.close()
                self?.selectProject(key)
            },
            onResize: { [weak popover] size in
                guard popover?.isShown == true else { return }
                popover?.contentSize = size
            }
        )
        projectPopover = popover
        let edge: NSRectEdge = isExpanded ? .minY : .maxX
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
    }

    private func selectProject(_ key: String?) {
        selectedProjectKey = key
        if let key {
            UserDefaults.standard.set(key, forKey: "apertureProjectFilterKey")
        } else {
            UserDefaults.standard.removeObject(forKey: "apertureProjectFilterKey")
        }
        updateProjectScopeUI(animateIncrease: false)
        let keyLiteral: String = {
            guard
                let key,
                let data = try? JSONEncoder().encode(key)
            else { return "null" }
            return String(data: data, encoding: .utf8) ?? "null"
        }()
        webView.evaluateJavaScript("""
        window.__APERTURE_PROJECT_FILTER__ = \(keyLiteral);
        window.dispatchEvent(new CustomEvent('apertureProjectFilter', {
          detail: { key: \(keyLiteral) }
        }));
        """)
    }

    private func selectedProjectName() -> String? {
        guard let selectedProjectKey else { return nil }
        if let option = projectOptions.first(where: {
            $0.key == selectedProjectKey
        }) {
            return option.name
        }
        let fallback = (selectedProjectKey as NSString).lastPathComponent
        return fallback.isEmpty ? selectedProjectKey : fallback
    }

    private func scopedUnreadCount() -> Int {
        guard let selectedProjectKey else { return globalUnreadCount }
        return projectOptions.first(where: {
            $0.key == selectedProjectKey
        })?.unreadCount ?? 0
    }

    private func updateProjectScopeUI(animateIncrease: Bool = true) {
        updateProjectScopeLabels()
        state = AttentionState(
            reviewID: state.reviewID,
            unreadCount: scopedUnreadCount(),
            connected: state.connected
        )
        expandedView.update(state: state)
        bubbleView.update(state: state, animateIncrease: animateIncrease)
    }

    private func updateProjectScopeLabels() {
        let projectName = selectedProjectName()
        expandedView.setProjectFilterName(projectName)
        bubbleView.setProjectFilterName(projectName)
    }

    private func closeSettings() {
        guard let settings = settingsPanel else { return }
        panel.removeChildWindow(settings)
        settings.orderOut(nil)
        settings.contentViewController = nil
        settingsPanel = nil
        settingsController = nil
    }

    private func settingsFrame() -> NSRect {
        let visible = currentScreen().visibleFrame
        let gap: CGFloat = 10
        let available = visible.width - panel.frame.width - gap - 48
        let preferredWidth = max(430, panel.frame.width)
        let width = min(preferredWidth, max(360, available))
        let height = panel.frame.height
        return NSRect(
            x: panel.frame.maxX + gap,
            y: panel.frame.minY,
            width: width,
            height: height
        )
    }

    private func positionSettingsPanel() {
        guard let settings = settingsPanel, !isPositioningSettings else { return }
        isPositioningSettings = true
        defer { isPositioningSettings = false }

        let visible = currentScreen().visibleFrame
        let gap: CGFloat = 10
        let targetFrame = settingsFrame()
        let targetSize = targetFrame.size
        let requiredWidth = panel.frame.width + gap + targetSize.width
        let maximumX = visible.maxX - 16
        if panel.frame.maxX + gap + targetSize.width > maximumX {
            let originX = max(visible.minX + 16, maximumX - requiredWidth)
            panel.setFrameOrigin(NSPoint(x: originX, y: panel.frame.minY))
        }
        settings.setFrame(
            NSRect(
                x: panel.frame.maxX + gap,
                y: panel.frame.minY,
                width: targetSize.width,
                height: targetSize.height
            ),
            display: true
        )
    }

    func reload() {
        loadWebView(force: true)
        refresh()
    }

    @objc private func refresh() {
        var request = URLRequest(url: reviewURL)
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let data,
               error == nil,
               let envelope = try? JSONDecoder().decode(ReviewEnvelope.self, from: data) {
                DispatchQueue.main.async {
                    let recovered = !self.state.connected
                    self.globalUnreadCount =
                        envelope.inbox?.unreadCount ?? self.globalUnreadCount
                    self.monitoringEnabled =
                        envelope.monitoring?.enabled ?? self.monitoringEnabled
                    if self.pendingFocusRevision == nil {
                        self.focusLevel =
                            envelope.focus?.level ?? self.focusLevel
                    }
                    let nextLanguage = envelope.language?.value ?? self.language
                    if nextLanguage != self.language {
                        self.language = nextLanguage
                        NotificationCenter.default.post(
                            name: languageChangedNotification,
                            object: nextLanguage
                        )
                        self.expandedView.setLanguage(nextLanguage)
                        self.bubbleView.setLanguage(nextLanguage)
                        self.settingsController?.setLanguage(nextLanguage)
                    }
                    self.customPrompt =
                        envelope.prompt?.value ?? self.customPrompt
                    self.expandedView.setMonitoring(
                        enabled: self.monitoringEnabled,
                        connected: true
                    )
                    self.expandedView.setFocus(level: self.focusLevel)
                    self.expandedView.setPrompt(self.customPrompt)
                    if self.displayedReviewID == nil ||
                       self.displayedReviewID == envelope.review?.id {
                        self.expandedView.setDisplayedProjectName(
                            envelope.review?.projectName
                        )
                    }
                    self.settingsController?.setFocus(level: self.focusLevel)
                    self.bubbleView.setFocus(level: self.focusLevel)
                    self.apply(AttentionState(
                        reviewID: self.selectedProjectKey == nil
                            ? envelope.review?.id
                            : self.state.reviewID,
                        unreadCount: self.scopedUnreadCount(),
                        connected: true
                    ))
                    self.updateProjectScopeLabels()
                    if recovered {
                        self.loadWebView(force: true)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.expandedView.setMonitoring(
                        enabled: self.monitoringEnabled,
                        connected: false
                    )
                    self.apply(AttentionState(
                        reviewID: self.state.reviewID,
                        unreadCount: self.state.unreadCount,
                        connected: false
                    ))
                }
            }
        }.resume()
    }

    private func apply(_ next: AttentionState) {
        let isNewReview = hasBaseline
            && next.reviewID != nil
            && next.reviewID != latestReviewID
        state = next
        expandedView.update(state: next)
        bubbleView.update(state: next)

        if let reviewID = next.reviewID {
            latestReviewID = reviewID
        }
        if !hasBaseline {
            hasBaseline = true
        } else if isNewReview {
            panel.orderFrontRegardless()
        }
    }

    private func currentScreen() -> NSScreen {
        if let screen = panel.screen { return screen }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard isExpanded else { return }
        expandedSize = panel.frame.size
        positionSettingsPanel()
        persistExpandedSize()
    }

    func windowDidResize(_ notification: Notification) {
        guard isExpanded else { return }
        expandedSize = panel.frame.size
        positionSettingsPanel()
        resizeSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistExpandedSize()
        }
        resizeSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func windowDidMove(_ notification: Notification) {
        guard isExpanded else { return }
        positionSettingsPanel()
    }

    private func persistExpandedSize() {
        UserDefaults.standard.set(
            Double(expandedSize.width),
            forKey: "apertureExpandedWidth"
        )
        UserDefaults.standard.set(
            Double(expandedSize.height),
            forKey: "apertureExpandedHeight"
        )
    }

    private func expandedFrame(anchoredAt topLeft: NSPoint? = nil) -> NSRect {
        let visible = currentScreen().visibleFrame
        let width: CGFloat = min(
            max(320, expandedSize.width),
            visible.width - 32
        )
        let height: CGFloat = min(
            max(360, expandedSize.height),
            visible.height - 34
        )
        let anchor = topLeft ?? NSPoint(
            x: panel.frame.minX,
            y: panel.frame.maxY
        )
        let x = min(
            max(anchor.x, visible.minX + 16),
            visible.maxX - width - 16
        )
        let topY = min(
            max(anchor.y, visible.minY + height + 17),
            visible.maxY - 17
        )
        return NSRect(x: x, y: topY - height, width: width, height: height)
    }

    private func bubbleFrame(anchoredAt topLeft: NSPoint? = nil) -> NSRect {
        let visible = currentScreen().visibleFrame
        let size: CGFloat = 64
        let anchor = topLeft ?? NSPoint(
            x: panel.frame.minX,
            y: panel.frame.maxY
        )
        let x = min(
            max(anchor.x, visible.minX + 16),
            visible.maxX - size - 16
        )
        let topY = min(
            max(anchor.y, visible.minY + size + 18),
            visible.maxY - 18
        )
        return NSRect(x: x, y: topY - size, width: size, height: size)
    }

    private func expand() {
        guard !isExpanded else {
            panel.orderFrontRegardless()
            return
        }
        bubbleView.setIdleAnimationEnabled(false)
        isExpanded = true
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let target = expandedFrame(anchoredAt: topLeft)
        panel.hasShadow = true
        panel.styleMask.remove(.nonactivatingPanel)
        panel.styleMask.insert(.resizable)
        panel.minSize = NSSize(width: 320, height: 360)
        expandedView.alphaValue = 0
        panel.contentView = expandedView
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
            expandedView.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
        loadWebView(force: false)
        markReviewSeen(displayedReviewID)
    }

    private func collapse() {
        guard isExpanded else { return }
        projectPopover?.close()
        closeSettings()
        expandedSize = panel.frame.size
        persistExpandedSize()
        isExpanded = false
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let target = bubbleFrame(anchoredAt: topLeft)
        panel.styleMask.remove(.resizable)
        panel.styleMask.insert(.nonactivatingPanel)
        panel.minSize = NSSize(width: 64, height: 64)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            expandedView.animator().alphaValue = 0
            panel.animator().setFrame(target, display: true)
        }, completionHandler: {
            self.panel.contentView = self.bubbleView
            self.panel.setFrame(target, display: true)
            self.panel.hasShadow = false
            self.bubbleView.frame = NSRect(
                origin: .zero,
                size: target.size
            )
            self.bubbleView.autoresizingMask = [.width, .height]
            self.expandedView.alphaValue = 1
            self.bubbleView.update(state: self.state)
            self.bubbleView.setIdleAnimationEnabled(true)
            self.bubbleView.playFocusAnimation()
        })
    }

    private func loadWebView(force: Bool) {
        if !force && webView.url != nil { return }
        if !force && Date().timeIntervalSince(lastWebLoad) < 2 { return }
        lastWebLoad = Date()
        webView.load(URLRequest(url: apertureURL))
    }

    private func setTheme(isDark: Bool) {
        guard self.isDark != isDark else { return }
        self.isDark = isDark
        UserDefaults.standard.set(isDark, forKey: "apertureThemeDark")
        expandedView.setTheme(isDark: isDark)
        settingsController?.setTheme(isDark: isDark)
        bubbleView.setTheme(isDark: isDark)
        webView.evaluateJavaScript(
            "document.documentElement.dataset.theme = '\(isDark ? "dark" : "light")';"
        )
    }

    private func setReaderSize(_ value: Int) {
        guard [16, 18, 20, 22, 24].contains(value) else { return }
        readerSize = value
        UserDefaults.standard.set(value, forKey: "apertureReaderSize")
        expandedView.setReaderSize(value)
        settingsController?.setReaderSize(value)
        webView.evaluateJavaScript(
            "document.documentElement.style.setProperty('--reader-size', '\(value)px');"
        )
    }

    private func updateMonitoring(enabled: Bool) {
        monitoringEnabled = enabled
        expandedView.setMonitoring(enabled: enabled, connected: state.connected)
        var request = URLRequest(url: monitoringURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 2.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["enabled": enabled]
        )
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                DispatchQueue.main.async { self.refresh() }
            }
        }.resume()
    }

    private func markReviewSeen(_ reviewID: String?) {
        guard
            let reviewID,
            !acknowledgedReviewIDs.contains(reviewID),
            !pendingSeenReviewIDs.contains(reviewID)
        else { return }
        pendingSeenReviewIDs.insert(reviewID)
        seenReviewQueue.append(reviewID)
        processNextSeenReview()
    }

    private func processNextSeenReview() {
        guard !isMarkingReviewSeen, !seenReviewQueue.isEmpty else { return }
        isMarkingReviewSeen = true
        let reviewID = seenReviewQueue.removeFirst()
        var request = URLRequest(url: inboxSeenURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 2.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["reviewId": reviewID]
        )
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let envelope = data.flatMap {
                try? JSONDecoder().decode(InboxEnvelope.self, from: $0)
            }
            DispatchQueue.main.async {
                self.pendingSeenReviewIDs.remove(reviewID)
                self.isMarkingReviewSeen = false
                if (response as? HTTPURLResponse)?.statusCode == 200,
                   let envelope {
                    self.acknowledgedReviewIDs.insert(reviewID)
                    self.globalUnreadCount = envelope.inbox.unreadCount
                    self.state = AttentionState(
                        reviewID: self.state.reviewID,
                        unreadCount: self.scopedUnreadCount(),
                        connected: self.state.connected
                    )
                    self.expandedView.update(state: self.state)
                    self.bubbleView.update(state: self.state)
                } else {
                    self.refresh()
                }
                self.processNextSeenReview()
            }
        }.resume()
    }

    private func updateLanguage(_ value: AppLanguage) {
        language = value
        NotificationCenter.default.post(
            name: languageChangedNotification,
            object: value
        )
        expandedView.setLanguage(value)
        bubbleView.setLanguage(value)
        updateProjectScopeLabels()
        settingsController?.setLanguage(value)
        var request = URLRequest(url: languageURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["value": value.rawValue]
        )
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            guard
                let data,
                (response as? HTTPURLResponse)?.statusCode == 200,
                let envelope = try? JSONDecoder().decode(
                    LanguageUpdateEnvelope.self,
                    from: data
                )
            else {
                DispatchQueue.main.async { self.refresh() }
                return
            }
            DispatchQueue.main.async {
                self.language = envelope.language.value
                self.customPrompt = envelope.prompt.value
                self.expandedView.setLanguage(self.language)
                self.expandedView.setPrompt(self.customPrompt)
                self.bubbleView.setLanguage(self.language)
                self.settingsController?.setLanguage(self.language)
            }
        }.resume()
    }

    private func updatePrompt(_ value: String) {
        customPrompt = String(value.prefix(4000))
        expandedView.setPrompt(customPrompt)
        var request = URLRequest(url: promptURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["value": customPrompt]
        )
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                DispatchQueue.main.async { self.refresh() }
            }
        }.resume()
    }

    private func updateFocus(level: Double) {
        focusLevel = min(1, max(0, level))
        focusRevision += 1
        let revision = focusRevision
        pendingFocusRevision = revision
        expandedView.setFocus(level: focusLevel)
        settingsController?.setFocus(level: focusLevel)
        bubbleView.setFocus(level: focusLevel)
        focusWorkItem?.cancel()
        let value = focusLevel
        let work = DispatchWorkItem { [weak self] in
            self?.persistFocus(level: value, revision: revision)
        }
        focusWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func persistFocus(level: Double, revision: Int) {
        var request = URLRequest(url: focusURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["level": level]
        )
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.pendingFocusRevision == revision else { return }
                self.pendingFocusRevision = nil
                self.focusWorkItem = nil
                if (response as? HTTPURLResponse)?.statusCode != 200 {
                    self.refresh()
                }
            }
        }.resume()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            message.name == "aperture",
            let body = message.body as? [String: Any],
            let type = body["type"] as? String
        else { return }
        if type == "phase" {
            guard body["phase"] as? String == "processing" else { return }
            if selectedProjectKey == nil {
                panel.orderFrontRegardless()
            }
            return
        }
        if type == "copy" {
            guard let text = body["text"] as? String else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }
        if type == "displayedReview" {
            displayedReviewID = body["reviewId"] as? String
            expandedView.setDisplayedProjectName(body["projectName"] as? String)
            state = AttentionState(
                reviewID: displayedReviewID,
                unreadCount: scopedUnreadCount(),
                connected: state.connected
            )
            if isExpanded {
                markReviewSeen(displayedReviewID)
            }
            return
        }
        if type == "projectCatalog" {
            globalUnreadCount = body["unreadCount"] as? Int ?? globalUnreadCount
            if let rawProjects = body["projects"] as? [[String: Any]] {
                projectOptions = rawProjects.compactMap { value in
                    guard
                        let key = value["key"] as? String,
                        let name = value["name"] as? String
                    else { return nil }
                    return ProjectFilterOption(
                        key: key,
                        name: name,
                        path: value["path"] as? String,
                        unreadCount: value["unreadCount"] as? Int ?? 0
                    )
                }
            }
            updateProjectScopeUI()
            return
        }
        guard type == "review" else { return }
        let reviewID = body["reviewId"] as? String
        let projectPath = body["projectPath"] as? String
        let projectName = body["projectName"] as? String
        if let selectedProjectKey {
            let incomingKey = projectPath?.isEmpty == false
                ? projectPath
                : projectName.map { "name:\($0)" }
            guard incomingKey == selectedProjectKey else { return }
        }
        let next = AttentionState(
            reviewID: reviewID,
            unreadCount: scopedUnreadCount(),
            connected: body["connected"] as? Bool ?? true
        )
        apply(next)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        apply(AttentionState(
            reviewID: state.reviewID,
            unreadCount: state.unreadCount,
            connected: false
        ))
    }
}

private enum DaemonBootstrap {
    private static var launchedProcess: Process?

    static func ensureRunning(completion: @escaping () -> Void) {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 0.8
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let health = data.flatMap {
                try? JSONDecoder().decode(HealthEnvelope.self, from: $0)
            }
            if (response as? HTTPURLResponse)?.statusCode == 200,
               health?.ok == true,
               health?.service == "aperture-attention",
               health?.capabilities?.contains("language-v1") == true,
               health?.capabilities?.contains("public-model-catalog-v1") == true {
                completion()
                return
            }
            if health?.service == "aperture-attention" {
                stopLegacyDaemon()
                DispatchQueue.global(qos: .utility).asyncAfter(
                    // The daemon's SIGTERM fallback is 1.5 seconds. Starting a
                    // replacement sooner can leave the old process holding
                    // port 4317 and make the new client talk to the old API.
                    deadline: .now() + 1.8
                ) {
                    launch()
                    completion()
                }
                return
            }
            launch()
            completion()
        }.resume()
    }

    private static func stopLegacyDaemon() {
        let lookup = Process()
        let output = Pipe()
        lookup.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lookup.arguments = [
            "-nP",
            "-t",
            "-iTCP:4317",
            "-sTCP:LISTEN"
        ]
        lookup.standardOutput = output
        lookup.standardError = FileHandle.nullDevice
        guard (try? lookup.run()) != nil else { return }
        lookup.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let pids = String(data: data, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0) } ?? []
        for pid in pids where pid > 1 && pid != getpid() {
            Darwin.kill(pid, SIGTERM)
        }
    }

    private static func launch() {
        guard launchedProcess == nil else { return }
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        let bundledRuntime = Bundle.main.resourceURL?
            .appendingPathComponent("runtime/server.mjs")
        let installedRuntime = home
            .appendingPathComponent("plugins/aperture-attention/runtime/server.mjs")
        guard let runtime = [bundledRuntime, installedRuntime]
            .compactMap({ $0 })
            .first(where: { fileManager.fileExists(atPath: $0.path) })
        else { return }

        guard let node = nodeExecutable() else { return }
        let dataDirectory = home.appendingPathComponent(".aperture")
        try? fileManager.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true
        )

        let bundledWeb = Bundle.main.resourceURL?
            .appendingPathComponent("runtime/web")
        let process = Process()
        process.executableURL = node
        process.arguments = [runtime.path]
        process.currentDirectoryURL = dataDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["APERTURE_DATA_DIR"] = dataDirectory.path
        applySystemProxy(to: &environment)
        if let bundledWeb,
           fileManager.fileExists(atPath: bundledWeb.path) {
            environment["APERTURE_WEB_DIR"] = bundledWeb.path
        }
        process.environment = environment

        let logURL = dataDirectory.appendingPathComponent("daemon.log")
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: logURL) {
            _ = try? log.seekToEnd()
            process.standardOutput = log
            process.standardError = log
        }
        do {
            try process.run()
            launchedProcess = process
            process.terminationHandler = { finishedProcess in
                if launchedProcess === finishedProcess {
                    launchedProcess = nil
                }
            }
        } catch {
            launchedProcess = nil
        }
    }

    private static func applySystemProxy(
        to environment: inout [String: String]
    ) {
        guard let settingsReference = CFNetworkCopySystemProxySettings()
        else { return }
        let settings = settingsReference.takeRetainedValue() as NSDictionary

        func proxyURL(
            enabledKey: CFString,
            hostKey: CFString,
            portKey: CFString
        ) -> String? {
            guard
                (settings[enabledKey] as? NSNumber)?.boolValue == true,
                let host = settings[hostKey] as? String,
                !host.isEmpty,
                let port = settings[portKey] as? NSNumber
            else { return nil }
            return "http://\(host):\(port.intValue)"
        }

        let httpProxy = proxyURL(
            enabledKey: kCFNetworkProxiesHTTPEnable,
            hostKey: kCFNetworkProxiesHTTPProxy,
            portKey: kCFNetworkProxiesHTTPPort
        )
        let httpsProxy = proxyURL(
            enabledKey: kCFNetworkProxiesHTTPSEnable,
            hostKey: kCFNetworkProxiesHTTPSProxy,
            portKey: kCFNetworkProxiesHTTPSPort
        )

        if environment["HTTP_PROXY"] == nil, let httpProxy {
            environment["HTTP_PROXY"] = httpProxy
        }
        if environment["HTTPS_PROXY"] == nil, let httpsProxy {
            environment["HTTPS_PROXY"] = httpsProxy
        }
        if environment["HTTP_PROXY"] != nil || environment["HTTPS_PROXY"] != nil {
            environment["NODE_USE_ENV_PROXY"] = "1"
            let current = environment["NO_PROXY"] ?? ""
            let local = "127.0.0.1,localhost"
            environment["NO_PROXY"] = current.isEmpty ? local : "\(current),\(local)"
        }
    }

    private static func nodeExecutable() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates = [
            ProcessInfo.processInfo.environment["APERTURE_NODE"],
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            home.appendingPathComponent(".volta/bin/node").path
        ].compactMap { $0 }

        let versions = home.appendingPathComponent(".nvm/versions/node")
        if let entries = try? fileManager.contentsOfDirectory(
            at: versions,
            includingPropertiesForKeys: nil
        ) {
            let versionNodes = entries
                .sorted {
                    $0.lastPathComponent.compare(
                        $1.lastPathComponent,
                        options: .numeric
                    ) == .orderedDescending
                }
                .map { $0.appendingPathComponent("bin/node").path }
            candidates.append(contentsOf: versionNodes)
        }

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AttentionPanelController?
    private var statusItem: NSStatusItem?
    private var editMenu: NSMenu?
    private var copyMenuItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var refreshMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: languageChangedNotification,
            object: nil
        )
        let controller = AttentionPanelController()
        self.controller = controller
        configureStatusItem()
        controller.start()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        let copyItem = NSMenuItem(
            title: "复制",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(copyItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
        self.editMenu = editMenu
        copyMenuItem = copyItem
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "circle.circle.fill",
                accessibilityDescription: "Aperture"
            )
            button.image?.isTemplate = true
            button.toolTip = "Aperture Attention Router"
        }

        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: "展开 / 收起",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        toggleMenuItem = toggle

        let refresh = NSMenuItem(
            title: "刷新 Review",
            action: #selector(refreshReview),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)
        refreshMenuItem = refresh
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 Aperture",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        quitMenuItem = quit

        item.menu = menu
        statusItem = item
    }

    @objc private func languageDidChange(_ notification: Notification) {
        guard let language = notification.object as? AppLanguage else { return }
        editMenu?.title = language.text("编辑", "Edit")
        copyMenuItem?.title = language.text("复制", "Copy")
        toggleMenuItem?.title = language.text("展开 / 收起", "Expand / Collapse")
        refreshMenuItem?.title = language.text("刷新 Review", "Refresh Review")
        quitMenuItem?.title = language.text("退出 Aperture", "Quit Aperture")
    }

    @objc private func togglePanel() {
        controller?.toggle()
        controller?.show()
    }

    @objc private func refreshReview() {
        controller?.reload()
        controller?.show()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

private let application = NSApplication.shared
private let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
