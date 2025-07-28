import UIKit

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
            showAnimation(animationName)
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
        // Backdrop - full screen dark overlay (matching webcomponent: rgba(0, 0, 0, 0.85))
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        addSubview(backdropView)
        
        // No background view - use full screen backdrop like webcomponent
        
        // Content container
        contentView.backgroundColor = .clear
        addSubview(contentView)
        
        // Instruction title (h2 equivalent)
        instructionTitleLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        instructionTitleLabel.textColor = .white
        instructionTitleLabel.textAlignment = .center
        instructionTitleLabel.numberOfLines = 0
        contentView.addSubview(instructionTitleLabel)
        
        // Main instruction text
        instructionLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        contentView.addSubview(instructionLabel)
        
        // Instruction subtext
        instructionSubtextLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        instructionSubtextLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        instructionSubtextLabel.textAlignment = .center
        instructionSubtextLabel.numberOfLines = 0
        contentView.addSubview(instructionSubtextLabel)
        
        // Animation container - hidden in text-only mode
        animationContainerView.backgroundColor = .clear
        animationContainerView.isHidden = true
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
            
            // Animation container between title and text (hidden for now)
            animationContainerView.topAnchor.constraint(equalTo: instructionTitleLabel.bottomAnchor, constant: 30),
            animationContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            animationContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            animationContainerView.heightAnchor.constraint(equalToConstant: 0),
            
            // Main instruction text
            instructionLabel.topAnchor.constraint(equalTo: animationContainerView.bottomAnchor, constant: 30),
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
    
    private func showAnimation(_ animationName: String) {
        // Skip animations - text only mode
        return
    }
    
    private func createAnimationView(for animationName: String) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        view.layer.cornerRadius = 40
        
        // Create appropriate placeholder based on animation name or URL
        if animationName.contains("glasses") {
            view.backgroundColor = UIColor.blue.withAlphaComponent(0.3)
            addGlassesPlaceholder(to: view)
        } else if animationName.contains("hat") {
            view.backgroundColor = UIColor.green.withAlphaComponent(0.3)
            addHatPlaceholder(to: view)
        } else if animationName.contains("headphones") {
            view.backgroundColor = UIColor.purple.withAlphaComponent(0.3)
            addHeadphonesPlaceholder(to: view)
        } else if animationName.contains("light") {
            view.backgroundColor = UIColor.yellow.withAlphaComponent(0.3)
            addLightPlaceholder(to: view)
        } else {
            // Handle old animation names
            switch animationName {
            case "center_face":
                view.layer.borderWidth = 2
                view.layer.borderColor = UIColor.white.cgColor
                
            case "move_closer":
                view.backgroundColor = UIColor.green.withAlphaComponent(0.3)
                
            case "move_away":
                view.backgroundColor = UIColor.orange.withAlphaComponent(0.3)
                
            case "hold_still":
                view.backgroundColor = UIColor.blue.withAlphaComponent(0.3)
                
            default:
                view.layer.borderWidth = 2
                view.layer.borderColor = UIColor.white.cgColor
            }
        }
        
        return view
    }
    
    
    private func addGlassesPlaceholder(to view: UIView) {
        let leftLens = UIView()
        leftLens.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        leftLens.layer.cornerRadius = 8
        leftLens.frame = CGRect(x: 15, y: 30, width: 16, height: 16)
        view.addSubview(leftLens)
        
        let rightLens = UIView()
        rightLens.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        rightLens.layer.cornerRadius = 8
        rightLens.frame = CGRect(x: 49, y: 30, width: 16, height: 16)
        view.addSubview(rightLens)
    }
    
    private func addHatPlaceholder(to view: UIView) {
        let hatTop = UIView()
        hatTop.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        hatTop.layer.cornerRadius = 6
        hatTop.frame = CGRect(x: 30, y: 20, width: 20, height: 20)
        view.addSubview(hatTop)
        
        let hatBrim = UIView()
        hatBrim.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        hatBrim.layer.cornerRadius = 4
        hatBrim.frame = CGRect(x: 20, y: 35, width: 40, height: 8)
        view.addSubview(hatBrim)
    }
    
    private func addHeadphonesPlaceholder(to view: UIView) {
        let leftEar = UIView()
        leftEar.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        leftEar.layer.cornerRadius = 8
        leftEar.frame = CGRect(x: 10, y: 25, width: 16, height: 20)
        view.addSubview(leftEar)
        
        let rightEar = UIView()
        rightEar.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        rightEar.layer.cornerRadius = 8
        rightEar.frame = CGRect(x: 54, y: 25, width: 16, height: 20)
        view.addSubview(rightEar)
    }
    
    private func addLightPlaceholder(to view: UIView) {
        let lightBulb = UIView()
        lightBulb.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        lightBulb.layer.cornerRadius = 12
        lightBulb.frame = CGRect(x: 28, y: 28, width: 24, height: 24)
        view.addSubview(lightBulb)
    }
    
    
    private func startAnimation(_ view: UIView, for animationName: String) {
        // Animate based on animation name or URL content
        if animationName.contains("glasses") {
            animateGlasses(view)
        } else if animationName.contains("hat") {
            animateHat(view)
        } else if animationName.contains("headphones") {
            animateHeadphones(view)
        } else if animationName.contains("light") {
            animateLight(view)
        } else {
            // Handle old animation names
            switch animationName {
            case "center_face":
                animateCenterFace(view)
                
            case "move_closer":
                animateMoveCloser(view)
                
            case "move_away":
                animateMoveAway(view)
                
            case "hold_still":
                animateHoldStill(view)
                
            default:
                animateDefault(view)
            }
        }
    }
    
    private func animateCenterFace(_ view: UIView) {
        UIView.animate(withDuration: 1.0, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        })
    }
    
    private func animateMoveCloser(_ view: UIView) {
        UIView.animate(withDuration: 1.5, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        })
    }
    
    private func animateMoveAway(_ view: UIView) {
        UIView.animate(withDuration: 1.5, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        })
    }
    
    private func animateHoldStill(_ view: UIView) {
        UIView.animate(withDuration: 0.5, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.alpha = 0.5
        })
    }
    
    private func animateDefault(_ view: UIView) {
        UIView.animate(withDuration: 2.0, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.transform = CGAffineTransform(rotationAngle: .pi)
        })
    }
    
    private func animateGlasses(_ view: UIView) {
        UIView.animate(withDuration: 1.0, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        })
    }
    
    private func animateHat(_ view: UIView) {
        UIView.animate(withDuration: 1.2, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.transform = CGAffineTransform(translationX: 0, y: -8)
        })
    }
    
    private func animateHeadphones(_ view: UIView) {
        UIView.animate(withDuration: 0.8, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.transform = CGAffineTransform(rotationAngle: .pi / 12)
        })
    }
    
    private func animateLight(_ view: UIView) {
        UIView.animate(withDuration: 0.6, delay: 0, options: [.repeat, .autoreverse], animations: {
            view.alpha = 0.4
        })
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
    
    
    @objc private func helpButtonTapped() {
        // Delegate back to the main controller
        delegate?.instructionViewHelpButtonTapped(self)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Always allow touches on help button
        if let hitView = helpButton.hitTest(convert(point, to: helpButton), with: event) {
            return hitView
        }
        
        // For instruction content, only allow touches when background and content are visible
        if !backgroundView.isHidden && backgroundView.alpha > 0.0 && !contentView.isHidden && contentView.alpha > 0.0 {
            return super.hitTest(point, with: event)
        }
        
        // If instructions are hidden, don't intercept touches (let them pass through)
        return nil
    }
    
    deinit {
        stopCurrentTimer()
    }
    
    // MARK: - Button Visual Effects
    
    @objc private func buttonTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            sender.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }
    
    @objc private func buttonTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
            sender.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            sender.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
            sender.transform = .identity
        })
    }
    
    private func forceResetSegmentProgress(stepIndex: Int) {
        guard stepIndex < segmentFills.count && stepIndex < progressSegments.count else { return }
        
        let fill = segmentFills[stepIndex]
        let segment = progressSegments[stepIndex]
        
        // Remove ALL existing width constraints immediately
        fill.removeFromSuperview()
        segment.addSubview(fill)
        
        // Set up fresh constraints for 0% progress
        fill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fill.topAnchor.constraint(equalTo: segment.topAnchor),
            fill.leadingAnchor.constraint(equalTo: segment.leadingAnchor),
            fill.bottomAnchor.constraint(equalTo: segment.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: 0) // 0% width
        ])
        
        // Reset segment background to inactive state
        segment.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        
        // Force immediate layout update
        segment.setNeedsLayout()
        segment.layoutIfNeeded()
    }
    
    private func forceCompleteSegmentProgress(stepIndex: Int) {
        guard stepIndex < segmentFills.count && stepIndex < progressSegments.count else { return }
        
        let fill = segmentFills[stepIndex]
        let segment = progressSegments[stepIndex]
        
        // Remove existing width constraints
        fill.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }
        
        // Set to 100% width immediately
        let widthConstraint = fill.widthAnchor.constraint(equalTo: segment.widthAnchor, multiplier: 1.0)
        widthConstraint.isActive = true
        
        // Update segment background to active/completed state
        segment.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        
        // Force immediate layout update (no animation)
        segment.setNeedsLayout()
        segment.layoutIfNeeded()
        
        print("✅ [JAAKInstructionView] Segment \(stepIndex) forced to 100%")
    }
}

// MARK: - JAAKInstructionViewDelegate

protocol JAAKInstructionViewDelegate: AnyObject {
    func instructionView(_ instructionView: JAAKInstructionView, didComplete completed: Bool)
    func instructionViewHelpButtonTapped(_ instructionView: JAAKInstructionView)
    func instructionView(_ instructionView: JAAKInstructionView, willStartInstructions isStarting: Bool)
}