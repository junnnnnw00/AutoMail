import Foundation
import NaturalLanguage
import CoreML

public struct ClassificationResult: Sendable {
    public let labels: Set<MailLabel>
    public let scores: [MailLabel: Double]
    public let source: Source

    public var score: Double {
        scores.values.max() ?? 0.5
    }

    public enum Source: Sendable {
        case rule(String)
        case model
        case fallback
        case combined(ruleReason: String)
    }
}

public final class NLClassifier: @unchecked Sendable {
    private var model: NLModel?
    private let rules: Rules
    private let queue = DispatchQueue(label: "com.junwoo.mailsorter.classifier")

    public init(rules: Rules = Rules()) {
        self.rules = rules
        reloadModel()
    }

    public func reloadModel() {
        queue.sync {
            let compiled = AppPaths.compiledClassifierURL
            if FileManager.default.fileExists(atPath: compiled.path) {
                do {
                    self.model = try NLModel(contentsOf: compiled)
                    MailSorterLog.classifier.info("loaded model at \(compiled.path, privacy: .public)")
                } catch {
                    MailSorterLog.classifier.error("model load failed: \(error.localizedDescription, privacy: .public)")
                    self.model = nil
                }
                return
            }
            let raw = AppPaths.classifierModelURL
            if FileManager.default.fileExists(atPath: raw.path) {
                do {
                    let compiledURL = try MLModelCompiler.compile(at: raw)
                    self.model = try NLModel(contentsOf: compiledURL)
                    MailSorterLog.classifier.info("compiled+loaded model at \(compiledURL.path, privacy: .public)")
                } catch {
                    MailSorterLog.classifier.error("compile/load failed: \(error.localizedDescription, privacy: .public)")
                    self.model = nil
                }
            } else {
                self.model = nil
            }
        }
    }

    public func classify(subject: String, body: String, fromAddress: String) -> ClassificationResult {
        let ruleHits = rules.evaluate(subject: subject, body: body, fromAddress: fromAddress)
        
        let text = ("[From: \(fromAddress)]\n" + subject + "\n\n" + body).prefix(4000)
        let modelResult: (predicted: Set<MailLabel>, scores: [MailLabel: Double], isFallback: Bool) = queue.sync {
            guard let model else {
                return (Set([.normal]), [.normal: 0.5], true)
            }
            let predictions = model.predictedLabelHypotheses(for: String(text), maximumCount: MailLabel.allCases.count)
            var predicted: Set<MailLabel> = []
            var scores: [MailLabel: Double] = [:]
            for (labelStr, conf) in predictions {
                guard let label = MailLabel(rawValue: labelStr) else { continue }
                scores[label] = conf
                if conf >= 0.40 {
                    predicted.insert(label)
                }
            }
            if predicted.isEmpty, let (top, conf) = predictions.max(by: { $0.value < $1.value }), let label = MailLabel(rawValue: top) {
                predicted.insert(label)
                scores[label] = conf
            }
            return (predicted, scores, false)
        }

        var finalLabels = modelResult.predicted
        var finalScores = modelResult.scores
        var source: ClassificationResult.Source = modelResult.isFallback ? .fallback : .model

        if !ruleHits.isEmpty {
            let ruleLabels = Set(ruleHits.map { $0.label })
            finalLabels.formUnion(ruleLabels)
            for hit in ruleHits {
                finalScores[hit.label] = max(finalScores[hit.label] ?? 0.0, hit.score)
            }
            let ruleReasons = ruleHits.map { $0.reason }.joined(separator: ", ")
            if modelResult.isFallback {
                source = .rule(ruleReasons)
            } else {
                source = .combined(ruleReason: ruleReasons)
            }
        }

        let isSchoolMail = fromAddress.lowercased() == "postech.ac.kr" ||
                           fromAddress.lowercased().hasSuffix("@postech.ac.kr") ||
                           fromAddress.lowercased().hasSuffix(".postech.ac.kr")
        if isSchoolMail {
            finalLabels.remove(.ad)
        }

        if finalLabels.count > 1 {
            finalLabels.remove(.normal)
        }
        
        if finalLabels.isEmpty {
            finalLabels.insert(.normal)
        }

        return ClassificationResult(labels: finalLabels, scores: finalScores, source: source)
    }
}

enum MLModelCompiler {
    static func compile(at modelURL: URL) throws -> URL {
        let compiled = try MLModel.compileModel(at: modelURL)
        let destination = AppPaths.compiledClassifierURL
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: compiled, to: destination)
        return destination
    }
}
