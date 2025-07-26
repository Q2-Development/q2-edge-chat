import SwiftUI

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack {
            if message.speaker == .assistant {
                bubble(color: Color(.systemGray5), textColor: .primary)
                Spacer()
            } else {
                Spacer()
                bubble(color: Color.accentColor, textColor: .white)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func bubble(color: Color, textColor: Color) -> some View {
        Text(message.text)
            .foregroundColor(textColor)
            .padding(10)
            .background(color)
            .cornerRadius(12)
    }
}
