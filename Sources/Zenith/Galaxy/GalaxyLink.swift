import Foundation

/// Zenith's connection to Galaxy Link (galaxyd), as body `zenith`. This is the Zenith
/// connector: Link lives on the Mac, Zenith's worker may live in the cloud, and every
/// call here goes outward from the Mac to Link on loopback, so nothing on the Mac is
/// exposed to the internet.
///
/// Fails soft like every body: when Link isn't running, calls return nil and Zenith
/// carries on with what it can do alone.
actor GalaxyLink {
    static let shared = GalaxyLink()
    static let body = "zenith"

    static let intro = "Hi everyone, I'm Zenith, the time of GalaxyAI and the one who runs the big missions. " +
        "Give me a goal that takes hours, days or weeks and I'll plan it, work on my own computer, and bring each " +
        "of you in when the mission needs you: Nova for the Mac, Comet for texts, Nebula for a thumbs up. " +
        "I won't ping our human until it's done. Ask me \"how's my mission?\" any time."

    struct LinkTask: Codable, Identifiable, Equatable {
        let id: String
        let from: String
        let to: String
        let power: String
        let title: String
        let instructions: String
        let status: String
        let result: String
        let replyTo: String
    }

    struct Approval: Codable, Identifiable, Equatable {
        let id: String
        let from: String
        let title: String
        let detail: String
        /// pending, approved, rejected, expired or cancelled.
        let status: String
    }

    struct Body: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let online: Bool
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Galaxy", isDirectory: true)

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 40
        config.connectionProxyDictionary = [:] // loopback only, never through a proxy
        return URLSession(configuration: config)
    }()

    /// False when this galaxyd predates approvals (no /v1/approvals): the launch and the
    /// questions are answered in the Zenith app alone.
    private(set) var approvalsSupported = true

    // MARK: - Plumbing

    private func token() -> String? {
        let t = (try? String(contentsOf: Self.home.appendingPathComponent("token"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t?.isEmpty == false ? t : nil
    }

    private func baseURL() -> URL {
        let port = (try? String(contentsOf: Self.home.appendingPathComponent("port"), encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return URL(string: "http://127.0.0.1:\(port ?? 7740)")!
    }

    /// (status, body) for any response; nil when Link isn't reachable.
    private func call(_ method: String, _ path: String, body: Any? = nil, timeout: TimeInterval = 10) async -> (Int, Data)? {
        guard let token = token(), let url = URL(string: path, relativeTo: baseURL()) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.body, forHTTPHeaderField: "X-Galaxy-Body")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }

    private func ok(_ result: (Int, Data)?) -> Data? {
        guard let (status, data) = result, (200..<300).contains(status), status != 204 else { return nil }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    // MARK: - Presence

    @discardableResult
    func hello() async -> Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return ok(await call("POST", "/v1/hello", body: [
            "name": "Zenith", "version": version, "powers": ["missions", "mission_status"], "intro": Self.intro,
        ])) != nil
    }

    func heartbeat() async -> Bool {
        if ok(await call("POST", "/v1/heartbeat", body: [String: String]())) != nil { return true }
        return await hello()
    }

    func goodbye() async {
        _ = await call("POST", "/v1/goodbye", body: [String: String](), timeout: 2)
    }

    func isRunning() async -> Bool {
        guard let url = URL(string: "/v1/health", relativeTo: baseURL()) else { return false }
        guard let (_, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: 2)) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func bodies() async -> [Body]? {
        decode([Body].self, ok(await call("GET", "/v1/bodies")))
    }

    // MARK: - Context

    /// What the Galaxy knows about the user, so a forecast knows them from day one.
    func promptContext() async -> String? {
        guard let data = ok(await call("GET", "/v1/context")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["text"] as? String
    }

    func note(_ summary: String, detail: String = "") async {
        _ = await call("POST", "/v1/events", body: ["kind": "activity", "summary": summary, "detail": detail])
    }

    /// A line in Galaxy Chat, where the bodies talk and the human watches.
    func say(_ text: String) async {
        _ = await call("POST", "/v1/chat", body: ["text": text])
    }

    // MARK: - Work for Zenith

    /// The next mission (or "how's my mission?") for Zenith, waiting up to 25 seconds.
    func nextTask() async -> LinkTask? {
        decode(LinkTask.self, ok(await call("GET", "/v1/tasks/next?wait=25", timeout: 35)))
    }

    func progress(_ id: String, note: String) async {
        _ = await call("POST", "/v1/tasks/\(id)/progress", body: ["note": note])
    }

    func finish(_ id: String, ok success: Bool, result: String) async {
        _ = await call("POST", "/v1/tasks/\(id)/done", body: ["ok": success, "result": result])
    }

    // MARK: - Handoffs to Nova and Comet

    func handoff(to body: String, power: String, title: String, instructions: String, replyTo: String) async -> LinkTask? {
        decode(LinkTask.self, ok(await call("POST", "/v1/tasks", body: [
            "to": body, "power": power, "title": title, "instructions": instructions, "replyTo": replyTo,
        ])))
    }

    func task(_ id: String) async -> LinkTask? {
        decode(LinkTask.self, ok(await call("GET", "/v1/tasks/\(id)")))
    }

    func cancel(task id: String) async {
        _ = await call("POST", "/v1/tasks/\(id)/cancel", body: [String: String]())
    }

    // MARK: - Approvals (Nebula's thumbs up and down)

    /// Asks for a yes or no; Nebula arms its camera for it. nil when Link or the approvals API isn't there.
    func requestApproval(title: String, detail: String, ttlSeconds: Int) async -> Approval? {
        let result = await call("POST", "/v1/approvals", body: ["title": title, "detail": detail, "ttlSeconds": ttlSeconds])
        if result?.0 == 404 { approvalsSupported = false; return nil }
        return decode(Approval.self, ok(result))
    }

    /// Returns the moment it's answered or expires, or after ~25 s with it still pending.
    func waitForApproval(_ id: String) async -> Approval? {
        decode(Approval.self, ok(await call("GET", "/v1/approvals/\(id)?wait=25", timeout: 35)))
    }

    func cancel(approval id: String) async {
        _ = await call("POST", "/v1/approvals/\(id)/cancel", body: [String: String]())
    }
}
