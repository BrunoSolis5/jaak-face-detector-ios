Pod::Spec.new do |spec|
  spec.name          = "JAAKVisage"
  spec.version       = "1.0.0"
  spec.summary       = "AI-powered face detection and recording library for iOS using MediaPipe BlazeFace"
  spec.description   = <<-DESC
                       JAAKVisage is an advanced face detection library that provides:
                       - Real-time face detection using MediaPipe BlazeFace
                       - Auto-recording with quality analysis
                       - Face quality metrics and validation
                       - Security monitoring and device validation
                       - Customizable UI overlays and instructions
                       - Video recording
                       DESC

  spec.homepage      = "https://github.com/BrunoSolis5/jaak-face-detector-ios"
  spec.license       = { :type => "MIT", :file => "LICENSE" }
  spec.author        = { "Diego Bruno" => "diego.bruno@jaak.ai" }
  
  spec.platform      = :ios, "12.0"
  spec.swift_version = "5.0"
  
  spec.source        = { :http => "https://github.com/BrunoSolis5/jaak-face-detector-ios/releases/download/v#{spec.version}/JAAKVisage-#{spec.version}.zip" }
  
  spec.source_files  = "JAAKVisage/**/*.swift"
  spec.exclude_files = "JAAKVisage/Info.plist"
  
  spec.resource_bundles = {
    'JAAKVisage' => ['JAAKVisage/Resources/**/*']
  }
  
  spec.frameworks = 'UIKit', 'AVFoundation', 'Vision', 'CoreML'
  
  # MediaPipe dependency
  spec.dependency 'MediaPipeTasksVision', '~> 0.10.3'
  
  # Build settings
  spec.requires_arc = true
  spec.static_framework = true
  
  spec.pod_target_xcconfig = {
    'SWIFT_VERSION' => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => '12.0',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  
  spec.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end