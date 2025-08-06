import SwiftUI

struct DynamicTextEditor: View {
    @Binding var text: String
    let placeholder: String?
    let maxHeight: CGFloat?
    let maxHeightCompact: CGFloat?
    
    @Environment(\.verticalSizeClass) private var verticalSize
    @State private var textHeight: CGFloat = 0
    
    init(text: Binding<String>, placeholder: String? = "Type a message...", maxHeight: CGFloat? = 120, maxHeightCompact: CGFloat? = 80) {
        self._text = text
        self.placeholder = placeholder
        self.maxHeight = maxHeight
        self.maxHeightCompact = maxHeightCompact
    }
    
    private var currentMaxHeight: CGFloat {
        if verticalSize == .compact, let maxHeightCompact = maxHeightCompact {
            return maxHeightCompact
        } else if let maxHeight = maxHeight {
            return maxHeight
        } else {
            return 120
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                Text(placeholder ?? "Type a message...")
                    .foregroundColor(Color.secondary.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            
            // TextEditor
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 36, maxHeight: currentMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}