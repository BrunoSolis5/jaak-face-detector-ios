import UIKit

/// Face tracking overlay view for showing face detection feedback
internal class JAAKFaceTrackingOverlay: UIView {
    
    // MARK: - Properties
    
    private let faceBox = UIView()
    private let faceShape = CAShapeLayer()
    private var configuration: JAAKFaceTrackerStyles
    private var currentFaceFrame: CGRect = .zero
    private var isValidFace: Bool = false
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceTrackerStyles) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        self.configuration = JAAKFaceTrackerStyles()
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Public Methods
    
    /// Update the face tracking frame
    /// - Parameter frame: normalized face bounds (0.0 to 1.0)
    func updateFaceFrame(_ frame: CGRect) {
        currentFaceFrame = frame
        updateFaceOverlay()
    }
    
    /// Set the validation state of the detected face
    /// - Parameter isValid: true if face is in correct position
    func setValidationState(_ isValid: Bool) {
        isValidFace = isValid
        updateFaceOverlay()
    }
    
    /// Show the face tracking overlay
    func show() {
        isHidden = false
        alpha = 0.0
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1.0
        }
    }
    
    /// Hide the face tracking overlay
    func hide() {
        UIView.animate(withDuration: 0.3) {
            self.alpha = 0.0
        } completion: { _ in
            self.isHidden = true
        }
    }
    
    /// Update configuration
    /// - Parameter configuration: new face tracker styles
    func updateConfiguration(_ configuration: JAAKFaceTrackerStyles) {
        self.configuration = configuration
        updateFaceOverlay()
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        
        // Setup face shape layer
        faceShape.fillColor = UIColor.clear.cgColor
        faceShape.lineWidth = 3.0
        faceShape.lineJoin = .round
        layer.addSublayer(faceShape)
        
        // Initial state
        hide()
    }
    
    private func updateFaceOverlay() {
        guard !currentFaceFrame.isEmpty else {
            hide()
            return
        }
        
        // Convert normalized coordinates to view coordinates
        let viewFrame = convertNormalizedFrameToView(currentFaceFrame)
        
        // Update colors based on validation state
        let strokeColor = isValidFace ? configuration.validColor : configuration.invalidColor
        faceShape.strokeColor = strokeColor.cgColor
        
        // Create face outline path
        let path = createFaceOutlinePath(for: viewFrame)
        faceShape.path = path
        
        // Show overlay if hidden
        if isHidden {
            show()
        }
        
        // Animate the change
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        faceShape.path = path
        CATransaction.commit()
    }
    
    private func convertNormalizedFrameToView(_ normalizedFrame: CGRect) -> CGRect {
        let viewSize = bounds.size
        
        // Vision framework uses bottom-left origin, UIKit uses top-left
        let x = normalizedFrame.minX * viewSize.width
        let y = (1.0 - normalizedFrame.maxY) * viewSize.height
        let width = normalizedFrame.width * viewSize.width
        let height = normalizedFrame.height * viewSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func createFaceOutlinePath(for frame: CGRect) -> CGPath {
        // Create a rounded rectangle for the face outline
        let cornerRadius: CGFloat = 8.0
        let path = UIBezierPath(roundedRect: frame, cornerRadius: cornerRadius)
        
        // Add corner indicators for better visibility
        addCornerIndicators(to: path, frame: frame)
        
        return path.cgPath
    }
    
    private func addCornerIndicators(to path: UIBezierPath, frame: CGRect) {
        let indicatorLength: CGFloat = 20.0
        let cornerRadius: CGFloat = 8.0
        
        // Top-left corner
        path.move(to: CGPoint(x: frame.minX, y: frame.minY + cornerRadius + indicatorLength))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + cornerRadius))
        path.addLine(to: CGPoint(x: frame.minX + cornerRadius, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX + cornerRadius + indicatorLength, y: frame.minY))
        
        // Top-right corner
        path.move(to: CGPoint(x: frame.maxX - cornerRadius - indicatorLength, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX - cornerRadius, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + cornerRadius))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + cornerRadius + indicatorLength))
        
        // Bottom-right corner
        path.move(to: CGPoint(x: frame.maxX, y: frame.maxY - cornerRadius - indicatorLength))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - cornerRadius))
        path.addLine(to: CGPoint(x: frame.maxX - cornerRadius, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX - cornerRadius - indicatorLength, y: frame.maxY))
        
        // Bottom-left corner
        path.move(to: CGPoint(x: frame.minX + cornerRadius + indicatorLength, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX + cornerRadius, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY - cornerRadius))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY - cornerRadius - indicatorLength))
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update face overlay when view bounds change
        if !currentFaceFrame.isEmpty {
            updateFaceOverlay()
        }
    }
}
