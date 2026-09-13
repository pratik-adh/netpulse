import Foundation

/// An on-demand internet speed test — the one place in Downtime that makes
/// an actual network request. Everything else in the app (usage tracking,
/// calendar checks, notifications) is a purely local read; there is no way
/// to measure real throughput without moving real bytes across the internet,
/// so this only ever runs when you explicitly tap "Test Speed" — never in
/// the background, never automatically.
///
/// Uses Cloudflare's public speed-test endpoints (the same infrastructure
/// behind speed.cloudflare.com and many third-party speed test tools) —
/// no API key, no account, no data attached beyond what any ordinary HTTPS
/// request carries.
struct SpeedTestResult: Equatable {
    var downloadMbps: Double
    var uploadMbps: Double
    var pingMs: Double
}

enum SpeedTestStage: Equatable {
    case idle
    case ping
    case download
    case upload
    case done(SpeedTestResult)
    case failed
}

final class SpeedTestService {

    private static let downloadBytes = 25_000_000  // 25 MB — enough for a stable reading without dragging on
    private static let uploadBytes = 10_000_000     // 10 MB

    private let session: URLSession
    private var currentTask: URLSessionTask?
    private var generation = 0

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func cancel() {
        generation += 1
        currentTask?.cancel()
        currentTask = nil
    }

    /// Pings, then downloads, then uploads, reporting each stage as it
    /// starts so the UI can show real progress rather than one long spinner.
    func run(onStageChange: @escaping (SpeedTestStage) -> Void) {
        cancel()
        let myGeneration = generation
        onStageChange(.ping)

        measurePing { [weak self] pingMs in
            guard let self, self.generation == myGeneration else { return }
            guard let pingMs else {
                onStageChange(.failed)
                return
            }
            onStageChange(.download)

            self.measureDownload { downloadMbps in
                guard self.generation == myGeneration else { return }
                guard let downloadMbps else {
                    onStageChange(.failed)
                    return
                }
                onStageChange(.upload)

                self.measureUpload { uploadMbps in
                    guard self.generation == myGeneration else { return }
                    guard let uploadMbps else {
                        onStageChange(.failed)
                        return
                    }
                    onStageChange(.done(SpeedTestResult(
                        downloadMbps: downloadMbps,
                        uploadMbps: uploadMbps,
                        pingMs: pingMs
                    )))
                }
            }
        }
    }

    // MARK: - Stages

    private func measurePing(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0") else {
            completion(nil)
            return
        }
        var samples: [Double] = []
        var failures = 0

        func sample(_ remaining: Int) {
            guard remaining > 0 else {
                completion(samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count))
                return
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let start = Date()
            let task = session.dataTask(with: request) { _, _, error in
                if error == nil {
                    samples.append(Date().timeIntervalSince(start) * 1000)
                } else {
                    failures += 1
                }
                if failures >= 3 {
                    completion(nil)
                } else {
                    sample(remaining - 1)
                }
            }
            currentTask = task
            task.resume()
        }
        sample(3)
    }

    private func measureDownload(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(Self.downloadBytes)") else {
            completion(nil)
            return
        }
        let start = Date()
        let task = session.dataTask(with: url) { data, _, error in
            let elapsed = Date().timeIntervalSince(start)
            guard error == nil, let data, elapsed > 0.05 else {
                completion(nil)
                return
            }
            completion((Double(data.count) * 8) / elapsed / 1_000_000)
        }
        currentTask = task
        task.resume()
    }

    private func measureUpload(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        // Content doesn't matter, only size — this never carries anything
        // about you beyond the bytes themselves and standard HTTP headers.
        let payload = Data(count: Self.uploadBytes)

        let start = Date()
        let task = session.uploadTask(with: request, from: payload) { _, _, error in
            let elapsed = Date().timeIntervalSince(start)
            guard error == nil, elapsed > 0.05 else {
                completion(nil)
                return
            }
            completion((Double(Self.uploadBytes) * 8) / elapsed / 1_000_000)
        }
        currentTask = task
        task.resume()
    }
}
