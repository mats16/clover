import Foundation

/// サイドバー表示用のフラット化されたプロジェクト行。
struct FlatProjectRow: Identifiable {
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

    /// フラットな ProjectRecord 配列からツリーを構築する。
    static func buildTree(from records: [ProjectRecord]) -> [ProjectNode] {
        let sorted = records.sorted { $0.name < $1.name }

        // name → record のルックアップ
        var lookup: [String: ProjectRecord] = [:]
        for record in sorted {
            lookup[record.name] = record
        }

        // ルートノード群を構築
        var roots: [ProjectNode] = []

        // 再帰的にノードを挿入する
        func insertNode(_ record: ProjectRecord) {
            let components = record.name.split(separator: "/").map(String.init)
            insertInto(nodes: &roots, components: components, depth: 0, record: record)
        }

        func insertInto(nodes: inout [ProjectNode], components: [String], depth: Int, record: ProjectRecord) {
            guard depth < components.count else { return }

            let pathUpToDepth = components[0...depth].joined(separator: "/")
            let isLeaf = depth == components.count - 1

            if let existingIndex = nodes.firstIndex(where: { $0.name == pathUpToDepth }) {
                if isLeaf {
                    // 既にノードが存在する場合はスキップ（先に中間ノードとして作られた場合）
                    return
                }
                insertInto(nodes: &nodes[existingIndex].children, components: components, depth: depth + 1, record: record)
            } else {
                if isLeaf {
                    let node = ProjectNode(
                        id: record.id,
                        name: record.name,
                        displayName: components[depth],
                        children: []
                    )
                    nodes.append(node)
                } else {
                    // 中間ノード: lookup から対応する record を取得
                    guard let intermediateRecord = lookup[pathUpToDepth] else { return }
                    var node = ProjectNode(
                        id: intermediateRecord.id,
                        name: pathUpToDepth,
                        displayName: components[depth],
                        children: []
                    )
                    insertInto(nodes: &node.children, components: components, depth: depth + 1, record: record)
                    nodes.append(node)
                }
            }
        }

        for record in sorted {
            insertNode(record)
        }

        return roots
    }
}
