import SwiftUI

struct MessagesView: View {
    let messages: [Message]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(messages) { MessageRow(message: $0) }
            }
            .padding(.vertical)
        }
    }
}
