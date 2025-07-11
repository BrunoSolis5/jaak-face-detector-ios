import AVFoundation
import UIKit
import MediaPipeTasksVision

/// Progressive auto-recording system that records multiple attempts with increasing quality thresholds
internal class JAAKProgressiveRecorder {
    
    // MARK: - Types
    
    struct RecordingAttempt {
        let attemptNumber: Int
        let qualityScore: Float
        let faceConfidence: Float
        let faceSize: Float
        let timestamp: Date
        let fileResult: JAAKFileResult?
        let meetsCriteria: Bool
        
        init(attemptNumber: Int, qualityScore: Float, faceConfidence: Float, faceSize: Float, fileResult: JAAKFileResult? = nil) {
            self.attemptNumber = attemptNumber
            self.qualityScore = qualityScore
            self.faceConfidence = faceConfidence
            self.faceSize = faceSize
            self.timestamp = Date()
            self.fileResult = fileResult
            self.meetsCriteria = qualityScore >= JAAKProgressiveRecorder.getQualityThreshold(for: attemptNumber)
        }
    }
    
    struct RecordingSession {
        let sessionId: String
        let startTime: Date
        var attempts: [RecordingAttempt]
        var currentAttempt: Int
        var isCompleted: Bool
        var bestAttempt: RecordingAttempt?
        
        init() {
            self.sessionId = UUID().uuidString
            self.startTime = Date()
            self.attempts = []
            self.currentAttempt = 0
            self.isCompleted = false
            self.bestAttempt = nil
        }
        
        mutating func addAttempt(_ attempt: RecordingAttempt) {
            attempts.append(attempt)
            currentAttempt = attempt.attemptNumber
            
            // Update best attempt if this one is better
            if bestAttempt == nil || attempt.qualityScore > bestAttempt!.qualityScore {
                bestAttempt = attempt
            }
        }
        
        mutating func complete() {
            isCompleted = true
        }
        
        func shouldContinue() -> Bool {
            return !isCompleted && currentAttempt < 3 && (bestAttempt?.meetsCriteria != true)
        }
    }
    
    // MARK: - Properties
    
    private var configuration: JAAKFaceDetectorConfiguration
    private let videoRecorder: JAAKVideoRecorder
    private let cameraManager: JAAKCameraManager
    
    private var currentSession: RecordingSession?
    private var faceQualityAnalyzer: JAAKFaceQualityAnalyzer?
    private var recordingTimer: Timer?
    private var qualityCheckTimer: Timer?
    private var isMonitoring: Bool = false
    
    // Quality thresholds for progressive attempts
    private static let qualityThresholds: [Float] = [0.6, 0.75, 0.9] // 60%, 75%, 90%
    private static let confidenceThresholds: [Float] = [0.7, 0.8, 0.9] // 70%, 80%, 90%
    private static let sizeThresholds: [Float] = [0.15, 0.20, 0.25] // 15%, 20%, 25% of frame
    
