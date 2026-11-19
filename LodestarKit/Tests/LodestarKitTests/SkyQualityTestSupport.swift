import Foundation
@testable import LodestarKit

/// Synthetic light pollution maps and file images shared by the SkyQuality tests.
enum SkyQualityTestSupport {
    static let width = LightPollutionMap.width
    static let height = LightPollutionMap.height

    /// The cells of an all-dark map.
    static func darkCells() -> [UInt8] {
        [UInt8](repeating: 0, count: width * height)
    }

    /// The cells of a map whose level at (row, column) is `level(row, column)`.
    static func cells(_ level: (Int, Int) -> Int) -> [UInt8] {
        var cells = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width { cells[row * width + column] = UInt8(level(row, column)) }
        }
        return cells
    }

    /// The file image of a grid: the 16-byte header and the rows as runs (the format of `build_light_pollution.py`).
    static func encode(_ cells: [UInt8]) -> Data {
        var data = [UInt8]()
        for row in 0..<height {
            var column = 0
            while column < width {
                let value = cells[row * width + column]
                var end = column + 1
                while end < width && cells[row * width + end] == value { end += 1 }
                let run = end - column
                if run <= 15 {
                    data.append(UInt8(((run - 1) << 4) | Int(value)))
                } else {
                    data.append(UInt8(0xF0 | Int(value)))
                    var extra = run - 16
                    while true {
                        let low = extra & 0x7F
                        extra >>= 7
                        data.append(UInt8(low | (extra != 0 ? 0x80 : 0)))
                        if extra == 0 { break }
                    }
                }
                column = end
            }
        }
        return header(length: data.count) + Data(data)
    }

    /// A header for `length` bytes of run data; the other fields may be overridden to build bad files.
    static func header(length: Int, gridWidth: Int = width, gridHeight: Int = height, levels: Int = 16,
                       magic: String = "LPM1", reserved: Int = 0) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, scalar) in magic.utf8.enumerated() { bytes[index] = scalar }
        bytes[4] = UInt8(gridWidth & 0xFF)
        bytes[5] = UInt8((gridWidth >> 8) & 0xFF)
        bytes[6] = UInt8(gridHeight & 0xFF)
        bytes[7] = UInt8((gridHeight >> 8) & 0xFF)
        bytes[8] = UInt8(levels)
        bytes[9] = UInt8(reserved)
        for index in 0..<4 { bytes[10 + index] = UInt8((length >> (8 * index)) & 0xFF) }
        return Data(bytes)
    }

    /// The map of a grid, through the encoder and the decoder.
    static func map(_ cells: [UInt8]) throws -> LightPollutionMap {
        try LightPollutionMap.parse(encode(cells))
    }

    /// The place at the centre of the cell at `row` and `column`.
    static func centre(row: Int, column: Int) -> GeographicLocation {
        GeographicLocation(latitude: 90 - (Double(row) + 0.5) * 0.1, longitude: -180 + (Double(column) + 0.5) * 0.1)
    }

    /// The bytes of an all-dark file whose first row is replaced by `firstRow` (every other row is one run of 3600).
    static func file(firstRow: [Int]) -> Data {
        let darkRow = [0xF0, 0x80, 0x1C]
        let data = (firstRow + (1..<height).flatMap { _ in darkRow }).map { UInt8($0) }
        return header(length: data.count) + Data(data)
    }
}
