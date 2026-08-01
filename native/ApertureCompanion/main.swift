import AppKit
import CFNetwork
import QuartzCore
import WebKit

private let apertureURL = URL(string: "http://127.0.0.1:4317/?surface=companion")!
private let reviewURL = URL(string: "http://127.0.0.1:4317/api/review/current")!
private let monitoringURL = URL(string: "http://127.0.0.1:4317/api/monitoring")!
private let focusURL = URL(string: "http://127.0.0.1:4317/api/focus")!
private let promptURL = URL(string: "http://127.0.0.1:4317/api/prompt")!
private let configURL = URL(string: "http://127.0.0.1:4317/api/config")!
private let configSecretURL = URL(string: "http://127.0.0.1:4317/api/config/secret")!
private let modelsURL = URL(string: "http://127.0.0.1:4317/api/models")!
private let modelTestURL = URL(string: "http://127.0.0.1:4317/api/config/test")!
private let inboxSeenURL = URL(string: "http://127.0.0.1:4317/api/inbox/seen")!
private let healthURL = URL(string: "http://127.0.0.1:4317/api/health")!

private struct ReviewEnvelope: Decodable {
    let review: ReviewSummary?
    let monitoring: MonitoringSummary?
    let focus: FocusSummary?
    let prompt: PromptSummary?
    let inbox: InboxSummary?
}

private struct MonitoringSummary: Decodable {
    let enabled: Bool
}

private struct FocusSummary: Decodable {
    let level: Double
}

private struct PromptSummary: Decodable {
    let value: String
}

private struct InboxSummary: Decodable {
    let unreadCount: Int
}

private struct ReviewSummary: Decodable {
    let id: String
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
}

private struct ModelTestEnvelope: Decodable {
    let ok: Bool
    let model: String
    let latencyMs: Int
}

private struct APIErrorEnvelope: Decodable {
    let error: String
}

private struct AttentionState {
    let reviewID: String?
    let unreadCount: Int
    let connected: Bool
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

private final class CompactActionButton: NSButton {
    var actionHandler: (() -> Void)?

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        self.title = title
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )
        imagePosition = .imageLeading
        isBordered = true
        bezelStyle = .rounded
        controlSize = .regular
        font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        focusRingType = .default
        target = self
        action = #selector(invoke)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        actionHandler?()
    }
}

private final class PromptTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        if modifiers.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSave?()
            return
        }
        if modifiers.contains(.command), event.keyCode == 36 {
            onSave?()
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if isEditable {
            menu.addItem(NSMenuItem(
                title: "剪切",
                action: #selector(NSText.cut(_:)),
                keyEquivalent: ""
            ))
        }
        menu.addItem(NSMenuItem(
            title: "复制",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: ""
        ))
        if isEditable {
            menu.addItem(NSMenuItem(
                title: "粘贴",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: ""
            ))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "全选",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: ""
        ))
        for item in menu.items where !item.isSeparatorItem {
            item.target = self
        }
        return menu
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

