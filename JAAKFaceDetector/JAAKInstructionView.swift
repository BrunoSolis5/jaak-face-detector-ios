import UIKit

protocol JAAKInstructionViewDelegate: AnyObject {
    func instructionView(_ instructionView: JAAKInstructionView, didComplete completed: Bool)
    func instructionViewHelpButtonTapped(_ instructionView: JAAKInstructionView)
    func instructionView(_ instructionView: JAAKInstructionView, willStartInstructions isStarting: Bool)
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
    
    private let configuration: JAAKFaceDetectorConfiguration
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
    private let helpButton = UIButton()
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
    
    weak var delegate: JAAKInstructionViewDelegate?
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceDetectorConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
        setupInstructionSteps()
    }
    
    required init?(coder: NSCoder) {
        self.configuration = JAAKFaceDetectorConfiguration()
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
        
        // THIRD: Force immediate visual reset of ALL progress bars to 0%
        for i in 0..<segmentFills.count {
            forceResetSegmentProgress(stepIndex: i)
        }
        
        // Notify delegate that instructions are starting (to pause detection)
        delegate?.instructionView(self, willStartInstructions: true)
        
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
        guard stepIndex < segmentFills.count && stepIndex < progressSegments.count else { return }
        
        let fill = segmentFills[stepIndex]
        let segment = progressSegments[stepIndex]
        
        // Remove existing width constraint
        fill.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }
        
        let fillWidth = CGFloat(max(0, min(1, progress))) // Clamp between 0 and 1
        
        // Update segment background based on state
        if progress > 0 {
            segment.backgroundColor = UIColor.white.withAlphaComponent(0.3) // Active background
        } else {
            segment.backgroundColor = UIColor.white.withAlphaComponent(0.2) // Inactive background
        }
        
        // Apply new width constraint
        let widthConstraint = fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: fillWidth)
        widthConstraint.isActive = true
        
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
        
        // Help button (?) - positioned at top-left of the main view
        helpButton.setTitle("?", for: .normal)
        helpButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        helpButton.setTitleColor(.white, for: .normal)
        helpButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        helpButton.layer.cornerRadius = 16
        helpButton.clipsToBounds = true
        helpButton.addTarget(self, action: #selector(helpButtonTapped), for: .touchUpInside)
        addSubview(helpButton) // Add to main view, not contentView
        
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
            NSLayoutConstraint.activate([
                fill.topAnchor.constraint(equalTo: segment.topAnchor),
                fill.leadingAnchor.constraint(equalTo: segment.leadingAnchor),
                fill.bottomAnchor.constraint(equalTo: segment.bottomAnchor),
                fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: 0) // Start with 0 width
            ])
        }
    }
    
    // MARK: - Button Actions
    
    @objc private func pauseButtonTapped() {
        print("🔘 [JAAKInstructionView] Pause button tapped")
        isPaused.toggle()
        
        if isPaused {
            // Pause both timers
            stopCurrentTimer()
            pauseButton.setTitle("Continuar", for: .normal)
        } else {
            // Resume both timers
            resumeCurrentStep()
            pauseButton.setTitle("Pausar", for: .normal)
        }
    }
    
    @objc private func nextButtonTapped() {
        print("➡️ [JAAKInstructionView] Next button tapped - current step: \(currentStepIndex)")
        
        // Complete current step's progress bar IMMEDIATELY to 100%
        if currentStepIndex < segmentFills.count {
            print("📊 [JAAKInstructionView] Forcing completion of segment \(currentStepIndex)")
            forceCompleteSegmentProgress(stepIndex: currentStepIndex)
        } else {
            print("⚠️ [JAAKInstructionView] Cannot complete segment - currentStepIndex (\(currentStepIndex)) >= segmentFills.count (\(segmentFills.count))")
        }
        
        // Stop timers and reset pause state
        stopCurrentTimer()
        isPaused = false
        pauseButton.setTitle("Pausar", for: .normal)
        
        // Move to next step
        moveToNextStep()
    }
    
    private func resumeCurrentStep() {
        guard currentStepIndex < instructionSteps.count else { return }
        
        let step = instructionSteps[currentStepIndex]
        
        // Get current progress of the individual segment
        let currentSegmentProgress = getCurrentSegmentProgress()
        let remainingDuration = step.duration * (1.0 - Double(currentSegmentProgress))
        
        // Reset start time for continuous progress calculation
        let elapsedTime = step.duration - remainingDuration
        stepStartTime = Date().addingTimeInterval(-elapsedTime)
        
        // Resume both timers
        startProgressTimer()
        
        stepTimer = Timer.scheduledTimer(withTimeInterval: remainingDuration, repeats: false) { [weak self] _ in
            self?.stopProgressTimer()
            self?.moveToNextStep()
        }
    }
    
    private func getCurrentSegmentProgress() -> Float {
        // Get the current fill width of the active segment
        guard currentStepIndex < segmentFills.count else { return 0.0 }
        
        let fill = segmentFills[currentStepIndex]
        let segment = progressSegments[currentStepIndex]
        
        // Find the width constraint to get current progress
        for constraint in fill.constraints {
            if constraint.firstAttribute == .width && constraint.secondItem === segment {
                return Float(constraint.multiplier)
            }
        }
        
        return 0.0
    }
    
    private func stopCurrentTimer() {
        // Stop step timer
        stepTimer?.invalidate()
        stepTimer = nil
        
        // Stop progress timer
        stopProgressTimer()
        
        // Reset timing state
        stepStartTime = nil
        totalStepDuration = 0
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
        guard let startTime = stepStartTime, !isPaused else { return }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let progressRatio = min(elapsedTime / totalStepDuration, 1.0)
        
        // Update individual segment progress (0 to 1 for current step)
        updateIndividualSegmentProgress(stepIndex: currentStepIndex, progress: Float(progressRatio))
    }
    
    private func setupLayout() {
        // Get responsive sizes
        let sizes = getResponsiveSizes()
        let topMargin: CGFloat = sizes.animationHeight >= 85 ? 30 : 20 // Reduce margins on smaller screens
        
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
            
            // Content - centered on full screen like webcomponent
            contentView.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            contentView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            
            // Instruction title at top
            instructionTitleLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            instructionTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            instructionTitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Animation container between title and text (responsive height)
            animationContainerView.topAnchor.constraint(equalTo: instructionTitleLabel.bottomAnchor, constant: topMargin),
            animationContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            animationContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            animationContainerView.heightAnchor.constraint(equalToConstant: sizes.animationHeight),
            
            // Main instruction text (responsive margin)
            instructionLabel.topAnchor.constraint(equalTo: animationContainerView.bottomAnchor, constant: topMargin),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Instruction subtext
            instructionSubtextLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 10),
            instructionSubtextLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            instructionSubtextLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Progress container at top (like webcomponent)
            progressContainerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 40),
            progressContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressContainerView.widthAnchor.constraint(equalToConstant: 300),
            progressContainerView.heightAnchor.constraint(equalToConstant: 4),
            
            // Progress segments stack view
            progressSegmentsStackView.topAnchor.constraint(equalTo: progressContainerView.topAnchor),
            progressSegmentsStackView.leadingAnchor.constraint(equalTo: progressContainerView.leadingAnchor),
            progressSegmentsStackView.trailingAnchor.constraint(equalTo: progressContainerView.trailingAnchor),
            progressSegmentsStackView.bottomAnchor.constraint(equalTo: progressContainerView.bottomAnchor),
            
            // Button container at bottom (like webcomponent)
            buttonContainerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -40),
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
            
            // Content view bottom constraint (above buttons)
            instructionSubtextLabel.bottomAnchor.constraint(lessThanOrEqualTo: buttonContainerView.topAnchor, constant: -30),
            
            // Help button (?) - positioned at top-left of the full screen
            helpButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            helpButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            helpButton.widthAnchor.constraint(equalToConstant: 32),
            helpButton.heightAnchor.constraint(equalToConstant: 32),
            
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
        // Complete current step's progress bar at 100% immediately
        if currentStepIndex < segmentFills.count {
            forceCompleteSegmentProgress(stepIndex: currentStepIndex)
        }
        
        currentStepIndex += 1
        
        if currentStepIndex < instructionSteps.count {
            // Start next step with fresh progress (0%)
            showCurrentStep()
        } else {
            // All steps completed
            completeInstructions()
        }
    }
    
    private func completeInstructions() {
        currentState = .hidden
        delegate?.instructionView(self, didComplete: true)
        
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
        
        // Try loading from resource bundle (JAAKFaceDetector.bundle)
        if let resourceBundleURL = frameworkBundle.url(forResource: "JAAKFaceDetector", withExtension: "bundle"),
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
            "/Users/diego.bruno/Development/iOS/JAAKFaceDetector/JAAKFaceDetector/Resources/\(named).png",
            "/Users/diego.bruno/Development/iOS/JAAKFaceDetector/JAAKFaceDetector/Assets/\(named).png",
            "/Users/diego.bruno/Development/iOS/JAAKFaceDetector/JAAKFaceDetector/\(named).png"
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
        if let resourceBundleURL = frameworkBundle.url(forResource: "JAAKFaceDetector", withExtension: "bundle") {
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
                centerIcon: 60,        // 60x60 for center icon
                accessoryIcon: 50,     // 50x50 for accessory icons
                fontSize: 16,          // Smaller text
                titleFontSize: 20,     // Smaller title
                animationHeight: 70    // Reduced animation container
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
        guard stepIndex < segmentFills.count && stepIndex < progressSegments.count else { return }
        
        let fill = segmentFills[stepIndex]
        let segment = progressSegments[stepIndex]
        
        // Remove all existing width constraints
        fill.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }
        
        // Reset background to inactive state
        segment.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        
        // Create new constraint with 0 width
        let resetConstraint = fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: 0)
        resetConstraint.isActive = true
        
        // Force immediate layout update
        segment.layoutIfNeeded()
    }
    
    private func forceCompleteSegmentProgress(stepIndex: Int) {
        guard stepIndex < segmentFills.count && stepIndex < progressSegments.count else { return }
        
        let fill = segmentFills[stepIndex]
        let segment = progressSegments[stepIndex]
        
        // Remove all existing width constraints
        fill.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }
        
        // Set background to active state
        segment.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        
        // Create new constraint with 100% width
        let completeConstraint = fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: 1.0)
        completeConstraint.isActive = true
        
        // Force immediate layout update
        segment.layoutIfNeeded()
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
