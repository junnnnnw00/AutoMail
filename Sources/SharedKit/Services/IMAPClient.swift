import Foundation
import Network

public struct IMAPMessage: Sendable {
    public let uid: UInt32
    public let from: String
    public let fromName: String?
    public let subject: String
    public let body: String
    public let date: Date
    public let messageId: String
}

public protocol IMAPClientProtocol: AnyObject, Sendable {
    func connect() async throws
    func login() async throws
    func selectFolder(_ folder: String) async throws
    func listFolders() async throws -> [String]
    func createFolder(_ name: String) async throws
    func fetchUnseen(excluding knownUIDs: Set<UInt32>) async throws -> [IMAPMessage]
    func move(uid: UInt32, toFolder: String) async throws
    func delete(uid: UInt32) async throws
    func idle(onChange: @Sendable @escaping () -> Void) async throws
    func disconnect() async
}

public final class IMAPClient: IMAPClientProtocol, @unchecked Sendable {
    private let creds: IMAPCredentials
    private var connection: NWConnection?
    private var tagCounter = 0
    private let queue = DispatchQueue(label: "com.junwoo.mailsorter.imap")
    private var buffer = Data()
    private var responseContinuations: [String: CheckedContinuation<[String], Error>] = [:]
    private var idleHandler: (@Sendable () -> Void)?
    private var connected = false

    public init(creds: IMAPCredentials) {
        self.creds = creds
    }

    private func nextTag() -> String {
        tagCounter += 1
        return String(format: "a%04d", tagCounter)
    }

