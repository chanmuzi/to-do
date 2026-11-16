/// 노트를 디스크에 쓰지 못하고 있는 까닭. 상단 줄에 표시 하나로 알린다.
enum NoteProblem: Hashable {
    /// 다른 프로그램이 파일을 고쳤다. 사용자가 고를 때까지 쓰지 않는다. 이 앱에서 고친 글은 그대로 보인다.
    case conflict
    case saveFailed(message: String)
    /// 다른 프로그램이 노트 파일을 지웠다(Finder, 동기화 도구, `git checkout`). 쓰지 못한 글이 창에 남아 있다.
    /// 새 노트로 저장하거나 버릴 때까지 창을 닫지 않는다.
    case fileMissing

    var accessibilityLabel: String {
        switch self {
        case .conflict: "다른 프로그램이 이 노트를 고쳤습니다"
        case .saveFailed: "저장하지 못했습니다"
        case .fileMissing: "노트 파일이 없어졌습니다"
        }
    }
}
