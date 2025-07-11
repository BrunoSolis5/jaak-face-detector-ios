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
        let delay: TimeInterval
        
        init(text: String, animation: String? = nil, duration: TimeInterval = 3.0, delay: TimeInterval = 0.5) {
            self.text = text
            self.animation = animation
            self.duration = duration
            self.delay = delay
        }
    }
    
    // MARK: - Properties
    
    private let configuration: JAAKFaceDetectorConfiguration
    private var currentState: InstructionState = .hidden
    private var instructionSteps: [InstructionStep] = []
    private var currentStepIndex: Int = 0
    
    // UI Components
    private let backgroundView = UIView()
    private let contentView = UIView()
    private let instructionLabel = UILabel()
    private let animationContainerView = UIView()
    private let replayButton = UIButton()
    private let skipButton = UIButton()
    private let progressView = UIProgressView()
    
    // Animation
    private var currentAnimationView: UIView?
    private var stepTimer: Timer?
    
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
        
        currentState = .showing
        currentStepIndex = 0
        isHidden = false
        
        // Animate in
        alpha = 0.0
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
            self.alpha = 1.0
            self.transform = .identity
        }) { _ in
            self.startInstructionSequence()
        }
    }
    
    /// Hide instructions
    func hideInstructions() {
        currentState = .hidden
        stopCurrentTimer()
        
        UIView.animate(withDuration: 0.3) {
            self.alpha = 0.0
            self.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.isHidden = true
            self.delegate?.instructionView(self, didComplete: false)
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
        progressView.setProgress(progress, animated: true)
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
        // Background
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        backgroundView.layer.cornerRadius = 16
        addSubview(backgroundView)
        
        // Content container
        contentView.backgroundColor = .clear
        addSubview(contentView)
        
        // Instruction label
        instructionLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        contentView.addSubview(instructionLabel)
        
        // Animation container
        animationContainerView.backgroundColor = .clear
        contentView.addSubview(animationContainerView)
        
        // Replay button
        replayButton.setTitle(configuration.instructionsButtonText, for: .normal)
        replayButton.setTitleColor(.white, for: .normal)
        replayButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        replayButton.layer.cornerRadius = 8
        replayButton.addTarget(self, action: #selector(replayButtonTapped), for: .touchUpInside)
        contentView.addSubview(replayButton)
        
        // Skip button
        skipButton.setTitle("Skip", for: .normal)
        skipButton.setTitleColor(.white, for: .normal)
        skipButton.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        skipButton.layer.cornerRadius = 8
        skipButton.addTarget(self, action: #selector(skipButtonTapped), for: .touchUpInside)
        contentView.addSubview(skipButton)
        
        // Progress view
        progressView.progressTintColor = .white
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        contentView.addSubview(progressView)
        
        // Layout
        setupLayout()
        
        // Initial state
        isHidden = true
        alpha = 0.0
    }
    
    private func setupLayout() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.translatesAutoresizingMaskIntoConstraints = false
        replayButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Background
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Content
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            
            // Animation container
            animationContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            animationContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            animationContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            animationContainerView.heightAnchor.constraint(equalToConstant: 120),
            
            // Instruction label
            instructionLabel.topAnchor.constraint(equalTo: animationContainerView.bottomAnchor, constant: 20),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Progress view
            progressView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 20),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            
            // Buttons
            replayButton.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 20),
            replayButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            replayButton.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.45),
            replayButton.heightAnchor.constraint(equalToConstant: 44),
            replayButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            skipButton.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 20),
            skipButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            skipButton.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.45),
            skipButton.heightAnchor.constraint(equalToConstant: 44),
            skipButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    private func setupInstructionSteps() {
        guard configuration.enableInstructions else { return }
        
        // Use configured instructions if available, otherwise use defaults
        let instructionTexts = configuration.instructionsText.isEmpty ? getDefaultInstructions() : configuration.instructionsText
        let instructionAnimations = configuration.instructionsAnimations
        
        instructionSteps = instructionTexts.enumerated().map { index, text in
            let animation = index < instructionAnimations.count ? instructionAnimations[index] : nil
            return InstructionStep(
                text: text,
                animation: animation,
                duration: configuration.instructionDelay,
                delay: configuration.instructionReplayDelay
            )
        }
    }
    
    private func getDefaultInstructions() -> [String] {
        return [
            "Welcome to face detection",
            "Position your face in the center of the screen",
            "Make sure your face is clearly visible",
            "Stay still while we detect your face",
            "Great! You're ready to start"
        ]
    }
    
    private func startInstructionSequence() {
        currentStepIndex = 0
        showCurrentStep()
    }
    
    private func showCurrentStep() {
        guard currentStepIndex < instructionSteps.count else {
            completeInstructions()
            return
        }
        
        currentState = .animating
        let step = instructionSteps[currentStepIndex]
        
        // Update text
        instructionLabel.text = step.text
        
        // Update progress
        let progress = Float(currentStepIndex + 1) / Float(instructionSteps.count)
        updateProgress(progress)
        
        // Show animation if available
        if let animationName = step.animation {
            showAnimation(animationName)
        }
        
        // Start timer for next step
        stepTimer = Timer.scheduledTimer(withTimeInterval: step.duration, repeats: false) { [weak self] _ in
            self?.moveToNextStep()
        }
    }
    
    private func moveToNextStep() {
        currentStepIndex += 1
        
        if currentStepIndex < instructionSteps.count {
            // Show next step after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + instructionSteps[currentStepIndex - 1].delay) {
                self.showCurrentStep()
            }
        } else {
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
        // Remove previous animation
        currentAnimationView?.removeFromSuperview()
        
        // Create animation view based on name
        let animationView = createAnimationView(for: animationName)
        animationContainerView.addSubview(animationView)
        currentAnimationView = animationView
        
        // Layout animation view
        animationView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            animationView.centerXAnchor.constraint(equalTo: animationContainerView.centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: animationContainerView.centerYAnchor),
            animationView.widthAnchor.constraint(equalToConstant: 80),
            animationView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        // Start animation
        startAnimation(animationView, for: animationName)
    }
    
    private func createAnimationView(for animationName: String) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        view.layer.cornerRadius = 40
        
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
            break
        }
        
        return view
    }
    
    private func startAnimation(_ view: UIView, for animationName: String) {
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
    
    private func stopCurrentTimer() {
        stepTimer?.invalidate()
        stepTimer = nil
    }
    
    @objc private func replayButtonTapped() {
        replayCurrentInstruction()
    }
    
    @objc private func skipButtonTapped() {
        skipCurrentInstruction()
    }
    
    deinit {
        stopCurrentTimer()
    }
}

// MARK: - JAAKInstructionViewDelegate

protocol JAAKInstructionViewDelegate: AnyObject {
    func instructionView(_ instructionView: JAAKInstructionView, didComplete completed: Bool)
}