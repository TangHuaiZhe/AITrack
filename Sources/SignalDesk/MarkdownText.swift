import SwiftUI

enum MarkdownTextParser {
    static func parse(_ markdown: String) -> AttributedString {
        let blockAwareMarkdown = markdown
            .components(separatedBy: .newlines)
            .map { line in
                if let heading = line.range(of: #"^\s{0,3}#{1,6}\s+(.+?)\s*$"#, options: .regularExpression) {
                    let content = String(line[heading]).replacingOccurrences(
                        of: #"^\s{0,3}#{1,6}\s+|\s+$"#,
                        with: "",
                        options: .regularExpression
                    )
                    return "**\(content)**"
                }
                return line
            }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: blockAwareMarkdown, options: options))
            ?? AttributedString(blockAwareMarkdown)
    }
}

struct MarkdownText: View {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        Text(MarkdownTextParser.parse(markdown))
    }
}
