import AppIntents
import Foundation

extension ShortcutTool: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Shortcuts: ツール"))

    static var caseDisplayRepresentations: [ShortcutTool: DisplayRepresentation] = [
        .webSearch: DisplayRepresentation(title: LocalizedStringResource("Shortcuts: Web 検索")),
        .python: DisplayRepresentation(title: LocalizedStringResource("Shortcuts: Python 実行")),
        .editor: DisplayRepresentation(title: LocalizedStringResource("Shortcuts: ファイル編集")),
        .genUI: DisplayRepresentation(title: LocalizedStringResource("Shortcuts: GenUI"))
    ]
}
