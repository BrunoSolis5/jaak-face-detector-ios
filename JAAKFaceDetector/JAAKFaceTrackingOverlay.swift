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
        let changed = imageWidth != width || imageHeight != height
        imageWidth = width
        imageHeight = height
        
        
        // If dimensions changed, redraw any existing detections
        if changed && !currentDetections.isEmpty {
            setNeedsDisplay()
        }
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
        
        // Listen for orientation changes like MediaPipe example
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func orientationDidChange() {
        
        // Notify via notification that capture orientation should be updated
        NotificationCenter.default.post(
            name: NSNotification.Name("JAAKUpdateCaptureOrientation"),
            object: nil
        )
        
        // Clear current detections and redraw with new orientation
        DispatchQueue.main.async {
            self.clearDetections()
            // Force redraw when new detections come in
            self.setNeedsDisplay()
        }
    }
    
    /// Apply orientation transform to face detection coordinates (like native camera app)
    private func applyOrientationTransform(to rect: CGRect) -> CGRect {
        let currentOrientation = UIDevice.current.orientation
        
        // Important: Don't transform coordinates here since MediaPipe already provides
        // coordinates relative to the current video orientation. Just return as-is.
        // The real issue is ensuring imageWidth/imageHeight are correctly oriented.
        return rect
    }
    
    /// Get image dimensions (now that camera captures in correct orientation, use dimensions as-is)
    private func getOrientationAdjustedImageSize() -> CGSize {
        // Since camera now captures in the correct orientation, 
        // use the image dimensions directly without transformation
        return CGSize(width: imageWidth, height: imageHeight)
    }
    
    private func drawFaceDetection(_ detection: FaceDetection, in context: CGContext) {
        // Get orientation-adjusted image dimensions for proper coordinate mapping
        let adjustedImageSize = getOrientationAdjustedImageSize()
        
        // Transform MediaPipe coordinates to view coordinates using adjusted dimensions
        let transformedRect = rectAfterApplyingBoundsAdjustment(
            originalRect: detection.boundingBox,
            imageSize: adjustedImageSize,
            viewSize: bounds.size
        )
        
        // Validate that the transformed frame has valid dimensions but allow it to extend beyond bounds
        guard transformedRect.width > 0 && transformedRect.height > 0 else {
            print("⚠️ [FaceTrackingOverlay] Invalid transformed frame dimensions: \(transformedRect)")
            return
        }
        
        // Clip the rectangle to view bounds if it extends beyond
        let clippedRect = transformedRect.intersection(bounds)
        guard !clippedRect.isEmpty else {
            print("⚠️ [FaceTrackingOverlay] Transformed frame completely outside bounds: \(transformedRect)")
            return
        }
        
        // Set drawing properties
        context.setLineWidth(lineWidth)
        let strokeColor = detection.isValid ? configuration.validColor : configuration.invalidColor
        context.setStrokeColor(strokeColor.cgColor)
        context.setFillColor(UIColor.clear.cgColor)
        
        // Draw rounded rectangle using the clipped bounds
        let path = UIBezierPath(roundedRect: clippedRect, cornerRadius: cornerRadius)
        context.addPath(path.cgPath)
        context.strokePath()
    }
    
    /// Transform detection coordinates to view coordinates (MediaPipe official pattern)
    /// Following MediaPipe iOS sample exactly - no orientation transforms at overlay level
    /// - Parameters:
    ///   - originalRect: Original detection rectangle from MediaPipe (already oriented)
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
        
        // MediaPipe pattern: calculate offsets and scale factor
        let (xOffset, yOffset, scaleFactor) = offsetsAndScaleFactor(
            forImageOfSize: imageSize,
            tobeDrawnInViewOfSize: viewSize,
            withContentMode: .scaleAspectFit
        )
        
        // Apply MediaPipe transformation pattern
        let transformedRect = originalRect
            .applying(CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
            .applying(CGAffineTransform(translationX: xOffset, y: yOffset))
        
        return transformedRect
    }
    
    /// MediaPipe pattern for calculating offsets and scale factor
    /// Exactly as implemented in MediaPipe iOS sample
    private func offsetsAndScaleFactor(
        forImageOfSize imageSize: CGSize,
        tobeDrawnInViewOfSize viewSize: CGSize,
        withContentMode contentMode: UIView.ContentMode
    ) -> (xOffset: CGFloat, yOffset: CGFloat, scaleFactor: CGFloat) {
        
        let widthScale = viewSize.width / imageSize.width
        let heightScale = viewSize.height / imageSize.height
        
        var scaleFactor: CGFloat = 1.0
        
        switch contentMode {
        case .scaleAspectFit:
            scaleFactor = min(widthScale, heightScale)
        case .scaleAspectFill:
            scaleFactor = max(widthScale, heightScale)
        case .scaleToFill:
            // For scaleToFill, we would need different handling
            scaleFactor = 1.0
        default:
            scaleFactor = min(widthScale, heightScale)
        }
        
        let scaledSize = CGSize(
            width: imageSize.width * scaleFactor,
            height: imageSize.height * scaleFactor
        )
        
        let xOffset = (viewSize.width - scaledSize.width) / 2.0
        let yOffset = (viewSize.height - scaledSize.height) / 2.0
        
        return (xOffset, yOffset, scaleFactor)
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
        NotificationCenter.default.removeObserver(self)
    }
}
