/// 요청을 보낸 뒤 받는 답. 보낸 쪽은 이것으로 닫을지, 적던 글을 둘지, 포커스를 돌려줄지 정한다.
public enum RouteResult: Hashable, Sendable {
    /// 그 일을 했다.
    case handled
    /// 하려 했으나 하지 못했다(노트를 만들지 못함, 파일이 없어짐). 사용자에게 알리는 일은 받은 쪽이 이미 했다.
    case failed
    /// 그 일을 하는 화면이 아직 이어져 있지 않다. 아무 일도 일어나지 않았다.
    case unconnected
}

/// 기능 사이 요청을 받는 쪽. 구현은 App 타깃이 한다.
@MainActor
public protocol Routing: AnyObject {
    /// 요청을 보낸다. 받은 쪽이 일을 마친 뒤(실패를 알리는 알림 창이 닫힌 뒤)에 돌아온다.
    @discardableResult
    func route(_ route: Route) -> RouteResult

    /// 그 요청을 받아 일하는 화면이 이어져 있는지. 기능 모듈은 이어지지 않은 요청을 보내는 줄이나 메뉴 항목을
    /// 보이지 않거나 고를 수 없게 둔다(눌러도 아무 일이 없는 것을 내놓지 않는다).
    func isConnected(_ route: Route) -> Bool
}

/// 클로저로 요청을 넘기는 기본 구현. App이 조립할 때, 그리고 테스트에서 쓴다.
@MainActor
public final class RouteDispatcher: Routing {
    private let connected: @MainActor (Route) -> Bool
    private let handler: @MainActor (Route) -> RouteResult

    /// 모든 요청이 이어져 있고 언제나 해낸 것으로 답한다.
    public convenience init(handler: @escaping @MainActor (Route) -> Void) {
        self.init(isConnected: { _ in true }, answering: {
            handler($0)
            return .handled
        })
    }

    /// - Parameters:
    ///   - isConnected: 이어져 있는 요청인지.
    ///   - handler: 요청을 받아 답을 돌려준다.
    public init(
        isConnected: @escaping @MainActor (Route) -> Bool = { _ in true },
        answering handler: @escaping @MainActor (Route) -> RouteResult
    ) {
        connected = isConnected
        self.handler = handler
    }

    @discardableResult
    public func route(_ route: Route) -> RouteResult {
        handler(route)
    }

    public func isConnected(_ route: Route) -> Bool {
        connected(route)
    }
}
