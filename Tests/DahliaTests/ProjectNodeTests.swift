import Foundation
#if canImport(Testing)
import Testing
@testable import Dahlia

struct ProjectNodeTests {
    @Test
    func marksDirectParentAsHavingChildren() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "foo"),
                project(named: "foo/bar")
            ]
        )

        #expect(rows.map(\.hasChildren) == [true, false])
    }

    @Test
    func ignoresSiblingPrefixesWhenDeterminingChildren() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "foo"),
                project(named: "foo-archive"),
                project(named: "foo/bar")
            ]
        )

        #expect(rows.map(\.hasChildren) == [true, false, false])
    }

    @Test
    func ignoresNonDescendantPrefixMatches() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "foo"),
                project(named: "foo.bar"),
                project(named: "foo/bar"),
                project(named: "foo0")
            ]
        )

        #expect(rows.map(\.hasChildren) == [true, false, false, false])
    }

    @Test
    func marksIntermediateNodesAsHavingChildren() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "a/b"),
                project(named: "a/b/c"),
                project(named: "z")
            ]
        )

        #expect(rows.map(\.hasChildren) == [true, false, false])
    }

    @Test
    func keepsInputOrderWhileComputingChildrenIndependently() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "foo/bar"),
                project(named: "foo"),
                project(named: "foo/baz")
            ]
        )

        #expect(rows.map(\.name) == ["foo/bar", "foo", "foo/baz"])
        #expect(rows.map(\.hasChildren) == [false, true, false])
    }

    private func project(named name: String) -> ProjectRecord {
        ProjectRecord(id: .v7(), vaultId: .v7(), name: name, createdAt: Date())
    }
}
#elseif canImport(XCTest)
import XCTest
@testable import Dahlia

final class ProjectNodeTests: XCTestCase {
    func testMarksDirectParentAsHavingChildren() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "foo"),
                project(named: "foo/bar")
            ]
        )

        XCTAssertEqual(rows.map(\.hasChildren), [true, false])
    }

    func testIgnoresSiblingPrefixesWhenDeterminingChildren() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "foo"),
                project(named: "foo-archive"),
                project(named: "foo/bar")
            ]
        )

        XCTAssertEqual(rows.map(\.hasChildren), [true, false, false])
    }

    func testIgnoresNonDescendantPrefixMatches() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "foo"),
                project(named: "foo.bar"),
                project(named: "foo/bar"),
                project(named: "foo0")
            ]
        )

        XCTAssertEqual(rows.map(\.hasChildren), [true, false, false, false])
    }

    func testMarksIntermediateNodesAsHavingChildren() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "a/b"),
                project(named: "a/b/c"),
                project(named: "z")
            ]
        )

        XCTAssertEqual(rows.map(\.hasChildren), [true, false, false])
    }

    func testKeepsInputOrderWhileComputingChildrenIndependently() {
        let rows = FlatProjectRow.buildRows(
            fromRecords: [
                project(named: "foo/bar"),
                project(named: "foo"),
                project(named: "foo/baz")
            ]
        )

        XCTAssertEqual(rows.map(\.name), ["foo/bar", "foo", "foo/baz"])
        XCTAssertEqual(rows.map(\.hasChildren), [false, true, false])
    }

    private func project(named name: String) -> ProjectRecord {
        ProjectRecord(id: .v7(), vaultId: .v7(), name: name, createdAt: Date())
    }
}
#endif
