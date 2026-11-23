import Foundation

/// 접수 폴더에는 실행 원문 대신 사용자가 보낸 메시지와 지침 스냅숏의 지문만 둔다.
package struct InstructionEvidence: Codable, Sendable {
    package static let filename = ".instruction-context"
    let message: String
    let document: String
    let requestID: UUID

    package init(request: AgentRequest, instructions: String) {
        message = TodoSubmission.fingerprint(Data(request.userText.utf8))
        document = TodoSubmission.fingerprint(Data(instructions.utf8))
        requestID = request.id
    }

    package func validate(_ args: ProposalArguments, for request: AgentRequest? = nil) throws {
        guard let quote = args.user_message, !quote.isEmpty else { throw ProposalArguments.Invalid.missingMessage }
        guard TodoSubmission.fingerprint(Data(quote.utf8)) == message else { throw ProposalArguments.Invalid.evidence }
        guard let before = args.before, TodoSubmission.fingerprint(Data(before.utf8)) == document else {
            throw ProposalArguments.Invalid.instructionBase
        }
        if let request {
            guard request.id == requestID, request.userText.utf8.elementsEqual(quote.utf8) else {
                throw ProposalArguments.Invalid.evidence
            }
        }
    }
}
