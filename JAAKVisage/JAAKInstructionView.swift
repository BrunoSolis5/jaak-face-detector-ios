import UIKit

protocol JAAKInstructionViewDelegate: AnyObject {
    func instructionView(_ instructionView: JAAKInstructionView, didComplete completed: Bool)
    func instructionViewHelpButtonTapped(_ instructionView: JAAKInstructionView)
    func instructionView(_ instructionView: JAAKInstructionView, willStartInstructions isStarting: Bool)
    func instructionView(_ instructionView: JAAKInstructionView, didRequestCameraList completion: @escaping ([String], String?) -> Void)
    func instructionView(_ instructionView: JAAKInstructionView, didSelectCamera cameraName: String)
}

/// Instruction view for guiding users through face detection process
internal class JAAKInstructionView: UIView {
    
    // MARK: - Types
    
    enum InstructionState {
        case hidden
        case showing
        case animating
        case waiting
    }
    
    struct InstructionStep {
        let text: String
        let animation: String?
        let duration: TimeInterval
        
        init(text: String, animation: String? = nil, duration: TimeInterval = 2.0) {
            self.text = text
            self.animation = animation
            self.duration = duration
        }
    }
    
    // MARK: - Properties
    
    private let configuration: JAAKVisageConfiguration
    private var currentState: InstructionState = .hidden
    private var instructionSteps: [InstructionStep] = []
    private var currentStepIndex: Int = 0
    
    // UI Components
    private let backdropView = UIView()
    private let backgroundView = UIView()
    private let contentView = UIView()
    private let instructionTitleLabel = UILabel()
    private let instructionLabel = UILabel()
    private let instructionSubtextLabel = UILabel()
    private let animationContainerView = UIView()
    private let progressContainerView = UIView()
    private let progressSegmentsStackView = UIStackView()
    private var progressSegments: [UIView] = []
    private var segmentFills: [UIView] = []
    private var segmentWidthConstraints: [NSLayoutConstraint] = []
    private let helpButton = UIButton()
    private let cameraButton = UIButton()
    private let cameraMenuView = UIView()
    private let cameraMenuContainerView = UIStackView()
    private var cameraMenuButtons: [UIButton] = []
    private var isCameraMenuVisible = false
    private let watermarkImageView = UIImageView()
    
    // Instruction buttons
    private let buttonContainerView = UIView()
    private let pauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    
    // Animation
    private var currentAnimationView: UIView?
    private var stepTimer: Timer?
    private var progressTimer: Timer?
    private var isPaused = false
    private var currentProgress: Float = 0.0
    private var targetProgress: Float = 0.0
    private var stepStartTime: Date?
    private var totalStepDuration: TimeInterval = 0
    private var currentSegmentProgress: Float = 0.0 // Track current segment progress
    
    weak var delegate: JAAKInstructionViewDelegate?
    
    // MARK: - Initialization
    
    init(configuration: JAAKVisageConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
        setupInstructionSteps()
    }
    
    required init?(coder: NSCoder) {
        self.configuration = JAAKVisageConfiguration()
        super.init(coder: coder)
        setupUI()
        setupInstructionSteps()
    }
    
    // MARK: - Public Methods
    