    public func connect() async throws {
        let host = NWEndpoint.Host(creds.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(creds.port))
        let params: NWParameters = creds.useTLS ? .tls : .tcp
        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.connected = true
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    self?.connected = false
                default:
                    break
                }
            }
            conn.start(queue: queue)
            self.startReading()
        }
        _ = try await readGreeting()
    }

    private func startReading() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                self.connected = false
                return
            }
            self.startReading()
        }
    }

    private func processBuffer() {
        while !buffer.isEmpty {
            if let literalSize = pendingLiteralSize {
                if buffer.count >= literalSize {
                    let literalData = buffer.prefix(literalSize)
                    buffer.removeFirst(literalSize)
                    let text = String(data: literalData, encoding: .utf8) ?? String(data: literalData, encoding: .isoLatin1) ?? ""
                    literalAccumulator += text
                    pendingLiteralSize = nil
                } else {
                    // Need more data for literal
                    break
                }
            } else {
                guard let range = buffer.range(of: Data([0x0D, 0x0A])) else {
                    break // Need more data for a full line
                }
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                let line = String(data: lineData, encoding: .utf8) ?? String(data: lineData, encoding: .isoLatin1) ?? ""
                
                if let size = extractLiteralSize(from: line) {
                    literalAccumulator = line + "\n"
                    pendingLiteralSize = size
                } else {
                    if !literalAccumulator.isEmpty {
                        handleLine(literalAccumulator + line)
                        literalAccumulator = ""
                    } else {
                        handleLine(line)
                    }
                }
            }
        }
    }

    private var pendingLiteralSize: Int? = nil
    private var literalAccumulator: String = ""

    private func extractLiteralSize(from line: String) -> Int? {
        let pattern = #"\{(\d+)\}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        if let range = Range(match.range(at: 1), in: line) {
            return Int(line[range])
        }
        return nil
    }

    private var pendingTag: String?
    private var pendingLines: [String] = []
    private var pendingContinuation: CheckedContinuation<[String], Error>?
    private var isAuthenticating = false

    private func handleLine(_ line: String) {
        MailSorterLog.imap.debug("S: \(line, privacy: .public)")
        
        if line.hasPrefix("* ") && (line.contains("EXISTS") || line.contains("EXPUNGE") || line.contains("RECENT")) {
            if let handler = idleHandler {
                self.idleHandler = nil // Prevent multiple triggers
                connection?.send(content: "DONE\r\n".data(using: .utf8), completion: .contentProcessed { _ in })
                handler()
            }
        }
        if isAuthenticating && line.hasPrefix("+ ") {
            connection?.send(content: "\r\n".data(using: .utf8), completion: .contentProcessed { _ in })
        }
        
        guard let tag = pendingTag else { return }
        
        pendingLines.append(line)
        if line.hasPrefix(tag + " ") {
            let lines = pendingLines
            pendingTag = nil
            pendingLines = []
            if line.contains(" OK ") {
                pendingContinuation?.resume(returning: lines)
            } else {
                pendingContinuation?.resume(throwing: NSError(domain: "IMAP", code: 1, userInfo: [NSLocalizedDescriptionKey: line]))
            }
            pendingContinuation = nil
        }
    }

    private func readGreeting() async throws -> String {
        try await Task.sleep(nanoseconds: 200_000_000)
        return ""
    }

    private func send(_ command: String) async throws -> [String] {
        let tag = nextTag()
        let line = "\(tag) \(command)\r\n"
        MailSorterLog.imap.debug("C: \(tag, privacy: .public) \(command, privacy: .public)")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            self.pendingTag = tag
            self.pendingLines = []
            self.pendingContinuation = continuation
            guard let conn = self.connection else {
                continuation.resume(throwing: NSError(domain: "IMAP", code: 2))
                return
            }
            conn.send(content: line.data(using: .utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                }
            })
        }
    }

    public func login() async throws {
        let escapedUser = creds.username.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPwd = creds.password.replacingOccurrences(of: "\"", with: "\\\"")
        _ = try await send("LOGIN \"\(escapedUser)\" \"\(escapedPwd)\"")
    }

    public func authenticateXOAUTH2(username: String, token: String) async throws {
        let oauthStr = "user=\(username)\u{01}auth=Bearer \(token)\u{01}\u{01}"
        let b64 = Data(oauthStr.utf8).base64EncodedString()
        isAuthenticating = true
        defer { isAuthenticating = false }
        _ = try await send("AUTHENTICATE XOAUTH2 \(b64)")
    }

    public func selectFolder(_ folder: String) async throws {
        _ = try await send("SELECT \"\(folder)\"")
    }

    public func listFolders() async throws -> [String] {
        let lines = try await send("LIST \"\" \"*\"")
        return lines.compactMap { line -> String? in
            guard line.hasPrefix("* LIST") else { return nil }
            if let lastQuote = line.range(of: "\"", options: .backwards),
               let firstQuote = line.range(of: "\"", options: .backwards, range: line.startIndex..<lastQuote.lowerBound) {
                return String(line[firstQuote.upperBound..<lastQuote.lowerBound])
            }
            return nil
        }
    }

    public func createFolder(_ name: String) async throws {
        do {
            _ = try await send("CREATE \"\(name)\"")
        } catch {
            MailSorterLog.imap.info("CREATE \(name, privacy: .public) maybe exists: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func fetchUnseen(excluding knownUIDs: Set<UInt32> = []) async throws -> [IMAPMessage] {
        let searchLines = try await send("UID SEARCH UNSEEN")
        var uids: [UInt32] = searchLines
            .filter { $0.hasPrefix("* SEARCH") }
            .flatMap { line -> [UInt32] in
                let parts = line.dropFirst("* SEARCH".count).split(separator: " ")
                return parts.compactMap { UInt32($0) }
            }
        
        uids = uids.filter { !knownUIDs.contains($0) }
        
        // Limit to 50 unseen emails at once to avoid blocking UI or daemon forever
        let limit = 50
        if uids.count > limit {
            uids = Array(uids.suffix(limit))
        }

        var messages: [IMAPMessage] = []
        for uid in uids {
            let lines = try await send("UID FETCH \(uid) BODY.PEEK[]")
            var joined = lines.joined(separator: "\n")
            
            // IMAP FETCH 응답의 시작 부분 찌꺼기 제거: 예) "* 1 FETCH (UID 1 BODY[] {1234}"
            if let braceRange = joined.range(of: "\\{\\d+\\}\\s*\\n", options: .regularExpression) {
                joined = String(joined[braceRange.upperBound...])
            } else if let bodyBracketRange = joined.range(of: "BODY[]") {
                joined = String(joined[bodyBracketRange.upperBound...])
            }

            var bodyText = ""
            var headersText = ""
            // 헤더와 본문을 분리하는 첫 번째 빈 줄 찾기
            if let separatorRange = joined.range(of: "\n\n") ?? joined.range(of: "\r\n\r\n") {
                headersText = String(joined[..<separatorRange.lowerBound])
                bodyText = String(joined[separatorRange.upperBound...])
                
                // 맨 마지막에 붙어있는 IMAP 응답 찌꺼기 제거 (ex: ") \n a0008 OK Success")
                if let lastParen = bodyText.lastIndex(of: ")") {
                    let suffix = bodyText[lastParen...]
                    if suffix.contains(" OK ") || suffix.contains(" BAD ") || suffix.contains(" FETCH ") {
                        bodyText = String(bodyText[..<lastParen])
                    }
                }
                bodyText = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                headersText = joined
                bodyText = joined
            }

            let from = extractHeader(name: "From", in: headersText) ?? ""
            let subject = decodeMIMEHeader(extractHeader(name: "Subject", in: headersText) ?? "")
            let dateStr = extractHeader(name: "Date", in: headersText) ?? ""
            let messageId = extractHeader(name: "Message-ID", in: headersText) ?? UUID().uuidString
            let date = parseRFC5322Date(dateStr) ?? Date()
            let (addr, name) = parseAddress(from)
            
            // MIME Multipart 디코딩 (HTML 또는 Plain Text 추출)
            bodyText = extractMIMEText(from: bodyText, headers: headersText)

            messages.append(IMAPMessage(
                uid: uid,
                from: addr,
                fromName: name,
                subject: subject,
                body: bodyText,
                date: date,
                messageId: messageId
            ))
        }
        return messages
    }

    public func move(uid: UInt32, toFolder: String) async throws {
        do {
            _ = try await send("UID MOVE \(uid) \"\(toFolder)\"")
        } catch {
            _ = try await send("UID COPY \(uid) \"\(toFolder)\"")
            _ = try await send("UID STORE \(uid) +FLAGS (\\Deleted)")
            _ = try await send("EXPUNGE")
        }
    }

    public func delete(uid: UInt32) async throws {
        _ = try await send("UID STORE \(uid) +FLAGS (\\Deleted)")
        _ = try await send("EXPUNGE")
    }

    public func idle(onChange: @Sendable @escaping () -> Void = {}) async throws {
        self.idleHandler = onChange
        
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 28 * 60 * 1_000_000_000)
            if !Task.isCancelled {
                self.connection?.send(content: "DONE\r\n".data(using: .utf8), completion: .contentProcessed { _ in })
            }
        }
        
        _ = try await send("IDLE")
        timeoutTask.cancel()
    }

    public func disconnect() async {
        _ = try? await send("LOGOUT")
        connection?.cancel()
        connection = nil
        connected = false
    }
}

