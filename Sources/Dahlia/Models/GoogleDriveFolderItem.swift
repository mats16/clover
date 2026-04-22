import Foundation

enum GoogleDriveFolderItemKind: Equatable {
    case folder
    case sharedDrive
}

struct GoogleDriveFolderItem: Equatable, Identifiable {
    let id: String
    let name: String
    let detail: String
    let kind: GoogleDriveFolderItemKind
    let driveId: String?
    let driveName: String?

    init(
        id: String,
        name: String,
        detail: String,
        kind: GoogleDriveFolderItemKind = .folder,
        driveId: String? = nil,
        driveName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.kind = kind
        self.driveId = driveId
        self.driveName = driveName
    }
}
