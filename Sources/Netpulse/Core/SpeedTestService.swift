import Foundation

/// An on-demand internet speed test - the one place in Netpulse that makes
/// an actual network request. Everything else in the app (usage tracking,
/// Wi-Fi names, the data-budget notification) is a purely local read; there is no way
/// to measure real throughput without moving real bytes across the internet,
/// so this only ever runs when you explicitly tap "Test Speed" - never in
/// the background, never automatically.
///
/// Uses Cloudflare's public speed-test endpoints (the same infrastructure
/// behind speed.cloudflare.com and many third-party speed test tools) -
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

    private static let downloadBytes = 25_000_000  // 25 MB - enough for a stable reading without dragging on
    private static let uploadBytes = 10_000_000     // 10 MB

    private let session: URLSession
    private var currentTask: URLSessionTask?
    private var progressTimer: DispatchSourceTimer?
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
        progressTimer?.cancel()
        progressTimer = nil
    }

    /// Pings, then downloads, then uploads, reporting each stage as it
    /// starts so the UI can show real progress rather than one long spinner.
    /// `onProgress` fires roughly every 200ms during the download and upload
    /// stages with the instantaneous throughput measured so far (Mbps), so
    /// the UI can animate a live gauge instead of waiting for the final
    /// number at the end of each stage.
    func run(onStageChange: @escaping (SpeedTestStage) -> Void, onProgress: @escaping (Double) -> Void) {
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

            self.measureDownload(onProgress: onProgress) { downloadMbps in
                guard self.generation == myGeneration else { return }
                guard let downloadMbps else {
                    onStageChange(.failed)
                    return
                }
                onStageChange(.upload)

                self.measureUpload(onProgress: onProgress) { uploadMbps in
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

    /// Polls a task's cumulative byte counter on a fixed interval and turns
    /// the delta since the last poll into an instantaneous Mbps reading -
    /// `URLSession` only hands back a single total at completion, so this is
    /// the one place that manufactures a "live" number during the transfer.
    private func startProgressTimer(byteCount: @escaping () -> Int64, onProgress: @escaping (Double) -> Void) {
        progressTimer?.cancel()
        var lastBytes: Int64 = 0
        var lastTime = Date()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler {
            let bytes = byteCount()
            let now = Date()
            let deltaBytes = bytes - lastBytes
            let deltaTime = now.timeIntervalSince(lastTime)
            lastBytes = bytes
            lastTime = now
            guard deltaTime > 0, deltaBytes > 0 else { return }
            onProgress((Double(deltaBytes) * 8) / deltaTime / 1_000_000)
        }
        timer.resume()
        progressTimer = timer
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

    private func measureDownload(onProgress: @escaping (Double) -> Void, completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(Self.downloadBytes)") else {
            completion(nil)
            return
        }
        let start = Date()
        let task = session.dataTask(with: url) { [weak self] data, _, error in
            self?.progressTimer?.cancel()
            self?.progressTimer = nil
            let elapsed = Date().timeIntervalSince(start)
            guard error == nil, let data, elapsed > 0.05 else {
                completion(nil)
                return
            }
            completion((Double(data.count) * 8) / elapsed / 1_000_000)
        }
        currentTask = task
        startProgressTimer(byteCount: { [weak task] in task?.countOfBytesReceived ?? 0 }, onProgress: onProgress)
        task.resume()
    }

    private func measureUpload(onProgress: @escaping (Double) -> Void, completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        // Content doesn't matter, only size - this never carries anything
        // about you beyond the bytes themselves and standard HTTP headers.
        let payload = Data(count: Self.uploadBytes)

        let start = Date()
        let task = session.uploadTask(with: request, from: payload) { [weak self] _, _, error in
            self?.progressTimer?.cancel()
            self?.progressTimer = nil
            let elapsed = Date().timeIntervalSince(start)
            guard error == nil, elapsed > 0.05 else {
                completion(nil)
                return
            }
            completion((Double(Self.uploadBytes) * 8) / elapsed / 1_000_000)
        }
        currentTask = task
        startProgressTimer(byteCount: { [weak task] in task?.countOfBytesSent ?? 0 }, onProgress: onProgress)
        task.resume()
    }
}