private func extractMIMEText(from rawBody: String, headers: String? = nil) -> String {
    let searchArea = (headers ?? "") + "\n" + rawBody
    let boundaryPattern = #"boundary="?([^"\s;]+)"?"#
    var boundaries: Set<String> = []
    if let regex = try? NSRegularExpression(pattern: boundaryPattern) {
        let matches = regex.matches(in: searchArea, range: NSRange(searchArea.startIndex..., in: searchArea))
        for match in matches {
            if let range = Range(match.range(at: 1), in: searchArea) {
                boundaries.insert(String(searchArea[range]))
            }
        }
    }

    let splitRegex: NSRegularExpression?
    if !boundaries.isEmpty {
        let escapedBoundaries = boundaries.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let splitPattern = "(?m)^--(?:" + escapedBoundaries + ")(?:--)?\\s*$"
        splitRegex = try? NSRegularExpression(pattern: splitPattern)
    } else {
        splitRegex = try? NSRegularExpression(pattern: #"(?m)^--.+?$"#)
    }

    guard let regex = splitRegex else { return processPart(rawBody, topLevelHeaders: headers) }

    let matches = regex.matches(in: rawBody, range: NSRange(rawBody.startIndex..., in: rawBody))
    if matches.count <= 1 { return processPart(rawBody, topLevelHeaders: headers) }

    var parts: [String] = []
    let nsBody = rawBody as NSString
    for i in 0..<matches.count {
        let start = matches[i].range.upperBound
        let end = i < matches.count - 1 ? matches[i+1].range.lowerBound : nsBody.length
        let partString = nsBody.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !partString.isEmpty { parts.append(partString) }
    }

    // Collect CID inline images so HTML <img src="cid:xxx"> can be resolved
    var cidMap: [String: String] = [:]
    for part in parts {
        if let (cid, dataURI) = extractCIDImage(from: part) {
            cidMap[cid] = dataURI
        }
    }

    var htmlPart: String?
    var plainPart: String?
    for part in parts {
        if part.localizedCaseInsensitiveContains("Content-Type: text/html") {
            if htmlPart == nil { htmlPart = part }
        } else if part.localizedCaseInsensitiveContains("Content-Type: text/plain") {
            if plainPart == nil { plainPart = part }
        }
    }

    let selectedPart = htmlPart ?? plainPart ?? parts.first
    var html = selectedPart != nil ? processPart(selectedPart!) : processPart(rawBody, topLevelHeaders: headers)

    for (cid, dataURI) in cidMap {
        html = html.replacingOccurrences(of: "cid:\(cid)", with: dataURI, options: .caseInsensitive)
    }

    return html
}

private func extractCIDImage(from part: String) -> (String, String)? {
    guard let sep = part.range(of: "\n\n") ?? part.range(of: "\r\n\r\n") else { return nil }
    let headers = String(part[..<sep.lowerBound])
    let content = String(part[sep.upperBound...])

    guard headers.localizedCaseInsensitiveContains("base64") else { return nil }

    // Extract Content-ID (with or without angle brackets or quotes)
    let cidPattern = #"(?im)^Content-ID:\s*(?:<|")?([^>"\s\r\n]+)(?:>|")?"#
    guard let cidRegex = try? NSRegularExpression(pattern: cidPattern),
          let cidMatch = cidRegex.firstMatch(in: headers, range: NSRange(headers.startIndex..., in: headers)),
          let cidRange = Range(cidMatch.range(at: 1), in: headers) else { return nil }
    let cid = String(headers[cidRange])

    // Extract MIME type
    let ctPattern = #"(?im)^Content-Type:\s*([^;\s\r\n]+)"#
    var mimeType: String
    if let ctRegex = try? NSRegularExpression(pattern: ctPattern),
       let ctMatch = ctRegex.firstMatch(in: headers, range: NSRange(headers.startIndex..., in: headers)),
       let ctRange = Range(ctMatch.range(at: 1), in: headers) {
        mimeType = String(headers[ctRange]).trimmingCharacters(in: .whitespaces).lowercased()
    } else {
        mimeType = "image/jpeg"
    }
    
    if !mimeType.hasPrefix("image/") {
        mimeType = "image/jpeg"
    }

    let b64 = content.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
    guard Data(base64Encoded: b64, options: .ignoreUnknownCharacters) != nil else { return nil }

    return (cid, "data:\(mimeType);base64,\(b64)")
}

private func processPart(_ part: String, topLevelHeaders: String? = nil) -> String {
    let separatorRange = part.range(of: "\n\n") ?? part.range(of: "\r\n\r\n")
    var headers = topLevelHeaders ?? ""
    var content = part
    if let sep = separatorRange {
        let possibleHeaders = String(part[part.startIndex..<sep.lowerBound])
        if possibleHeaders.localizedCaseInsensitiveContains("Content-Type:") || possibleHeaders.localizedCaseInsensitiveContains("Content-Transfer-Encoding:") {
            headers += "\n" + possibleHeaders
            content = String(part[sep.upperBound..<part.endIndex])
        }
    }

    let charset = extractMIMECharset(from: headers)
    let isBase64 = headers.localizedCaseInsensitiveContains("base64") || part.prefix(1000).localizedCaseInsensitiveContains("Content-Transfer-Encoding: base64")
    let isQP = headers.localizedCaseInsensitiveContains("quoted-printable") || part.prefix(1000).localizedCaseInsensitiveContains("Content-Transfer-Encoding: quoted-printable")

    if isQP {
        content = decodeQuotedPrintable(content, charset: charset)
    } else if isBase64 {
        let base64String = content.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        if let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) {
            let enc = stringEncoding(charset)
            content = String(data: data, encoding: enc)
                ?? String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(data: data, encoding: .ascii)
                ?? content
        }
    }

    let isHtml = headers.localizedCaseInsensitiveContains("text/html") || part.prefix(1000).localizedCaseInsensitiveContains("text/html")
    if isHtml {
        return content
    } else {
        let safeText = content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<pre style=\"white-space: pre-wrap; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;\">\(safeText)</pre>"
    }
}

