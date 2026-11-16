import Testing
import Models
import Routing

@Suite @MainActor struct RoutingTests {
    @Test func dispatcherForwardsRoutesInOrder() {
        var received: [Route] = []
        let router: any Routing = RouteDispatcher { received.append($0) }
        let id = NoteID(rawValue: "a")

        router.route(.openNote(id))
        router.route(.newNote(NewNoteRequest(draft: NoteDraft(title: "새 노트"), nextTo: id)))
        router.route(.openBrowse(anchor: nil))

        #expect(received == [
            .openNote(id),
            .newNote(NewNoteRequest(draft: NoteDraft(title: "새 노트"), nextTo: id)),
            .openBrowse(anchor: nil),
        ])
    }
}

extension RoutingTests {
    /// 클로저 하나로 만든 것은 모든 요청이 이어져 있고 해낸 것으로 답한다.
    @Test func plainDispatcherAnswersHandled() {
        let router: any Routing = RouteDispatcher { _ in }
        #expect(router.route(.openLibrary) == .handled)
        #expect(router.isConnected(.openLibrary))
    }

    /// 보낸 쪽이 답(해냄, 하지 못함, 이어지지 않음)과 이어져 있는지를 받아 볼 수 있다.
    @Test func dispatcherReportsResultsAndConnections() {
        let missing = NoteID(rawValue: "missing")
        let router: any Routing = RouteDispatcher(
            isConnected: { $0 != .openLibrary },
            answering: { route in
                switch route {
                case .openLibrary: .unconnected
                case .openNote(missing): .failed
                default: .handled
                }
            }
        )
        #expect(router.route(.openNote(NoteID(rawValue: "a"))) == .handled)
        #expect(router.route(.openNote(missing)) == .failed)
        #expect(router.route(.openLibrary) == .unconnected)
        #expect(!router.isConnected(.openLibrary))
        #expect(router.isConnected(.openCapture))
    }
}
