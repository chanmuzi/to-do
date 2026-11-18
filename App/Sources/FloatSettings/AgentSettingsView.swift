import SwiftUI
import Theme

extension SettingsView {
    var assistant: some View {
        card("엔진") {
            Button { model.pane = .accounts } label: {
                row("엔진과 계정", "Float 전용 계정으로 CLI 연결") {
                    let selected = model.agents?.engines.first { $0.provider.rawValue == model.values.agentProvider }
                    HStack(spacing: theme.space(.sp1)) {
                        Text(selected?.name ?? "Claude")
                        Image(systemName: "chevron.right").font(.system(size: theme.component(.settingsCloseIcon)))
                    }.font(valueFont).foregroundStyle(theme.color(.text2))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            setting("모델", "Claude가 사용할 기본 모델", \.agentModel,
                    [("auto", "자동"), ("opus", "opus"), ("sonnet", "sonnet"), ("haiku", "haiku")])
        }
    }

    var accounts: some View {
        card {
            ForEach(model.agents?.engines ?? [], id: \.provider) { engine in
                row(engine.name, engine.detail) {
                    HStack(spacing: theme.space(.sp1)) {
                        if let activity = engine.activity {
                            if activity != .checking { textButton("취소") { engine.cancel() } }
                        } else {
                            switch engine.status {
                            case .signedOut:
                                textButton("연결") { engine.login() }
                            case .connected:
                                if model.values.agentProvider == engine.provider.rawValue {
                                    Text("사용 중").font(valueFont).foregroundStyle(theme.color(.text2))
                                } else {
                                    textButton("고르기") { model.change { $0.agentProvider = engine.provider.rawValue } }
                                }
                                textButton("시험") { engine.testConnection() }
                            default: EmptyView()
                            }
                            textButton("다시 확인") { engine.refresh() }
                        }
                    }.fixedSize()
                }
            }
        }.onAppear { model.agents?.refresh() }
    }
}