private func extractMIMECharset(from headers: String) -> String {
    guard let keyRange = headers.range(of: "charset", options: .caseInsensitive) else { return "utf-8" }
    let afterKey = headers[keyRange.upperBound...]
    guard let eqRange = afterKey.range(of: "=") else { return "utf-8" }
    var value = String(afterKey[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("\"") { value = String(value.dropFirst()) }
    let terminators = CharacterSet(charactersIn: ";\r\n\"")
    if let end = value.rangeOfCharacter(from: terminators) {
        value = String(value[..<end.lowerBound])
    }
    value = value.trimmingCharacters(in: .whitespaces)
    return value.isEmpty ? "utf-8" : value
}

private func decodeQuotedPrintable(_ input: String, charset: String = "utf-8") -> String {
    let stripped = input
        .replacingOccurrences(of: "=\r\n", with: "")
        .replacingOccurrences(of: "=\n", with: "")
    var bytes: [UInt8] = []
    var i = stripped.startIndex
    while i < stripped.endIndex {
        let c = stripped[i]
        if c == "=",
           let next1 = stripped.index(i, offsetBy: 1, limitedBy: stripped.endIndex),
           let next2 = stripped.index(i, offsetBy: 2, limitedBy: stripped.endIndex),
           next1 < stripped.endIndex, next2 < stripped.endIndex {
            let hexStr = String(stripped[next1...next2])
            if let byte = UInt8(hexStr, radix: 16) {
                bytes.append(byte)
                i = stripped.index(after: next2)
                continue
            }
        }
        if let ascii = c.asciiValue {
            bytes.append(ascii)
        } else {
            bytes.append(contentsOf: String(c).utf8)
        }
        i = stripped.index(after: i)
    }
    let data = Data(bytes)
    let enc = stringEncoding(charset)
    return String(data: data, encoding: enc)
        ?? String(data: data, encoding: .utf8)
        ?? input
}

private func extractHeader(name: String, in text: String) -> String? {
    let pattern = "(?im)^\(name):\\s*(.+(?:\\r?\\n[ \\t]+.+)*)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
    if let r = Range(match.range(at: 1), in: text) {
        return text[r].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
}

private func decodeMIMEHeader(_ s: String) -> String {
    // RFC 2822 unfolding: remove only the CRLF/LF before WSP, keep the WSP itself
    let cleanS = s.replacingOccurrences(of: "\r\n\t", with: "\t")
                  .replacingOccurrences(of: "\r\n ", with: " ")
                  .replacingOccurrences(of: "\n\t", with: "\t")
                  .replacingOccurrences(of: "\n ", with: " ")
    let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]+)\?="#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return cleanS }
    let ns = cleanS as NSString
    let matches = regex.matches(in: cleanS, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return cleanS }

    var result = ""
    var cursor = cleanS.startIndex
    var lastMatchEnd: String.Index? = nil

    for match in matches {
        guard let matchRange = Range(match.range, in: cleanS) else { continue }
        let between = String(cleanS[cursor..<matchRange.lowerBound])

        // RFC 2047 §6.2: linear white space between adjacent encoded-words is ignored
        if lastMatchEnd != nil && between.allSatisfy(\.isWhitespace) {
            // skip whitespace between encoded-words
        } else {
            result += between
        }

        let charset = ns.substring(with: match.range(at: 1))
        let encoding = ns.substring(with: match.range(at: 2)).uppercased()
        let payload = ns.substring(with: match.range(at: 3))

        var decoded = ""
        if encoding == "B" {
            var b64 = payload
            let rem = b64.count % 4
            if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
            
            if let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                let enc = stringEncoding(charset)
                decoded = String(data: data, encoding: enc)
                    ?? String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
            }
        } else if encoding == "Q" {
            decoded = decodeQuotedPrintable(payload.replacingOccurrences(of: "_", with: " "), charset: charset)
        }

        result += decoded.isEmpty ? ns.substring(with: match.range) : decoded
        cursor = matchRange.upperBound
        lastMatchEnd = matchRange.upperBound
    }
    result += String(cleanS[cursor...])
    return result
}

