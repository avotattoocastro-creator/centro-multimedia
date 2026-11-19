import Foundation
import AVFoundation
import CryptoKit

// MARK: - Lectura de nombres de archivo

struct ParsedName {
    var title: String
    var year: Int?
    var show: String?
    var season: Int?
    var episode: Int?
}

enum FilenameParser {
    private struct Match {
        let range: Range<String.Index>
        let groups: [String]
    }

    private static func firstMatch(_ pattern: String, in s: String) -> Match? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: ns), let r = Range(m.range, in: s) else { return nil }
        var groups: [String] = []
        if m.numberOfRanges > 1 {
            for i in 1..<m.numberOfRanges {
                if let gr = Range(m.range(at: i), in: s) { groups.append(String(s[gr])) } else { groups.append("") }
            }
        }
        return Match(range: r, groups: groups)
    }

    /// Etiquetas técnicas que se eliminan (y todo lo que va detrás).
    private static let junk = #"(?i)\b(2160p|1080p|720p|576p|480p|4k|uhd|hdr|x264|x265|h264|h265|hevc|xvid|web-?dl|webrip|bluray|blu-ray|brrip|bdrip|dvdrip|dvd|hdtv|hdrip|microhd|aac|ac3|dts|castellano|spanish|español|espanol|esp|latino|dual|vose|multi|subs?|proper|repack|extended|remastered)\b.*$"#

    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: junk, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " -–_()[]"))
        if t == t.lowercased() { t = t.capitalized }
        return t
    }

    static func parse(_ raw: String) -> ParsedName {
        var name = raw.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"[._]"#, with: " ", options: .regularExpression)

        // Episodios: S01E02, s1 e2 o 1x02
        if let m = firstMatch(#"(?i)\bS(\d{1,2})\s*E(\d{1,3})"#, in: name) ?? firstMatch(#"\b(\d{1,2})x(\d{2,3})\b"#, in: name),
           m.groups.count >= 2 {
            let show = clean(String(name[..<m.range.lowerBound]))
            let s = Int(m.groups[0]) ?? 1
            let e = Int(m.groups[1]) ?? 1
            let finalShow = show.isEmpty ? "Serie sin nombre" : show
            return ParsedName(title: finalShow, show: finalShow, season: s, episode: e)
        }

        // Películas: "Título (2019)" o "Título 2019 ..."
        if let m = firstMatch(#"\(?\b(19[2-9]\d|20[0-4]\d)\b\)?"#, in: name),
           m.range.lowerBound > name.startIndex, let y = Int(m.groups.first ?? "") {
            let title = clean(String(name[..<m.range.lowerBound]))
            if !title.isEmpty { return ParsedName(title: title, year: y) }
        }
        let t = clean(name)
        return ParsedName(title: t.isEmpty ? raw : t)
    }

    /// Quita números de pista ("01 - ", "1. ") del inicio.
    static func stripTrackNumber(_ s: String) -> String {
        s.replacingOccurrences(of: #"^\d{1,3}\s*[-.]?\s+"#, with: "", options: .regularExpression)
    }
}

// MARK: - Organizador de archivos (nunca borra nada)

struct OrganizeOptions {
    var organize: Bool
    var rename: Bool
    var reorganizeKnown: Bool
}

struct ScanResult {
    var newItems: [MediaItem] = []
    var missingIDs: Set<String> = []
    var pathUpdates: [String: String] = [:]   // id -> nueva ruta relativa
    var batch: OrganizeBatch?
    var report: ScanReport
}

enum FileOrganizer {
    private static var fm: FileManager { FileManager.default }

    static func scan(known: [MediaItem], pinned: Set<String>, options: OrganizeOptions) async -> ScanResult {
        FileLocations.ensureFolders()
        var moves: [MoveRecord] = []
        var errors: [String] = []
        var duplicates = 0
        var result = ScanResult(report: ScanReport(date: Date(), added: 0, duplicates: 0, moved: 0, missing: 0, errors: []))

        let knownByPath = Dictionary(known.map { ($0.relativePath, $0) }, uniquingKeysWith: { a, _ in a })
        var hashes = Set(known.compactMap { $0.hash })
        var seenIDs = Set<String>()

        for url in mediaFiles() {
            let ext = url.pathExtension.lowercased()
            let rel = FileLocations.relativePath(of: url)

            // Ya conocido
            if var item = knownByPath[rel] {
                seenIDs.insert(item.id)
                if options.organize && options.reorganizeKnown && !pinned.contains(rel) {
                    if let newRel = place(&item, from: url, rename: options.rename, moves: &moves, errors: &errors) {
                        result.pathUpdates[item.id] = newRel
                    }
                }
                continue
            }

            // Nuevo archivo
            let hash = try? quickHash(url)
            if !pinned.contains(rel), let h = hash, hashes.contains(h) {
                let dest = uniqueURL(FileLocations.duplicates.appendingPathComponent(url.lastPathComponent))
                do {
                    try fm.moveItem(at: url, to: dest)
                    moves.append(MoveRecord(from: rel, to: FileLocations.relativePath(of: dest)))
                    duplicates += 1
                } catch {
                    errors.append("No se pudo apartar el duplicado \(url.lastPathComponent)")
                }
                continue
            }
            if let h = hash { hashes.insert(h) }

            var item = await buildItem(url: url, ext: ext, hash: hash)
            if options.organize && !pinned.contains(rel) {
                _ = place(&item, from: url, rename: options.rename, moves: &moves, errors: &errors)
            }
            result.newItems.append(item)
        }

        result.missingIDs = Set(known.map(\.id)).subtracting(seenIDs)
        if !moves.isEmpty { result.batch = OrganizeBatch(date: Date(), moves: moves) }
        result.report = ScanReport(date: Date(), added: result.newItems.count, duplicates: duplicates,
                                   moved: moves.count - duplicates, missing: result.missingIDs.count, errors: errors)
        return result
    }

    /// Mueve el archivo a su sitio dentro de "Biblioteca". Devuelve la nueva ruta relativa si cambió.
    private static func place(_ item: inout MediaItem, from url: URL, rename: Bool,
                              moves: inout [MoveRecord], errors: inout [String]) -> String? {
        let target = targetURL(for: item, original: url, rename: rename)
        let current = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard target.resolvingSymlinksInPath().standardizedFileURL.path != current else { return nil }
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let final = uniqueURL(target)
            let fromRel = FileLocations.relativePath(of: url)
            try fm.moveItem(at: url, to: final)
            let toRel = FileLocations.relativePath(of: final)
            moves.append(MoveRecord(from: fromRel, to: toRel))
            moveSidecars(of: url, to: final, moves: &moves)
            item.relativePath = toRel
            return toRel
        } catch {
            errors.append("No se pudo mover \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    static func targetURL(for item: MediaItem, original: URL, rename: Bool) -> URL {
        let ext = original.pathExtension
        let keep = original.lastPathComponent
        let root = FileLocations.library.appendingPathComponent(item.kind.folderName, isDirectory: true)
        switch item.kind {
        case .movie:
            let name = sanitize(item.year.map { "\(item.title) (\($0))" } ?? item.title)
            return root.appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(rename ? "\(name).\(ext)" : keep)
        case .episode:
            let show = sanitize(item.show ?? "Serie")
            let s = item.season ?? 1, e = item.episode ?? 1
            let season = String(format: "Temporada %02d", s)
            let file = "\(show) - " + String(format: "S%02dE%02d", s, e) + ".\(ext)"
            return root.appendingPathComponent(show, isDirectory: true)
                .appendingPathComponent(season, isDirectory: true)
                .appendingPathComponent(rename ? file : keep)
        case .music:
            let artist = sanitize(item.artist ?? "Artista desconocido")
            let album = sanitize(item.album ?? "Sin album")
            let file = item.artist != nil ? "\(artist) - \(sanitize(item.title)).\(ext)" : "\(sanitize(item.title)).\(ext)"
            return root.appendingPathComponent(artist, isDirectory: true)
                .appendingPathComponent(album, isDirectory: true)
                .appendingPathComponent(rename ? file : keep)
        case .video:
            return root.appendingPathComponent(rename ? "\(sanitize(item.title)).\(ext)" : keep)
        }
    }

    // MARK: Deshacer

    /// Devuelve [ruta nueva: ruta original] de lo que se ha podido devolver a su sitio.
    static func undo(_ batch: OrganizeBatch) -> [String: String] {
        var restored: [String: String] = [:]
        let docs = FileLocations.documents
        for m in batch.moves.reversed() {
            let src = docs.appendingPathComponent(m.to)
            let dst = docs.appendingPathComponent(m.from)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: src, to: dst)) != nil { restored[m.to] = m.from }
        }
        return restored
    }

    // MARK: Utilidades

    static func mediaFiles() -> [URL] {
        let docs = FileLocations.documents
        let dupPath = FileLocations.duplicates.resolvingSymlinksInPath().path
        guard let en = fm.enumerator(at: docs, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en {
            if url.resolvingSymlinksInPath().path.hasPrefix(dupPath) { continue }
            let ext = url.pathExtension.lowercased()
            if MediaTypes.video.contains(ext) || MediaTypes.audio.contains(ext) { out.append(url) }
        }
        return out
    }

    static func subtitles(for video: URL, preferredLanguage: String) -> URL? {
        let dir = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let subs = list.filter { MediaTypes.subtitles.contains($0.pathExtension.lowercased()) && $0.lastPathComponent.hasPrefix(base) }
        let tags = preferredLanguage == "es" ? [".es.", ".spa.", "castellano", "spanish", "español"] : [".\(preferredLanguage)."]
        return subs.first { s in tags.contains { s.lastPathComponent.lowercased().contains($0) } } ?? subs.first
    }

    private static func moveSidecars(of original: URL, to final: URL, moves: inout [MoveRecord]) {
        let dir = original.deletingLastPathComponent()
        let base = original.deletingPathExtension().lastPathComponent
        let newBase = final.deletingPathExtension().lastPathComponent
        guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in list where MediaTypes.subtitles.contains(f.pathExtension.lowercased()) {
            let name = f.lastPathComponent
            guard name.hasPrefix(base) else { continue }
            let suffix = String(name.dropFirst(base.count))
            let dest = uniqueURL(final.deletingLastPathComponent().appendingPathComponent(newBase + suffix))
            let fromRel = FileLocations.relativePath(of: f)
            if (try? fm.moveItem(at: f, to: dest)) != nil {
                moves.append(MoveRecord(from: fromRel, to: FileLocations.relativePath(of: dest)))
            }
        }
    }

    static func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? "Sin titulo" : String(cleaned.prefix(120))
    }

    static func uniqueURL(_ url: URL) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// Huella rápida: tamaño + primeros y últimos 4 MB (SHA-256).
    static func quickHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let size = try handle.seekToEnd()
        var le = size.littleEndian
        withUnsafeBytes(of: &le) { hasher.update(bufferPointer: $0) }
        let chunk = 4 << 20
        try handle.seek(toOffset: 0)
        if let d = try handle.read(upToCount: chunk) { hasher.update(data: d) }
        if size > UInt64(chunk * 2) {
            try handle.seek(toOffset: size - UInt64(chunk))
            if let d = try handle.read(upToCount: chunk) { hasher.update(data: d) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func saveArtwork(_ data: Data, id: String) -> String? {
        let name = "\(id).jpg"
        do {
            try data.write(to: FileLocations.artwork.appendingPathComponent(name), options: .atomic)
            return name
        } catch { return nil }
    }

    // MARK: Detección del tipo de contenido

    static func buildItem(url: URL, ext: String, hash: String?) async -> MediaItem {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let base = url.deletingPathExtension().lastPathComponent
        let rel = FileLocations.relativePath(of: url)
        var item = MediaItem(relativePath: rel, kind: .video, title: base, fileSize: size, hash: hash)
        let asset = AVURLAsset(url: url)

        if MediaTypes.audio.contains(ext) {
            item.kind = .music
            item.title = FilenameParser.stripTrackNumber(base)
            if let md = try? await asset.load(.commonMetadata) {
                for m in md {
                    guard let key = m.commonKey else { continue }
                    if key == .commonKeyTitle, let v = try? await m.load(.stringValue), !v.isEmpty { item.title = v }
                    else if key == .commonKeyArtist, let v = try? await m.load(.stringValue), !v.isEmpty { item.artist = v }
                    else if key == .commonKeyAlbumName, let v = try? await m.load(.stringValue), !v.isEmpty { item.album = v }
                    else if key == .commonKeyArtwork, item.artworkFile == nil, let d = try? await m.load(.dataValue) {
                        item.artworkFile = saveArtwork(d, id: item.id)
                    }
                }
            }
            if item.artist == nil {
                let parts = item.title.components(separatedBy: " - ")
                if parts.count >= 2 {
                    item.artist = parts[0].trimmingCharacters(in: .whitespaces)
                    item.title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                }
            }
        } else {
            let p = FilenameParser.parse(base)
            if let show = p.show {
                item.kind = .episode
                item.show = show
                item.season = p.season
                item.episode = p.episode
                item.title = show
            } else {
                item.title = p.title
                item.year = p.year
                item.kind = p.year != nil ? .movie : .video
            }
        }

        if let d = try? await asset.load(.duration) {
            let s = CMTimeGetSeconds(d)
            if s.isFinite && s > 0 { item.duration = s }
        }
        // Vídeos largos sin año o ya guardados en la carpeta de películas → película
        if item.kind == .video {
            let inMoviesFolder = rel.hasPrefix("Biblioteca/\(MediaKind.movie.folderName)/")
            if inMoviesFolder || (item.duration ?? 0) >= 60 * 60 { item.kind = .movie }
        }
        return item
    }
}
