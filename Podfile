# Uncomment the next line to define a global platform for your project
platform :ios, '13.0'
source "https://gitlab.linphone.org/BC/public/podspec.git"
source "https://github.com/CocoaPods/Specs.git"

def all_pods
	if ENV['PODFILE_PATH'].nil?
		pod 'linphone-sdk', '~>5.3.20'
	else
		pod 'linphone-sdk', :path => ENV['PODFILE_PATH']  # local sdk
	end

	crashlytics
end

def crashlytics
	if not ENV['USE_CRASHLYTICS'].nil?
		pod 'Firebase/Analytics'
		pod 'Firebase/Crashlytics'
	end
end

target 'bcsphone' do
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  use_frameworks!

  # Pods for linphone
	pod 'SVProgressHUD'
	pod 'SnapKit', '~> 5.7'
	pod 'DropDown'
	pod 'IQKeyboardManager', '~> 6.0'
	pod 'SwipeCellKit'
		#License: https://github.com/SwipeCellKit/SwipeCellKit/blob/develop/LICENSE
	pod 'EmojiPicker', :git => 'https://github.com/htmlprogrammist/EmojiPicker'
		#License: https://github.com/htmlprogrammist/EmojiPicker/blob/main/LICENSE
	all_pods

end

target 'msgNotificationService' do
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  use_frameworks!

  # Pods for messagesNotification
  all_pods

end

target 'msgNotificationContent' do
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  use_frameworks!

  # Pods for messagesNotification
  all_pods

end

#target 'LocalPushProvider' do
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  #use_frameworks!

  # Pods for CallUITests
  #all_pods

#end

post_install do |installer|
        system("sed 's/fileprivate let tableView =/public let tableView =/g' ./Pods/DropDown/DropDown/src/DropDown.swift > tmp.swift && mv -f tmp.swift ./Pods/DropDown/DropDown/src/DropDown.swift")
	# Get the version of linphone-sdk
	installer.pod_targets.each do |target|
		if target.pod_name == 'linphone-sdk'
			target.specs.each do |spec|
				$linphone_sdk_version = spec.version
			end
		end
	end
			
  # Forza la disattivazione del Bitcode su tutti i target dei Pods
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
      
	app_project = Xcodeproj::Project.open(Dir.glob("*.xcodeproj")[0])
	app_project.native_targets.each do |target|
		target.build_configurations.each do |config|
			if target.name == "bcsphone" || target.name == 'msgNotificationService' || target.name == 'msgNotificationContent'
				if ENV['USE_CRASHLYTICS'].nil?
					if config.name == "Debug" then
						config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = '$(inherited) DEBUG=1'
						else
						config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = '$(inherited)'
					end
					config.build_settings['OTHER_SWIFT_FLAGS'] = '$(inherited)'
				else
					# activate crashlytics
					if config.name == "Debug" then
						config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = '$(inherited) DEBUG=1 USE_CRASHLYTICS=1'
					else
						config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = '$(inherited) USE_CRASHLYTICS=1'
					end
					config.build_settings['OTHER_SWIFT_FLAGS'] = '$(inherited) -DUSE_CRASHLYTICS'
				end
			end

			if target.name == "bcsphone"
				config.build_settings['OTHER_CFLAGS'] = '-DBCTBX_LOG_DOMAIN=\"ios\"',
																							'-DCHECK_VERSION_UPDATE=FALSE',
																							'-DENABLE_QRCODE=TRUE',
																							'-DENABLE_SMS_INVITE=TRUE',
																							'$(inherited)',
																							"-DLINPHONE_SDK_VERSION=\\\"#{$linphone_sdk_version}\\\""
			end

			app_project.save
		end
	end
	
	installer.pods_project.targets.each do |target| 
		target.build_configurations.each do |config| 
			config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
		end
	end
  
  bitcode_strip_path = `xcrun --find bitcode_strip`.chop!
    def strip_bitcode_from_framework(bitcode_strip_path, framework_relative_path)
      command = "#{bitcode_strip_path} #{framework_relative_path} -r -o #{framework_relative_path}"
      puts "Stripping bitcode: #{command}"
      system(command)
    end

  framework_paths = [
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/bctoolbox-ios.xcframework/ios-arm64/bctoolbox-ios.framework/bctoolbox-ios",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/bctoolbox-tester.xcframework/ios-arm64/bctoolbox-tester.framework/bctoolbox-tester",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/bctoolbox.xcframework/ios-arm64/bctoolbox.framework/bctoolbox",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/belcard.xcframework/ios-arm64/belcard.framework/belcard",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/belle-sip.xcframework/ios-arm64/belle-sip.framework/belle-sip",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/belr.xcframework/ios-arm64/belr.framework/belr",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/lime.xcframework/ios-arm64/lime.framework/lime",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/limetester.xcframework/ios-arm64/limetester.framework/limetester",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/linphone.xcframework/ios-arm64/linphone.framework/linphone",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/linphonetester.xcframework/ios-arm64/linphonetester.framework/linphonetester",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/mediastreamer2.xcframework/ios-arm64/mediastreamer2.framework/mediastreamer2",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/msamr.xcframework/ios-arm64/msamr.framework/msamr",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/mscodec2.xcframework/ios-arm64/mscodec2.framework/mscodec2",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/msopenh264.xcframework/ios-arm64/msopenh264.framework/msopenh264",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/mssilk.xcframework/ios-arm64/mssilk.framework/mssilk",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/mswebrtc.xcframework/ios-arm64/mswebrtc.framework/mswebrtc",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/ortp.xcframework/ios-arm64/ortp.framework/ortp",
      "/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/linphone-sdk/apple-darwin/XCFrameworks/ZXing.xcframework/ios-arm64/ZXing.framework/ZXing",
    ]

    framework_paths.each do |framework_relative_path|
      strip_bitcode_from_framework(bitcode_strip_path, framework_relative_path)
    end
  
end

