import UIKit

/// Face tracking overlay view for showing face detection feedback
/// Following MediaPipe official iOS implementation pattern
internal class JAAKFaceTrackingOverlay: UIView {
    
    // MARK: - Properties
    
    private var configuration: JAAKFaceTrackerStyles
    private var currentDetections: [FaceDetection] = []
    private var hideTimer: Timer?
    private var lastFaceDetectionTime: Date = Date()
    
    // Image dimensions for coordinate transformation (MediaPipe pattern)
    private var imageWidth: CGFloat = 0
    private var imageHeight: CGFloat = 0
    
    // Overlay configuration
    private let lineWidth: CGFloat = 3.0
    private let cornerRadius: CGFloat = 8.0
    
    // Face detection structure (following MediaPipe pattern)
    struct FaceDetection {
        let boundingBox: CGRect
        let isValid: Bool
        let confidence: Float
    }
    
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
    
    /// Set image dimensions for coordinate transformation (MediaPipe pattern)
    /// - Parameters:
    ///   - width: Image width
    ///   - height: Image height
    func setImageDimensions(width: CGFloat, height: CGFloat) {
        imageWidth = width
        imageHeight = height
        print("📐 [FaceTrackingOverlay] Image dimensions set: \(width) x \(height)")
    }
    
    /// Update face detections (MediaPipe pattern)
    /// - Parameters:
    ///   - boundingBox: Detection bounding box
    ///   - isValid: Whether face is in valid position
    ///   - confidence: Detection confidence
    func updateFaceDetection(boundingBox: CGRect, isValid: Bool, confidence: Float) {
        // Only update if frame has valid dimensions
        guard boundingBox.width > 0 && boundingBox.height > 0 else {
            print("⚠️ [FaceTrackingOverlay] Invalid bounding box received: \(boundingBox)")
            clearDetections()
            return
        }
        
        let detection = FaceDetection(
            boundingBox: boundingBox,
            isValid: isValid,
            confidence: confidence
        )
        
        currentDetections = [detection]
        lastFaceDetectionTime = Date()
        setNeedsDisplay()
        
        // Reset hide timer when face is detected
        resetHideTimer()
        
        // Show overlay if hidden
        if isHidden {
            show()
        }
    }
    
    /// Clear all detections
    func clearDetections() {
        currentDetections = []
        setNeedsDisplay()
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
        setNeedsDisplay()
    }
    
    /// Notify that no face was detected (for delayed hiding)
    func notifyNoFaceDetected() {
        // Clear current detections
        currentDetections = []
        
        // Only start hide timer if we haven't seen a face recently
        let timeSinceLastDetection = Date().timeIntervalSince(lastFaceDetectionTime)
        if timeSinceLastDetection > 0.5 { // 500ms delay
            scheduleHideTimer()
        } else {
            // Hide immediately if no valid detections exist
            if currentDetections.isEmpty {
                hide()
            }
            print("👤 [FaceTrackingOverlay] No face detected but recent detection exists, detections cleared")
        }
    }
    
    // MARK: - UIView Overrides
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Clear the context
        context.clear(rect)
        
        // Draw all face detections
        for detection in currentDetections {
            drawFaceDetection(detection, in: context)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        
        // Initial state - start hidden but ready to show
        alpha = 0.0
        isHidden = true
    }
    
    private func drawFaceDetection(_ detection: FaceDetection, in context: CGContext) {
        // Transform MediaPipe coordinates to view coordinates
        let transformedRect = rectAfterApplyingBoundsAdjustment(
            originalRect: detection.boundingBox,
            imageSize: CGSize(width: imageWidth, height: imageHeight),
            viewSize: bounds.size
        )
        
        // Validate that the transformed frame is reasonable
        guard transformedRect.width > 0 && transformedRect.height > 0 &&
              transformedRect.minX >= 0 && transformedRect.minY >= 0 &&
              transformedRect.maxX <= bounds.width && transformedRect.maxY <= bounds.height else {
            print("⚠️ [FaceTrackingOverlay] Invalid transformed frame: \(transformedRect)")
            return
        }
        
        // Set drawing properties
        context.setLineWidth(lineWidth)
        let strokeColor = detection.isValid ? configuration.validColor : configuration.invalidColor
        context.setStrokeColor(strokeColor.cgColor)
        context.setFillColor(UIColor.clear.cgColor)
        
        // Draw rounded rectangle
        let path = UIBezierPath(roundedRect: transformedRect, cornerRadius: cornerRadius)
        context.addPath(path.cgPath)
        context.strokePath()
        
        print("📐 [FaceTrackingOverlay] Drew detection: \(detection.boundingBox) -> \(transformedRect)")
    }
    