private final class SettingsViewController: NSViewController, NSTextViewDelegate {
    private let titleLabel = NSTextField(labelWithString: "设置")
    private let focusLabel = NSTextField(labelWithString: "聚焦")
    private let focusSlider = NSSlider(
        value: 0.62,
        minValue: 0,
        maxValue: 1,
        target: nil,
        action: nil
    )
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
    private let secureKeyField = NSSecureTextField(frame: .zero)
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
    private let testModelButton = ActionButton(
        symbol: "bolt.horizontal.circle",
        label: "测试模型"
    )
    private let saveModelButton = ActionButton(
        symbol: "checkmark",
        label: "保存模型配置"
    )
    private let modelStatus = NSTextField(labelWithString: "")
    private let promptLabel = NSTextField(labelWithString: "Prompt")
    private let promptStatus = NSTextField(labelWithString: "")
    private let promptScroll = NSScrollView(frame: .zero)
    private let promptEditor = PromptTextView(frame: .zero)
    private let promptActions = NSStackView(frame: .zero)
    private let copyPromptButton = CompactActionButton(
        title: "复制",
        symbol: "doc.on.doc"
    )
    private let editPromptButton = CompactActionButton(
        title: "编辑",
        symbol: "pencil"
    )
    private let selectAllPromptButton = CompactActionButton(
        title: "全选",
        symbol: "selection.pin.in.out"
    )
    private let cancelPromptButton = CompactActionButton(
        title: "取消",
        symbol: "xmark"
    )
    private let savePromptButton = CompactActionButton(
        title: "保存",
        symbol: "checkmark"
    )
    private let sizeChoices = [
        (16, "16 · 紧凑"),
        (18, "18 · 舒适"),
        (20, "20 · 大"),
        (22, "22 · 特大"),
        (24, "24 · 最大")
    ]
    private var isDark: Bool
    private var readerSize: Int
    private var showsKey = false
    private var apiKeyConfigured = false
    private var isEditingPrompt = false
    private var promptBeforeEditing = ""
    private var promptStatusWorkItem: DispatchWorkItem?
    private var focusHandler: ((Double) -> Void)?
    private var themeHandler: ((Bool) -> Void)?
    private var sizeHandler: ((Int) -> Void)?
    private var promptHandler: ((String) -> Void)?

