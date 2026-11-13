# Switches the Runner target to manual signing for one App Store build,
# on the CI runner only: the committed project stays unsigned, so that
# anyone can build it without an Apple account.
#
# Only Runner's Release configuration changes. The same settings passed
# on the xcodebuild command line would reach the CocoaPods targets too,
# which refuse a provisioning profile.
#
#   ruby .github/ios-signing.rb <ios/Runner.xcodeproj> <team id> <profile name>
#
# xcodeproj is the gem CocoaPods is built on; the macOS runner has it.
require 'xcodeproj'

project_path, team, profile = ARGV
abort 'usage: ios-signing.rb <project> <team id> <profile name>' unless profile

project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'no Runner target' unless runner

release = runner.build_configurations.find { |config| config.name == 'Release' }
abort 'no Release configuration in Runner' unless release

release.build_settings.merge!(
  'CODE_SIGN_STYLE' => 'Manual',
  'DEVELOPMENT_TEAM' => team,
  'CODE_SIGN_IDENTITY' => 'Apple Distribution',
  'CODE_SIGN_IDENTITY[sdk=iphoneos*]' => 'Apple Distribution',
  'PROVISIONING_PROFILE_SPECIFIER' => profile
)
project.save
puts "Runner/Release: manual signing, team #{team}, profile #{profile}"
