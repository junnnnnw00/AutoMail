import Foundation
import SharedKit

public actor RetrainScheduler {
    private let trainer = Trainer()
    private let prefs: Prefs
    private var task: Task<Void, Never>?

    public init(prefs: Prefs = .standard) {
        self.prefs = prefs
    }

    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            await self?.loop()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func triggerIfNeeded() async {
        do {
            let pending = try Database.shared.unconsumedFeedback()
            if pending.count >= prefs.retrainThreshold {
                await retrain()
            }
        } catch {
            MailSorterLog.trainer.error("threshold check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 24 * 3600 * 1_000_000_000)
            if Task.isCancelled { return }
            await retrain()
        }
    }

    private func retrain() async {
        do {
            if let _ = try await trainer.trainIfReady() {
                MailSorterLog.trainer.info("retrain complete, model swapped")
                if let pending = try? Database.shared.unconsumedFeedback() {
                    let ids = pending.compactMap { $0.id }
                    try? Database.shared.markFeedbackConsumed(ids: ids)
                }
                prefs.lastTrainedAt = Date()
                EventBus.post(.modelReloaded)
            }
        } catch TrainerError.notEnoughSamples(let count) {
            MailSorterLog.trainer.info("not enough samples: \(count)")
        } catch {
            MailSorterLog.trainer.error("train failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
