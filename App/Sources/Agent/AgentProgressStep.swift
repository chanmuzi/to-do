import Foundation
import Models
import Theme

extension AgentRequest.Step.Kind {
    var face: AgentFaceState {
        switch self { case .think: .think; case .search: .search; case .read: .read; case .write: .write }
    }
}

extension AgentRequest.Step {
    enum Phase { case active, completed, stopped, failed }

    func phase(in status: AgentRequest.Status, last: Bool) -> Phase {
        switch result {
        case "실패": return .failed
        case "중단": return .stopped
        case "완료": return .completed
        default: break
        }
        // 옛 기록은 실행을 끝낼 때 열린 단계에도 종료 시각만 붙였다.
        if endedAt == nil || last || callID != nil {
            if status == .interrupted { return .stopped }
            if status == .failed { return .failed }
        }
        return endedAt == nil && status == .running ? .active : .completed
    }

    func title(for phase: Phase) -> String {
        let note = noteTitle ?? "노트"
        switch phase {
        case .active: return kind == .read && noteTitle != nil ? note + " 읽는 중" : kind.face.rawValue
        case .completed:
            switch kind {
            case .think: return "생각함"
            case .search: return "노트 찾음"
            case .read: return note + " 읽음"
            case .write: return "답 작성"
            }
        case .stopped, .failed:
            let action = switch kind {
            case .think: "생각"
            case .search: "노트 찾기"
            case .read: note + " 읽기"
            case .write: "답 작성"
            }
            return action + (phase == .failed ? " 실패" : " 중단")
        }
    }

    var durationLabel: String? {
        guard let elapsed, elapsed.isFinite, elapsed > 0 else { return nil }
        if elapsed < 60 {
            let tenths = (elapsed * 10).rounded()
            guard tenths > 0 else { return nil }
            return String(format: "%.1f초", tenths / 10)
        }
        guard let seconds = Int(exactly: elapsed.rounded()) else { return nil }
        let remainder = seconds % 60
        return "\(seconds / 60)분" + (remainder == 0 ? "" : " \(remainder)초")
    }
}