    init(
        focusLevel: Double,
        isDark: Bool,
        readerSize: Int,
        prompt: String,
        onFocusChanged: @escaping (Double) -> Void,
        onThemeChanged: @escaping (Bool) -> Void,
        onSizeChanged: @escaping (Int) -> Void,
        onPromptChanged: @escaping (String) -> Void
    ) {
        self.isDark = isDark
        self.readerSize = readerSize
        super.init(nibName: nil, bundle: nil)
        focusSlider.doubleValue = min(1, max(0, focusLevel))
        promptEditor.string = prompt
        focusHandler = onFocusChanged
        themeHandler = onThemeChanged
        sizeHandler = onSizeChanged
        promptHandler = onPromptChanged
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 800))
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        view = root

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        root.addSubview(titleLabel)

        let labels = [
            focusLabel,
            appearanceLabel,
            sizeLabel,
            providerLabel,
            keyLabel,
            modelLabel,
            promptLabel
        ]
        for label in labels {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            root.addSubview(label)
        }
        promptStatus.translatesAutoresizingMaskIntoConstraints = false
        promptStatus.font = NSFont.monospacedDigitSystemFont(
            ofSize: 12,
            weight: .regular
        )
        promptStatus.lineBreakMode = .byTruncatingTail
        promptStatus.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        root.addSubview(promptStatus)

        focusSlider.translatesAutoresizingMaskIntoConstraints = false
        focusSlider.controlSize = .regular
        focusSlider.isContinuous = true
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

        for button in [refreshModelsButton, testModelButton, saveModelButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(button)
        }
        refreshModelsButton.actionHandler = { [weak self] in self?.fetchModels() }
        testModelButton.actionHandler = { [weak self] in self?.testModel() }
        saveModelButton.actionHandler = { [weak self] in self?.saveModelConfig() }

        modelStatus.translatesAutoresizingMaskIntoConstraints = false
        modelStatus.font = NSFont.systemFont(ofSize: 12)
        modelStatus.lineBreakMode = .byWordWrapping
        modelStatus.maximumNumberOfLines = 2
        root.addSubview(modelStatus)

        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.hasVerticalScroller = true
        promptScroll.hasHorizontalScroller = false
        promptScroll.autohidesScrollers = true
        promptScroll.horizontalScrollElasticity = .none
        promptScroll.verticalScrollElasticity = .automatic
        promptScroll.drawsBackground = false
        promptScroll.borderType = .noBorder
        promptScroll.wantsLayer = true
        promptScroll.layer?.cornerRadius = 9
        promptScroll.layer?.cornerCurve = .continuous
        root.addSubview(promptScroll)

        promptEditor.isRichText = false
        promptEditor.importsGraphics = false
        promptEditor.isAutomaticQuoteSubstitutionEnabled = false
        promptEditor.isAutomaticDashSubstitutionEnabled = false
        promptEditor.isAutomaticTextReplacementEnabled = false
        promptEditor.isEditable = false
        promptEditor.isSelectable = true
        promptEditor.isHorizontallyResizable = false
        promptEditor.isVerticallyResizable = true
        promptEditor.autoresizingMask = [.width]
        promptEditor.minSize = NSSize(width: 0, height: 0)
        promptEditor.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        promptEditor.frame = NSRect(x: 0, y: 0, width: 398, height: 420)
        promptEditor.textContainer?.containerSize = NSSize(
            width: 398,
            height: CGFloat.greatestFiniteMagnitude
        )
        promptEditor.textContainer?.widthTracksTextView = true
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        promptEditor.defaultParagraphStyle = paragraphStyle
        updatePromptFont()
        promptEditor.textContainerInset = NSSize(width: 12, height: 12)
        promptEditor.delegate = self
        promptEditor.onSave = { [weak self] in self?.savePrompt() }
        promptEditor.onCancel = { [weak self] in self?.cancelPromptEditing() }
        promptScroll.documentView = promptEditor
        DispatchQueue.main.async { [weak self] in
            self?.promptEditor.scrollToBeginningOfDocument(nil)
        }

        promptActions.translatesAutoresizingMaskIntoConstraints = false
        promptActions.orientation = .horizontal
        promptActions.alignment = .centerY
        promptActions.spacing = 6
        promptActions.detachesHiddenViews = true
        for button in [
            copyPromptButton,
            editPromptButton,
            selectAllPromptButton,
            cancelPromptButton,
            savePromptButton
        ] {
            button.translatesAutoresizingMaskIntoConstraints = false
            promptActions.addArrangedSubview(button)
        }
        copyPromptButton.actionHandler = { [weak self] in self?.copyPrompt() }
        editPromptButton.actionHandler = {
            [weak self] in self?.beginPromptEditing()
        }
        selectAllPromptButton.actionHandler = {
            [weak self] in self?.selectAllPrompt()
        }
        cancelPromptButton.actionHandler = {
            [weak self] in self?.cancelPromptEditing()
        }
        savePromptButton.actionHandler = { [weak self] in self?.savePrompt() }
        root.addSubview(promptActions)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            focusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 26),
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
            refreshModelsButton.trailingAnchor.constraint(equalTo: testModelButton.leadingAnchor, constant: -2),
            testModelButton.trailingAnchor.constraint(equalTo: saveModelButton.leadingAnchor, constant: -2),
            saveModelButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            refreshModelsButton.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            testModelButton.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            saveModelButton.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            refreshModelsButton.widthAnchor.constraint(equalToConstant: 28),
            testModelButton.widthAnchor.constraint(equalToConstant: 28),
            saveModelButton.widthAnchor.constraint(equalToConstant: 28),
            refreshModelsButton.heightAnchor.constraint(equalToConstant: 28),
            testModelButton.heightAnchor.constraint(equalToConstant: 28),
            saveModelButton.heightAnchor.constraint(equalToConstant: 28),

            modelStatus.topAnchor.constraint(equalTo: modelCombo.bottomAnchor, constant: 9),
            modelStatus.leadingAnchor.constraint(equalTo: modelCombo.leadingAnchor),
            modelStatus.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            promptLabel.topAnchor.constraint(equalTo: modelStatus.bottomAnchor, constant: 22),
            promptLabel.leadingAnchor.constraint(equalTo: focusLabel.leadingAnchor),
            promptStatus.leadingAnchor.constraint(equalTo: promptLabel.trailingAnchor, constant: 8),
            promptStatus.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),
            promptStatus.centerYAnchor.constraint(equalTo: promptLabel.centerYAnchor),

            promptActions.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 10),
            promptActions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            promptActions.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),

            promptScroll.topAnchor.constraint(equalTo: promptActions.bottomAnchor, constant: 12),
            promptScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            promptScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            promptScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])

        applyTheme()
        setPromptEditing(false)
        loadModelConfig()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let availableWidth = promptScroll.contentSize.width
        guard availableWidth > 0 else { return }
        promptEditor.minSize.width = availableWidth
        promptEditor.maxSize.width = availableWidth
        var editorFrame = promptEditor.frame
        editorFrame.size.width = availableWidth
        promptEditor.frame = editorFrame
        promptEditor.textContainer?.containerSize = NSSize(
            width: availableWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        if promptScroll.contentView.bounds.origin.x != 0 {
            promptScroll.contentView.scroll(
                to: NSPoint(x: 0, y: promptScroll.contentView.bounds.origin.y)
            )
            promptScroll.reflectScrolledClipView(promptScroll.contentView)
        }
    }

    func setFocus(level: Double) {
        focusSlider.doubleValue = min(1, max(0, level))
    }

    func setTheme(isDark: Bool) {
        self.isDark = isDark
        applyTheme()
    }

    func setReaderSize(_ value: Int) {
        readerSize = value
        updatePromptFont()
        if let index = sizeChoices.firstIndex(where: { $0.0 == value }) {
            sizePopup.selectItem(at: index)
        }
    }

    private func updatePromptFont() {
        promptEditor.font = NSFont.systemFont(
            ofSize: max(15, CGFloat(readerSize - 2)),
            weight: .regular
        )
    }

    func setPrompt(_ value: String) {
        guard !isEditingPrompt, promptEditor.string != value else { return }
        promptEditor.string = value
        updatePromptStatus()
    }

    func textDidChange(_ notification: Notification) {
        updatePromptStatus()
    }

    @objc private func changeFocus() {
        focusHandler?(focusSlider.doubleValue)
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
                if self.apiKeyConfigured {
                    self.fetchModels()
                }
            }
        }.resume()
    }

    private func fetchModels() {
        setModelStatus("正在拉取模型…", success: nil)
        postJSON(url: modelsURL, body: requestBody()) { [weak self] data, response in
            guard let self else { return }
            guard
                let data,
                let response,
                (200..<300).contains(response.statusCode),
                let payload = try? JSONDecoder().decode(
                    ModelListEnvelope.self,
                    from: data
                )
            else {
                self.showAPIError(data, fallback: "模型列表拉取失败")
                return
            }
            DispatchQueue.main.async {
                let selected = self.modelCombo.stringValue
                self.modelCombo.removeAllItems()
                self.modelCombo.addItems(
                    withObjectValues: payload.models.map(\.id)
                )
                self.modelCombo.stringValue = selected
                self.setModelStatus(
                    "已载入 \(payload.models.count) 个模型",
                    success: true
                )
            }
        }
    }

    private func testModel() {
        guard !modelCombo.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            setModelStatus("请先选择模型", success: false)
            return
        }
        setModelStatus("正在测试模型…", success: nil)
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
                self.showAPIError(data, fallback: "模型测试失败")
                return
            }
            DispatchQueue.main.async {
                self.setModelStatus(
                    "可用 · \(payload.latencyMs) ms",
                    success: true
                )
            }
        }
    }

    private func saveModelConfig() {
        guard !modelCombo.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            setModelStatus("请先选择模型", success: false)
            return
        }
        setModelStatus("正在保存…", success: nil)
        postJSON(url: configURL, body: requestBody()) { [weak self] data, response in
            guard let self else { return }
            guard
                let response,
                (200..<300).contains(response.statusCode)
            else {
                self.showAPIError(data, fallback: "模型配置保存失败")
                return
            }
            DispatchQueue.main.async {
                self.apiKeyConfigured =
                    self.apiKeyConfigured || !self.currentKey().isEmpty
                self.updateKeyPlaceholder()
                self.setModelStatus("配置已保存", success: true)
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

    private func showAPIError(_ data: Data?, fallback: String) {
        let message = data.flatMap {
            try? JSONDecoder().decode(APIErrorEnvelope.self, from: $0).error
        } ?? fallback
        DispatchQueue.main.async {
            self.setModelStatus(message, success: false)
        }
    }

    private func updateKeyPlaceholder() {
        let placeholder = apiKeyConfigured ? "已保存；输入可替换" : "填写 Key"
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

    private func beginPromptEditing() {
        guard !isEditingPrompt else { return }
        promptBeforeEditing = promptEditor.string
        let visibleOrigin = promptScroll.contentView.bounds.origin
        setPromptEditing(true)
        view.window?.makeFirstResponder(promptEditor)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.promptScroll.contentView.scroll(to: visibleOrigin)
            self.promptScroll.reflectScrolledClipView(self.promptScroll.contentView)
        }
    }

    private func savePrompt() {
        guard isEditingPrompt, promptEditor.string.count <= 4000 else { return }
        let value = promptEditor.string.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        promptEditor.string = value
        promptBeforeEditing = value
        promptHandler?(value)
        setPromptEditing(false)
        showPromptStatus("已保存")
    }

    private func cancelPromptEditing() {
        guard isEditingPrompt else { return }
        promptEditor.string = promptBeforeEditing
        setPromptEditing(false)
        showPromptStatus("已取消")
    }

    private func copyPrompt() {
        let selectedRange = promptEditor.selectedRange()
        let source = promptEditor.string as NSString
        let value = selectedRange.length > 0
            ? source.substring(with: selectedRange)
            : promptEditor.string
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        showPromptStatus("已复制")
    }

    private func selectAllPrompt() {
        view.window?.makeFirstResponder(promptEditor)
        promptEditor.selectAll(nil)
    }

    private func setPromptEditing(_ editing: Bool) {
        isEditingPrompt = editing
        promptEditor.isEditable = editing
        copyPromptButton.isHidden = false
        editPromptButton.isHidden = editing
        selectAllPromptButton.isHidden = !editing
        cancelPromptButton.isHidden = !editing
        savePromptButton.isHidden = !editing
        if !editing {
            view.window?.makeFirstResponder(nil)
        }
        updatePromptStatus()
        applyTheme()
    }

    private func updatePromptStatus() {
        promptStatusWorkItem?.cancel()
        let count = promptEditor.string.count
        if isEditingPrompt {
            promptStatus.stringValue = count > 4000
                ? "超出 \(count - 4000) 字"
                : "\(count) / 4000"
            savePromptButton.isEnabled = count <= 4000
        } else {
            promptStatus.stringValue = "\(count) 字"
            savePromptButton.isEnabled = true
        }
    }

    private func showPromptStatus(_ value: String) {
        promptStatusWorkItem?.cancel()
        promptStatus.stringValue = value
        let work = DispatchWorkItem { [weak self] in
            self?.updatePromptStatus()
        }
        promptStatusWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func applyTheme() {
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        appearanceControl.selectedSegment = isDark ? 1 : 0
        let text = isDark
            ? NSColor(calibratedWhite: 0.90, alpha: 1)
            : NSColor(calibratedWhite: 0.18, alpha: 1)
        let editorBackground = isDark
            ? NSColor(calibratedWhite: 0.10, alpha: 0.96)
            : NSColor(calibratedWhite: 0.96, alpha: 0.98)
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
            focusLabel,
            appearanceLabel,
            sizeLabel,
            providerLabel,
            keyLabel,
            modelLabel,
            promptLabel
        ] {
            label.textColor = text
        }
        focusSlider.trackFillColor = isDark
            ? NSColor(calibratedRed: 0.92, green: 0.70, blue: 0.29, alpha: 1)
            : NSColor(calibratedRed: 0.65, green: 0.43, blue: 0.04, alpha: 1)
        promptScroll.layer?.backgroundColor = editorBackground.cgColor
        promptScroll.layer?.borderWidth = isEditingPrompt ? 1 : 0
        promptScroll.layer?.borderColor = (
            isDark
                ? NSColor(calibratedRed: 0.92, green: 0.70, blue: 0.29, alpha: 0.72)
                : NSColor(calibratedRed: 0.65, green: 0.43, blue: 0.04, alpha: 0.62)
        ).cgColor
        promptEditor.backgroundColor = editorBackground
        promptEditor.textColor = isEditingPrompt
            ? text
            : (isDark
                ? NSColor(calibratedWhite: 0.72, alpha: 1)
                : NSColor(calibratedWhite: 0.30, alpha: 1))
        promptEditor.insertionPointColor = text
        promptStatus.textColor = isDark
            ? NSColor(calibratedWhite: 0.54, alpha: 1)
            : NSColor(calibratedWhite: 0.47, alpha: 1)
        let tint = isDark
            ? NSColor(calibratedWhite: 0.72, alpha: 1)
            : NSColor(calibratedWhite: 0.36, alpha: 1)
        for button in [
            keyVisibilityButton,
            refreshModelsButton,
            testModelButton,
            saveModelButton,
            copyPromptButton,
            editPromptButton,
            selectAllPromptButton,
            cancelPromptButton,
            savePromptButton
        ] {
            button.contentTintColor = tint
        }
        if !modelStatus.stringValue.isEmpty {
            setModelStatus(modelStatus.stringValue, success: nil)
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
    private let mark = ApertureMarkView(frame: .zero)
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
    private var currentFocus = 0.62
    private var currentIsDark: Bool
    private var currentReaderSize: Int
    private var currentPrompt = ""

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
        settingsButton.contentTintColor = tint
    }
}

private final class BubbleView: NSView {
    private let badge = NSTextField(labelWithString: "0")
    private var bubbleConnected = false
    private var bubbleFocus: CGFloat = 0.62
    private var bubbleIsDark = true
    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var didDrag = false

    var onOpen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.borderWidth = 0

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.alignment = .center
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        badge.textColor = NSColor(
            calibratedRed: 0.28,
            green: 0.78,
            blue: 0.52,
            alpha: 1
        )
        addSubview(badge)

        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
            badge.heightAnchor.constraint(equalToConstant: 13)
        ])

        toolTip = "Aperture · 点击展开，拖动可移动"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("展开 Aperture")
        setAccessibilityHelp("点击展开注意力侧边栏，拖动可移动气泡")
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
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

    func update(state: AttentionState) {
        bubbleConnected = state.connected
        needsDisplay = true
        badge.stringValue =
            state.unreadCount > 99 ? "99+" : String(state.unreadCount)
        badge.isHidden = state.unreadCount == 0
    }

    func setFocus(level: Double) {
        bubbleFocus = CGFloat(min(1, max(0, level)))
        needsDisplay = true
    }

    func setTheme(isDark: Bool) {
        bubbleIsDark = isDark
        layer?.backgroundColor = (
            isDark
                ? NSColor(
                    calibratedRed: 0.055,
                    green: 0.070,
                    blue: 0.080,
                    alpha: 0.94
                )
                : NSColor(calibratedWhite: 0.985, alpha: 0.96)
        ).cgColor
        layer?.borderWidth = 0
        badge.textColor = isDark
            ? NSColor(calibratedRed: 0.36, green: 0.88, blue: 0.62, alpha: 1)
            : NSColor(calibratedRed: 0.10, green: 0.58, blue: 0.34, alpha: 1)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        didDrag = false
    }

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
        }
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
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
    private var customPrompt = ""
    private var focusWorkItem: DispatchWorkItem?
    private var resizeSaveWorkItem: DispatchWorkItem?
    private var monitorTimer: Timer?
    private var isExpanded = true
    private var hasBaseline = false
    private var latestReviewID: String?
    private var state = AttentionState(
        reviewID: nil,
        unreadCount: 0,
        connected: false
    )
    private var lastWebLoad = Date.distantPast
    private var expandedSize = NSSize(width: 430, height: 800)
    private var settingsPanel: FloatingPanel?
    private var settingsController: SettingsViewController?
    private var isPositioningSettings = false

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
        let storedWidth = UserDefaults.standard.double(
            forKey: "apertureExpandedWidth"
        )
        let storedHeight = UserDefaults.standard.double(
            forKey: "apertureExpandedHeight"
        )
        if storedWidth >= 320, storedHeight >= 360 {
            expandedSize = NSSize(width: storedWidth, height: storedHeight)
        }

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: """
            document.documentElement.dataset.theme = '\(initialIsDark ? "dark" : "light")';
            document.documentElement.style.setProperty(
                '--reader-size',
                '\(initialReaderSize)px'
            );
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
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 800),
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
        contentController.add(self, name: "aperture")
        webView.navigationDelegate = self
        bubbleView.onOpen = { [weak self] in self?.expand() }
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
    }

    deinit {
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
            prompt: customPrompt,
            onFocusChanged: { [weak self] level in
                self?.updateFocus(level: level)
            },
            onThemeChanged: { [weak self] isDark in
                self?.setTheme(isDark: isDark)
            },
            onSizeChanged: { [weak self] value in
                self?.setReaderSize(value)
            },
            onPromptChanged: { [weak self] value in
                self?.updatePrompt(value)
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
        return NSRect(
            x: panel.frame.maxX + gap,
            y: panel.frame.minY,
            width: width,
            height: panel.frame.height
        )
    }

    private func positionSettingsPanel() {
        guard let settings = settingsPanel, !isPositioningSettings else { return }
        isPositioningSettings = true
        defer { isPositioningSettings = false }

        let visible = currentScreen().visibleFrame
        let gap: CGFloat = 10
        let targetSize = settingsFrame().size
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
                height: panel.frame.height
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
                let next = AttentionState(
                    reviewID: envelope.review?.id,
                    unreadCount:
                        envelope.inbox?.unreadCount ?? self.state.unreadCount,
                    connected: true
                )
                DispatchQueue.main.async {
                    let recovered = !self.state.connected
                    self.monitoringEnabled =
                        envelope.monitoring?.enabled ?? self.monitoringEnabled
                    self.focusLevel =
                        envelope.focus?.level ?? self.focusLevel
                    self.customPrompt =
                        envelope.prompt?.value ?? self.customPrompt
                    self.expandedView.setMonitoring(
                        enabled: self.monitoringEnabled,
                        connected: true
                    )
                    self.expandedView.setFocus(level: self.focusLevel)
                    self.expandedView.setPrompt(self.customPrompt)
                    self.settingsController?.setFocus(level: self.focusLevel)
                    self.settingsController?.setPrompt(self.customPrompt)
                    self.bubbleView.setFocus(level: self.focusLevel)
                    self.apply(next)
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
        if isExpanded, next.unreadCount > 0 {
            markInboxSeen()
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
        isExpanded = true
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let target = expandedFrame(anchoredAt: topLeft)
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
        markInboxSeen()
    }

    private func collapse() {
        guard isExpanded else { return }
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
            self.bubbleView.frame = NSRect(
                origin: .zero,
                size: target.size
            )
            self.bubbleView.autoresizingMask = [.width, .height]
            self.expandedView.alphaValue = 1
            self.bubbleView.update(state: self.state)
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

    private func markInboxSeen() {
        guard state.unreadCount > 0 else { return }
        state = AttentionState(
            reviewID: state.reviewID,
            unreadCount: 0,
            connected: state.connected
        )
        bubbleView.update(state: state)
        var request = URLRequest(url: inboxSeenURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 2.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                DispatchQueue.main.async { self.refresh() }
            }
        }.resume()
    }

    private func updatePrompt(_ value: String) {
        customPrompt = String(value.prefix(4000))
        expandedView.setPrompt(customPrompt)
        settingsController?.setPrompt(customPrompt)
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
        expandedView.setFocus(level: focusLevel)
        settingsController?.setFocus(level: focusLevel)
        bubbleView.setFocus(level: focusLevel)
        focusWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistFocus()
        }
        focusWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func persistFocus() {
        var request = URLRequest(url: focusURL)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["level": focusLevel]
        )
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                DispatchQueue.main.async { self.refresh() }
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
            panel.orderFrontRegardless()
            return
        }
        if type == "copy" {
            guard let text = body["text"] as? String else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }
        guard type == "review" else { return }
        let next = AttentionState(
            reviewID: body["reviewId"] as? String,
            unreadCount: state.unreadCount,
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
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                completion()
                return
            }
            launch()
            completion()
        }.resume()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
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

        let refresh = NSMenuItem(
            title: "刷新 Review",
            action: #selector(refreshReview),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 Aperture",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
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
