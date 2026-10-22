import Darwin
import Foundation

/// Ek ve `@yol` okumaları için tek dosya okuyucu (güvenlik incelemesi 2026-10-22, bulgular 1–3):
/// - `O_NOFOLLOW`: kontrol ile okuma arasında son bileşen sembolik bağa çevrilirse açılmaz.
/// - `F_GETPATH`: açılan dosyanın gerçek yolu yeniden kontrol edilir (ara dizin değiştirilse bile kök dışı reddedilir).
/// - `fstat` + `S_ISREG`: FIFO/aygıt gibi özel dosyalar reddedilir; `O_NONBLOCK` açılışta beklemeyi önler.
/// - Okuma `maxBytes + 1` ile sınırlıdır; stat'tan sonra büyüyen dosya sınırı aşamaz.
enum SafeFile {
    enum Outcome: Equatable {
        case data(Data)
        /// Sınır aşıldı; `head` ilk baytlar (tür tanıma için), `size` fstat boyutu.
        case tooLarge(head: Data, size: Int)
        case notRegular
        case outsideRoot
        case unreadable
    }

    /// `root` verilirse açılan dosyanın gerçek yolu (`F_GETPATH`) kökün `realpath`'i altında olmalı. Foundation'ın
    /// `resolvingSymlinksInPath`'i `/private` önekini attığı için karşılaştırma iki tarafta da çekirdek yoluyla yapılır.
    static func read(_ url: URL, maxBytes: Int, within root: URL? = nil) -> Outcome {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return errno == ELOOP ? .outsideRoot : .unreadable }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0 else { return .unreadable }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return .notRegular }

        if let root {
            guard let resolved = realpath(root.path, nil) else { return .unreadable }
            let canonical = String(cString: resolved)
            free(resolved)
            let prefix = canonical.hasSuffix("/") ? canonical : canonical + "/"
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(fd, F_GETPATH, &buffer) == 0 else { return .unreadable }
            let real = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard real.hasPrefix(prefix) else { return .outsideRoot }
        }

        let limit = maxBytes + 1
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < limit {
            let want = min(chunk.count, limit - data.count)
            let n = Darwin.read(fd, &chunk, want)
            if n < 0 {
                if errno == EINTR { continue }
                return .unreadable
            }
            if n == 0 { break }
            data.append(chunk, count: n)
        }
        if data.count > maxBytes {
            return .tooLarge(head: data.prefix(16), size: max(Int(info.st_size), data.count))
        }
        return .data(data)
    }

    /// NUL içermeyen geçerli UTF-8 ise metin.
    static func text(from data: Data) -> String? {
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