    /// Transform detection coordinates to view coordinates (MediaPipe official pattern)
    /// - Parameters:
    ///   - originalRect: Original detection rectangle
    ///   - imageSize: Size of the image being processed
    ///   - viewSize: Size of the view
    /// - Returns: Transformed rectangle in view coordinates
    private func rectAfterApplyingBoundsAdjustment(
        originalRect: CGRect,
        imageSize: CGSize,
        viewSize: CGSize
    ) -> CGRect {
        
        guard imageSize.width > 0 && imageSize.height > 0 else {
            print("⚠️ [FaceTrackingOverlay] Invalid image size: \(imageSize)")
            return originalRect
        }
        
        // Calculate scale factors
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        
        // Use the same scale for both dimensions to maintain aspect ratio
        // This matches AVLayerVideoGravityResizeAspect behavior
        let scale = min(scaleX, scaleY)
        
        // Calculate the scaled image size
        let scaledImageSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        
        // Calculate offset to center the scaled image in the view
        let offsetX = (viewSize.width - scaledImageSize.width) / 2
        let offsetY = (viewSize.height - scaledImageSize.height) / 2
        
        // Apply coordinate system transformation based on current device orientation
        let currentOrientation = UIDevice.current.orientation
        let (rotatedX, rotatedY, rotatedWidth, rotatedHeight) = transformCoordinatesForOrientation(
            originalRect: originalRect,
            imageSize: imageSize,
            orientation: currentOrientation
        )
        
        // Transform the rotated rectangle
        let transformedRect = CGRect(
            x: rotatedX * scale + offsetX,
            y: rotatedY * scale + offsetY,
            width: rotatedWidth * scale,
            height: rotatedHeight * scale
        )
        
        print("📐 [FaceTrackingOverlay] Original: \(originalRect)")
        print("📐 [FaceTrackingOverlay] Rotated: (\(rotatedX), \(rotatedY), \(rotatedWidth), \(rotatedHeight))")
        print("📐 [FaceTrackingOverlay] Image size: \(imageSize), View size: \(viewSize)")
        print("📐 [FaceTrackingOverlay] Scale: \(scale), Offset: (\(offsetX), \(offsetY))")
        print("📐 [FaceTrackingOverlay] Transformed: \(transformedRect)")
        
        return transformedRect
    }
    
    /// Transform coordinates based on device orientation (like native camera app)
    private func transformCoordinatesForOrientation(
        originalRect: CGRect,
        imageSize: CGSize,
        orientation: UIDeviceOrientation
    ) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        
        switch orientation {
        case .portrait:
            // Corrected transform for portrait (fix down-left offset)
            return (
                x: originalRect.origin.y,
                y: imageSize.width - originalRect.origin.x - originalRect.width,
                width: originalRect.height,
                height: originalRect.width
            )
            
        case .portraitUpsideDown:
            // 180-degree rotation
            return (
                x: originalRect.origin.y,
                y: imageSize.width - originalRect.origin.x - originalRect.width,
                width: originalRect.height,
                height: originalRect.width
            )
            
        case .landscapeLeft:
            // 90-degree clockwise
            return (
                x: originalRect.origin.x,
                y: originalRect.origin.y,
                width: originalRect.width,
                height: originalRect.height
            )
            
        case .landscapeRight:
            // 90-degree counter-clockwise
            return (
                x: imageSize.width - originalRect.origin.x - originalRect.width,
                y: imageSize.height - originalRect.origin.y - originalRect.height,
                width: originalRect.width,
                height: originalRect.height
            )
            
        default:
            // Default to portrait
            return (
                x: imageSize.height - originalRect.origin.y - originalRect.height,
                y: originalRect.origin.x,
                width: originalRect.height,
                height: originalRect.width
            )
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Redraw overlays when view bounds change
        setNeedsDisplay()
    }
    
    // MARK: - Timer Management
    
    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
    
    private func scheduleHideTimer() {
        hideTimer?.invalidate()
        
        // If no current detections, hide immediately
        if currentDetections.isEmpty {
            hide()
            return
        }
        
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
    
    deinit {
        hideTimer?.invalidate()
    }
}