    weak var delegate: JAAKProgressiveRecorderDelegate?
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceDetectorConfiguration, videoRecorder: JAAKVideoRecorder, cameraManager: JAAKCameraManager) {
        self.configuration = configuration
        self.videoRecorder = videoRecorder
        self.cameraManager = cameraManager
        
        self.faceQualityAnalyzer = JAAKFaceQualityAnalyzer()
    }
    
    // MARK: - Public Methods
    
    /// Start progressive recording session
    func startProgressiveRecording() {
        guard configuration.progressiveAutoRecorder else { return }
        guard currentSession == nil else { return }
        
        currentSession = RecordingSession()
        isMonitoring = true
        
        delegate?.progressiveRecorder(self, didStartSession: currentSession!)
        
        // Start monitoring for optimal conditions
        startQualityMonitoring()
    }
    
    /// Stop progressive recording session
    func stopProgressiveRecording() {
        isMonitoring = false
        stopQualityMonitoring()
        
        currentSession?.complete()
        
        if let session = currentSession {
            delegate?.progressiveRecorder(self, didCompleteSession: session)
        }
        
        currentSession = nil
    }
    
    /// Process face detection results for quality analysis
    /// - Parameters:
    ///   - faces: detected faces
    ///   - sampleBuffer: current video frame
    func processFaceDetectionResults(_ detections: [Detection], sampleBuffer: CMSampleBuffer) {
        guard isMonitoring, let session = currentSession else { return }
        guard session.shouldContinue() else { return }
        
        // Analyze face quality
        if let primaryFace = detections.first {
            let qualityScore = analyzeFrameQuality(primaryFace, sampleBuffer: sampleBuffer)
            let attemptNumber = session.currentAttempt + 1
            
            // Check if this frame meets criteria for current attempt
            if shouldTriggerRecording(qualityScore: qualityScore, detection: primaryFace, attemptNumber: attemptNumber) {
                startRecordingAttempt(qualityScore: qualityScore, detection: primaryFace, attemptNumber: attemptNumber)
            }
        }
    }
    
    /// Get current recording session
    /// - Returns: current session or nil
    func getCurrentSession() -> RecordingSession? {
        return currentSession
    }
    
    /// Force start next attempt
    func forceNextAttempt() {
        guard let session = currentSession, session.shouldContinue() else { return }
        
        let attemptNumber = session.currentAttempt + 1
        let attempt = RecordingAttempt(
            attemptNumber: attemptNumber,
            qualityScore: 0.5, // Low quality for forced attempt
            faceConfidence: 0.5,
            faceSize: 0.1
        )
        
        startRecordingAttempt(attempt: attempt)
    }
    
    // MARK: - Private Methods
    
    private func startQualityMonitoring() {
        qualityCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForOptimalConditions()
        }
    }
    
    private func stopQualityMonitoring() {
        qualityCheckTimer?.invalidate()
        qualityCheckTimer = nil
    }
    
    private func checkForOptimalConditions() {
        // This method would be called periodically to check if conditions are optimal
        // In a real implementation, this would analyze the current video frame
        // For now, it's a placeholder for the monitoring logic
    }
    
    private func analyzeFrameQuality(_ detection: Detection, sampleBuffer: CMSampleBuffer) -> Float {
        guard let analyzer = faceQualityAnalyzer else { return 0.0 }
        
        return analyzer.analyzeQuality(detection: detection)
    }
    
    private func shouldTriggerRecording(qualityScore: Float, detection: Detection, attemptNumber: Int) -> Bool {
        let qualityThreshold = Self.getQualityThreshold(for: attemptNumber)
        let confidenceThreshold = Self.getConfidenceThreshold(for: attemptNumber)
        let sizeThreshold = Self.getSizeThreshold(for: attemptNumber)
        
        let faceSize = Float(detection.boundingBox.width * detection.boundingBox.height)
        let confidence = detection.categories.first?.score ?? 0.0
        
        return qualityScore >= qualityThreshold &&
               confidence >= confidenceThreshold &&
               faceSize >= sizeThreshold
    }
    
    private func startRecordingAttempt(qualityScore: Float, detection: Detection, attemptNumber: Int) {
        let faceSize = detection.boundingBox.width * detection.boundingBox.height
        let attempt = RecordingAttempt(
            attemptNumber: attemptNumber,
            qualityScore: qualityScore,
            faceConfidence: detection.categories.first?.score ?? 0.0,
            faceSize: Float(faceSize)
        )
        
        startRecordingAttempt(attempt: attempt)
    }
    
    private func startRecordingAttempt(attempt: RecordingAttempt) {
        guard currentSession != nil else { return }
        
        delegate?.progressiveRecorder(self, didStartAttempt: attempt)
        
        // Start actual recording
        videoRecorder.startRecording(with: cameraManager) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let fileResult):
                self.handleAttemptSuccess(attempt: attempt, fileResult: fileResult)
                
            case .failure(let error):
                self.handleAttemptFailure(attempt: attempt, error: error)
            }
        }
    }
    
    private func handleAttemptSuccess(attempt: RecordingAttempt, fileResult: JAAKFileResult) {
        guard var session = currentSession else { return }
        
        // Create completed attempt
        let completedAttempt = RecordingAttempt(
            attemptNumber: attempt.attemptNumber,
            qualityScore: attempt.qualityScore,
            faceConfidence: attempt.faceConfidence,
            faceSize: attempt.faceSize,
            fileResult: fileResult
        )
        
        session.addAttempt(completedAttempt)
        currentSession = session
        
        delegate?.progressiveRecorder(self, didCompleteAttempt: completedAttempt)
        
        // Check if we should continue or finish
        if completedAttempt.meetsCriteria || !session.shouldContinue() {
            finishRecordingSession()
        } else {
            // Wait a bit before next attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.prepareForNextAttempt()
            }
        }
    }
    
    private func handleAttemptFailure(attempt: RecordingAttempt, error: JAAKFaceDetectorError) {
        guard var session = currentSession else { return }
        
        let failedAttempt = RecordingAttempt(
            attemptNumber: attempt.attemptNumber,
            qualityScore: 0.0,
            faceConfidence: 0.0,
            faceSize: 0.0
        )
        
        session.addAttempt(failedAttempt)
        currentSession = session
        
        delegate?.progressiveRecorder(self, didFailAttempt: failedAttempt, error: error)
        
        // Try next attempt or finish
        if session.shouldContinue() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.prepareForNextAttempt()
            }
        } else {
            finishRecordingSession()
        }
    }
    
    private func prepareForNextAttempt() {
        // Prepare for next recording attempt
        // This could involve adjusting camera settings, giving user feedback, etc.
        delegate?.progressiveRecorder(self, willStartNextAttempt: (currentSession?.currentAttempt ?? 0) + 1)
    }
    
    private func finishRecordingSession() {
        guard let session = currentSession else { return }
        
        stopProgressiveRecording()
        
        // Return the best attempt
        if let bestAttempt = session.bestAttempt, let fileResult = bestAttempt.fileResult {
            delegate?.progressiveRecorder(self, didProduceBestResult: fileResult, from: session)
        }
    }
    
    // MARK: - Static Methods
    
    static func getQualityThreshold(for attempt: Int) -> Float {
        let index = min(attempt - 1, qualityThresholds.count - 1)
        return qualityThresholds[max(0, index)]
    }
    
    static func getConfidenceThreshold(for attempt: Int) -> Float {
        let index = min(attempt - 1, confidenceThresholds.count - 1)
        return confidenceThresholds[max(0, index)]
    }
    
    static func getSizeThreshold(for attempt: Int) -> Float {
        let index = min(attempt - 1, sizeThresholds.count - 1)
        return sizeThresholds[max(0, index)]
    }
    
    /// Update configuration
    /// - Parameter newConfiguration: new progressive recorder configuration
    func updateConfiguration(_ newConfiguration: JAAKFaceDetectorConfiguration) {
        self.configuration = newConfiguration
        print("✅ [ProgressiveRecorder] Configuration updated")
    }
}

// MARK: - JAAKProgressiveRecorderDelegate

protocol JAAKProgressiveRecorderDelegate: AnyObject {
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didStartSession session: JAAKProgressiveRecorder.RecordingSession)
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didStartAttempt attempt: JAAKProgressiveRecorder.RecordingAttempt)
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didCompleteAttempt attempt: JAAKProgressiveRecorder.RecordingAttempt)
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didFailAttempt attempt: JAAKProgressiveRecorder.RecordingAttempt, error: JAAKFaceDetectorError)
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, willStartNextAttempt attemptNumber: Int)
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didCompleteSession session: JAAKProgressiveRecorder.RecordingSession)
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didProduceBestResult fileResult: JAAKFileResult, from session: JAAKProgressiveRecorder.RecordingSession)
}
