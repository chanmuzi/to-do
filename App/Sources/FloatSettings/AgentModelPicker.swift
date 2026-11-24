import AgentRunner
import SwiftUI
import Theme

struct ModelChoices {
    struct Option {
        let value: String?
        let title: String
    }
    enum Group { case model, effort, both }
    let provider: AgentProvider
    let options: [Option]
    let model: Option
    let efforts: [String]
    let effort: String?
    var providerName: String { provider == .claude ? "Claude" : "Codex" }
    static func label(_ value: String?) -> String {
        guard let value else { return "자동" }
        return value == "xhigh" ? "XHigh" : value.prefix(1).uppercased() + value.dropFirst()
    }

    init(values: SettingsValues, engine: EngineAccount?) {
        provider = AgentProvider(rawValue: values.agentProvider) ?? .claude
        let saved = provider == .claude ? AgentEngine.claude(values.agentModel).model : values.codexModel
        let catalog: [Option]
        let supported: [String]?
        if provider == .codex {
            let models = engine?.models ?? []
            let selected = models.first { $0.slug == saved }
            var visible = Array(models.prefix(5))
            if let selected, !visible.contains(where: { $0.slug == selected.slug }) { visible.append(selected) }
            catalog = visible.map { Option(value: $0.slug, title: $0.displayName) }
            supported = (saved == nil ? models.first : selected)?.efforts
        } else {
            catalog = engine?.claudeModels?.map { Option(value: $0.value, title: $0.displayName) }
                ?? ["Fable", "Opus", "Sonnet", "Haiku"].map { Option(value: $0.lowercased(), title: $0) }
            supported = engine?.claudeModels?.first { $0.value == saved }?.efforts
        }
        options = [Option(value: nil, title: provider == .codex ? "CLI 기본" : "자동")] + catalog
        model = options.first { $0.value == saved } ?? options[0]
        let levels = supported ?? provider.fallbackEfforts
        efforts = levels
        effort = values.effort.flatMap { levels.contains($0) ? $0 : nil }
    }

    func menu(_ group: Group, theme: Theme) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let width = PickerMenuRow.widthToFitTitles(options.map(\.title), minimum: theme.component(provider == .codex ? .codexMenuWidth : .claudeMenuWidth), theme: theme)
        func add(_ option: Option, selected: String?, prefix: String) {
            let item = menu.addItem(withTitle: option.title, action: nil, keyEquivalent: "")
            item.representedObject = prefix + (option.value ?? "")
            item.state = option.value == selected ? .on : .off
            item.view = PickerMenuRow(theme: theme, text: option.title, dot: nil, selected: item.state == .on, width: width)
        }
        if group != .effort {
            for (index, option) in options.enumerated() {
                if index == 1 { menu.addItem(.separator()) }
                add(option, selected: model.value, prefix: "model:")
            }
        }
        if group != .model && !efforts.isEmpty {
            if group == .both { menu.addItem(.separator()) }
            add(Option(value: nil, title: "자동"), selected: effort, prefix: "effort:")
            if group == .effort { menu.addItem(.separator()) }
            for value in efforts { add(Option(value: value, title: Self.label(value)), selected: effort, prefix: "effort:") }
        }
        return menu
    }
}

extension SettingsModel {
    var selectedAccount: EngineAccount? { agents?.engines.first { $0.provider.rawValue == values.agentProvider } }
    package var selectedEffort: String? { choices.effort }
    package func supportedEfforts(provider: AgentProvider, model: String?) -> [String]? {
        guard let account = agents?.engines.first(where: { $0.provider == provider }) else { return nil }
        if provider == .claude {
            return account.claudeModels?.first { $0.value == model }?.efforts
        }
        return (model == nil ? account.models.first : account.models.first { $0.slug == model })?.efforts
    }
    var choices: ModelChoices { ModelChoices(values: values, engine: selectedAccount) }
    func chooseModelOption(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String, let separator = key.firstIndex(of: ":") else { return }
        let raw = String(key[key.index(after: separator)...])
        let value = raw.isEmpty ? nil : raw
        change {
            if key[..<separator] == "effort" { $0.effort = value }
            else if $0.agentProvider == "codex" { $0.codexModel = value }
            else { $0.agentModel = value ?? "auto" }
        }
    }

    package func inlinePicker(theme: Theme, visible: Bool, lineSpace: CommandLineSpace? = nil) -> AnyView {
        AnyView(InlineModelPicker(model: self, theme: theme, visible: visible, lineSpace: lineSpace))
    }
}

private struct InlineModelPicker: View {
    let model: SettingsModel
    let theme: Theme
    let visible: Bool
    let lineSpace: CommandLineSpace?

    var body: some View {
        let choices = model.choices
        let name = choices.model.value == nil ? choices.providerName : choices.model.title
        let detail = choices.model.value == nil ? choices.model.title : choices.effort.map { ModelChoices.label($0) }
        return InlineValuePopup(theme: theme, name: name, detail: detail, visible: visible, lineSpace: lineSpace,
                                label: "모델: " + name + ", 강도: " + ModelChoices.label(choices.effort),
                                makeMenu: { model.choices.menu(.both, theme: theme) }, choose: model.chooseModelOption)
            .task(id: model.values.agentProvider + String(model.selectedAccount?.generation ?? 0)) { model.selectedAccount?.loadIfNeeded() }
    }
}
