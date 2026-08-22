#
# Shared iOS/macOS pod for the Local Network privacy probe.
# Run `pod lib lint local_network_permission.podspec` to validate.
#
Pod::Spec.new do |s|
  s.name             = 'local_network_permission'
  s.version          = '1.0.0'
  s.summary          = "Probes Apple's Local Network privacy permission."
  s.description      = <<-DESC
Apple ships no authorization-status API for the Local Network permission, so
this plugin infers it from an NWListener/NWBrowser Bonjour round trip.
                       DESC
  s.homepage         = 'https://bikecontrol.app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'BikeControl' => 'jonas@bikecontrol.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.ios.dependency 'Flutter'
  s.ios.deployment_target = '15.0'

  s.osx.dependency 'FlutterMacOS'
  s.osx.deployment_target = '12.0'
end
