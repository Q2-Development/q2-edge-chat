import SwiftUI

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer()
            } else {
                Spacer()
                bubble.foregroundColor(.white)
                    .background(Color.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    private var bubble: some View {
        Text(message.text)
            .padding(10)
            .background(Color(.systemGray5))
            .cornerRadius(12)
    }
}
