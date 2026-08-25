// RulesText.swift
// A small lossless document model for the rules file's JSON5 subset, so the
// GUI editor can save WITHOUT destroying hand-written comments (ADR 0003).
// parse() keeps comments attached to the members they precede; print() emits
// them back; encode(_:preserving:) rebuilds only what the editor changed —
// an untouched rule keeps its text (inner comments included), an edited rule
// keeps its leading comments, and everything outside `targets` is untouched.
// In coverage. Imports only Foundation.

import Foundation

/// Comment-preserving parsing, printing, and merging of the rules file.
enum RulesText {

    /// A parsed file: comments above the root, the root value, comments below.
    struct Document: Equatable {
        var leading: [String]
        var root: Node
        var trailing: [String]
    }

    /// One JSON5 value with its comment-carrying structure.
    indirect enum Node: Equatable {
        case object([Member], trailing: [String])
        case array([Element], trailing: [String])
        /// Verbatim text of a string, number, boolean, or null.
        case scalar(String)
    }

    /// An object member and the comments written above it.
    struct Member: Equatable {
        var comments: [String]
        /// The key exactly as written — quoted or bare.
        var key: String
        var value: Node
    }

    /// An array element and the comments written above it.
    struct Element: Equatable {
        var comments: [String]
        var value: Node
    }

    // MARK: - Parse

    /// Parse `text`, or nil when it is not well-formed enough to edit safely.
    static func parse(_ text: String) -> Document? {
        let chars = Array(text)
        var index = 0
        guard let leading = skipTrivia(chars, &index) else { return nil }
        guard let root = parseValue(chars, &index) else { return nil }
        guard let trailing = skipTrivia(chars, &index) else { return nil }
        guard index >= chars.count else { return nil }
        return Document(leading: leading, root: root, trailing: trailing)
    }

