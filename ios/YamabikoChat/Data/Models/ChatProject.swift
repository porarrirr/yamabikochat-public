import Foundation
import GRDB

struct ChatProject: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "projects"

    var id: Int64?
    var title: String
    var iconName: String
    var colorHex: String
    var instructions: String?
    var createdAtMs: Int64
    var updatedAtMs: Int64

    init(
        id: Int64? = nil,
        title: String,
        iconName: String = "folder",
        colorHex: String = "#5856D6",
        instructions: String? = nil,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        self.instructions = instructions
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
