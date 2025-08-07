import SwiftUI

struct MarkdownText: View {
    let markdown: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown(markdown), id: \.id) { element in
                renderElement(element)
            }
        }
    }
    
    private func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = text.components(separatedBy: .newlines)
        var currentIndex = 0
        var isInCodeBlock = false
        var currentCodeLines: [String] = []
        var codeLanguage: String? = nil
        
        func flushCodeBlock() {
            if !currentCodeLines.isEmpty {
                let codeContent = currentCodeLines.joined(separator: "\n")
                elements.append(
                    MarkdownElement(
                        id: currentIndex,
                        type: .codeBlock,
                        content: codeContent,
                        extra: codeLanguage
                    )
                )
                currentCodeLines.removeAll()
                codeLanguage = nil
                currentIndex += 1
            }
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    // End of code block
                    flushCodeBlock()
                    isInCodeBlock = false
                } else {
                    // Start of code block
                    isInCodeBlock = true
                    // Capture language if provided after ```
                    let lang = trimmed.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    codeLanguage = lang.isEmpty ? nil : lang
                }
                continue
            }
            
            if isInCodeBlock {
                currentCodeLines.append(line)
                continue
            }
            
            if trimmed.isEmpty {
                elements.append(MarkdownElement(id: currentIndex, type: .spacing))
            } else if trimmed.hasPrefix("# ") {
                elements.append(MarkdownElement(id: currentIndex, type: .header1, content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("## ") {
                elements.append(MarkdownElement(id: currentIndex, type: .header2, content: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("### ") {
                elements.append(MarkdownElement(id: currentIndex, type: .header3, content: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                elements.append(MarkdownElement(id: currentIndex, type: .bulletPoint, content: String(trimmed.dropFirst(2))))
            } else {
                elements.append(MarkdownElement(id: currentIndex, type: .paragraph, content: trimmed))
            }
            currentIndex += 1
        }
        // Flush any trailing code block (if file ended without closing)
        if isInCodeBlock {
            flushCodeBlock()
        }
        return elements
    }
    
    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element.type {
        case .header1:
            Text(element.content ?? "")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 8)
                
        case .header2:
            Text(element.content ?? "")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 6)
                
        case .header3:
            Text(element.content ?? "")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 4)
                
        case .paragraph:
            Text(element.content ?? "")
                .font(.body)
                .lineLimit(nil)
                
        case .bulletPoint:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body)
                Text(element.content ?? "")
                    .font(.body)
                    .lineLimit(nil)
                Spacer(minLength: 0)
            }
            
        case .codeBlock:
            VStack(alignment: .leading, spacing: 0) {
                if let lang = element.extra, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(element.content ?? "")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                }
            }
                
        case .spacing:
            Spacer()
                .frame(height: 4)
        }
    }
    

}

struct MarkdownElement {
    let id: Int
    let type: MarkdownElementType
    let content: String?
    let extra: String?
    
    init(id: Int, type: MarkdownElementType, content: String? = nil, extra: String? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.extra = extra
    }
}

enum MarkdownElementType {
    case header1
    case header2
    case header3
    case paragraph
    case bulletPoint
    case codeBlock
    case spacing
}