import SwiftUI

struct MessageRow: View {
    let message: Message
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.speaker == .assistant {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Assistant")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    bubble(
                        color: Color(.systemGray6),
                        textColor: .primary,
                        alignment: .leading
                    )
                }
                .frame(maxWidth: .infinity * 0.75, alignment: .leading)
                
                Spacer()
            } else {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Spacer()
                        Text("You")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Image(systemName: "person.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    bubble(
                        color: Color.accentColor,
                        textColor: .white,
                        alignment: .trailing
                    )
                }
                .frame(maxWidth: .infinity * 0.75, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func bubble(color: Color, textColor: Color, alignment: HorizontalAlignment) -> some View {
        Text(message.text)
            .font(.body)
            .foregroundColor(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            )
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}
