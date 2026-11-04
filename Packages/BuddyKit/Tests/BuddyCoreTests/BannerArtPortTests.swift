import Foundation
import Testing
@testable import BuddyCore

/// The Swift banner art must draw exactly what the Figma Make file draws. `design/banners/states`
/// holds SVG rendered from the Make file's own `IllustratedScene.tsx` for every banner × light ×
/// weather (at 2 of 5 done) and for every step of progress (daytime, sunny); this compares each,
/// element by element and attribute by attribute, with what `BannerArt` builds.
@Suite struct BannerArtPortTests {
    static let states: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("design/banners/states")

    @Test(arguments: BannerID.allCases)
    func everyLightAndWeatherMatchesTheMakeFile(banner: BannerID) throws {
        for time in BannerTimeOfDay.allCases {
            for weather in BannerWeather.allCases {
                let file = Self.states.appendingPathComponent("\(banner.rawValue)/\(time.rawValue)-\(weather.rawValue).svg")
                let state = BannerState(banner: banner, time: time, weather: weather, progress: .init(done: 2, total: 5))
                try Self.compare(file: file, with: BannerArt.document(state), label: "\(banner) \(time) \(weather)")
            }
        }
    }

    @Test(arguments: BannerID.allCases)
    func everyStepOfFiveMatchesTheMakeFile(banner: BannerID) throws {
        for done in 0...5 {
            let file = Self.states.appendingPathComponent("\(banner.rawValue)/progress/daytime-sunny-\(done)of5.svg")
            let state = BannerState(banner: banner, time: .daytime, weather: .sunny, progress: .init(done: done, total: 5))
            try Self.compare(file: file, with: BannerArt.document(state), label: "\(banner) \(done)/5")
        }
    }

    @Test func everyPathParses() throws {
        for banner in BannerID.allCases {
            for time in BannerTimeOfDay.allCases {
                for weather in BannerWeather.allCases {
                    for total in [0, 1, 3, 5, 8, 12, 40] {
                        let doc = BannerArt.document(.init(banner: banner, time: time, weather: weather,
                                                           progress: .init(done: total / 2, total: total)))
                        for node in Self.flatten(doc.art) + Self.flatten(doc.rail) + doc.defs.flatMap(Self.flatten) {
                            if let d = node["d"] { #expect(!(try SVGPath.parse(d)).isEmpty, "\(d)") }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Comparing

    static func compare(file: URL, with document: SceneDocument, label: String) throws {
        let root = try XMLTree.parse(Data(contentsOf: file))
        #expect(root.name == "svg")
        let defs = try #require(root.children.first { $0.name == "defs" })
        let clipped = try #require(root.children.first { $0.name == "g" })
        // The text group (count, note, light · weather) is SwiftUI's job in the app.
        let drawn = clipped.children.filter { !$0.containsText }
        #expect(defs.children.count == document.defs.count, "\(label): defs")
        for (ref, mine) in zip(defs.children, document.defs) { match(ref, mine, path: "\(label) defs") }
        let expected = document.art.children + [document.rail]
        #expect(drawn.count == expected.count, "\(label): top-level layers")
        for (ref, mine) in zip(drawn, expected) { match(ref, mine, path: label) }
    }

    static func match(_ ref: XMLTree, _ mine: SceneNode, path: String) {
        let here = "\(path) > \(ref.name)"
        #expect(ref.name == mine.kind.rawValue, "\(here): element")
        let theirs = normalized(ref.attributes)
        let ours = normalized(mine.attributes)
        #expect(Set(theirs.keys) == Set(ours.keys), "\(here): attributes \(theirs.keys.sorted()) vs \(ours.keys.sorted())")
        for (key, value) in theirs {
            guard let other = ours[key] else { continue }
            #expect(sameValue(value, other), "\(here) \(key): \(value) vs \(other)")
        }
        #expect(ref.children.count == mine.children.count, "\(here): \(ref.children.count) vs \(mine.children.count) children")
        for (index, (a, b)) in zip(ref.children, mine.children).enumerated() {
            match(a, b, path: "\(here)[\(index)]")
        }
    }

    /// React's `useId` prefix comes off ids and url(#…) references; empty classes go.
    static func normalized(_ attributes: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in attributes {
            if key == "class", value.isEmpty { continue }
            var value = value
            if let range = value.range(of: "«[^»]*»-", options: .regularExpression) { value.removeSubrange(range) }
            result[key] = value
        }
        return result
    }

    /// Equal, treating numbers as numbers: `.4` is `0.4`, `168.00000000000003` is `168`.
    static func sameValue(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (wordsA, numbersA) = split(a), (wordsB, numbersB) = split(b)
        guard wordsA == wordsB, numbersA.count == numbersB.count else { return false }
        return zip(numbersA, numbersB).allSatisfy { abs($0 - $1) <= 1e-9 * max(1, abs($0)) }
    }

    static func split(_ text: String) -> (String, [Double]) {
        let pattern = try! NSRegularExpression(pattern: "[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
        let ns = text as NSString
        var words = "", numbers: [Double] = [], last = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            words += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            words += "#"
            numbers.append(Double(ns.substring(with: match.range)) ?? .nan)
            last = match.range.location + match.range.length
        }
        words += ns.substring(from: last)
        return (words.filter { $0 != " " && $0 != "," }, numbers)
    }

    static func flatten(_ node: SceneNode) -> [SceneNode] { [node] + node.children.flatMap(flatten) }
}

/// A minimal XML element tree from Foundation's parser.
final class XMLTree {
    let name: String
    let attributes: [String: String]
    var children: [XMLTree] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    var containsText: Bool { name == "text" || children.contains { $0.containsText } }

    static func parse(_ data: Data) throws -> XMLTree {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [XMLTree] = []
        var root: XMLTree?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            var attributes = attributes
            attributes.removeValue(forKey: "xmlns")
            let node = XMLTree(name: name, attributes: attributes)
            stack.last?.children.append(node)
            stack.append(node)
            if root == nil { root = node }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}
