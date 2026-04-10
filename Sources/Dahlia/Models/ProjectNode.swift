import Foundation

/// サイドバー表示用のフラット化されたプロジェクト行。
struct FlatProjectRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let displayName: String
    let depth: Int
    let hasChildren: Bool
    let missingOnDisk: Bool

    /// ProjectRecord 配列から、入力順を保ったままサイドバー表示用のフラット行を構築する。
    static func buildRows(fromRecords records: [ProjectRecord]) -> [FlatProjectRow] {
        guard !records.isEmpty else { return [] }

        let parentNames = parentNames(in: records)
        var rows: [FlatProjectRow] = []
        rows.reserveCapacity(records.count)

        for record in records {
            let components = record.name.split(separator: "/")
            let displayName = components.last.map(String.init) ?? record.name
            let depth = max(components.count - 1, 0)
            let hasChildren = parentNames.contains(record.name)

            rows.append(
                FlatProjectRow(
                    id: record.id,
                    name: record.name,
                    displayName: displayName,
                    depth: depth,
                    hasChildren: hasChildren,
                    missingOnDisk: record.missingOnDisk
                )
            )
        }

        return rows
    }

    /// この行の全祖先パスを返す。例: "a/b/c" → ["a", "a/b"]
    func parentPaths() -> [String] {
        let components = name.split(separator: "/")
        guard components.count > 1 else { return [] }
        return (1 ..< components.count).map { depth in
            components[0 ..< depth].joined(separator: "/")
        }
    }

    private static func parentNames(in records: [ProjectRecord]) -> Set<String> {
        var parentNames = Set<String>()

        for record in records {
            let components = record.name.split(separator: "/")
            guard components.count > 1 else { continue }

            for depth in 1 ..< components.count {
                parentNames.insert(components[0 ..< depth].joined(separator: "/"))
            }
        }

        return parentNames
    }
}
