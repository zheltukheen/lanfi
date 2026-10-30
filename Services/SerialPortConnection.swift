import Foundation
import Darwin

/// Minimal POSIX serial-port wrapper (no external dependencies).
/// RF Explorer enumerates as a CP210x USB-UART bridge (`/dev/cu.usbserial-*`
/// or `/dev/cu.SLAB_USBtoUART`); 500000 8N1 is the documented default.
final class SerialPortConnection {
    enum ConnectionError: LocalizedError {
        case openFailed(String)
        case configureFailed

        var errorDescription: String? {
            switch self {
            case .openFailed(let path): return "Cannot open serial port \(path)."
            case .configureFailed: return "Cannot configure the serial port."
            }
        }
    }

    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "lanfi.serial.read")
    private var reading = false

    /// Candidate RF Explorer ports present on this Mac.
    static func availablePorts() -> [String] {
        let patterns = ["/dev/cu.usbserial-", "/dev/cu.SLAB_USBtoUART", "/dev/cu.wchusbserial"]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else { return [] }
        return patterns.flatMap { pattern in
            names
                .filter {
                    $0.hasPrefix(pattern.replacingOccurrences(of: "/dev/cu.", with: ""))
                        || $0 == "cu.SLAB_USBtoUART"
                }
                .sorted()
                .map { "/dev/cu.\($0)" }
        }
    }

    var isOpen: Bool { fileDescriptor >= 0 }

    func open(path: String, baudRate: speed_t = 500_000) throws {
        close()
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw ConnectionError.openFailed(path) }
        fileDescriptor = fd
        do {
            try configure(baudRate: baudRate)
        } catch {
            close()
            throw error
        }
    }

    private func configure(baudRate: speed_t) throws {
        var settings = termios()
        guard tcgetattr(fileDescriptor, &settings) == 0 else { throw ConnectionError.configureFailed }
        cfmakeraw(&settings)
        cfsetispeed(&settings, baudRate)
        cfsetospeed(&settings, baudRate)
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        settings.c_cflag &= ~tcflag_t(CSIZE | PARENB | CSTOPB)
        settings.c_cflag |= tcflag_t(CS8)
        // On Darwin VMIN == 16 and VTIME == 17 in c_cc.
        settings.c_cc.16 = 0  // VMIN: return whatever is available
        settings.c_cc.17 = 10  // VTIME: 1 s read timeout
        guard tcsetattr(fileDescriptor, TCSANOW, &settings) == 0 else { throw ConnectionError.configureFailed }
    }

    /// Starts a blocking read loop on a background queue; the handler is
    /// called on that queue with every chunk read.
    func startReading(handler: @escaping ([UInt8]) -> Void) {
        guard isOpen, !reading else { return }
        reading = true
        let fd = fileDescriptor
        queue.async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while let self, self.reading, self.fileDescriptor == fd {
                let count = buffer.withUnsafeMutableBytes { ptr in
                    read(fd, ptr.baseAddress, ptr.count)
                }
                if count > 0 {
                    handler(Array(buffer[0..<count]))
                } else if count == 0 || (count < 0 && errno != EAGAIN) {
                    break
                } else {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
    }

    func write(_ data: Data) {
        guard isOpen else { return }
        _ = data.withUnsafeBytes { ptr in
            Darwin.write(fileDescriptor, ptr.baseAddress, ptr.count)
        }
    }

    func close() {
        guard fileDescriptor >= 0 else { return }
        reading = false
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }

    deinit { close() }
}
