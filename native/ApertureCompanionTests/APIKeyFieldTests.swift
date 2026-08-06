import AppKit

@main
private enum APIKeyFieldTests {
    static func main() {
        _ = NSApplication.shared

        let field = makeSecureAPIKeyField()
        precondition(field.cell is NSSecureTextFieldCell)
        precondition(field is NSSecureTextField)
        precondition(field.contentType == .oneTimeCode)
        precondition(field.isEditable)
        precondition(field.isSelectable)
        precondition(field.isEnabled)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        field.frame = NSRect(x: 20, y: 20, width: 280, height: 24)
        window.contentView?.addSubview(field)
        precondition(window.makeFirstResponder(field))

        guard let editor = window.fieldEditor(true, for: field) as? NSTextView else {
            preconditionFailure("The API key field must provide an editable field editor")
        }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("com.aperture.attention.api-key-test")
        )
        pasteboard.clearContents()
        precondition(pasteboard.setString("sk-or-test-value", forType: .string))
        precondition(editor.readSelection(from: pasteboard, type: .string))
        field.validateEditing()
        precondition(field.stringValue == "sk-or-test-value")

        print("API key field editing and paste test passed")
    }
}
