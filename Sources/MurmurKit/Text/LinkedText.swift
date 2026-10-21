import Foundation

/// Text holding linked snippets in their plain form, cut back into runs of plain and linked
/// text for the clipboard's rich flavours.
///
/// The pipeline writes "my calendar (https://…)" and records the link; only insertion knows
/// whether the app can show a link instead. The plain form contains the address, so finding
/// it again can't pick up the same words said elsewhere in the dictation.
public enum LinkedText {
    public struct Run: Equatable, Sendable {
        public var text: String
        /// What `text` opens; `nil` for ordinary text.
        public var url: String?

        public init(_ text: String, url: String? = nil) {
            self.text = text
            self.url = url
        }
    }

    /// `text` in order, each occurrence of a link's plain form replaced by its linked text.
    public static func runs(in text: String, links: [SnippetLink]) -> [Run] {
        let links = links.filter { !$0.text.isEmpty && !$0.url.isEmpty }
        guard !links.isEmpty else { return text.isEmpty ? [] : [Run(text)] }
        var runs: [Run] = []
        var rest = text[...]
        while !rest.isEmpty {
            // The earliest match wins; at the same place, the longer plain form.
            var best: (range: Range<Substring.Index>, link: SnippetLink)?
            for link in links {
                guard let range = rest.range(of: link.plain) else { continue }
                if let current = best {
                    if range.lowerBound > current.range.lowerBound { continue }
                    if range.lowerBound == current.range.lowerBound, link.plain.count <= current.link.plain.count {
                        continue
                    }
                }
                best = (range, link)
            }
            guard let best else {
                runs.append(Run(String(rest)))
                break
            }
            if best.range.lowerBound > rest.startIndex {
                runs.append(Run(String(rest[rest.startIndex..<best.range.lowerBound])))
            }
            runs.append(Run(best.link.text, url: best.link.url))
            rest = rest[best.range.upperBound...]
        }
        return runs
    }

    /// Whether any run is a link.
    public static func hasLinks(_ runs: [Run]) -> Bool {
        runs.contains { $0.url != nil }
    }

    /// The runs as an HTML fragment for the clipboard: escaped, with line breaks kept.
    /// Unstyled, so a page or editor pastes it in the style around the caret.
    public static func html(_ runs: [Run]) -> String {
        var html = "<meta charset=\"utf-8\">"
        for run in runs {
            let body = escape(run.text).replacingOccurrences(of: "\n", with: "<br>")
            if let url = run.url {
                html += "<a href=\"\(escape(url))\">\(body)</a>"
            } else {
                html += body
            }
        }
        return html
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
