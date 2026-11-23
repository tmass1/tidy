import XCTest
import SwiftUI
@testable import Tidy

final class WordmarkTests: XCTestCase {
    func testParsesCompactNumbersAndRelativeCommands() {
        // "0-.5.25" is three numbers: 0, −0.5, 0.25.
        let path = SVGPath.parse("M10,10h5v5l-5,0-.5.25Z")
        var points: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(let to), .line(let to): points.append(to)
            default: break
            }
        }
        XCTAssertEqual(points, [CGPoint(x: 10, y: 10), CGPoint(x: 15, y: 10), CGPoint(x: 15, y: 15),
                                CGPoint(x: 10, y: 15), CGPoint(x: 9.5, y: 15.25)])
    }

    func testSmoothCurveMirrorsThePreviousControlPoint() {
        let path = SVGPath.parse("M0,0c0,10,10,10,10,0s10-10,10,0")
        var curves: [(CGPoint, CGPoint, CGPoint)] = []
        path.forEach { if case .curve(let to, let c1, let c2) = $0 { curves.append((to, c1, c2)) } }
        XCTAssertEqual(curves.count, 2)
        XCTAssertEqual(curves[1].1, CGPoint(x: 10, y: -10), "mirror of (10, 10) about (10, 0)")
        XCTAssertEqual(curves[1].0, CGPoint(x: 20, y: 0))
    }

    func testTheArtworkFillsItsViewBox() {
        let box = WordmarkArt.box
        let letters = WordmarkArt.letters.path.boundingRect
        XCTAssertFalse(letters.isEmpty)
        XCTAssertTrue(box.insetBy(dx: -0.5, dy: -0.5).contains(letters), "\(letters) should sit inside \(box)")
        XCTAssertGreaterThan(letters.width, box.width * 0.95)
        XCTAssertGreaterThan(letters.height, box.height * 0.9)
        XCTAssertTrue(box.contains(WordmarkArt.dot.path.boundingRect))
    }

    func testTheArtworkMatchesTheLandingPagesFile() throws {
        // The app's copy of the outlines must be the site's, character for character.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let svg = try String(contentsOf: root.appendingPathComponent("site/assets/tidy-app-wordmark.svg"), encoding: .utf8)
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Tidy/Wordmark.swift"), encoding: .utf8)
        let outlines = svg.components(separatedBy: " d=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
        XCTAssertEqual(outlines.count, 4)
        for outline in outlines { XCTAssertTrue(source.contains("\"\(outline)\""), "an outline in the site's SVG is missing from the app") }
        XCTAssertTrue(svg.contains(#"viewBox="267.93 389.79 134 73.3""#))
        XCTAssertTrue(svg.contains(#"cx="304.44" cy="397.84" r="6.12""#))
    }

    func testFitsCentredInTheSpaceGiven() {
        let rect = CGRect(x: 0, y: 0, width: 54, height: 30)
        let fitted = WordmarkArt.letters.path(in: rect).boundingRect
        XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(fitted))
        XCTAssertEqual(fitted.midX, rect.midX, accuracy: 1)
    }
}
