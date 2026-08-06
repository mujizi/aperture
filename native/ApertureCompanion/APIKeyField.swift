import AppKit

func makeSecureAPIKeyField() -> NSTextField {
    let field = NSSecureTextField(frame: .zero)
    field.isEditable = true
    field.isSelectable = true
    field.isEnabled = true

    // A secure field requires AppKit's secure field editor. Classify the value
    // as a one-time secret so Password AutoFill does not offer saved logins for
    // an API key while typing and paste remain fully supported.
    field.contentType = .oneTimeCode
    field.isAutomaticTextCompletionEnabled = false
    return field
}
