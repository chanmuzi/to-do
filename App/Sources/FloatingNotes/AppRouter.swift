import Foundation
import Routing

/// 기능 모듈이 보낸 요청을 받아 창을 띄우는 곳.
/// 지금은 화면이 없어 요청을 기록만 한다. 기능 모듈이 생기면 case마다 그 모듈을 부른다.
final class AppRouter: Routing {
    private(set) var unhandled: [Route] = []

    func route(_ route: Route) {
        unhandled.append(route)
        FileHandle.standardError.write(Data("AppRouter: 아직 연결되지 않은 요청입니다: \(route)\n".utf8))
    }
}
