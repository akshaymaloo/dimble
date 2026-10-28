import CryptoKit
import Darwin
import Foundation
import Security

/// Derived from an executable inside our own app, never from a peer's claims.
/// Ad-hoc development builds are pinned to their code hash; signed releases
/// use the executable's designated identifier and signing authority.
public final class HelperPeerIdentity: @unchecked Sendable {
    private let requirement: SecRequirement
    private let executableURL: URL

    public init?(executableURL: URL) {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        self.requirement = requirement
        self.executableURL = executableURL.resolvingSymlinksInPath().standardizedFileURL
    }

    fileprivate func accepts(socket: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(socket, &uid, &gid) == 0, uid == geteuid() else { return false }
        var token = audit_token_t()
        var size = socklen_t(MemoryLayout.size(ofValue: token))
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0,
              size == MemoryLayout.size(ofValue: token) else { return false }
        let audit = withUnsafeBytes(of: token) { Data($0) }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(
            nil, [kSecGuestAttributeAudit: audit] as CFDictionary, [], &code
        ) == errSecSuccess, let code else { return false }
        guard SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        // A copied, legitimately signed helper under an attacker's parent
        // bundle must not become a trusted helper for this app.
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let fields = information as? [String: Any],
              let executable = fields[kSecCodeInfoMainExecutable as String] as? URL else { return false }
        return executable.resolvingSymlinksInPath().standardizedFileURL == executableURL
    }
}

/// A bounded local socket transport. Both ends verify the kernel-provided
/// peer audit token before sending or accepting application data.
public final class HelperListener: @unchecked Sendable {
    private let source: DispatchSourceRead
    private let path: String

    public init?(
        name: String, peers: [String: HelperPeerIdentity],
        handler: @escaping @Sendable (Data, String) -> Void
    ) {
        guard !peers.isEmpty, let path = HelperLink.path(for: name),
              var address = HelperLink.address(for: path) else { return nil }
        let fd = HelperLink.makeSocket()
        guard fd >= 0 else { return nil }
        // A live owner (trusted or not) is never replaced. Only a stale
        // socket in our private user directory may be unlinked.
        if HelperLink.connect(fd, address) == 0 {
            close(fd)
            return nil
        }
        if errno != ENOENT && errno != ECONNREFUSED {
            close(fd)
            return nil
        }
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { close(fd); return nil }
        guard listen(fd, 8) == 0 else {
            close(fd)
            unlink(path)
            return nil
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        self.path = path
        let queue = DispatchQueue(label: "app.fif7y.Pelmet.helper-link")
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            HelperLink.configure(client)
            guard let peer = peers.first(where: { $0.value.accepts(socket: client) })?.key,
                  let data = HelperLink.receive(client) else { return }
            handler(data, peer)
            _ = HelperLink.write(Data([1]), to: client)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
        unlink(path)
    }
}

public enum HelperLink {
    public static let maximumMessageBytes = 4 * 1024 * 1024

    @discardableResult
    public static func send(_ data: Data, to name: String, peer: HelperPeerIdentity) -> Bool {
        guard !data.isEmpty, data.count <= maximumMessageBytes,
              let path = path(for: name), let address = address(for: path) else { return false }
        let fd = makeSocket()
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard connect(fd, address) == 0, peer.accepts(socket: fd) else { return false }
        var count = UInt32(data.count).bigEndian
        let header = withUnsafeBytes(of: &count) { Data($0) }
        guard write(header, to: fd), write(data, to: fd),
              let reply = read(1, from: fd) else { return false }
        return reply == Data([1])
    }

    fileprivate static func path(for name: String) -> String? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dimble-ipc")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { return nil }
        let key = SHA256.hash(data: Data(name.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).path
    }

    fileprivate static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    fileprivate static func makeSocket() -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd >= 0 { configure(fd) }
        return fd
    }

    fileprivate static func configure(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, 0)
        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
    }

    fileprivate static func connect(_ fd: Int32, _ address: sockaddr_un) -> Int32 {
        // A full listen queue must not hang the UI while a helper is busy.
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        defer { _ = fcntl(fd, F_SETFL, 0) }
        var address = address
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 { return 0 }
        guard errno == EINPROGRESS else { return -1 }
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&descriptor, 1, 250) > 0 else { errno = ETIMEDOUT; return -1 }
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout.size(ofValue: error))
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0 else { return -1 }
        if error != 0 { errno = error; return -1 }
        return 0
    }

    fileprivate static func receive(_ fd: Int32) -> Data? {
        guard let header = read(4, from: fd) else { return nil }
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0, count <= maximumMessageBytes else { return nil }
        return read(count, from: fd)
    }

    private static func read(_ count: Int, from fd: Int32) -> Data? {
        var data = Data(count: count)
        let complete = data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                let received = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
                if received < 0, errno == EINTR { continue }
                guard received > 0 else { return false }
                offset += received
            }
            return true
        }
        return complete ? data : nil
    }

    fileprivate static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < data.count {
                let sent = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), data.count - offset)
                if sent < 0, errno == EINTR { continue }
                guard sent > 0 else { return false }
                offset += sent
            }
            return true
        }
    }
}
