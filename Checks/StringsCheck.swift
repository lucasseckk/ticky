import Foundation

/// Every text the compiler marks as localizable needs an English translation (#113).
/// Arguments: the folder with the compiler's .stringsdata files and Resources/Localizable.en.json.
@main struct StringsCheck {
    static func main() throws {
        struct Table: Decodable { struct Entry: Decodable { let key: String }; let tables: [String: [Entry]] }
        let arguments = CommandLine.arguments
        let folder = URL(fileURLWithPath: arguments[1])
        let english = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
        var keys = Set<String>()
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.pathExtension == "stringsdata" {
            let table = try JSONDecoder().decode(Table.self, from: Data(contentsOf: file))
            keys.formUnion(table.tables.values.joined().map(\.key))
        }
        let missing = keys.subtracting(english.keys).sorted()
        let unused = Set(english.keys).subtracting(keys).sorted()
        for key in missing { print("Fehlt in Localizable.en.json: \(key.debugDescription)") }
        for key in unused { print("Nicht mehr verwendet: \(key.debugDescription)") }
        guard missing.isEmpty, unused.isEmpty else { exit(1) }
        print("OK: \(keys.count) Texte übersetzt")
    }
}
