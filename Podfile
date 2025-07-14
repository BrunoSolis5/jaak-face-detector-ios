# Podfile para JAAKFaceDetector
platform :ios, '12.0'
use_frameworks!

target 'JAAKFaceDetector' do
  # MediaPipe Tasks Vision for face detection
  pod 'MediaPipeTasksVision'
  
  
  # Testing target
  target 'JAAKFaceDetectorTests' do
    inherit! :search_paths
  end
end

# Post install configurations
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
      config.build_settings['SWIFT_VERSION'] = '5.0'
    end
  end
end