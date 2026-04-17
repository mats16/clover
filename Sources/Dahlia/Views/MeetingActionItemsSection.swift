import SwiftUI

struct MeetingActionItemsSection: View {
    @ObservedObject var viewModel: CaptionViewModel

    var body: some View {
        let actionItems = viewModel.orderedCurrentMeetingActionItems

        if !actionItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.actionItems)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(actionItems) { actionItem in
                        MeetingActionItemRow(actionItem: actionItem, viewModel: viewModel)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
