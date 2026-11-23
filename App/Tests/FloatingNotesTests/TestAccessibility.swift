import AppKit

/// 같은 테스트 프로세스의 창들이 SwiftUI 접근성 트리를 함께 사용하는 동안 설정을 유지한다.
@MainActor
enum TestAccessibility {
    private static let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    private static var users = 0
    private static var wasEnabled = false

    static func enableForTest() -> @MainActor () -> Void {
        if users == 0 {
            wasEnabled = (NSApp.accessibilityAttributeValue(attribute) as? NSNumber)?.boolValue == true
            if !wasEnabled { NSApp.accessibilitySetValue(true, forAttribute: attribute) }
        }
        users += 1
        return {
            users -= 1
            if users == 0 && !wasEnabled {
                NSApp.accessibilitySetValue(false, forAttribute: attribute)
            }
        }
    }
}
