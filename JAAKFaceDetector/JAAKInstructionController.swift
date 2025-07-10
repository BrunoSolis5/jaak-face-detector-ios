import UIKit

/// Controller for managing instruction sequences during face detection
internal class JAAKInstructionController {
    
    // MARK: - Types
    
    enum InstructionTrigger {
        case onStart
        case noFaceDetected
        case faceDetected
        case faceNotCentered
        case faceTooFar
        case faceToClose
        case faceNotStill
        case recordingStarted
        case recordingCompleted
        case error(String)
    }
    
    // MARK: - Properties
    
    private let configuration: JAAKFaceDetectorConfiguration
    private let instructionView: JAAKInstructionView
    private var currentTrigger: InstructionTrigger?
    private var instructionTimer: Timer?
    private var lastInstructionTime: Date?
    
    weak var delegate: JAAKInstructionControllerDelegate?
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceDetectorConfiguration, instructionView: JAAKInstructionView) {
        self.configuration = configuration
        self.instructionView = instructionView
        
        instructionView.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// Start instruction sequence
    func startInstructions() {
        guard configuration.enableInstructions else { return }
        
        showInstructionForTrigger(.onStart)
    }
    
    /// Handle face detection message for instruction updates
    /// - Parameter message: face detection message
    func handleFaceDetectionMessage(_ message: JAAKFaceDetectionMessage) {
        guard configuration.enableInstructions else { return }
        
        // Determine appropriate instruction trigger
        let trigger = determineTrigger(from: message)
        
        // Show instruction if trigger changed or enough time has passed
        if shouldShowInstruction(for: trigger) {
            showInstructionForTrigger(trigger)
        }
    }
    
    /// Handle status changes for instruction updates
    /// - Parameter status: new detector status
    func handleStatusChange(_ status: JAAKFaceDetectorStatus) {
        guard configuration.enableInstructions else { return }
        
        switch status {
        case .recording:
            showInstructionForTrigger(.recordingStarted)
            
        case .finished:
            showInstructionForTrigger(.recordingCompleted)
            
        case .error:
            showInstructionForTrigger(.error("An error occurred"))
            
        default:
            break
        }
    }
    
    /// Handle errors for instruction updates
    /// - Parameter error: detector error
    func handleError(_ error: JAAKFaceDetectorError) {
        guard configuration.enableInstructions else { return }
        
        showInstructionForTrigger(.error(error.label))
    }
    
    /// Hide instructions
    func hideInstructions() {
        instructionView.hideInstructions()
        stopInstructionTimer()
    }
    
    /// Force show specific instruction
    /// - Parameter trigger: instruction trigger
    func forceShowInstruction(_ trigger: InstructionTrigger) {
        showInstructionForTrigger(trigger)
    }
    
    // MARK: - Private Methods
    
    private func determineTrigger(from message: JAAKFaceDetectionMessage) -> InstructionTrigger {
        if !message.faceExists {
            return .noFaceDetected
        }
        
        if message.faceExists && message.correctPosition {
            return .faceDetected
        }
        
        // For more specific positioning feedback, we'd need more detailed face analysis
        // For now, we'll use general positioning feedback
        return .faceNotCentered
    }
    
    private func shouldShowInstruction(for trigger: InstructionTrigger) -> Bool {
        // Check if enough time has passed since last instruction
        if let lastTime = lastInstructionTime {
            let timeSinceLastInstruction = Date().timeIntervalSince(lastTime)
            if timeSinceLastInstruction < configuration.instructionReplayDelay {
                return false
            }
        }
        
        // Check if trigger is different from current
        if let currentTrigger = currentTrigger {
            return !isSameTrigger(currentTrigger, trigger)
        }
        
        return true
    }
    
    private func isSameTrigger(_ trigger1: InstructionTrigger, _ trigger2: InstructionTrigger) -> Bool {
        switch (trigger1, trigger2) {
        case (.onStart, .onStart),
             (.noFaceDetected, .noFaceDetected),
             (.faceDetected, .faceDetected),
             (.faceNotCentered, .faceNotCentered),
             (.faceTooFar, .faceTooFar),
             (.faceToClose, .faceToClose),
             (.faceNotStill, .faceNotStill),
             (.recordingStarted, .recordingStarted),
             (.recordingCompleted, .recordingCompleted):
            return true
        case (.error(let msg1), .error(let msg2)):
            return msg1 == msg2
        default:
            return false
        }
    }
    
    private func showInstructionForTrigger(_ trigger: InstructionTrigger) {
        currentTrigger = trigger
        lastInstructionTime = Date()
        
        // Create instruction steps based on trigger
        let instructionText = getInstructionText(for: trigger)
        let animationName = getAnimationName(for: trigger)
        
        // Update instruction view with specific content
        updateInstructionView(text: instructionText, animation: animationName)
        
        // Show the instruction
        instructionView.showInstructions()
        
        // Start auto-hide timer
        startInstructionTimer()
    }
    
    private func getInstructionText(for trigger: InstructionTrigger) -> String {
        switch trigger {
        case .onStart:
            return "Welcome! Please position your face in the center"
            
        case .noFaceDetected:
            return "No face detected. Please position your face in front of the camera"
            
        case .faceDetected:
            return "Great! Face detected. Hold still"
            
        case .faceNotCentered:
            return "Please center your face in the frame"
            
        case .faceTooFar:
            return "Please move closer to the camera"
            
        case .faceToClose:
            return "Please move away from the camera"
            
        case .faceNotStill:
            return "Please hold still for better detection"
            
        case .recordingStarted:
            return "Recording started. Please hold still"
            
        case .recordingCompleted:
            return "Recording completed successfully!"
            
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private func getAnimationName(for trigger: InstructionTrigger) -> String? {
        switch trigger {
        case .onStart:
            return "center_face"
            
        case .noFaceDetected:
            return "center_face"
            
        case .faceDetected:
            return "hold_still"
            
        case .faceNotCentered:
            return "center_face"
            
        case .faceTooFar:
            return "move_closer"
            
        case .faceToClose:
            return "move_away"
            
        case .faceNotStill:
            return "hold_still"
            
        case .recordingStarted:
            return "hold_still"
            
        case .recordingCompleted:
            return nil
            
        case .error:
            return nil
        }
    }
    
    private func updateInstructionView(text: String, animation: String?) {
        // Create a single instruction step
        _ = JAAKInstructionView.InstructionStep(
            text: text,
            animation: animation,
            duration: configuration.instructionDelay,
            delay: configuration.instructionReplayDelay
        )
        
        // For now, we'll update the instruction view directly
        // In a more complex implementation, we'd modify the instruction view to accept dynamic steps
    }
    
    private func startInstructionTimer() {
        stopInstructionTimer()
        
        // Auto-hide after configured delay
        instructionTimer = Timer.scheduledTimer(withTimeInterval: configuration.instructionDelay + 1.0, repeats: false) { [weak self] _ in
            self?.instructionView.hideInstructions()
        }
    }
    
    private func stopInstructionTimer() {
        instructionTimer?.invalidate()
        instructionTimer = nil
    }
    
    deinit {
        stopInstructionTimer()
    }
}

// MARK: - JAAKInstructionViewDelegate

extension JAAKInstructionController: JAAKInstructionViewDelegate {
    func instructionView(_ instructionView: JAAKInstructionView, didComplete completed: Bool) {
        delegate?.instructionController(self, didCompleteInstructions: completed)
        
        if completed {
            // Reset for next instruction sequence
            currentTrigger = nil
            lastInstructionTime = nil
        }
    }
}

// MARK: - JAAKInstructionControllerDelegate

protocol JAAKInstructionControllerDelegate: AnyObject {
    func instructionController(_ controller: JAAKInstructionController, didCompleteInstructions completed: Bool)
}