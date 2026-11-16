/// 노트를 디스크에 쓰지 못하고 있는 까닭. 상단 줄에 표시 하나로 알린다.
enum NoteProblem: Hashable {
    /// 다른 프로그램이 파일을 고쳤다. 사용자가 고를 때까지 쓰지 않는다. 이 앱에서 고친 글은 그대로 보인다.
    case conflict
    case saveFailed(message: String)

    var accessibilityLabel: String {
        switch self {
        case .conflict: "다른 프로그램이 이 노트를 고쳤습니다"
        case .saveFailed: "저장하지 못했습니다"
        }
    }
}
