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