    /// Show instructions with animation
    func showInstructions() {
        guard configuration.enableInstructions else { return }
        
        // FIRST: Stop any running timers
        stopCurrentTimer()
        
        // SECOND: Reset all progress state completely
        currentState = .showing
        currentStepIndex = 0
        currentProgress = 0.0
        targetProgress = 0.0
        stepStartTime = nil
        totalStepDuration = 0
        isPaused = false
        pauseButton.setTitle("Pausar", for: .normal)
        pauseButton.isEnabled = true // Re-enable pause button for new instructions
        
        // THIRD: Force immediate visual reset of ALL progress bars to 0%
        for i in 0..<segmentFills.count {
            forceResetSegmentProgress(stepIndex: i)
        }
        
        // Notify delegate that instructions are starting (to pause detection)
        delegate?.instructionView(self, willStartInstructions: true)
        
        // Hide help button when instructions are showing (matching webcomponent behavior)
        helpButton.isHidden = true
        
        // Hide camera button when instructions are showing (matching webcomponent behavior)
        cameraButton.isHidden = true
        
        // Show the backdrop and instruction content
        backdropView.isHidden = false
        backdropView.alpha = 0.0
        
        contentView.isHidden = false
        contentView.alpha = 0.0
        contentView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        
        buttonContainerView.isHidden = false
        buttonContainerView.alpha = 0.0
        
        progressContainerView.isHidden = false
        progressContainerView.alpha = 0.0
        
        // Fade in animation like webcomponent
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseOut], animations: {
            self.backdropView.alpha = 1.0
            self.contentView.alpha = 1.0
            self.contentView.transform = .identity
            self.buttonContainerView.alpha = 1.0
            self.progressContainerView.alpha = 1.0
        }) { _ in
            self.startInstructionSequence()
        }
    }
    
    /// Hide instructions
    func hideInstructions() {
        currentState = .hidden
        
        // Stop ALL timers immediately
        stopCurrentTimer()
        
        // Reset all state completely
        currentStepIndex = 0
        isPaused = false
        pauseButton.setTitle("Pausar", for: .normal)
        currentProgress = 0.0
        targetProgress = 0.0
        stepStartTime = nil
        totalStepDuration = 0
        
        // Force reset all segments to 0 for next time
        for i in 0..<segmentFills.count {
            forceResetSegmentProgress(stepIndex: i)
        }
        
        UIView.animate(withDuration: 0.3) {
            self.backdropView.alpha = 0.0
            self.contentView.alpha = 0.0
            self.buttonContainerView.alpha = 0.0
            self.progressContainerView.alpha = 0.0
        } completion: { _ in
            self.backdropView.isHidden = true
            self.contentView.isHidden = true
            self.buttonContainerView.isHidden = true
            self.progressContainerView.isHidden = true
            
            // Show help button again when instructions are hidden (matching webcomponent behavior)
            self.helpButton.isHidden = false
            
            // Show camera button again when instructions are hidden (matching webcomponent behavior)
            self.cameraButton.isHidden = false
            
            self.delegate?.instructionView(self, didComplete: false)
            
            // Notify delegate that instructions ended (to resume detection)
            self.delegate?.instructionView(self, willStartInstructions: false)
        }
    }
    
    /// Skip to next instruction
    func skipCurrentInstruction() {
        guard currentState == .showing || currentState == .animating else { return }
        
        stopCurrentTimer()
        moveToNextStep()
    }
    
    /// Replay current instruction
    func replayCurrentInstruction() {
        guard currentStepIndex < instructionSteps.count else { return }
        
        stopCurrentTimer()
        showCurrentStep()
    }
    
    
    /// Update instruction progress
    /// - Parameter progress: progress from 0.0 to 1.0
    func updateProgress(_ progress: Float) {
        updateSegmentedProgress(progress)
    }
    
    private func updateSegmentedProgress(_ progress: Float) {
        // Legacy function - convert to individual segment updates
        let totalSegments = segmentFills.count
        guard totalSegments > 0 else { return }
        
        let segmentProgress = progress * Float(totalSegments)
        let currentSegmentIndex = min(Int(segmentProgress), totalSegments - 1)
        let currentSegmentFill = segmentProgress - Float(currentSegmentIndex)
        
        // Update segments with new individual logic
        for index in 0..<totalSegments {
            if index < currentSegmentIndex {
                updateIndividualSegmentProgress(stepIndex: index, progress: 1.0)
            } else if index == currentSegmentIndex {
                updateIndividualSegmentProgress(stepIndex: index, progress: currentSegmentFill)
            } else {
                updateIndividualSegmentProgress(stepIndex: index, progress: 0.0)
            }
        }
    }
    
    private func updateIndividualSegmentProgress(stepIndex: Int, progress: Float) {
        guard stepIndex < segmentFills.count && stepIndex < progressSegments.count && stepIndex < segmentWidthConstraints.count else { return }
        
        let segment = progressSegments[stepIndex]
        let oldConstraint = segmentWidthConstraints[stepIndex]
        
        let fillWidth = CGFloat(max(0, min(1, progress))) // Clamp between 0 and 1
        
        // Update segment background based on state
        if progress > 0 {
            segment.backgroundColor = UIColor.white.withAlphaComponent(0.3) // Active background
        } else {
            segment.backgroundColor = UIColor.white.withAlphaComponent(0.2) // Inactive background
        }
        
        // Deactivate old constraint
        oldConstraint.isActive = false
        
        // Create and activate new constraint
        let fill = segmentFills[stepIndex]
        let newConstraint = fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: fillWidth)
        newConstraint.isActive = true
        
        // Store the new constraint
        segmentWidthConstraints[stepIndex] = newConstraint
        
        // Force immediate layout update if resetting to 0
        if fillWidth == 0 {
            segment.layoutIfNeeded()
        } else {
            UIView.animate(withDuration: 0.05) {
                segment.layoutIfNeeded()
            }
        }
    }
    
    /// Show a direct instruction message immediately
    /// - Parameters:
    ///   - text: instruction text to display
    ///   - animation: optional animation name
    func showDirectInstruction(text: String, animation: String? = nil) {
        guard configuration.enableInstructions else { return }
        
        // Update the label directly
        instructionLabel.text = text
        
        // Show animation if provided
        if let animationName = animation {
            showAnimationForStep(0) // Default to first step animation
        }
        
        // Show the instruction view if hidden
        if isHidden || alpha == 0.0 {
            currentState = .showing
            isHidden = false
            
            // Animate in
            alpha = 0.0
            transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
                self.alpha = 1.0
                self.transform = .identity
            })
        }
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        // Get responsive sizes
        let sizes = getResponsiveSizes()
        
        // Backdrop - full screen dark overlay (matching webcomponent: rgba(0, 0, 0, 0.85))
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        addSubview(backdropView)
        
        // No background view - use full screen backdrop like webcomponent
        
        // Content container
        contentView.backgroundColor = .clear
        addSubview(contentView)
        
        // Instruction title (h2 equivalent) - responsive font size
        instructionTitleLabel.font = UIFont.systemFont(ofSize: sizes.titleFontSize, weight: .bold)
        instructionTitleLabel.textColor = .white
        instructionTitleLabel.textAlignment = .center
        instructionTitleLabel.numberOfLines = 0
        contentView.addSubview(instructionTitleLabel)
        
        // Main instruction text - responsive font size
        instructionLabel.font = UIFont.systemFont(ofSize: sizes.fontSize, weight: .semibold)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        contentView.addSubview(instructionLabel)
        
        // Instruction subtext - responsive font size (slightly smaller than main text)
        instructionSubtextLabel.font = UIFont.systemFont(ofSize: sizes.fontSize - 2, weight: .medium)
        instructionSubtextLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        instructionSubtextLabel.textAlignment = .center
        instructionSubtextLabel.numberOfLines = 0
        contentView.addSubview(instructionSubtextLabel)
        
        // Animation container - now enabled for webcomponent-style icons
        animationContainerView.backgroundColor = .clear
        animationContainerView.isHidden = false
        contentView.addSubview(animationContainerView)
        
        // Setup segmented progress bar (like webcomponent)
        setupSegmentedProgressBar()
        
        // Help button (?) - positioned at top-right of the main view (matching webcomponent)
        setupHelpButton()
        addSubview(helpButton) // Add to main view, not contentView
        
        // Camera button - positioned below help button (matching webcomponent)
        setupCameraButton()
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cameraButton) // Add to main view, not contentView
        
        // Camera menu setup
        setupCameraMenu()
        cameraMenuView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cameraMenuView) // Add to main view, not contentView
        
        // Watermark - positioned at bottom-right of the main view
        watermarkImageView.contentMode = .scaleAspectFit
        watermarkImageView.alpha = 0.6
        addSubview(watermarkImageView)
        loadWatermarkImage()
        
        // Setup instruction buttons (matching webcomponent style)
        setupInstructionButtons()
        
        // Layout
        setupLayout()
        
        // Initial state - view is always visible for help button, but content is hidden
        isHidden = false
        alpha = 1.0
        isUserInteractionEnabled = true
        
        // Hide the instruction content and backdrop initially
        backdropView.isHidden = true
        backdropView.alpha = 0.0
        contentView.isHidden = true
        contentView.alpha = 0.0
        buttonContainerView.isHidden = true
        buttonContainerView.alpha = 0.0
        progressContainerView.isHidden = true
        progressContainerView.alpha = 0.0
        
        // Help button visible by default (matching webcomponent: shown when instructions are NOT active)
        helpButton.isHidden = false
        helpButton.alpha = 1.0
        
        // Camera button visible by default (matching webcomponent: shown when instructions are NOT active)
        cameraButton.isHidden = false
        cameraButton.alpha = 1.0
    }
    
    private func setupInstructionButtons() {
        // Button container - add to backdrop directly for interaction
        buttonContainerView.backgroundColor = .clear
        buttonContainerView.isUserInteractionEnabled = true
        addSubview(buttonContainerView)
        
        // Pause button (matching webcomponent style)
        pauseButton.setTitle("Pausar", for: .normal)
        pauseButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        pauseButton.setTitleColor(.white, for: .normal)
        pauseButton.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        pauseButton.layer.borderWidth = 1
        pauseButton.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        pauseButton.layer.cornerRadius = 20
        pauseButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        
        // Enable interaction
        pauseButton.isUserInteractionEnabled = true
        
        // Add hover effects
        pauseButton.addTarget(self, action: #selector(pauseButtonTapped), for: .touchUpInside)
        pauseButton.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        pauseButton.addTarget(self, action: #selector(buttonTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        buttonContainerView.addSubview(pauseButton)
        
        // Next button (matching webcomponent style)
        nextButton.setTitle("Siguiente", for: .normal)
        nextButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        nextButton.layer.borderWidth = 1
        nextButton.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        nextButton.layer.cornerRadius = 20
        nextButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        
        // Enable interaction
        nextButton.isUserInteractionEnabled = true
        
        // Add hover effects
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        nextButton.addTarget(self, action: #selector(buttonTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        buttonContainerView.addSubview(nextButton)
    }
    
    private func setupSegmentedProgressBar() {
        // Progress container (matching webcomponent positioning)
        progressContainerView.backgroundColor = .clear
        addSubview(progressContainerView)
        
        // Stack view for segments
        progressSegmentsStackView.axis = .horizontal
        progressSegmentsStackView.spacing = 8 // gap between segments
        progressSegmentsStackView.distribution = .fillEqually
        progressContainerView.addSubview(progressSegmentsStackView)
        
        // Create 2 segments (matching webcomponent)
        for i in 0..<2 {
            // Segment background
            let segment = UIView()
            segment.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            segment.layer.cornerRadius = 2
            segment.clipsToBounds = true
            
            // Segment fill
            let fill = UIView()
            fill.backgroundColor = .white
            fill.layer.cornerRadius = 2
            
            segment.addSubview(fill)
            progressSegmentsStackView.addArrangedSubview(segment)
            
            progressSegments.append(segment)
            segmentFills.append(fill)
            
            // Setup fill constraints
            fill.translatesAutoresizingMaskIntoConstraints = false
            
            // Create and store the width constraint
            let widthConstraint = fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: 0)
            segmentWidthConstraints.append(widthConstraint)
            
            NSLayoutConstraint.activate([
                fill.topAnchor.constraint(equalTo: segment.topAnchor),
                fill.leadingAnchor.constraint(equalTo: segment.leadingAnchor),
                fill.bottomAnchor.constraint(equalTo: segment.bottomAnchor),
                widthConstraint // Use the stored constraint
            ])
        }
    }
    
    private func setupHelpButton() {
        // Exact webcomponent styling: rgba(0, 0, 0, 0.25), backdrop-filter: blur(20px), border: 1px solid rgba(255, 255, 255, 0.1)
        helpButton.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        helpButton.layer.cornerRadius = 22 // 44px / 2 = 22px radius for perfect circle
        helpButton.clipsToBounds = true
        
        // Blur effect (iOS equivalent of backdrop-filter: blur(20px))
        let blurEffect: UIBlurEffect
        if #available(iOS 13.0, *) {
            blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        } else {
            blurEffect = UIBlurEffect(style: .dark)
        }
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        helpButton.insertSubview(blurView, at: 0)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: helpButton.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: helpButton.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: helpButton.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: helpButton.bottomAnchor)
        ])
        
        // Border: 1px solid rgba(255, 255, 255, 0.1)
        helpButton.layer.borderWidth = 1.0
        helpButton.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        
        // SVG question mark icon (exact replica of webcomponent SVG)
        let questionMarkImageView = createQuestionMarkSVG()
        questionMarkImageView.isUserInteractionEnabled = false
        helpButton.addSubview(questionMarkImageView)
        
        questionMarkImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            questionMarkImageView.centerXAnchor.constraint(equalTo: helpButton.centerXAnchor),
            questionMarkImageView.centerYAnchor.constraint(equalTo: helpButton.centerYAnchor),
            questionMarkImageView.widthAnchor.constraint(equalToConstant: 20),
            questionMarkImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        helpButton.addTarget(self, action: #selector(helpButtonTapped), for: .touchUpInside)
    }
    
    private func setupCameraButton() {
        // Exact webcomponent styling: rgba(0, 0, 0, 0.25), backdrop-filter: blur(20px), border: 1px solid rgba(255, 255, 255, 0.1)
        cameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        cameraButton.layer.cornerRadius = 22 // 44px / 2 = 22px radius for perfect circle
        cameraButton.clipsToBounds = true
        
        // Blur effect (iOS equivalent of backdrop-filter: blur(20px))
        let blurEffect: UIBlurEffect
        if #available(iOS 13.0, *) {
            blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        } else {
            blurEffect = UIBlurEffect(style: .dark)
        }
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        cameraButton.insertSubview(blurView, at: 0)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: cameraButton.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: cameraButton.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: cameraButton.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: cameraButton.bottomAnchor)
        ])
        
        // Border: 1px solid rgba(255, 255, 255, 0.1)
        cameraButton.layer.borderWidth = 1.0
        cameraButton.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        
        // SVG camera icon (exact replica of webcomponent SVG)
        let cameraImageView = createCameraSVG()
        cameraImageView.isUserInteractionEnabled = false
        cameraButton.addSubview(cameraImageView)
        
        cameraImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraImageView.centerXAnchor.constraint(equalTo: cameraButton.centerXAnchor),
            cameraImageView.centerYAnchor.constraint(equalTo: cameraButton.centerYAnchor),
            cameraImageView.widthAnchor.constraint(equalToConstant: 20),
            cameraImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        cameraButton.addTarget(self, action: #selector(cameraButtonTapped), for: .touchUpInside)
    }
    
    private func setupCameraMenu() {
        // Exact webcomponent styling
        cameraMenuView.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        cameraMenuView.layer.cornerRadius = 12
        cameraMenuView.layer.borderWidth = 1.0
        cameraMenuView.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        cameraMenuView.clipsToBounds = true
        cameraMenuView.isUserInteractionEnabled = true
        
        // Blur effect
        let blurEffect: UIBlurEffect
        if #available(iOS 13.0, *) {
            blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        } else {
            blurEffect = UIBlurEffect(style: .dark)
        }
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        cameraMenuView.insertSubview(blurView, at: 0)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: cameraMenuView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: cameraMenuView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: cameraMenuView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: cameraMenuView.bottomAnchor)
        ])
        
        // Container for menu items (UIStackView)
        cameraMenuContainerView.backgroundColor = .clear
        cameraMenuContainerView.axis = .vertical
        cameraMenuContainerView.distribution = .fill
        cameraMenuContainerView.alignment = .fill
        cameraMenuContainerView.spacing = 2 // Small spacing between items for better touch separation
        cameraMenuContainerView.isUserInteractionEnabled = true
        cameraMenuView.addSubview(cameraMenuContainerView)
        
        cameraMenuContainerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraMenuContainerView.topAnchor.constraint(equalTo: cameraMenuView.topAnchor, constant: 6),
            cameraMenuContainerView.leadingAnchor.constraint(equalTo: cameraMenuView.leadingAnchor, constant: 10),
            cameraMenuContainerView.trailingAnchor.constraint(equalTo: cameraMenuView.trailingAnchor, constant: -10),
            cameraMenuContainerView.bottomAnchor.constraint(equalTo: cameraMenuView.bottomAnchor, constant: -6)
        ])
        
        // Initially hidden
        cameraMenuView.isHidden = true
        cameraMenuView.alpha = 0.0
    }
    
    private func createQuestionMarkSVG() -> UIImageView {
        // Create the exact SVG from webcomponent as vector drawing
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let cgContext = context.cgContext
            
            // Set up drawing context
            cgContext.setStrokeColor(UIColor.white.cgColor)
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.setLineWidth(2.0)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            
            // Draw circle (cx="10" cy="10" r="9" stroke="currentColor" stroke-width="2")
            let circleCenter = CGPoint(x: 10, y: 10)
            let circleRadius: CGFloat = 9
            cgContext.addArc(center: circleCenter, radius: circleRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.strokePath()
            
            // Draw question mark path (d="M7.5 7.5C7.5 6.11929 8.61929 5 10 5C11.3807 5 12.5 6.11929 12.5 7.5C12.5 8.88071 11.3807 10 10 10V11.5")
            cgContext.beginPath()
            cgContext.move(to: CGPoint(x: 7.5, y: 7.5))
            
            // This is a curved path representing a question mark shape
            // Starting from 7.5,7.5 - curved path to 10,5 - curved to 12.5,7.5 - curved to 10,10 - line to 10,11.5
            cgContext.addCurve(to: CGPoint(x: 10, y: 5), control1: CGPoint(x: 7.5, y: 6.11929), control2: CGPoint(x: 8.61929, y: 5))
            cgContext.addCurve(to: CGPoint(x: 12.5, y: 7.5), control1: CGPoint(x: 11.3807, y: 5), control2: CGPoint(x: 12.5, y: 6.11929))
            cgContext.addCurve(to: CGPoint(x: 10, y: 10), control1: CGPoint(x: 12.5, y: 8.88071), control2: CGPoint(x: 11.3807, y: 10))
            cgContext.addLine(to: CGPoint(x: 10, y: 11.5))
            
            cgContext.strokePath()
            
            // Draw dot (cx="10" cy="14.5" r="1" fill="currentColor")
            let dotCenter = CGPoint(x: 10, y: 14.5)
            let dotRadius: CGFloat = 1
            cgContext.addArc(center: dotCenter, radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.fillPath()
        }
        
        let imageView = UIImageView(image: image)
        imageView.tintColor = .white
        return imageView
    }
    
    private func createCameraSVG() -> UIImageView {
        // Create the exact camera SVG from webcomponent as vector drawing
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let cgContext = context.cgContext
            
            // Set up drawing context
            cgContext.setStrokeColor(UIColor.white.cgColor)
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.setLineWidth(2.0)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            
            // Draw camera body path
            // d="M2 7C2 5.89543 2.89543 5 4 5H5.58579C6.11607 5 6.62464 4.78929 7 4.41421L7.58579 3.82843C8.33607 3.07815 9.36086 2.66667 10.4142 2.66667H11.5858C12.6391 2.66667 13.6639 3.07815 14.4142 3.82843L15 4.41421C15.3754 4.78929 15.8839 5 16.4142 5H18C19.1046 5 20 5.89543 20 7V15C20 16.1046 19.1046 17 18 17H4C2.89543 17 2 16.1046 2 15V7Z"
            
            // Camera body with rounded rectangle using UIBezierPath
            let cameraBodyRect = CGRect(x: 2, y: 7, width: 16, height: 8)
            let cameraBodyPath = UIBezierPath(roundedRect: cameraBodyRect, cornerRadius: 2)
            cgContext.addPath(cameraBodyPath.cgPath)
            cgContext.strokePath()
            
            // Camera lens housing (top part)
            cgContext.beginPath()
            cgContext.move(to: CGPoint(x: 7, y: 5))
            cgContext.addLine(to: CGPoint(x: 13, y: 5))
            cgContext.addLine(to: CGPoint(x: 15, y: 7))
            cgContext.addLine(to: CGPoint(x: 5, y: 7))
            cgContext.closePath()
            cgContext.strokePath()
            
            // Draw main lens circle (cx="10" cy="10" r="3")
            cgContext.addArc(center: CGPoint(x: 10, y: 10), radius: 3, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.strokePath()
            
            // Draw flash/indicator dot (cx="15" cy="7" r="1")
            cgContext.addArc(center: CGPoint(x: 15, y: 7), radius: 1, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.fillPath()
        }
        
        let imageView = UIImageView(image: image)
        imageView.tintColor = .white
        return imageView
    }
    
    // MARK: - Button Actions
    
    @objc private func pauseButtonTapped() {
        print("🔘 [JAAKInstructionView] Pause button tapped - isPaused: \(isPaused), currentStepIndex: \(currentStepIndex), totalSteps: \(instructionSteps.count)")
        
        // Safety check: Don't allow pause/resume if we're beyond the last step
        guard currentStepIndex < instructionSteps.count else {
            print("⚠️ [JAAKInstructionView] Cannot pause/resume - beyond last step")
            return
        }
        
        isPaused.toggle()
        
        if isPaused {
            print("⏸️ [JAAKInstructionView] Pausing - current progress: \(currentSegmentProgress)")
            // Pause both timers
            stopCurrentTimer()
            pauseButton.setTitle("Continuar", for: .normal)
        } else {
            print("▶️ [JAAKInstructionView] Resuming - stored progress: \(currentSegmentProgress)")
            // Resume both timers
            resumeCurrentStep()
            pauseButton.setTitle("Pausar", for: .normal)
        }
    }
    
    @objc private func cameraButtonTapped() {
        print("📷 [JAAKInstructionView] Camera button tapped")
        
        // Toggle camera menu visibility
        let isVisible = !cameraMenuView.isHidden
        
        if isVisible {
            // Hide menu
            hideCameraMenu()
        } else {
            // Show menu and populate with available cameras
            showCameraMenu()
        }
    }
    
    private func showCameraMenu() {
        // Request camera list from delegate
        delegate?.instructionView(self, didRequestCameraList: { [weak self] cameras, currentCamera in
            DispatchQueue.main.async {
                self?.populateCameraMenu(with: cameras, currentCamera: currentCamera)
                self?.animateMenuVisibility(show: true)
            }
        })
    }
    
    private func hideCameraMenu() {
        animateMenuVisibility(show: false)
    }
    
    private func populateCameraMenu(with cameras: [String], currentCamera: String?) {
        // Clear existing camera items
        cameraMenuContainerView.arrangedSubviews.forEach { view in
            if view.tag == 100 { // Camera item tag
                cameraMenuContainerView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
        
        // Add header if not present
        if cameraMenuContainerView.arrangedSubviews.isEmpty {
            let headerLabel = UILabel()
            headerLabel.text = "SELECT CAMERA"
            headerLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
            headerLabel.textColor = UIColor.white.withAlphaComponent(0.6)
            headerLabel.textAlignment = .left
            headerLabel.tag = 99 // Header tag
            
            let headerContainer = UIView()
            headerContainer.addSubview(headerLabel)
            headerLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                headerLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 6),
                headerLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 12),
                headerLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -12),
                headerLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -6)
            ])
            
            // Add border at bottom
            let borderView = UIView()
            borderView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            headerContainer.addSubview(borderView)
            borderView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                borderView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
                borderView.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
                borderView.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
                borderView.heightAnchor.constraint(equalToConstant: 1)
            ])
            
            cameraMenuContainerView.addArrangedSubview(headerContainer)
        }
        
        // Add camera items
        for (index, cameraName) in cameras.enumerated() {
            let isSelected = (cameraName == currentCamera)
            let cameraButton = createCameraMenuItem(name: cameraName, index: index, isSelected: isSelected)
            cameraMenuContainerView.addArrangedSubview(cameraButton)
        }
    }
    
    private func createCameraMenuItem(name: String, index: Int, isSelected: Bool) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = 100 // Camera item tag
        button.backgroundColor = UIColor.clear
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isUserInteractionEnabled = true
        
        // Create container for button content
        let container = UIView()
        container.isUserInteractionEnabled = false // Let touches pass through to button
        button.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: button.topAnchor, constant: 6),
            container.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            container.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -6)
        ])
        
        // Camera name label
        let nameLabel = UILabel()
        nameLabel.text = name.isEmpty ? "Camera \(index + 1)" : name
        nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .left
        container.addSubview(nameLabel)
        
        // Checkmark (show if selected)
        let checkmark = createCheckmarkSVG()
        checkmark.isHidden = !isSelected
        container.addSubview(checkmark)
        
        // Set background color if selected
        if isSelected {
            button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        } else {
            // Add subtle background for better touch visualization (debugging)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        }
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Button minimum height for proper touch area
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: checkmark.leadingAnchor, constant: -6),
            
            checkmark.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            checkmark.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 16),
            checkmark.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        // Add action
        button.addTarget(self, action: #selector(cameraMenuItemTapped(_:)), for: .touchUpInside)
        
        // Add hover effect
        button.addTarget(self, action: #selector(cameraMenuItemHighlighted(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(cameraMenuItemUnhighlighted(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        return button
    }
    
    private func createCheckmarkSVG() -> UIImageView {
        // Create checkmark SVG from web component: <path d="M13.5 4.5L6 12L2.5 8.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let cgContext = context.cgContext
            
            cgContext.setStrokeColor(UIColor(red: 92/255, green: 184/255, blue: 92/255, alpha: 1).cgColor) // #5cb85c
            cgContext.setLineWidth(2.0)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            
            // Scale path to fit 16x16 (original was 16x16)
            cgContext.beginPath()
            cgContext.move(to: CGPoint(x: 13.5, y: 4.5))
            cgContext.addLine(to: CGPoint(x: 6, y: 12))
            cgContext.addLine(to: CGPoint(x: 2.5, y: 8.5))
            cgContext.strokePath()
        }
        
        return UIImageView(image: image)
    }
    
    @objc private func cameraMenuItemTapped(_ sender: UIButton) {
        guard let nameLabel = sender.subviews.first?.subviews.first as? UILabel,
              let cameraName = nameLabel.text else { return }
        
        print("📷 [JAAKInstructionView] Camera selected: \(cameraName)")
        
        // Update UI to show selection
        updateCameraMenuSelection(selectedButton: sender)
        
        // Notify delegate
        delegate?.instructionView(self, didSelectCamera: cameraName)
        
        // Hide menu after selection
        hideCameraMenu()
    }
    
    @objc private func cameraMenuItemHighlighted(_ sender: UIButton) {
        print("🔘 [JAAKInstructionView] Camera menu item highlighted")
        UIView.animate(withDuration: 0.2) {
            sender.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        }
    }
    
    @objc private func cameraMenuItemUnhighlighted(_ sender: UIButton) {
        print("🔘 [JAAKInstructionView] Camera menu item unhighlighted")
        UIView.animate(withDuration: 0.2) {
            // Restore original background based on selection state
            let isSelected = !(sender.subviews.first?.subviews.last?.isHidden ?? true)
            sender.backgroundColor = isSelected ? UIColor.white.withAlphaComponent(0.15) : UIColor.white.withAlphaComponent(0.05)
        }
    }
    
    private func updateCameraMenuSelection(selectedButton: UIButton) {
        // Hide all checkmarks first
        cameraMenuContainerView.arrangedSubviews.forEach { view in
            if let button = view as? UIButton, button.tag == 100 {
                if let checkmark = button.subviews.first?.subviews.last as? UIImageView {
                    checkmark.isHidden = true
                }
                button.backgroundColor = UIColor.clear
            }
        }
        
        // Show checkmark for selected item
        if let checkmark = selectedButton.subviews.first?.subviews.last as? UIImageView {
            checkmark.isHidden = false
        }
        selectedButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
    }
    
    private func animateMenuVisibility(show: Bool) {
        if show {
            cameraMenuView.isHidden = false
            cameraMenuView.alpha = 0.0
            cameraMenuView.transform = CGAffineTransform(translationX: 10, y: 0)
            
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                self.cameraMenuView.alpha = 1.0
                self.cameraMenuView.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
                self.cameraMenuView.alpha = 0.0
                self.cameraMenuView.transform = CGAffineTransform(translationX: 10, y: 0)
            } completion: { _ in
                self.cameraMenuView.isHidden = true
            }
        }
    }

    @objc private func nextButtonTapped() {
        print("➡️ [JAAKInstructionView] Next button tapped - current step: \(currentStepIndex)")
        
        // FIRST: Stop all timers to prevent interference
        stopCurrentTimer()
        isPaused = false
        pauseButton.setTitle("Pausar", for: .normal)
        
        // SECOND: Complete current step's progress bar IMMEDIATELY to 100%
        if currentStepIndex < segmentFills.count {
            print("📊 [JAAKInstructionView] Forcing completion of segment \(currentStepIndex)")
            forceCompleteSegmentProgress(stepIndex: currentStepIndex)
            // Reset current segment progress tracking to indicate completion
            currentSegmentProgress = 1.0
        } else {
            print("⚠️ [JAAKInstructionView] Cannot complete segment - currentStepIndex (\(currentStepIndex)) >= segmentFills.count (\(segmentFills.count))")
        }
        
        // THIRD: Force immediate layout update to show the completion
        DispatchQueue.main.async {
            self.layoutIfNeeded()
            
            // FOURTH: Move to next step after ensuring visual update
            self.moveToNextStep()
        }
    }
    
    private func resumeCurrentStep() {
        guard currentStepIndex < instructionSteps.count else { 
            print("❌ [JAAKInstructionView] Cannot resume - currentStepIndex (\(currentStepIndex)) >= instructionSteps.count (\(instructionSteps.count))")
            // Reset pause state if we're beyond the last step
            isPaused = false
            pauseButton.setTitle("Pausar", for: .normal)
            return 
        }
        
        let step = instructionSteps[currentStepIndex]
        
        // Get current progress of the individual segment (this should be preserved from pause)
        let savedProgress = getCurrentSegmentProgress()
        let remainingDuration = step.duration * (1.0 - Double(savedProgress))
        
        print("🔄 [JAAKInstructionView] Resuming step \(currentStepIndex) - saved progress: \(savedProgress), remaining duration: \(remainingDuration)")
        
        // Safety check for remaining duration
        guard remainingDuration > 0 else {
            print("⚠️ [JAAKInstructionView] No remaining time - moving to next step immediately")
            moveToNextStep()
            return
        }
        
        // IMPORTANT: Calculate the elapsed time that should have passed to achieve savedProgress
        // Then set stepStartTime as if the timer started that much time ago
        let elapsedTime = step.duration * Double(savedProgress)
        stepStartTime = Date().addingTimeInterval(-elapsedTime)
        
        // Ensure totalStepDuration is set correctly
        totalStepDuration = step.duration
        
        print("🕐 [JAAKInstructionView] Time calculation - elapsed: \(elapsedTime)s, stepStartTime offset: \(-elapsedTime)s")
        
        // Resume progress timer first
        startProgressTimer()
        
        // Then resume step timer for remaining duration
        stepTimer = Timer.scheduledTimer(withTimeInterval: remainingDuration, repeats: false) { [weak self] _ in
            print("🔚 [JAAKInstructionView] Step timer completed after resume")
            self?.stopProgressTimer()
            self?.moveToNextStep()
        }
        
        print("✅ [JAAKInstructionView] Timers resumed - progress timer: \(progressTimer != nil), step timer: \(stepTimer != nil)")
        print("📊 [JAAKInstructionView] Expected progress after resume: \(savedProgress)")
    }
    
    private func getCurrentSegmentProgress() -> Float {
        // Return the tracked current segment progress
        return currentSegmentProgress
    }
    
    private func stopCurrentTimer() {
        // Stop step timer
        stepTimer?.invalidate()
        stepTimer = nil
        
        // Stop progress timer
        stopProgressTimer()
        
        // Reset timing state but PRESERVE currentSegmentProgress for pause/resume
        stepStartTime = nil
        totalStepDuration = 0
        // DON'T reset currentSegmentProgress here - it's needed for resume
        print("⏹️ [JAAKInstructionView] Timers stopped - preserving progress: \(currentSegmentProgress)")
    }
    
    private func startProgressTimer() {
        stopProgressTimer() // Stop any existing timer
        
        // Update progress every 50ms for smooth animation (20 FPS)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateContinuousProgress()
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateContinuousProgress() {
        guard let startTime = stepStartTime, !isPaused else { 
            if stepStartTime == nil {
                print("⚠️ [JAAKInstructionView] updateContinuousProgress called but stepStartTime is nil")
            }
            if isPaused {
                print("⚠️ [JAAKInstructionView] updateContinuousProgress called but isPaused is true")
            }
            return 
        }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let progressRatio = min(elapsedTime / totalStepDuration, 1.0)
        
        // Track current segment progress
        currentSegmentProgress = Float(progressRatio)
        
        // Debug log every 20 calls (once per second at 20fps)
        if Int(elapsedTime * 20) % 20 == 0 {
            print("📊 [JAAKInstructionView] Progress update - elapsed: \(elapsedTime)s, ratio: \(progressRatio), segment: \(currentSegmentProgress)")
        }
        
        // Update individual segment progress (0 to 1 for current step)
        updateIndividualSegmentProgress(stepIndex: currentStepIndex, progress: Float(progressRatio))
    }
    
    private func setupLayout() {
        // Get responsive sizes
        let sizes = getResponsiveSizes()
        let topMargin: CGFloat = sizes.animationHeight >= 85 ? 30 : 15 // More compact margins on iPhone
        
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        instructionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionSubtextLabel.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.translatesAutoresizingMaskIntoConstraints = false
        progressContainerView.translatesAutoresizingMaskIntoConstraints = false
        progressSegmentsStackView.translatesAutoresizingMaskIntoConstraints = false
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        watermarkImageView.translatesAutoresizingMaskIntoConstraints = false
        buttonContainerView.translatesAutoresizingMaskIntoConstraints = false
        pauseButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Backdrop - full screen overlay
            backdropView.topAnchor.constraint(equalTo: topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Content - positioned between progress bar and buttons with responsive spacing
            contentView.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentView.topAnchor.constraint(equalTo: progressContainerView.bottomAnchor, constant: sizes.animationHeight >= 85 ? 40 : 25),
            contentView.bottomAnchor.constraint(lessThanOrEqualTo: buttonContainerView.topAnchor, constant: -15),
            contentView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            contentView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            
            // Create a vertical stack-like layout with the title at the center reference point
            
            // Animation container - positioned above the center (title will be below it)
            animationContainerView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            animationContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -40), // Slightly above center
            animationContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            animationContainerView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            animationContainerView.heightAnchor.constraint(equalToConstant: sizes.animationHeight),
            
            // Instruction title - positioned below animation container
            instructionTitleLabel.topAnchor.constraint(equalTo: animationContainerView.bottomAnchor, constant: topMargin),
            instructionTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            instructionTitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Main instruction text - positioned below title
            instructionLabel.topAnchor.constraint(equalTo: instructionTitleLabel.bottomAnchor, constant: 15),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Instruction subtext - positioned below main text
            instructionSubtextLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 10),
            instructionSubtextLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            instructionSubtextLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            instructionSubtextLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor), // This closes the content view
            
            // Progress container at top (like webcomponent) - responsive spacing
            progressContainerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: sizes.animationHeight >= 85 ? 40 : 25),
            progressContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressContainerView.widthAnchor.constraint(equalToConstant: 300),
            progressContainerView.heightAnchor.constraint(equalToConstant: 4),
            
            // Progress segments stack view
            progressSegmentsStackView.topAnchor.constraint(equalTo: progressContainerView.topAnchor),
            progressSegmentsStackView.leadingAnchor.constraint(equalTo: progressContainerView.leadingAnchor),
            progressSegmentsStackView.trailingAnchor.constraint(equalTo: progressContainerView.trailingAnchor),
            progressSegmentsStackView.bottomAnchor.constraint(equalTo: progressContainerView.bottomAnchor),
            
            // Button container at bottom (like webcomponent) - responsive spacing
            buttonContainerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: sizes.animationHeight >= 85 ? -40 : -25),
            buttonContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonContainerView.heightAnchor.constraint(equalToConstant: 44),
            
            // Pause button
            pauseButton.leadingAnchor.constraint(equalTo: buttonContainerView.leadingAnchor),
            pauseButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor),
            pauseButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Next button
            nextButton.leadingAnchor.constraint(equalTo: pauseButton.trailingAnchor, constant: 12),
            nextButton.trailingAnchor.constraint(equalTo: buttonContainerView.trailingAnchor),
            nextButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor),
            nextButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Help button (?) - positioned at top-right matching webcomponent (20px from top and right)
            helpButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            helpButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            helpButton.widthAnchor.constraint(equalToConstant: 44),
            helpButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Camera button - positioned below help button matching webcomponent (76px from top, 20px from right)
            cameraButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            cameraButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 76),
            cameraButton.widthAnchor.constraint(equalToConstant: 44),
            cameraButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Camera menu - positioned next to camera button matching webcomponent (76px from top, 76px from right)
            cameraMenuView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -76),
            cameraMenuView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 76),
            cameraMenuView.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            
            // Watermark - positioned at bottom-right of the full screen with responsive size
            watermarkImageView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            watermarkImageView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            watermarkImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.2),
            watermarkImageView.heightAnchor.constraint(equalTo: watermarkImageView.widthAnchor, multiplier: 0.25)
        ])
    }
    
    private func setupInstructionSteps() {
        guard configuration.enableInstructions else { return }
        
        // Use configured instructions if available, otherwise use defaults
        let instructionTexts = configuration.instructionsText.isEmpty ? getDefaultInstructions() : configuration.instructionsText
        let instructionAnimations = configuration.instructionsAnimations.isEmpty ? getDefaultAnimations() : configuration.instructionsAnimations
        
        instructionSteps = instructionTexts.enumerated().map { index, text in
            let animation = index < instructionAnimations.count ? instructionAnimations[index] : nil
            return InstructionStep(
                text: text,
                animation: animation,
                duration: configuration.instructionDuration
            )
        }
    }
    
    private func getDefaultInstructions() -> [String] {
        return [
            "Centre su rostro en el encuadre, manténgase a la distancia correcta y mire de frente sin inclinar la cabeza",
            "Retire gorra, lentes, cubrebocas y otros accesorios"
        ]
    }
    
    private func getInstructionTitles() -> [String] {
        return [
            "Posición del rostro",
            "Sin accesorios"
        ]
    }
    
    private func getInstructionSubtexts() -> [String] {
        return [
            "La grabación iniciará automáticamente",
            "Para una detección facial óptima"
        ]
    }
    
    private func getDefaultAnimations() -> [String] {
        return []
    }
    
    private func startInstructionSequence() {
        // Double-check: Reset all progress tracking and bars
        currentStepIndex = 0
        currentProgress = 0.0
        targetProgress = 0.0
        stepStartTime = nil
        totalStepDuration = 0
        
        // Force immediate visual reset of all segments
        for i in 0..<segmentFills.count {
            forceResetSegmentProgress(stepIndex: i)
        }
        
        // Force layout update
        DispatchQueue.main.async {
            self.showCurrentStep()
        }
    }
    
    private func showCurrentStep() {
        guard currentStepIndex < instructionSteps.count else {
            completeInstructions()
            return
        }
        
        currentState = .animating
        let step = instructionSteps[currentStepIndex]
        
        // Update content following webcomponent structure
        let titles = getInstructionTitles()
        let instructions = getDefaultInstructions()
        let subtexts = getInstructionSubtexts()
        
        if currentStepIndex < titles.count {
            instructionTitleLabel.text = titles[currentStepIndex]
            instructionLabel.text = instructions[currentStepIndex]
            instructionSubtextLabel.text = subtexts[currentStepIndex]
            
            // Show corresponding animation/icon for current step
            showAnimationForStep(currentStepIndex)
        }
        
        // Setup progress tracking
        targetProgress = Float(currentStepIndex + 1) / Float(instructionSteps.count)
        totalStepDuration = step.duration
        stepStartTime = Date()
        currentSegmentProgress = 0.0 // Reset segment progress for new step
        
        // Start continuous progress updates (only if not paused)
        if !isPaused {
            startProgressTimer()
            
            // Start timer for next step
            stepTimer = Timer.scheduledTimer(withTimeInterval: step.duration, repeats: false) { [weak self] _ in
                self?.stopProgressTimer()
                self?.moveToNextStep()
            }
        }
    }
    
    private func moveToNextStep() {
        // Complete current step's progress bar at 100% immediately (if not already done)
        if currentStepIndex < segmentFills.count {
            forceCompleteSegmentProgress(stepIndex: currentStepIndex)
            // Ensure currentSegmentProgress reflects completion
            currentSegmentProgress = 1.0
        }
        
        currentStepIndex += 1
        
        if currentStepIndex < instructionSteps.count {
            // Reset segment progress for new step
            currentSegmentProgress = 0.0
            // Start next step with fresh progress (0%)
            showCurrentStep()
        } else {
            // All steps completed
            completeInstructions()
        }
    }
    
    private func completeInstructions() {
        print("✅ [JAAKInstructionView] Completing all instructions")
        
        // Disable pause button to prevent interaction
        pauseButton.isEnabled = false
        isPaused = false
        pauseButton.setTitle("Pausar", for: .normal)
        
        currentState = .hidden
        delegate?.instructionView(self, didComplete: true)
        
        // Show help button again since instructions are completing
        helpButton.isHidden = false
        
        // Show camera button again since instructions are completing
        cameraButton.isHidden = false
        
        // Hide after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hideInstructions()
        }
    }
    
    private func showAnimationForStep(_ stepIndex: Int) {
        // Clear previous animation
        currentAnimationView?.removeFromSuperview()
        currentAnimationView = nil
        
        let animationView: UIView
        
        switch stepIndex {
        case 0:
            // Step 1: "Posición del rostro" - Center face icon
            animationView = createCenterFaceIcon()
        case 1:
            // Step 2: "Sin accesorios" - Multiple accessory icons
            animationView = createAccessoryIcons()
        default:
            return
        }
        
        // Add animation view to container
        animationContainerView.addSubview(animationView)
        currentAnimationView = animationView
        
        // Layout animation view
        animationView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            animationView.centerXAnchor.constraint(equalTo: animationContainerView.centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: animationContainerView.centerYAnchor),
            animationView.widthAnchor.constraint(lessThanOrEqualTo: animationContainerView.widthAnchor),
            animationView.heightAnchor.constraint(lessThanOrEqualTo: animationContainerView.heightAnchor)
        ])
        
        // Add pulse animation like webcomponent
        addPulseAnimation(to: animationView)
    }
    
    private func createCenterFaceIcon() -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // Get responsive size
        let sizes = getResponsiveSizes()
        
        // Load PNG icon as UIImageView - responsive size
        if let iconImage = loadIconImage(named: "icon-center-face-dark") {
            let imageView = UIImageView(image: iconImage)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(imageView)
            
            // Center the icon perfectly using Auto Layout with responsive size
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: sizes.centerIcon),
                imageView.heightAnchor.constraint(equalToConstant: sizes.centerIcon)
            ])
        }
        
        return containerView
    }
    
    
    private func createAccessoryIcons() -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // Get responsive sizes
        let sizes = getResponsiveSizes()
        let spacing: CGFloat = sizes.accessoryIcon >= 65 ? 30 : 20 // Reduce spacing on smaller screens
        
        // Create horizontal stack view to center the icons (like webcomponent flexbox)
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = spacing
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)
        
        // Center the stack view in the container
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        // Cap icon (PNG) - responsive size
        if let capImage = loadIconImage(named: "icon-cap-dark") {
            let capImageView = UIImageView(image: capImage)
            capImageView.contentMode = .scaleAspectFit
            capImageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                capImageView.widthAnchor.constraint(equalToConstant: sizes.accessoryIcon),
                capImageView.heightAnchor.constraint(equalToConstant: sizes.accessoryIcon)
            ])
            stackView.addArrangedSubview(capImageView)
        }
        
        // Glasses icon (PNG) - responsive size
        if let glassesImage = loadIconImage(named: "icon-glasses-dark") {
            let glassesImageView = UIImageView(image: glassesImage)
            glassesImageView.contentMode = .scaleAspectFit
            glassesImageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                glassesImageView.widthAnchor.constraint(equalToConstant: sizes.accessoryIcon),
                glassesImageView.heightAnchor.constraint(equalToConstant: sizes.accessoryIcon)
            ])
            stackView.addArrangedSubview(glassesImageView)
        }
        
        // Headphones icon (PNG) - responsive size
        if let headphonesImage = loadIconImage(named: "icon-headphones-dark") {
            let headphonesImageView = UIImageView(image: headphonesImage)
            headphonesImageView.contentMode = .scaleAspectFit
            headphonesImageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                headphonesImageView.widthAnchor.constraint(equalToConstant: sizes.accessoryIcon),
                headphonesImageView.heightAnchor.constraint(equalToConstant: sizes.accessoryIcon)
            ])
            stackView.addArrangedSubview(headphonesImageView)
        }
        
        return containerView
    }
    
    
    private func addPulseAnimation(to view: UIView) {
        // Match webcomponent pulse animation exactly:
        // 0%: scale(1) opacity(0.8)
        // 50%: scale(1.05) opacity(1)
        // 100%: scale(1) opacity(0.8)
        
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.duration = 2.0
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 1.05
        scaleAnimation.autoreverses = true
        scaleAnimation.repeatCount = .infinity
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.duration = 2.0
        opacityAnimation.fromValue = 0.8
        opacityAnimation.toValue = 1.0
        opacityAnimation.autoreverses = true
        opacityAnimation.repeatCount = .infinity
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        view.layer.add(scaleAnimation, forKey: "pulseScale")
        view.layer.add(opacityAnimation, forKey: "pulseOpacity")
    }
    
    private func loadIconImage(named: String) -> UIImage? {
        // Get the bundle for this framework/library
        let frameworkBundle = Bundle(for: type(of: self))
        
        // Try loading from resource bundle (JAAKVisage.bundle)
        if let resourceBundleURL = frameworkBundle.url(forResource: "JAAKVisage", withExtension: "bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL),
           let image = UIImage(named: named, in: resourceBundle, compatibleWith: nil) {
            print("✅ Loaded icon '\(named)' from resource bundle")
            return image
        }
        
        // Try loading from framework bundle Resources directory
        if let path = frameworkBundle.path(forResource: named, ofType: "png", inDirectory: "Resources"),
           let image = UIImage(contentsOfFile: path) {
            print("✅ Loaded icon '\(named)' from framework bundle Resources")
            return image
        }
        
        // Try loading from framework bundle Assets directory
        if let path = frameworkBundle.path(forResource: named, ofType: "png", inDirectory: "Assets"),
           let image = UIImage(contentsOfFile: path) {
            print("✅ Loaded icon '\(named)' from framework bundle Assets")
            return image
        }
        
        // Try loading from framework bundle root
        if let path = frameworkBundle.path(forResource: named, ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            print("✅ Loaded icon '\(named)' from framework bundle root")
            return image
        }
        
        // Try absolute paths for development
        let developmentPaths = [
            "/Users/diego.bruno/Development/iOS/JAAKVisage/JAAKVisage/Resources/\(named).png",
            "/Users/diego.bruno/Development/iOS/JAAKVisage/JAAKVisage/Assets/\(named).png",
            "/Users/diego.bruno/Development/iOS/JAAKVisage/JAAKVisage/\(named).png"
        ]
        
        for devPath in developmentPaths {
            if let image = UIImage(contentsOfFile: devPath) {
                print("✅ Loaded icon '\(named)' from development path: \(devPath)")
                return image
            }
        }
        
        // Try main bundle as fallback
        if let image = UIImage(named: named, in: frameworkBundle, compatibleWith: nil) {
            print("✅ Loaded icon '\(named)' from framework bundle by name")
            return image
        }
        
        // Final fallback: main app bundle
        if let image = UIImage(named: named) {
            print("✅ Loaded icon '\(named)' from main app bundle")
            return image
        }
        
        print("❌ Failed to load icon '\(named)'")
        print("  - Framework bundle: \(frameworkBundle.bundlePath)")
        print("  - Framework bundle identifier: \(frameworkBundle.bundleIdentifier ?? "unknown")")
        
        // Debug: List available resources
        if let resourceBundleURL = frameworkBundle.url(forResource: "JAAKVisage", withExtension: "bundle") {
            print("  - Resource bundle found at: \(resourceBundleURL)")
        } else {
            print("  - No resource bundle found")
        }
        
        return nil
    }
    
    // MARK: - Helper Functions
    
    /// Get responsive sizes based on screen size (matching webcomponent behavior)
    private func getResponsiveSizes() -> (centerIcon: CGFloat, accessoryIcon: CGFloat, fontSize: CGFloat, titleFontSize: CGFloat, animationHeight: CGFloat) {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        // iPhone (small screens)
        if screenWidth <= 390 || screenHeight <= 667 {
            return (
                centerIcon: 50,        // Smaller center icon for better fit
                accessoryIcon: 40,     // Smaller accessory icons
                fontSize: 14,          // Smaller text for better fit
                titleFontSize: 18,     // Smaller title for better fit
                animationHeight: 60    // Reduced animation container for more space
            )
        }
        // iPad (large screens)
        else if screenWidth >= 768 {
            return (
                centerIcon: 100,       // 100x100 for center icon (webcomponent desktop)
                accessoryIcon: 80,     // 80x80 for accessory icons
                fontSize: 20,          // Larger text
                titleFontSize: 24,     // Standard title
                animationHeight: 100   // Full animation container
            )
        }
        // iPhone Plus/Max (medium screens)  
        else {
            return (
                centerIcon: 80,        // 80x80 for center icon
                accessoryIcon: 65,     // 65x65 for accessory icons
                fontSize: 18,          // Medium text
                titleFontSize: 22,     // Medium title
                animationHeight: 85    // Medium animation container
            )
        }
    }
    
    private func forceResetSegmentProgress(stepIndex: Int) {
        guard stepIndex < segmentFills.count && stepIndex < progressSegments.count && stepIndex < segmentWidthConstraints.count else { return }
        
        let fill = segmentFills[stepIndex]
        let segment = progressSegments[stepIndex]
        let oldConstraint = segmentWidthConstraints[stepIndex]
        
        // Deactivate old constraint
        oldConstraint.isActive = false
        
        // Reset background to inactive state
        segment.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        
        // Create new constraint with 0 width
        let resetConstraint = fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: 0)
        resetConstraint.isActive = true
        
        // Store the new constraint
        segmentWidthConstraints[stepIndex] = resetConstraint
        
        // Force immediate layout update
        segment.layoutIfNeeded()
    }
    
    private func forceCompleteSegmentProgress(stepIndex: Int) {
        guard stepIndex < segmentFills.count && stepIndex < progressSegments.count && stepIndex < segmentWidthConstraints.count else { return }
        
        let fill = segmentFills[stepIndex]
        let segment = progressSegments[stepIndex]
        let oldConstraint = segmentWidthConstraints[stepIndex]
        
        print("🔧 [JAAKInstructionView] Completing segment \(stepIndex) - old constraint active: \(oldConstraint.isActive)")
        
        // Deactivate old constraint
        oldConstraint.isActive = false
        
        // Set background to active state
        segment.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        
        // Create new constraint with 100% width
        let completeConstraint = fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: 1.0)
        completeConstraint.isActive = true
        
        // Store the new constraint
        segmentWidthConstraints[stepIndex] = completeConstraint
        
        print("✅ [JAAKInstructionView] New constraint created for segment \(stepIndex) - active: \(completeConstraint.isActive)")
        
        // Force immediate layout update with animation for visual feedback
        UIView.animate(withDuration: 0.2, animations: {
            segment.layoutIfNeeded()
        })
    }
    
    @objc private func helpButtonTapped() {
        showInstructions()
    }
    
    @objc private func buttonTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            sender.alpha = 0.8
        }
    }
    
    @objc private func buttonTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
            sender.alpha = 1.0
        }
    }
    
    private func loadWatermarkImage() {
        let urlString = "https://storage.googleapis.com/jaak-static/commons/powered-by-jaak.png"
        guard let url = URL(string: urlString) else {
            print("⚠️ [JAAKInstructionView] Invalid watermark URL")
            return
        }
        
        // Download image asynchronously
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else {
                print("⚠️ [JAAKInstructionView] Failed to load watermark image: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            DispatchQueue.main.async {
                self.watermarkImageView.image = image
                print("✅ [JAAKInstructionView] Watermark image loaded successfully")
            }
        }.resume()
    }
}
