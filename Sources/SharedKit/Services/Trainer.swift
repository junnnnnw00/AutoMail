import Foundation
#if canImport(CreateML)
import CreateML
#endif
#if canImport(TabularData)
import TabularData
#endif

public enum TrainerError: Error {
    case notEnoughSamples(count: Int)
    case unavailableOnPlatform
    case trainingFailed(String)
}

public final class Trainer: @unchecked Sendable {
    public init() {}

    public static let minimumSamples = 40

    public func trainIfReady() async throws -> URL? {
        let labeled = try Database.shared.allLabeledMails()
            .filter { $0.userOverridden || $0.score >= 0.85 }
        if labeled.count < Self.minimumSamples {
            MailSorterLog.trainer.info("not enough samples to train: \(labeled.count)")
            throw TrainerError.notEnoughSamples(count: labeled.count)
        }
        return try await train(samples: labeled)
    }

    public func train(samples: [Mail]) async throws -> URL {
#if canImport(CreateML) && canImport(TabularData)
        var texts: [String] = []
        var labels: [String] = []
        for sample in samples {
            let text = sample.subject + "\n" + sample.body
            for label in sample.labels {
                texts.append(text)
                labels.append(label.rawValue)
            }
        }
        guard !texts.isEmpty else {
            throw TrainerError.notEnoughSamples(count: samples.count)
        }
        
        var dataFrame = DataFrame()
        dataFrame.append(column: Column<String>(name: "text", contents: texts))
        dataFrame.append(column: Column<String>(name: "label", contents: labels))

        let trainerHandle = self
        return try await Task.detached(priority: .utility) { () throws -> URL in
            do {
                let classifier = try MLTextClassifier(trainingData: dataFrame, textColumn: "text", labelColumn: "label")
                let metrics = classifier.trainingMetrics
                MailSorterLog.trainer.info("training accuracy: \(1 - metrics.classificationError, privacy: .public)")
                let outURL = AppPaths.classifierModelURL
                if FileManager.default.fileExists(atPath: outURL.path) {
                    try? FileManager.default.removeItem(at: outURL)
                }
                try classifier.write(to: outURL, metadata: MLModelMetadata(
                    author: "MailSorter",
                    shortDescription: "School mail classifier",
                    version: ISO8601DateFormatter().string(from: Date())
                ))
                _ = try MLModelCompiler.compile(at: outURL)
                _ = trainerHandle
                return outURL
            } catch {
                throw TrainerError.trainingFailed(error.localizedDescription)
            }
        }.value
#else
        throw TrainerError.unavailableOnPlatform
#endif
    }
}
