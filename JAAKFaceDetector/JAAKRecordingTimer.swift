import UIKit

/// Recording timer view with circular progress indicator
internal class JAAKRecordingTimer: UIView {
    
    // MARK: - Properties
    
    private let progressLayer = CAShapeLayer()
    private let backgroundLayer = CAShapeLayer()
    private let timerLabel = UILabel()
    private var configuration: JAAKTimerStyles
    private var currentProgress: Float = 0.0
    private var isRecording: Bool = false
    private var totalDuration: TimeInterval = 0.0
    
    // MARK: - Initialization
    
    init(configuration: JAAKTimerStyles) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        self.configuration = JAAKTimerStyles()
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Public Methods
    
    /// Start the recording timer
    /// - Parameter duration: total recording duration in seconds
    func startTimer(duration: TimeInterval) {
        isRecording = true
        currentProgress = 0.0
        totalDuration = duration
        
        // Show the timer with animation
        show()
        
        // Update colors for recording state
        updateColors()
        
        // Reset progress and show initial countdown
        updateProgress(0.0)
    }
    
    /// Stop the recording timer
    func stopTimer() {
        isRecording = false
        
        // Update colors for success state
        updateColorsForSuccess()
        
        // Hide after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hide()
        }
    }
    
    /// Update recording progress
    /// - Parameter progress: progress value from 0.0 to 1.0
    func updateProgress(_ progress: Float) {
        currentProgress = progress
        
        // Update circular progress
        progressLayer.strokeEnd = CGFloat(progress)
        
        // Calculate remaining time (countdown from total duration to 0)
        let remainingTime = totalDuration * (1.0 - TimeInterval(progress))
        
        // Format time display (show only integer seconds)
        let remainingSeconds = Int(ceil(remainingTime))
        timerLabel.text = "\(max(0, remainingSeconds))"
        
        // Animate the progress change
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        progressLayer.strokeEnd = CGFloat(progress)
        CATransaction.commit()
    }
    
    /// Update timer configuration
    /// - Parameter configuration: new timer styles
    func updateConfiguration(_ configuration: JAAKTimerStyles) {
        self.configuration = configuration
        setupUI()
    }
    
    /// Show the timer
    func show() {
        isHidden = false
        alpha = 0.0
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
            self.alpha = 1.0
            self.transform = .identity
        })
    }
    
    /// Hide the timer
    func hide() {
        UIView.animate(withDuration: 0.3) {
            self.alpha = 0.0
            self.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.isHidden = true
        }
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        backgroundColor = .clear
        
        // Configure frame size
        frame.size = configuration.size
        
        // Setup background circle
        backgroundLayer.strokeColor = configuration.circleEmptyColor.cgColor
        backgroundLayer.fillColor = UIColor.clear.cgColor
        backgroundLayer.lineWidth = configuration.strokeWidth
        backgroundLayer.lineDashPattern = configuration.dashPattern
        layer.addSublayer(backgroundLayer)
        
        // Setup progress circle
        progressLayer.strokeColor = configuration.circleColor.cgColor
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineWidth = configuration.strokeWidth
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0.0
        layer.addSublayer(progressLayer)
        
        // Setup timer label
        timerLabel.textAlignment = .center
        timerLabel.font = UIFont.systemFont(ofSize: configuration.fontSize, weight: .medium)
        timerLabel.textColor = configuration.textColor
        timerLabel.text = "0"
        addSubview(timerLabel)
        
        // Layout
        updateLayout()
        
        // Initial state
        hide()
    }
    
    private func updateLayout() {
        // Create circular path
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - configuration.strokeWidth / 2
        let startAngle = -CGFloat.pi / 2 // Start from top
        let endAngle = startAngle + 2 * CGFloat.pi
        
        let circularPath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        
        backgroundLayer.path = circularPath.cgPath
        progressLayer.path = circularPath.cgPath
        
        // Layout label
        timerLabel.frame = bounds
    }
    
    private func updateColors() {
        progressLayer.strokeColor = configuration.circleColor.cgColor
        backgroundLayer.strokeColor = configuration.circleEmptyColor.cgColor
        timerLabel.textColor = configuration.textColor
    }
    
    private func updateColorsForSuccess() {
        progressLayer.strokeColor = configuration.circleSuccessColor.cgColor
        
        // Animate color change
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        progressLayer.strokeColor = configuration.circleSuccessColor.cgColor
        CATransaction.commit()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }
    
    override var intrinsicContentSize: CGSize {
        return configuration.size
    }
}