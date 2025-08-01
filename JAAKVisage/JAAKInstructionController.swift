import UIKit

/// Controller for managing instruction sequences during face detection
internal class JAAKInstructionController {
    
    // MARK: - Types
    
    enum InstructionTrigger {
        case onStart
        case error(String)
    }
    
    // MARK: - Properties
    
    private var configuration: JAAKVisageConfiguration
    private let instructionView: JAAKInstructionView
    private var currentTrigger: InstructionTrigger?
    private var instructionTimer: Timer?
    private var lastInstructionTime: Date?
    
    weak var delegate: JAAKInstructionControllerDelegate?
    
    // MARK: - Initialization
    
    init(configuration: JAAKVisageConfiguration, instructionView: JAAKInstructionView) {
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
    
    
    /// Handle status changes for instruction updates
    /// - Parameter status: new detector status
    func handleStatusChange(_ status: JAAKVisageStatus) {
        guard configuration.enableInstructions else { return }
        
        // Only show instructions for critical states, not for normal operation
        switch status {
        case .error:
            showInstructionForTrigger(.error("Ocurrió un error"))
            
        default:
            // Don't show instructions for normal state changes like .recording or .finished
            // These should be handled by the validation messages instead
            break
        }
    }
    
    /// Handle errors for instruction updates
    /// - Parameter error: detector error
    func handleError(_ error: JAAKVisageError) {
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
    
    
    private func shouldShowInstruction(for trigger: InstructionTrigger) -> Bool {
        // Check if enough time has passed since last instruction
        if let lastTime = lastInstructionTime {
            let timeSinceLastInstruction = Date().timeIntervalSince(lastTime)
            if timeSinceLastInstruction < configuration.instructionDuration {
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
        case (.onStart, .onStart):
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
            return "" // No welcome message, just show the instruction sequence
            
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private func getAnimationName(for trigger: InstructionTrigger) -> String? {
        switch trigger {
        case .onStart:
            return "initial_instructions"
            
        case .error:
            return nil
        }
    }
    
    private func updateInstructionView(text: String, animation: String?) {
        // Show the instruction directly on the view
        instructionView.showDirectInstruction(text: text, animation: animation)
    }
    
    private func startInstructionTimer() {
        stopInstructionTimer()
        
        // Calculate total time needed for all instructions
        // Each instruction shows for instructionDuration (no delay between instructions)
        let instructionCount = configuration.instructionsText.isEmpty ? 4 : configuration.instructionsText.count // 4 default instructions
        let totalTime = TimeInterval(instructionCount) * configuration.instructionDuration + 2.0 // Extra buffer
        
        // Auto-hide after all instructions complete
        instructionTimer = Timer.scheduledTimer(withTimeInterval: totalTime, repeats: false) { [weak self] _ in
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
    
    /// Update configuration
    /// - Parameter newConfiguration: new instruction controller configuration
    func updateConfiguration(_ newConfiguration: JAAKVisageConfiguration) {
        self.configuration = newConfiguration
        print("✅ [InstructionController] Configuration updated")
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
    
    func instructionViewHelpButtonTapped(_ instructionView: JAAKInstructionView) {
        // When help button is tapped, restart the instruction sequence
        startInstructions()
    }
    
    func instructionView(_ instructionView: JAAKInstructionView, willStartInstructions isStarting: Bool) {
        // Notify the main controller to pause/resume face detection
        delegate?.instructionController(self, shouldPauseDetection: isStarting)
    }
    
    func instructionView(_ instructionView: JAAKInstructionView, didRequestCameraList completion: @escaping ([String], String?) -> Void) {
        // Request available cameras from the main controller
        delegate?.instructionController(self, didRequestCameraList: completion)
    }
    
    func instructionView(_ instructionView: JAAKInstructionView, didSelectCamera cameraName: String) {
        // Notify the main controller about camera selection
        delegate?.instructionController(self, didSelectCamera: cameraName)
    }
}

// MARK: - JAAKInstructionControllerDelegate

protocol JAAKInstructionControllerDelegate: AnyObject {
    func instructionController(_ controller: JAAKInstructionController, didCompleteInstructions completed: Bool)
    func instructionController(_ controller: JAAKInstructionController, shouldPauseDetection pause: Bool)
    func instructionController(_ controller: JAAKInstructionController, didRequestCameraList completion: @escaping ([String], String?) -> Void)
    func instructionController(_ controller: JAAKInstructionController, didSelectCamera cameraName: String)
}