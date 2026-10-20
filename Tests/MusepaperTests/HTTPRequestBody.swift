import Foundation

extension URLRequest {
    /// URLSession can move httpBody into a stream before handing it to URLProtocol.
    func capturingBody() -> URLRequest {
        guard httpBody == nil, let stream = httpBodyStream else { return self }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        var captured = self
        captured.httpBodyStream = nil
        captured.httpBody = data
        return captured
    }
}
