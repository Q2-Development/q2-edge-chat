//https://pastebin.com/Rv6XAPmY
//bc textfield is for one line inputs
//and texteditor is trash by default

import SwiftUI
 
struct ManagedTextView: UIViewRepresentable {
    typealias UIViewType = UITextView
 
    @Binding var text: String
    let textDidChange: ((UITextView) -> Void)?
    
    init(text: Binding<String>, textDidChange: ((UITextView) -> Void)? = nil) {
        self.textDidChange = textDidChange
        self._text = text
    }
 
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = true
        view.delegate = context.coordinator
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        return view
    }
 
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = self.text
        DispatchQueue.main.async {
            self.textDidChange?(uiView)
        }
    }
 
    func makeCoordinator() -> Coordinator {
        return Coordinator(text: $text, textDidChange: textDidChange)
    }
 
    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        let textDidChange: ((UITextView) -> Void)?
 
        init(text: Binding<String>, textDidChange: ((UITextView) -> Void)?) {
            self._text = text
            self.textDidChange = textDidChange
        }
 
        func textViewDidChange(_ textView: UITextView) {
            self.text = textView.text
            self.textDidChange?(textView)
        }
    }
}
 
struct DynamicTextEditor: View {
    @Environment(\.verticalSizeClass) private var verticalSize
    @Binding var text: String
    
    private let minHeight: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize
    @State private var currentHeight: CGFloat?
    let maxHeight: CGFloat?
    let maxHeightCompact: CGFloat?
    let placeholder: String?
    
    private let placeholderPadding: CGFloat = 4
    
    init(text: Binding<String>, placeholder: String? = nil, maxHeight: CGFloat? = nil, maxHeightCompact: CGFloat? = nil) {
        self._text = text
        self.maxHeight = maxHeight
        self.maxHeightCompact = maxHeightCompact
        self.placeholder = placeholder
    }
    
    var body: some View {
        ManagedTextView(text: $text, textDidChange: textDidChange(_:))
            .frame(height: frameHeight)
            .background(Text(placeholder ?? "")
                .foregroundColor(placeholder?.isEmpty ?? true ? Color.secondary.opacity(0.5) : Color.secondary)
            .opacity(text.count == 0 ? 1.0 : 0)
            .padding(.leading, placeholderPadding),
                        alignment: .leading)
    }
    
    private var frameHeight: CGFloat {
        if verticalSize == .compact, let maxHeightCompact = maxHeightCompact {
            return min(currentHeight ?? minHeight, maxHeightCompact)
        } else if let maxHeight = maxHeight {
            return min(currentHeight ?? minHeight, maxHeight)
        } else {
            return currentHeight ?? minHeight
        }
    }
    
    private func textDidChange(_ textView: UITextView) {
        currentHeight = textView.contentSize.height
    }
}
