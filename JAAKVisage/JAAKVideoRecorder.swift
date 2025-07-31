import AVFoundation
import UIKit

/// Internal class for managing video recording operations
internal class JAAKVideoRecorder: NSObject {
    
    // MARK: - Properties
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var isCurrentlyRecording = false
    
    private var configuration: JAAKVisageConfiguration
    weak var delegate: JAAKVideoRecorderDelegate?
    
    // MARK: - Initialization
    
    init(configuration: JAAKVisageConfiguration) {
        self.configuration = configuration
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start recording video
    /// - Parameters:
    ///   - cameraManager: camera manager instance
    ///   - completion: completion handler with result
    func startRecording(with cameraManager: JAAKCameraManager, completion: @escaping (Result<JAAKFileResult, JAAKVisageError>) -> Void) {
        guard !isCurrentlyRecording else {
            let error = JAAKVisageError(
                label: "Grabación ya en progreso",
                code: "RECORDING_IN_PROGRESS"
            )
            completion(.failure(error))
            return
        }
        
        // Generate unique output URL
        let outputURL = generateOutputURL()
        
        // Start recording
        cameraManager.startRecording(to: outputURL)
        isCurrentlyRecording = true
        recordingStartTime = Date()
        
        // Start timer for recording duration
        startRecordingTimer(cameraManager: cameraManager, completion: completion)
        
        // Notify delegate
        print("🎬 [VideoRecorder] Recording started, notifying delegate: \(String(describing: delegate))")
        delegate?.videoRecorder(self, didStartRecording: outputURL)
    }
    
    /// Stop recording video
    /// - Parameter cameraManager: camera manager instance
    func stopRecording(with cameraManager: JAAKCameraManager) {
        guard isCurrentlyRecording else { return }
        
        cameraManager.stopRecording()
        stopRecordingTimer()
        isCurrentlyRecording = false
        recordingStartTime = nil
    }
    
    /// Get current recording progress (0.0 to 1.0)
    /// - Returns: recording progress or 0.0 if not recording
    func getRecordingProgress() -> Float {
        guard let startTime = recordingStartTime else { return 0.0 }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = Float(elapsed / configuration.videoDuration)
        
        return min(progress, 1.0)
    }
    
    /// Check if currently recording
    /// - Returns: true if recording is active
    func isRecording() -> Bool {
        return isCurrentlyRecording
    }
    
    /// Get remaining recording time
    /// - Returns: remaining time in seconds
    func getRemainingTime() -> TimeInterval {
        guard let startTime = recordingStartTime else { return 0.0 }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = configuration.videoDuration - elapsed
        
        return max(remaining, 0.0)
    }
    
    
    // MARK: - Private Methods
    
    private func generateOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "video_\(Int(Date().timeIntervalSince1970)).mp4"
        return documentsPath.appendingPathComponent(fileName)
    }
    
    private func startRecordingTimer(cameraManager: JAAKCameraManager, completion: @escaping (Result<JAAKFileResult, JAAKVisageError>) -> Void) {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update progress
            let progress = self.getRecordingProgress()
            self.delegate?.videoRecorder(self, didUpdateProgress: progress)
            
            // Check if recording should stop
            if progress >= 1.0 {
                self.stopRecording(with: cameraManager)
                
                // Recording completed, we'll get the file via delegate
                // This completion will be called from the file output delegate
                self.pendingCompletion = completion
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private var pendingCompletion: ((Result<JAAKFileResult, JAAKVisageError>) -> Void)?
    
    /// Handle successful video recording completion
    /// - Parameter outputURL: URL of the recorded video file
    func handleRecordingCompletion(_ outputURL: URL) {
        // Convert video file to JAAKFileResult
        do {
            let videoData = try Data(contentsOf: outputURL)
            let base64String = videoData.base64EncodedString()
            let fileName = outputURL.lastPathComponent
            
            let fileResult = JAAKFileResult(
                data: videoData,
                base64: base64String,
                mimeType: "video/mp4",
                fileName: fileName,
                fileSize: videoData.count
            )
            
            pendingCompletion?(.success(fileResult))
            pendingCompletion = nil
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: outputURL)
            
        } catch {
            let detectorError = JAAKVisageError(
                label: "Error al procesar video grabado",
                code: "VIDEO_PROCESSING_FAILED",
                details: error
            )
            pendingCompletion?(.failure(detectorError))
            pendingCompletion = nil
        }
    }
    
    /// Handle video recording error
    /// - Parameter error: the error that occurred
    func handleRecordingError(_ error: JAAKVisageError) {
        pendingCompletion?(.failure(error))
        pendingCompletion = nil
        
        isCurrentlyRecording = false
        recordingStartTime = nil
        stopRecordingTimer()
    }
    
    /// Update configuration
    /// - Parameter newConfiguration: new video recorder configuration
    func updateConfiguration(_ newConfiguration: JAAKVisageConfiguration) {
        self.configuration = newConfiguration
        print("✅ [VideoRecorder] Configuration updated")
    }
}

// MARK: - JAAKVideoRecorderDelegate

protocol JAAKVideoRecorderDelegate: AnyObject {
    func videoRecorder(_ recorder: JAAKVideoRecorder, didStartRecording outputURL: URL)
    func videoRecorder(_ recorder: JAAKVideoRecorder, didUpdateProgress progress: Float)
    func videoRecorder(_ recorder: JAAKVideoRecorder, didFinishRecording fileResult: JAAKFileResult)
    func videoRecorder(_ recorder: JAAKVideoRecorder, didFailWithError error: JAAKVisageError)
}