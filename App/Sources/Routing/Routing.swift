/// 기능 사이 요청을 받는 쪽. 구현은 App 타깃이 한다.
@MainActor
public protocol Routing: AnyObject {
    func route(_ route: Route)
}

/// 클로저 하나로 요청을 넘기는 기본 구현. App이 조립할 때, 그리고 테스트에서 쓴다.
@MainActor
public final class RouteDispatcher: Routing {
    private let handler: @MainActor (Route) -> Void

    public init(handler: @escaping @MainActor (Route) -> Void) {
        self.handler = handler
    }

    public func route(_ route: Route) {
        handler(route)
    }
}
