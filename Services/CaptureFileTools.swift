import Foundation

enum CaptureFileError: LocalizedError {
    case unreadable(String)
    case linkTypeMismatch

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return String(localized: "Could not read the capture part \(name).")
        case .linkTypeMismatch:
            return String(localized: "The capture parts use different link types and cannot be merged.")
        }
    }
}

/// The pieces tcpdump writes when it rotates with `-C`: the named file, then
/// `<name>1`, `<name>2`, … Those parts belong to one session and are merged
/// back into the named file before anything reads them.
enum CaptureFiles {
    static let globalHeaderLength = 24
    static let maximumParts = 999

    /// Existing parts of one capture, oldest first.
    static func partURLs(base: URL) -> [URL] {
        var urls: [URL] = []
        if FileManager.default.fileExists(atPath: base.path) { urls.append(base) }
        for index in 1...maximumParts {
            let candidate = URL(fileURLWithPath: base.path + "\(index)")
            guard FileManager.default.fileExists(atPath: candidate.path) else { break }
            urls.append(candidate)
        }
        return urls
    }

    static func totalSize(of urls: [URL]) -> Int {
        urls.reduce(0) { total, url in
            let size =
                (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size]
                as? NSNumber
            return total + (size?.intValue ?? 0)
        }
    }

    /// Appends every rotated part to the named file and removes the parts.
    /// Pure record concatenation: a pcap global header followed by records, so
    /// the result is the same file a non-rotating capture would have written.
    @discardableResult
    static func mergeParts(base: URL) throws -> URL {
        let parts = partURLs(base: base)
        guard parts.count > 1 else { return base }

        let globalHeader = try headerBytes(of: parts[0])
        for part in parts.dropFirst() where try headerBytes(of: part) != globalHeader {
            throw CaptureFileError.linkTypeMismatch
        }

        let writer = try FileHandle(forWritingTo: base)
        defer { try? writer.close() }
        try writer.seekToEnd()

        for part in parts.dropFirst() {
            let reader = try FileHandle(forReadingFrom: part)
            defer { try? reader.close() }
            try reader.seek(toOffset: UInt64(globalHeaderLength))
            while let chunk = try reader.read(upToCount: 4 << 20), !chunk.isEmpty {
                try writer.write(contentsOf: chunk)
            }
            try? FileManager.default.removeItem(at: part)
        }
        return base
    }

    private static func headerBytes(of url: URL) throws -> Data {
        guard let reader = try? FileHandle(forReadingFrom: url) else {
            throw CaptureFileError.unreadable(url.lastPathComponent)
        }
        defer { try? reader.close() }
        guard let data = try reader.read(upToCount: globalHeaderLength),
            data.count == globalHeaderLength
        else {
            throw CaptureFileError.unreadable(url.lastPathComponent)
        }
        return data
    }
}

/// Rewrites a classic pcap so data frames keep only their headers and at most
/// `maxDataFrameBytes` captured bytes, while management and control frames stay
/// whole. This is the offline half of Airtool-style frame slicing: tcpdump has
/// one snaplen for every frame, so slicing per frame type has to happen here.
enum PcapDataFrameSlicer {
    /// Returns nil when the file is not a classic pcap (pcapng keeps its own
    /// block structure and is left untouched).
    static func slice(_ data: Data, maxDataFrameBytes: Int) -> Data? {
        guard maxDataFrameBytes > 0, data.count >= CaptureFiles.globalHeaderLength else {
            return nil
        }
        guard let byteOrder = byteOrder(of: data) else { return nil }
        let linkType = readUInt32(data, at: 20, order: byteOrder)

        var output = Data(data.prefix(CaptureFiles.globalHeaderLength))
        output.reserveCapacity(min(data.count, 8 << 20))
        var offset = CaptureFiles.globalHeaderLength

        while offset + 16 <= data.count {
            let included = Int(readUInt32(data, at: offset + 8, order: byteOrder))
            let packetStart = offset + 16
            guard included >= 0, packetStart + included <= data.count else { break }

            var kept = included
            if isDataFrame(
                data, packetStart: packetStart, included: included, linkType: linkType),
                included > maxDataFrameBytes
            {
                kept = maxDataFrameBytes
            }

            var recordHeader = data.subdata(in: offset..<(offset + 16))
            recordHeader.replaceSubrange(
                8..<12, with: bytes(UInt32(kept), order: byteOrder))
            output.append(recordHeader)
            output.append(data.subdata(in: packetStart..<(packetStart + kept)))
            offset = packetStart + included
        }
        return output
    }

    /// Slices the file in place. Returns false when the file is not a classic
    /// pcap or nothing needed truncating.
    @discardableResult
    static func sliceInPlace(url: URL, maxDataFrameBytes: Int) throws -> Bool {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let sliced = slice(data, maxDataFrameBytes: maxDataFrameBytes),
            sliced.count != data.count
        else { return false }
        try sliced.write(to: url, options: .atomic)
        return true
    }

    // MARK: - Frame inspection

    private static func isDataFrame(
        _ data: Data, packetStart: Int, included: Int, linkType: UInt32
    ) -> Bool {
        let headerStart: Int
        switch linkType {
        case 105:  // bare 802.11
            headerStart = packetStart
        case 127:  // radiotap
            guard included >= 4 else { return false }
            let radiotapLength = Int(readUInt16(data, at: packetStart + 2, order: .little))
            guard radiotapLength >= 8, radiotapLength + 2 <= included else { return false }
            headerStart = packetStart + radiotapLength
        default:
            return false
        }
        guard headerStart + 2 <= packetStart + included else { return false }
        let frameControl = readUInt16(data, at: headerStart, order: .little)
        let type = (frameControl >> 2) & 0x3
        return type == 2  // data
    }

    // MARK: - Byte helpers

    private enum ByteOrder {
        case little
        case big
    }

    private static func byteOrder(of data: Data) -> ByteOrder? {
        switch readUInt32(data, at: 0, order: .little) {
        case 0xA1B2_C3D4, 0xA1B2_3C4D: return .little
        case 0xD4C3_B2A1, 0x4D3C_B2A1: return .big
        default: return nil
        }
    }

    private static func readUInt16(_ data: Data, at offset: Int, order: ByteOrder) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let low = UInt16(data[data.startIndex + offset])
        let high = UInt16(data[data.startIndex + offset + 1])
        return order == .little ? low | (high << 8) : (low << 8) | high
    }

    private static func readUInt32(_ data: Data, at offset: Int, order: ByteOrder) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        for index in 0..<4 {
            let byte = UInt32(data[data.startIndex + offset + index])
            if order == .little {
                value |= byte << (8 * UInt32(index))
            } else {
                value = (value << 8) | byte
            }
        }
        return value
    }

    private static func bytes(_ value: UInt32, order: ByteOrder) -> [UInt8] {
        if order == .little {
            return [
                UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF),
            ]
        }
        return [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ]
    }
}
