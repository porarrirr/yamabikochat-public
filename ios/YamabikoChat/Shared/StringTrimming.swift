import Foundation

extension String {
    /// Trims whitespace/newlines; returns `nil` when the result is empty.
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Foundation removes Markdown syntax; keep a space between distinct blocks.
    var conversationPreview: String {
        guard let attributed = try? AttributedString(markdown: self) else { return self }
        var text = ""
        var previousIntent: PresentationIntent?
        for run in attributed.runs {
            if !text.isEmpty, previousIntent != run.presentationIntent { text += " " }
            text += String(attributed[run.range].characters)
            previousIntent = run.presentationIntent
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
