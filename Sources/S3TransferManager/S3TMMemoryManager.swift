// Controls memory usage at batch-level in downloadObject and uploadObject operations.
internal actor S3TMMemoryManager {
    private var currentInMemoryBytes: Int = 0
    private let maxInMemoryBytes: Int
    private var waitingContinuations: [(CheckedContinuation<Void, Never>, Int)] = []

    init(maxInMemoryBytes: Int) {
        self.maxInMemoryBytes = maxInMemoryBytes
    }

    func waitForMemory(_ bytes: Int) async {
      await withCheckedContinuation { continuation in
          if currentInMemoryBytes + bytes <= maxInMemoryBytes {
              currentInMemoryBytes += bytes
              continuation.resume()
          } else {
              waitingContinuations.append((continuation, bytes))
          }
      }
    }

    func releaseMemory(_ bytes: Int) {
      currentInMemoryBytes -= bytes
      tryResumeNextContinuation()
    }

    private func tryResumeNextContinuation() {
        guard !waitingContinuations.isEmpty else { return }

        let next = waitingContinuations.first!
        if currentInMemoryBytes + next.1 <= maxInMemoryBytes {
            let request = waitingContinuations.removeFirst()
            currentInMemoryBytes += request.1
            request.0.resume()
        }
    }
}
