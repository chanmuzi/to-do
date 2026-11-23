import Models
import SwiftUI

struct ScheduleProposalPreview: View {
    let theme: Theme
    let note: Note?
    let proposed: ScheduleItem
    let pending: Bool
    let full: Bool

    private func time(_ item: ScheduleItem) -> String {
        ReminderPresentation(item: item, now: Date(), options: .init(), calendar: .current).text ?? ""
    }

    var body: some View {
        let item = note?.schedules.first { $0.id == proposed.id } ?? proposed
        VStack(spacing: theme.space(.sp3)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: theme.space(.sp1)) {
                    Text(note?.title ?? "제목 없음").lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: theme.component(.badgeGap)) {
                        Circle().fill(theme.color(.warn)).frame(width: theme.component(.badgeDot), height: theme.component(.badgeDot))
                        Text(time(item)).font(theme.libraryNumberFont).lineLimit(1)
                    }.layoutPriority(1).padding(.horizontal, theme.component(.badgePad)).frame(height: theme.component(.badgeHeight))
                        .background(theme.color(pending ? .diffAdd : .surface2), in: RoundedRectangle(cornerRadius: theme.shape(.chipRadius)))
                }.padding(.horizontal, theme.space(.sp3)).frame(minHeight: theme.shape(.chromeHeight))
                if full, let note, !note.body.isEmpty {
                    Divider()
                    ProposalNoteBody(theme: theme, markdown: note.body).padding(.vertical, theme.space(.sp2))
                }
            }.background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))

            VStack(alignment: .leading, spacing: 0) {
                Text("다가오는 일정").font(theme.font(.rowSub)).foregroundStyle(theme.color(.text3))
                    .padding(.horizontal, theme.space(.sp3))
                if full, let other = note?.schedules.first(where: { $0.id != item.id && $0.isUpcoming(at: Date()) }) {
                    upcoming(other, added: false)
                }
                upcoming(item, added: pending)
                if item.syncError != nil {
                    Text("외부 연동 실패, 앱에 저장됨").foregroundStyle(theme.color(.warn)).padding(.horizontal, theme.space(.sp3))
                }
            }.padding(.vertical, theme.space(.sp2))
                .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
        }
    }

    private func upcoming(_ item: ScheduleItem, added: Bool) -> some View {
        HStack(spacing: theme.space(.sp1)) {
            Text(added ? "+" : "").frame(width: theme.component(.proposalGutter))
            ScheduleMarker(item: item, destination: nil, theme: theme)
            Text(item.title).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            Text(time(item)).font(theme.libraryNumberFont).lineLimit(1)
                .foregroundStyle(theme.color(.text3)).layoutPriority(1)
        }.padding(.trailing, theme.space(.sp3)).frame(minHeight: theme.component(.proposalLineHeight))
            .background(added ? theme.color(.diffAdd) : .clear)
    }
}
