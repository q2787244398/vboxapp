Pod::Spec.new do |s|
  s.name             = 'node_bridge'
  s.version          = '1.0.0'
  s.summary          = 'Embedded Node.js runtime bridge for TVS'
  s.description      = <<-DESC
Wraps the nodejs-mobile NodeMobile.xcframework behind the
com.example.tvs/node_bridge method channel.
DESC
  s.homepage         = 'https://github.com/q2787244398/vboxapp'
  s.license          = { :type => 'MIT' }
  s.author           = { 'TVS' => 'tvs@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.dependency 'Flutter'

  # nodejs-mobile 的运行时（由 _scripts/fetch_node_runtime.sh 下载到 Frameworks/，
  # 目录已加入 .gitignore —— device 切片 52MB + simulator 切片 115MB，不适合入库）。
  s.vendored_frameworks = 'Frameworks/NodeMobile.xcframework'
  s.preserve_paths      = 'Frameworks/**'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }
end
