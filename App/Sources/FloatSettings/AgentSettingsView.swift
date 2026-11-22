import AgentRunner
import SwiftUI
import Theme

extension SettingsView {
    func logo(_ engine: EngineAccount, small: Bool = false) -> some View {
        let size = theme.component(small ? .settingsLogoSmall : .settingsLogo)
        return Group {
            if let icon = logoImage(engine, size: size) { Image(nsImage: icon).resizable() }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }

    private func logoImage(_ engine: EngineAccount, size: CGFloat) -> NSImage? {
        let asset = engine.provider == .claude ? "claude" : "openai"
        guard let url = try? ThemeResources.agentLogo(asset), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: size, height: size)
        return image
    }

    @ViewBuilder var assistant: some View {
        let engines = model.agents?.engines ?? []
        let selected = engines.first { $0.provider.rawValue == model.values.agentProvider }
        card {
            row("사용할 에이전트") {
                ValuePopup(label: "사용할 에이전트", value: selected?.name ?? "Claude",
                           dot: selected.flatMap { logoImage($0, size: theme.component(.iconLarge)) },
                           theme: theme, inSettings: true) {
                    let menu = NSMenu()
                    menu.autoenablesItems = false
                    for engine in engines {
                        let item = menu.addItem(withTitle: engine.name, action: nil, keyEquivalent: "")
                        item.representedObject = engine.provider.rawValue
                        item.isEnabled = engine.status == .connected && engine.activity == nil
                        item.state = engine === selected ? .on : .off
                        item.view = PickerMenuRow(theme: theme, text: engine.name,
                            dot: logoImage(engine, size: theme.component(.iconLarge)), selected: engine === selected)
                    }
                    return menu
                } choose: { item in
                    guard let engine = engines.first(where: { $0.provider.rawValue == item.representedObject as? String }),
                          engine.status == .connected, engine.activity == nil else { return }
                    model.change { $0.agentProvider = engine.provider.rawValue }
                }
            }
            modelPicker
        }
        card("에이전트") {
            ForEach(engines, id: \.provider) { engine in
                Button {
                    model.detailEngine = engine
                    model.showsInstallTip = false
                    model.pane = .accounts
                } label: {
                    HStack(spacing: theme.space(.sp3)) {
                        logo(engine)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(engine.name)
                            Text(engine.company).font(valueFont).foregroundStyle(theme.color(.text3))
                        }
                        Spacer()
                        Text(engine.detail).font(valueFont).foregroundStyle(theme.color(engine.status == .expired ? .warn : .text3))
                        Image(systemName: "chevron.right").font(valueFont).foregroundStyle(theme.color(.text3))
                    }.frame(height: theme.component(.settingsTop)).contentShape(Rectangle())
                }.buttonStyle(RowHoverStyle(theme: theme))
            }
        }
    }

    private var modelPicker: some View {
        let isCodex = model.values.agentProvider == "codex"
        let available = model.agents?.engines.first { $0.provider == .codex }?.models ?? []
        let options: [(id: String?, title: String)] = isCodex
            ? [(nil, "CLI 기본")] + available.map { ($0.slug, $0.displayName) }
            : [(nil, "자동"), ("fable", "Fable"), ("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku")]
        let saved = model.values.selectedEngine(codexModels: available).model
        let selected = options.first { $0.id == saved } ?? options[0]
        return row("모델") {
            ValuePopup(label: "모델", value: selected.title, theme: theme, inSettings: true) {
                let menu = NSMenu()
                menu.autoenablesItems = false
                for (index, option) in options.enumerated() {
                    if index == 1 { menu.addItem(.separator()) }
                    let item = menu.addItem(withTitle: option.title, action: nil, keyEquivalent: "")
                    item.representedObject = option.id
                    item.state = option.id == selected.id ? .on : .off
                    item.view = PickerMenuRow(theme: theme, text: option.title, dot: nil, selected: item.state == .on,
                                              width: theme.component(isCodex ? .codexMenuWidth : .claudeMenuWidth))
                }
                return menu
            } choose: { item in
                let value = item.representedObject as? String
                model.change {
                    if isCodex { $0.codexModel = value }
                    else { $0.agentModel = value ?? "auto" }
                }
            }
        }
    }

    @ViewBuilder func accountDetail(_ engine: EngineAccount) -> some View {
        if engine.status == .expired && engine.activity == nil {
            HStack(spacing: theme.space(.sp3)) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.color(.warn))
                Text("로그인이 만료됐어요")
                Spacer()
                actionButton("다시 로그인") { engine.login() }
            }.padding(.horizontal, theme.space(.sp3)).frame(height: theme.component(.settingsBannerH))
                .background(theme.color(.warn).opacity(theme.rgba(.connectFill).alpha),
                            in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
        }
        card {
            if engine.activity != nil {
                row("계정") {
                    HStack(spacing: theme.space(.sp1)) {
                        ProgressView().controlSize(.small)
                        Text(engine.detail)
                    }.foregroundStyle(theme.color(.text2))
                }
            } else if engine.status == .connected || engine.status == .expired {
                if let email = engine.account?.email { infoRow("계정", email) }
                else if engine.status == .expired || engine.provider == .claude { infoRow("계정", "확인할 수 없음") }
                if let plan = engine.account?.subscription ?? engine.account?.tier { infoRow("요금제", plan.capitalized) }
                else if engine.status == .expired { infoRow("요금제", "확인할 수 없음") }
                if engine.status == .connected, let method = engine.account?.method {
                    infoRow("로그인 방식", method == "claude.ai" ? "Claude 구독" : method)
                }
            } else {
                infoRow("계정", engine.status == .missing ? "설치 안 됨" : engine.detail)
            }
        }
        HStack {
            Spacer()
            if engine.activity == .login {
                actionButton("취소") { engine.cancel() }
            } else if engine.activity == nil {
                if engine.status == .connected { actionButton("로그아웃") { engine.logout() } }
                if engine.status == .signedOut { actionButton("연결") { engine.login() } }
            }
        }.frame(height: engine.activity == nil && engine.status == .missing ? 0 : nil)
        if engine.status == .missing { installCard(engine) }
        if let error = engine.message { Text(error).font(valueFont).foregroundStyle(theme.color(.warn)) }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        row(title) { Text(verbatim: value).foregroundStyle(theme.color(.text2)).textSelection(.enabled) }
    }

    private func installCard(_ engine: EngineAccount) -> some View {
        let claude = engine.provider == .claude
        let command = claude ? "curl -fsSL https://claude.ai/install.sh | bash" : "npm install -g @openai/codex"
        let guide = claude ? "https://code.claude.com/docs/en/setup" : "https://github.com/openai/codex#installing-and-running-codex-cli"
        let tooltipInk = theme.tokens.color(.surface, .light).color
        let tooltipFill = theme.tokens.color(.text, .light).color
        let tipOffset = theme.component(.iconLarge) + theme.space(.sp1)
        let tip = "설치가 끝나면 이 화면이 알아서 바뀌어요"
        return VStack(alignment: .leading, spacing: theme.space(.sp2)) {
            HStack(spacing: theme.space(.sp1)) {
                Text("터미널에서 실행")
                Image(systemName: "info.circle").foregroundStyle(theme.color(.text3))
                    .frame(width: theme.component(.iconLarge), height: theme.component(.iconLarge))
                    .onHover { model.showsInstallTip = $0 }.accessibilityLabel(tip)
                    .overlay(alignment: .bottom) {
                        if model.showsInstallTip {
                            VStack(spacing: 0) {
                                Text(tip).font(valueFont).foregroundStyle(tooltipInk).fixedSize()
                                    .padding(.horizontal, theme.space(.sp2)).padding(.vertical, theme.component(.settingsPopupGap))
                                    .background(tooltipFill, in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
                                Rectangle().fill(tooltipFill).frame(width: theme.component(.settingsTipTail), height: theme.component(.settingsTipTail))
                                    .rotationEffect(.degrees(45)).padding(.top, -theme.component(.settingsTipTail) / 2)
                            }.fixedSize().offset(y: -tipOffset).allowsHitTesting(false)
                        }
                    }
            }.zIndex(1)
            HStack {
                Text(verbatim: command).font(theme.font(.codeBlock))
                Spacer()
                ChromeIconButton(theme: theme, title: "설치 명령 복사", symbol: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }.padding(.leading, theme.component(.codeBlockPaddingX)).padding(.trailing, theme.component(.codeBlockGap))
                .frame(height: theme.component(.installCommandHeight))
                .background(theme.color(.codeBlockBackground), in: RoundedRectangle(cornerRadius: theme.shape(.codeBlockRadius)))
            if let url = URL(string: guide) {
                TextActionLink(theme: theme, title: "다른 설치 방법", symbol: "arrow.up.right") { openURL(url) }
                    .accessibilityAddTraits(.isLink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(theme.space(.sp3)).background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
    }
}
