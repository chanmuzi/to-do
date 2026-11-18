import AppKit
import CoreText
import FieldTestSupport
import Testing
import Theme
@testable import Editor

@MainActor @Test func linkFieldGeometry() throws {
    let url = try ThemeResources.fontsDirectoryURL().appendingPathComponent("D2Coding.ttf") as CFURL
    let registered = CTFontManagerRegisterFontsForURL(url, .process, nil)
    defer { if registered { CTFontManagerUnregisterFontsForURL(url, .process, nil) } }
    let theme = try Theme.bundled()
    let field = LinkField(theme: theme)
    field.apply(theme: theme, style: EditorStyle(theme: theme, configuration: .init(), increaseContrast: false))
    #expect(field.input.font?.familyName == "D2Coding")
    try FieldGeometry.verifyHosted(field, labels: ["링크 주소"])
}
