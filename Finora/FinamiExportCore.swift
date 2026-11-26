import Foundation

struct FinamiExportCell {
    let text: String
    var numeric = false
    init(_ text: String, numeric: Bool = false) { self.text = text; self.numeric = numeric }
    init(minor: Int64) { self.text = NSDecimalNumber(decimal: Decimal(minor) / 100).stringValue; self.numeric = true }
}
struct FinamiExportSheet {
    let name: String
    let rows: [[FinamiExportCell]]
}
func finamiXML(_ raw: String) -> String {
    let valid = raw.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || (0x20...0xD7FF).contains($0.value) || (0xE000...0xFFFD).contains($0.value) || (0x10000...0x10FFFF).contains($0.value) }
    return String(String.UnicodeScalarView(valid)).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}
// Minimal genuine OOXML workbook. Inline strings cannot execute spreadsheet formulas.
func finamiWorkbookParts(_ sheets: [FinamiExportSheet]) -> [String: Data] {
    let ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    let pkg = "http://schemas.openxmlformats.org/package/2006/relationships"
    let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    var parts: [String: Data] = [:]
    func put(_ path: String, _ value: String) { parts[path] = Data((header + value).utf8) }
    put("_rels/.rels", "<Relationships xmlns=\"\(pkg)\"><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
    var types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
    var workbook = "<workbook xmlns=\"\(ns)\" xmlns:r=\"\(rel)\"><sheets>"
    var relationships = "<Relationships xmlns=\"\(pkg)\">"
    for (index, sheet) in sheets.enumerated() {
        let i = index + 1
        types += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        workbook += "<sheet name=\"\(finamiXML(String(sheet.name.prefix(31))))\" sheetId=\"\(i)\" r:id=\"rId\(i)\"/>"
        relationships += "<Relationship Id=\"rId\(i)\" Type=\"\(rel)/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        var xml = "<worksheet xmlns=\"\(ns)\"><sheetData>"
        for (r, row) in sheet.rows.enumerated() {
            xml += "<row r=\"\(r+1)\">"
            for (c, cell) in row.enumerated() {
                var n = c + 1, col = ""
                while n > 0 { n -= 1; col = String(UnicodeScalar(65 + n % 26)!) + col; n /= 26 }
                let ref = col + String(r+1)
                if cell.numeric, Decimal(string: cell.text, locale: Locale(identifier:"en_US_POSIX")) != nil { xml += "<c r=\"\(ref)\"><v>\(finamiXML(cell.text))</v></c>" }
                else { xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(finamiXML(String(cell.text.prefix(32767))))</t></is></c>" }
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        put("xl/worksheets/sheet\(i).xml", xml)
    }
    put("[Content_Types].xml", types + "</Types>")
    put("xl/workbook.xml", workbook + "</sheets></workbook>")
    put("xl/_rels/workbook.xml.rels", relationships + "</Relationships>")
    return parts
}
func finamiCSVText(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = trimmed.first.map { "=+-@".contains($0) } == true || value.first == "\t" || value.first == "\r" ? "'" + value : value
    return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}
struct FinamiCalendarExportEvent { let id: String; let date: Date; let title: String; let detail: String }
func finamiCalendarData(_ events: [FinamiCalendarExportEvent], now: Date = Date(), calendar: Calendar = .current) -> Data {
    let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.calendar = Calendar(identifier:.gregorian); f.timeZone = TimeZone(secondsFromGMT:0); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let day = DateFormatter(); day.locale = f.locale; day.calendar = f.calendar; day.timeZone = calendar.timeZone; day.dateFormat = "yyyyMMdd"
    func escape(_ s: String) -> String { s.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\r\n",with:"\\n").replacingOccurrences(of:"\n",with:"\\n").replacingOccurrences(of:"\r",with:"\\n").replacingOccurrences(of:";",with:"\\;").replacingOccurrences(of:",",with:"\\,") }
    func fold(_ s: String) -> String { var lines = [String](), line = ""; for scalar in s.unicodeScalars { let token = String(scalar); if line.utf8.count + token.utf8.count > 75 { lines.append(line); line = " " }; line += token }; lines.append(line); return lines.joined(separator:"\r\n") }
    var lines = ["BEGIN:VCALENDAR","VERSION:2.0","PRODID:-//Finami//Payments//UK","CALSCALE:GREGORIAN"]
    for e in events { lines += ["BEGIN:VEVENT", "UID:" + escape(e.id) + "@finami.local", "DTSTAMP:" + f.string(from:now), "DTSTART;VALUE=DATE:" + day.string(from:e.date), "SUMMARY:" + escape(e.title), "DESCRIPTION:" + escape(e.detail), "END:VEVENT"] }
    lines.append("END:VCALENDAR"); return Data((lines.map(fold).joined(separator:"\r\n") + "\r\n").utf8)
}
