Pod::Spec.new do |s|
  s.name             = 'yl_player'
  s.version          = '2.0.0'
  s.summary          = 'Cross-platform video player plugin (yl_player).'
  s.description      = 'AVPlayer + VideoToolbox + FFmpeg bridge for video playback.'
  s.homepage         = 'https://github.com/yuluoos/TVBox-tvs'
  s.license          = { :type => 'MIT' }
  s.author           = { 'TVS' => 'tvs@example.com' }
  s.source           = { :git => 'https://github.com/yuluoos/TVBox-tvs.git', :tag => s.version.to_s }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'Flutter'

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '11.0'

  s.swift_version = '5.0'
end
