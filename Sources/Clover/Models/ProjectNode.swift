import Foundation

/// サイドバー表示用のフラット化されたプロジェクト行。
struct FlatProjectRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let displayName: String
    let depth: Int
    let hasChildren: Bool
}

/// projects テーブルのレコードから構築される階層ツリーのノード。
struct ProjectNode: Identifiable {
    let id: UUID
    let name: String
    let displayName: String
    var children: [ProjectNode]

    /// ツリーを深さ優先でフラットリストに変換する。
    static func flatten(_ nodes: [ProjectNode], depth: Int = 0) -> [FlatProjectRow] {
        var result: [FlatProjectRow] = []
        for node in nodes {
            result.append(FlatProjectRow(
                id: node.id,
                name: node.name,
                displayName: node.displayName,
                depth: depth,
                hasChildren: !node.children.isEmpty
            ))
            result.append(contentsOf: flatten(node.children, depth: depth + 1))
        }
        return result
    }

    /// フラットな ProjectRecord 配列からツリーを構築する。O(n) の Dictionary ベースアルゴリズム。
    static func buildTree(from records: [ProjectRecord]) -> [ProjectNode] {
        // ソート済みなので中間ノード（親）は子より先に処理される
        let sorted = records.sorted { $0.name < $1.name }

        // name → (ノード, 子ノード配列) を管理。子配列は参照型で共有して後から追加可能にする。
        final class MutableNode {
            let id: UUID
            let name: String
            let displayName: String
            var children: [MutableNode] = []

            init(id: UUID, name: String, displayName: String) {
                self.id = id
                self.name = name
                self.displayName = displayName
            }

            func toProjectNode() -> ProjectNode {
                ProjectNode(
                    id: id,
                    name: name,
                    displayName: displayName,
                    children: children.map { $0.toProjectNode() }
                )
            }
        }

        var nodeMap: [String: MutableNode] = [:]
        var roots: [MutableNode] = []

        for record in sorted {
            let components = record.name.split(separator: "/")
            let displayName = String(components.last!)
            let node = MutableNode(id: record.id, name: record.name, displayName: displayName)
            nodeMap[record.name] = node

            if components.count > 1 {
                let parentPath = components.dropLast().joined(separator: "/")
                if let parent = nodeMap[parentPath] {
                    parent.children.append(node)
                } else {
                    // 親レコードが存在しない場合はルートとして扱う
                    roots.append(node)
                }
            } else {
                roots.append(node)
            }
        }

        return roots.map { $0.toProjectNode() }
    }
}
