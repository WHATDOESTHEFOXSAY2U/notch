import ApplicationServices

/// Questions to another app through Accessibility.
/// The caller gives every element its time limit before asking it anything.
extension AXUIElement {
    /// The value of `name`, or nil if the app did not give one.
    func value(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        return value
    }

    /// The values of `names`, in one question; nil in place of each the app did not give.
    func values(_ names: [String]) -> [CFTypeRef?] {
        var list: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(self, names as CFArray, [], &list)
        guard error == .success, let got = list as? [AnyObject], got.count == names.count else { return names.map { _ in nil } }
        return got.map { item in
            // A value the app could not give comes back as its error code, wrapped.
            guard CFGetTypeID(item) == AXValueGetTypeID(), AXValueGetType(item as! AXValue) == .axError else { return item }
            return nil
        }
    }

    func bool(_ name: String) -> Bool? { value(name) as? Bool }
    func string(_ name: String) -> String? { value(name) as? String }

    /// The element `name` points to (a window, a button), given the time limit `limit`.
    func element(_ name: String, limit: Float) -> AXUIElement? {
        guard let value = value(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, limit)
        return element
    }

    func set(_ name: String, _ value: CFTypeRef) -> AXError { AXUIElementSetAttributeValue(self, name as CFString, value) }

    /// Whether the app lets `name` be changed; false if it did not say.
    func settable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        _ = AXUIElementIsAttributeSettable(self, name as CFString, &settable)
        return settable.boolValue
    }

    /// Where it is and how big, measured from the top left of the main screen, in one question. Nil if the app did not say.
    var frame: CGRect? {
        let got = values([kAXPositionAttribute, kAXSizeAttribute])
        var origin = CGPoint.zero, size = CGSize.zero
        guard let at = got[0], let extent = got[1], CFGetTypeID(at) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(at as! AXValue, .cgPoint, &origin), AXValueGetValue(extent as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Whether this is a text box: a text field, a text area or a combo box, or anything whose selected text can be
    /// changed. Both are asked every time, the role first.
    var isTextBox: Bool {
        let role = string(kAXRoleAttribute) ?? ""
        return settable(kAXSelectedTextAttribute) || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
    }
}
