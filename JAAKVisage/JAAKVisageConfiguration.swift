import UIKit
import AVFoundation

/// Timer styles configuration for recording timer display
public struct JAAKTimerStyles {
    public var textColor: UIColor = .white
    public var circleColor: UIColor = .white
    public var circleEmptyColor: UIColor = .clear
    public var circleSuccessColor: UIColor = UIColor(red: 0.29, green: 0.49, blue: 0.29, alpha: 1.0)
    public var size: CGSize = CGSize(width: 120, height: 120)
    public var fontSize: CGFloat = 120
    public var position: CGPoint = CGPoint(x: 0.5, y: 0.5)
    public var strokeWidth: CGFloat = 6
    public var dashPattern: [NSNumber] = [10, 5]
    
    public init() {}
}

/// Face tracker styles configuration for face tracking overlay
public struct JAAKFaceTrackerStyles {
    public var validColor: UIColor = UIColor(red: 0.29, green: 0.49, blue: 0.29, alpha: 1.0)
    public var invalidColor: UIColor = .white
    
    public init() {}
}

/// Main configuration structure for JAAKVisage
public struct JAAKVisageConfiguration {
    // Basic Settings
    public var width: CGFloat = 0
    public var height: CGFloat = 0
    
    // Video Settings
    public var videoDuration: TimeInterval = 4.0
    public var enableMicrophone: Bool = false
    public var cameraPosition: AVCaptureDevice.Position = .back
    public var videoQuality: AVCaptureSession.Preset = .photo
    
    // Face Detection Settings
    public var disableFaceDetection: Bool = false
    public var useOfflineModel: Bool = false            // Reserved for future use
    
    // Auto Recording Settings
    public var autoRecorder: Bool = false
    
    // Timer Settings
    public var timerStyles: JAAKTimerStyles = JAAKTimerStyles()
    
    // Face Tracker Settings
    public var faceTrackerStyles: JAAKFaceTrackerStyles = JAAKFaceTrackerStyles()
    
    // Security Settings removed for simplicity
    
    // Instruction Settings
    public var enableInstructions: Bool = false
    public var instructionDelay: TimeInterval = 5.0      // Time each instruction is displayed
    public var instructionDuration: TimeInterval = 2.0   // Duration each instruction stays visible
    public var instructionsButtonText: String = "Show Instructions"
    
    // Instruction Content
    public var instructionsAnimations: [String] = []
    public var instructionsText: [String] = []
    
    public init() {}
}