Pod::Spec.new do |s|
  s.name           = 'ReproAudio'
  s.version        = '1.0.0'
  s.summary        = 'Plain AVFoundation control for the expo-audio session repro'
  s.author         = ''
  s.homepage       = 'https://example.invalid'
  s.platforms      = { :ios => '16.4' }
  s.source         = { git: '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.source_files = '**/*.{h,m,swift}'
end