private func stringEncoding(_ charset: String) -> String.Encoding {
    let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
    if cf == kCFStringEncodingInvalidId { return .utf8 }
    return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
}

private func parseRFC5322Date(_ s: String) -> Date? {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    let formats = [
        "EEE, d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "d MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm Z",
        "d MMM yyyy HH:mm Z",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd MMM yyyy HH:mm Z",
    ]
    
    var trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    // Remove trailing comments like (KST) or (UTC)
    if let regex = try? NSRegularExpression(pattern: #" \([^)]+\)$"#) {
        trimmed = regex.stringByReplacingMatches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed), withTemplate: "")
    }
    // Handle double spaces
    trimmed = trimmed.replacingOccurrences(of: "  ", with: " ")
    
    for fmt in formats {
        df.dateFormat = fmt
        if let date = df.date(from: trimmed) { return date }
    }
    return nil
}

private func parseAddress(_ s: String) -> (String, String?) {
    if let lt = s.firstIndex(of: "<"), let gt = s.firstIndex(of: ">"), lt < gt {
        let addr = String(s[s.index(after: lt)..<gt])
        let nameRaw = s[s.startIndex..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        let name = decodeMIMEHeader(nameRaw)
        return (addr, name.isEmpty ? nil : name)
    }
    let decoded = decodeMIMEHeader(s.trimmingCharacters(in: .whitespaces))
    return (decoded, nil)
}
