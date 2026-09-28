import Foundation

nonisolated enum CSVTextDecoding {
    static func decode(from data: Data) -> String? {
        decodeWithEncoding(from: data)?.text
    }

    static func decodeWithEncoding(from data: Data) -> (text: String, encoding: String)? {
        if data.count >= 2 {
            if data[0] == 0xFF, data[1] == 0xFE,
               let text = String(data: data, encoding: .utf16LittleEndian)
            {
                return (text, "utf16le_bom")
            }
            if data[0] == 0xFE, data[1] == 0xFF,
               let text = String(data: data, encoding: .utf16BigEndian)
            {
                return (text, "utf16be_bom")
            }
        }
        if let text = String(data: data, encoding: .utf8) { return (text, "utf8") }
        if let text = String(data: data, encoding: .utf16LittleEndian) { return (text, "utf16le") }
        if let text = String(data: data, encoding: .isoLatin1) { return (text, "isoLatin1") }
        if let text = String(data: data, encoding: .windowsCP1252) { return (text, "windowsCP1252") }
        return nil
    }
}
