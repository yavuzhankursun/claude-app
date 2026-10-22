import Foundation

/// Pipe'tan gelen rastgele parçaları satırlara böler. Yarım satır bir sonraki parçaya taşınır.
/// Değer tipi; tek bir okuyucu tarafından kullanılır.
public struct NDJSONLineSplitter: Sendable {
    private var pending = Data()
    /// Tek satır için üst sınır; aşılırsa satır atılır (bozuk/kötü niyetli çıktıya karşı bellek koruması).
    public var maxLineBytes: Int

    public init(maxLineBytes: Int = 64 * 1024 * 1024) {
        self.maxLineBytes = maxLineBytes
    }

    public mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            var line = pending[start..<newline]
            if line.last == 0x0D { line = line.dropLast() }
            if !line.isEmpty { lines.append(Data(line)) }
            start = pending.index(after: newline)
        }
        pending = Data(pending[start...])
        if pending.count > maxLineBytes { pending.removeAll(keepingCapacity: false) }
        return lines
    }

    /// Akış kapandığında kalan (yeni satırla bitmemiş) son satırı döndürür.
    public mutating func finish() -> Data? {
        defer { pending.removeAll() }
        return pending.isEmpty ? nil : pending
    }
}
