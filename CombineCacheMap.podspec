Pod::Spec.new do |s|
  s.name             = 'CombineCacheMap'
  s.version          = '0.4.0'
  s.summary          = 'A collection of caching Combine operators.'
  s.description      = 'Cache/memoize the output of Combine.Publishers using cacheMap, cacheFlatMap and more.'
  s.homepage         = 'https://github.com/briansemiglia/combinecachemap'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Brian Semiglia' => 'brian.semiglia@gmail.com' }
  s.source           = {
      :git => 'https://github.com/briansemiglia/combinecachemap.git',
      :tag => s.version.to_s
  }
  s.social_media_url = 'https://twitter.com/brians_'
  s.ios.deployment_target = '13.0'
  s.macos.deployment_target = '10.15'
  s.source_files = 'Sources/CombineCacheMap/**/*.swift'
  s.swift_version = '5.9'
  s.dependency 'CombineExt', '~> 1.0.0'
end
