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
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty {
                elements.append(MarkdownElement(id: currentIndex, type: .spacing))
            } else if trimmed.hasPrefix("# ") {
                elements.append(MarkdownElement(id: currentIndex, type: .header1, content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("## ") {
                elements.append(MarkdownElement(id: currentIndex, type: .header2, content: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("### ") {
                elements.append(MarkdownElement(id: currentIndex, type: .header3, content: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("```") {
                elements.append(MarkdownElement(id: currentIndex, type: .codeBlock, content: trimmed))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                elements.append(MarkdownElement(id: currentIndex, type: .bulletPoint, content: String(trimmed.dropFirst(2))))
            } else {
                elements.append(MarkdownElement(id: currentIndex, type: .paragraph, content: trimmed))
            }
            
            currentIndex += 1
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
            Text(parseInlineMarkdown(element.content ?? ""))
                .font(.body)
                .lineLimit(nil)
                
        case .bulletPoint:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body)
                Text(parseInlineMarkdown(element.content ?? ""))
                    .font(.body)
                    .lineLimit(nil)
                Spacer(minLength: 0)
            }
            
        case .codeBlock:
            Text(element.content ?? "")
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
        case .spacing:
            Spacer()
                .frame(height: 4)
        }
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        
        let boldPattern = #/\*\*(.*?)\*\*/#
        let matches = text.matches(of: boldPattern)
        
        for match in matches.reversed() {
            let range = match.range
            let content = String(match.1)
            let startIndex = attributed.index(attributed.startIndex, offsetByCharacters: range.lowerBound.utf16Offset(in: text))
            let endIndex = attributed.index(attributed.startIndex, offsetByCharacters: range.upperBound.utf16Offset(in: text))
            
            attributed.replaceSubrange(startIndex..<endIndex, with: AttributedString(content))
            attributed[startIndex..<attributed.index(startIndex, offsetByCharacters: content.count)].font = .body.bold()
        }
        
        return attributed
    }
}

struct MarkdownElement {
    let id: Int
    let type: MarkdownElementType
    let content: String?
    
    init(id: Int, type: MarkdownElementType, content: String? = nil) {
        self.id = id
        self.type = type
        self.content = content
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