    /// Consume whitespace and comments, returning the comments verbatim; nil
    /// means an unterminated block comment.
    private static func skipTrivia(_ chars: [Character], _ index: inout Int) -> [String]? {
        var comments: [String] = []
        while index < chars.count {
            let char = chars[index]
            if char == " " || char == "\t" || char == "\n" || char == "\r" {
                index += 1
                continue
            }
            if char == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                var line = ""
                while index < chars.count, chars[index] != "\n" {
                    line.append(chars[index])
                    index += 1
                }
                comments.append(line)
                continue
            }
            if char == "/", index + 1 < chars.count, chars[index + 1] == "*" {
                var block = "/*"
                index += 2
                var closed = false
                while index < chars.count {
                    if chars[index] == "*", index + 1 < chars.count, chars[index + 1] == "/" {
                        block += "*/"
                        index += 2
                        closed = true
                        break
                    }
                    block.append(chars[index])
                    index += 1
                }
                guard closed else { return nil }
                comments.append(block)
                continue
            }
            break
        }
        return comments
    }

    private static func parseValue(_ chars: [Character], _ index: inout Int) -> Node? {
        guard index < chars.count else { return nil }
        let char = chars[index]
        if char == "{" { return parseObject(chars, &index) }
        if char == "[" { return parseArray(chars, &index) }
        if char == "\"" || char == "'" { return parseString(chars, &index).map(Node.scalar) }
        return parseBareScalar(chars, &index)
    }

    /// A quoted string, verbatim including its quotes and escapes.
    private static func parseString(_ chars: [Character], _ index: inout Int) -> String? {
        let quote = chars[index]
        var out = String(quote)
        index += 1
        while index < chars.count {
            let char = chars[index]
            if char == "\\" {
                guard index + 1 < chars.count else { return nil }
                out.append(char)
                out.append(chars[index + 1])
                index += 2
                continue
            }
            out.append(char)
            index += 1
            if char == quote { return out }
        }
        return nil
    }

    /// A number / boolean / null / bare word, verbatim.
    private static func parseBareScalar(_ chars: [Character], _ index: inout Int) -> Node? {
        var out = ""
        while index < chars.count, !" \t\n\r,:{}[]/".contains(chars[index]) {
            out.append(chars[index])
            index += 1
        }
        return out.isEmpty ? nil : .scalar(out)
    }

    /// A member key: a quoted string or a bare identifier, verbatim.
    private static func parseKey(_ chars: [Character], _ index: inout Int) -> String? {
        if chars[index] == "\"" || chars[index] == "'" { return parseString(chars, &index) }
        var out = ""
        while index < chars.count, !" \t\n\r,:{}[]/".contains(chars[index]) {
            out.append(chars[index])
            index += 1
        }
        return out.isEmpty ? nil : out
    }

    private static func parseObject(_ chars: [Character], _ index: inout Int) -> Node? {
        index += 1
        var members: [Member] = []
        var pending: [String] = []
        while index < chars.count {
            guard let lead = skipTrivia(chars, &index) else { return nil }
            var comments = pending + lead
            pending = []
            guard index < chars.count else { break }
            if chars[index] == "}" {
                index += 1
                return .object(members, trailing: comments)
            }
            guard let key = parseKey(chars, &index) else { return nil }
            guard let mid = skipTrivia(chars, &index), index < chars.count, chars[index] == ":" else { return nil }
            comments += mid
            index += 1
            guard let pre = skipTrivia(chars, &index) else { return nil }
            comments += pre
            guard let value = parseValue(chars, &index) else { return nil }
            members.append(Member(comments: comments, key: key, value: value))
            guard let post = skipTrivia(chars, &index), index < chars.count else { break }
            if chars[index] == "," {
                index += 1
                pending = post
                continue
            }
            if chars[index] == "}" {
                index += 1
                return .object(members, trailing: post)
            }
            return nil
        }
        // The file ended inside the object.
        return nil
    }

    private static func parseArray(_ chars: [Character], _ index: inout Int) -> Node? {
        index += 1
        var elements: [Element] = []
        var pending: [String] = []
        while index < chars.count {
            guard let lead = skipTrivia(chars, &index) else { return nil }
            let comments = pending + lead
            pending = []
            guard index < chars.count else { break }
            if chars[index] == "]" {
                index += 1
                return .array(elements, trailing: comments)
            }
            guard let value = parseValue(chars, &index) else { return nil }
            elements.append(Element(comments: comments, value: value))
            guard let post = skipTrivia(chars, &index), index < chars.count else { break }
            if chars[index] == "," {
                index += 1
                pending = post
                continue
            }
            if chars[index] == "]" {
                index += 1
                return .array(elements, trailing: post)
            }
            return nil
        }
        // The file ended inside the array.
        return nil
    }

    // MARK: - Print

    /// Re-emit a document as normalized, comment-carrying JSON5.
    static func print(_ document: Document) -> String {
        var out = ""
        appendComments(document.leading, indent: 0, to: &out)
        append(document.root, indent: 0, to: &out)
        out.append("\n")
        appendComments(document.trailing, indent: 0, to: &out)
        return out
    }

    private static func pad(_ indent: Int) -> String {
        String(repeating: "  ", count: indent)
    }

    private static func appendComments(_ comments: [String], indent: Int, to out: inout String) {
        for comment in comments {
            for line in comment.split(separator: "\n", omittingEmptySubsequences: false) {
                out += pad(indent) + line.trimmingCharacters(in: .whitespaces) + "\n"
            }
        }
    }

    private static func append(_ node: Node, indent: Int, to out: inout String) {
        switch node {
        case .scalar(let text):
            out += text
        case .object(let members, let trailing):
            if members.isEmpty && trailing.isEmpty {
                out += "{}"
                return
            }
            out += "{\n"
            for member in members {
                appendComments(member.comments, indent: indent + 1, to: &out)
                out += pad(indent + 1) + member.key + ": "
                append(member.value, indent: indent + 1, to: &out)
                out += ",\n"
            }
            appendComments(trailing, indent: indent + 1, to: &out)
            out += pad(indent) + "}"
        case .array(let elements, let trailing):
            if elements.isEmpty && trailing.isEmpty {
                out += "[]"
                return
            }
            out += "[\n"
            for element in elements {
                appendComments(element.comments, indent: indent + 1, to: &out)
                out += pad(indent + 1)
                append(element.value, indent: indent + 1, to: &out)
                out += ",\n"
            }
            appendComments(trailing, indent: indent + 1, to: &out)
            out += pad(indent) + "]"
        }
    }

    // MARK: - Merge

    /// Encode `set` while preserving the comments and untouched text of
    /// `originalText`. Falls back to strict encoding when the original cannot
    /// be parsed (the editor is then the only surviving source anyway).
    static func encode(_ set: RuleSet, preserving originalText: String) -> Data {
        guard let document = parse(originalText), case .object(var members, let trailing) = document.root else {
            return RuleParser.encode(set)
        }
        let merged = mergedTargets(set.targets, original: memberValue(members, key: "targets"))
        if let existing = members.firstIndex(where: { keyName($0.key) == "targets" }) {
            members[existing].value = merged
        } else {
            members.append(Member(comments: [], key: "targets", value: merged))
        }
        var updated = document
        updated.root = .object(members, trailing: trailing)
        return Data(print(updated).utf8)
    }

    /// A key with its quotes (if any) stripped.
    private static func keyName(_ key: String) -> String {
        guard let first = key.first, first == "\"" || first == "'" else { return key }
        return String(key.dropFirst().dropLast())
    }

    private static func memberValue(_ members: [Member], key: String) -> Node? {
        members.first { keyName($0.key) == key }?.value
    }

    /// Decode a scalar string node into its Swift value.
    private static func stringValue(_ node: Node?) -> String? {
        guard case .scalar(let text)? = node else { return nil }
        return try? JSONDecoder().decode(String.self, from: Data(text.utf8))
    }

    private static func elements(of node: Node?) -> [Element] {
        guard case .array(let elements, _)? = node else { return [] }
        return elements
    }

    private static func arrayTrailing(of node: Node?) -> [String] {
        guard case .array(_, let trailing)? = node else { return [] }
        return trailing
    }

    private static func mergedTargets(_ targets: [Target], original: Node?) -> Node {
        let originals = elements(of: original)
        let merged = targets.map { target in
            mergedTarget(target, original: originals.first { path(of: $0.value) == target.path })
        }
        return .array(merged, trailing: arrayTrailing(of: original))
    }

    private static func path(of node: Node) -> String? {
        guard case .object(let members, _) = node else { return nil }
        return stringValue(memberValue(members, key: "path"))
    }

    private static func mergedTarget(_ target: Target, original: Element?) -> Element {
        guard let original, case .object(var members, let trailing) = original.value else {
            return Element(comments: original?.comments ?? [], value: fragment(target))
        }
        let rules = mergedRules(target.rules, original: memberValue(members, key: "rules"))
        if let existing = members.firstIndex(where: { keyName($0.key) == "rules" }) {
            members[existing].value = rules
        } else {
            members.append(Member(comments: [], key: "rules", value: rules))
        }
        return Element(comments: original.comments, value: .object(members, trailing: trailing))
    }

    private static func mergedRules(_ rules: [Rule], original: Node?) -> Node {
        let originals = elements(of: original)
        let merged = rules.map { rule -> Element in
            guard let match = originals.first(where: { id(of: $0.value) == rule.id }) else {
                return Element(comments: [], value: fragment(rule))
            }
            if decodedRule(match.value) == rule { return match }
            return Element(comments: match.comments, value: fragment(rule))
        }
        return .array(merged, trailing: arrayTrailing(of: original))
    }

    private static func id(of node: Node) -> String? {
        guard case .object(let members, _) = node else { return nil }
        return stringValue(memberValue(members, key: "id"))
    }

    /// The rule an original element's text decodes to, for change detection.
    private static func decodedRule(_ node: Node) -> Rule? {
        var text = ""
        append(node, indent: 0, to: &text)
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try? decoder.decode(Rule.self, from: Data(text.utf8))
    }

    /// Strict-encode a value and re-parse it into a node; our own encoder's
    /// output always parses, so the round-trip cannot fail.
    private static func fragment(_ value: some Encodable) -> Node {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try! encoder.encode(value)
        return parse(String(decoding: data, as: UTF8.self))!.root
    }
}
