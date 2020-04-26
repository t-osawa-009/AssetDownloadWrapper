Pod::Spec.new do |spec|
  spec.name         = "AssetDownloadWrapper"
  spec.version      = "0.0.2"
  spec.summary      = "iOS AVAssetDownloadURLSession Wrapper"
  spec.homepage     = "https://github.com/t-osawa-009/AssetDownloadWrapper"
  spec.license      = "MIT"
  spec.author             = { "t-osawa-009" => "da87435@gmail.com" }
  spec.ios.deployment_target = "11.0"
  spec.source       = { :git => "https://github.com/t-osawa-009/AssetDownloadWrapper.git", :tag => "#{spec.version}" }
  spec.source_files = "Sources/**/*.{swift}"
  spec.requires_arc = true
  spec.swift_version = "5.0"
end
