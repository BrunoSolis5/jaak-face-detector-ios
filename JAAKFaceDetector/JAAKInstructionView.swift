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
    private let instructionLabel = UILabel()
    private let animationContainerView = UIView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let helpButton = UIButton()
    
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
        
        // Notify delegate that instructions are starting (to pause detection)
        delegate?.instructionView(self, willStartInstructions: true)
        
        // Show the backdrop and instruction content
        backdropView.isHidden = false
        backdropView.alpha = 0.0
        
        backgroundView.isHidden = false
        backgroundView.alpha = 0.0
        backgroundView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        contentView.isHidden = false
        contentView.alpha = 0.0
        contentView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
            self.backdropView.alpha = 1.0
            self.backgroundView.alpha = 1.0
            self.backgroundView.transform = .identity
            self.contentView.alpha = 1.0
            self.contentView.transform = .identity
        }) { _ in
            self.startInstructionSequence()
        }
    }
    
    /// Hide instructions
    func hideInstructions() {
        currentState = .hidden
        stopCurrentTimer()
        
        UIView.animate(withDuration: 0.3) {
            self.backdropView.alpha = 0.0
            self.backgroundView.alpha = 0.0
            self.backgroundView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            self.contentView.alpha = 0.0
            self.contentView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.backdropView.isHidden = true
            self.backgroundView.isHidden = true
            self.contentView.isHidden = true
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
        // Backdrop - full screen dark overlay
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        addSubview(backdropView)
        
        // Background
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        backgroundView.layer.cornerRadius = 16
        addSubview(backgroundView)
        
        // Content container
        contentView.backgroundColor = .clear
        addSubview(contentView)
        
        // Instruction label
        instructionLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        contentView.addSubview(instructionLabel)
        
        // Animation container
        animationContainerView.backgroundColor = .clear
        contentView.addSubview(animationContainerView)
        
        // Progress view
        progressView.progressTintColor = .white
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        progressView.progress = 0.0
        contentView.addSubview(progressView)
        
        // Help button (?) - positioned at top-left of the main view
        helpButton.setTitle("?", for: .normal)
        helpButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        helpButton.setTitleColor(.white, for: .normal)
        helpButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        helpButton.layer.cornerRadius = 16
        helpButton.clipsToBounds = true
        helpButton.addTarget(self, action: #selector(helpButtonTapped), for: .touchUpInside)
        addSubview(helpButton) // Add to main view, not contentView
        
        // Layout
        setupLayout()
        
        // Initial state - view is always visible for help button, but content is hidden
        isHidden = false
        alpha = 1.0
        isUserInteractionEnabled = true
        
        // Hide the instruction content and backdrop initially
        backdropView.isHidden = true
        backdropView.alpha = 0.0
        backgroundView.isHidden = true
        backgroundView.alpha = 0.0
        contentView.isHidden = true
        contentView.alpha = 0.0
    }
    
    private func setupLayout() {
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Backdrop - full screen overlay
            backdropView.topAnchor.constraint(equalTo: topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Background - centered both horizontally and vertically, width adjusts to content
            backgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: centerYAnchor),
            backgroundView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            backgroundView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            backgroundView.heightAnchor.constraint(lessThanOrEqualToConstant: 150),
            backgroundView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            
            // Content - positioned relative to background with generous padding
            contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 20),
            contentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 24),
            contentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -24),
            contentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -20),
            
            // Animation container
            animationContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            animationContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            animationContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            animationContainerView.heightAnchor.constraint(equalToConstant: 60),
            
            // Instruction label
            instructionLabel.topAnchor.constraint(equalTo: animationContainerView.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Progress view
            progressView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Help button (?) - positioned at top-left of the full screen
            helpButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            helpButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            helpButton.widthAnchor.constraint(equalToConstant: 32),
            helpButton.heightAnchor.constraint(equalToConstant: 32)
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
            "Remove glasses for better detection",
            "Remove hat or cap",
            "Remove headphones or earbuds", 
            "Ensure good lighting on your face"
        ]
    }
    
    private func getDefaultAnimations() -> [String] {
        return [
            "https://raw.githubusercontent.com/jaak-ai/jaak-storage/main/animations/rive/glasses.riv",
            "https://raw.githubusercontent.com/jaak-ai/jaak-storage/main/animations/rive/hat.riv",
            "https://raw.githubusercontent.com/jaak-ai/jaak-storage/main/animations/rive/headphones.riv",
            "https://raw.githubusercontent.com/jaak-ai/jaak-storage/main/animations/rive/light.riv"
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
            // Show next step immediately without delay
            showCurrentStep()
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
    
    private func stopCurrentTimer() {
        stepTimer?.invalidate()
        stepTimer = nil
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
}

// MARK: - JAAKInstructionViewDelegate

protocol JAAKInstructionViewDelegate: AnyObject {
    func instructionView(_ instructionView: JAAKInstructionView, didComplete completed: Bool)
    func instructionViewHelpButtonTapped(_ instructionView: JAAKInstructionView)
    func instructionView(_ instructionView: JAAKInstructionView, willStartInstructions isStarting: Bool)
}