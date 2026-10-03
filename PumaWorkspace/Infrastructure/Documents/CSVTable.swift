import Foundation

struct CSVTable: Sendable {
    let rows: [[String]]

    static func parse(_ text: String) throws -> CSVTable {
        guard text.utf8.count <= 2_000_000 else { throw WorkspaceError.message("CSV analysis is limited to 2 MB.") }
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false, closed = false
        var iterator = text.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if closed && character != "," && character != "\n" && character != "\r\n" && character != "\r" { throw WorkspaceError.message("Unexpected text after a quoted CSV field.") }
            if character == "\"" {
                if quoted {
                    let next = iterator.next()
                    if next == "\"" { cell.append("\"") }
                    else { quoted = false; closed = true; pending = next }
                } else if cell.isEmpty { quoted = true }
                else { throw WorkspaceError.message("Malformed CSV quotes.") }
            } else if character == ",", !quoted { row.append(cell);cell = "";closed = false }
            else if (character == "\n" || character == "\r\n" || character == "\r"), !quoted {
                row.append(cell);rows.append(row);row = [];cell = "";closed = false
            } else { cell.append(character) }
        }
        guard !quoted else { throw WorkspaceError.message("The CSV has an unterminated quoted field.") }
        if !cell.isEmpty || !row.isEmpty || closed { row.append(cell);rows.append(row) }
        guard let header = rows.first, !header.isEmpty, rows.allSatisfy({$0.count == header.count}) else {
            throw WorkspaceError.message("The CSV rows do not have consistent columns.")
        }
        return CSVTable(rows:rows)
    }

    func summary(column: String, operation: String) throws -> String {
        guard let index = rows.first?.firstIndex(where:{$0.caseInsensitiveCompare(column) == .orderedSame}) else { throw WorkspaceError.message("Column not found.") }
        if operation == "count" { return String(max(0,rows.count-1)) }
        let values = try rows.dropFirst().map { row -> Double in
            guard let value = Double(row[index]), value.isFinite else { throw WorkspaceError.message("This column contains nonnumeric values.") }
            return value
        }
        guard !values.isEmpty else { throw WorkspaceError.message("This column has no values.") }
        let result: Double
        switch operation {
        case "sum": result = values.reduce(0,+)
        case "average": result = values.reduce(0,+)/Double(values.count)
        case "min": result = values.min()!
        case "max": result = values.max()!
        default: throw WorkspaceError.message("Use count, sum, average, min, or max.")
        }
        guard result.isFinite else { throw WorkspaceError.message("The calculation overflowed.") }
        return String(result)
    }
}
