## (Dario Santomaso) Compiling custom BCS version:
Before compiling, install GitHub Desktop if needed (it will help in managing the repository instead of using the command line Git). 
Clone the linphone-sdk repository (git clone https://gitlab.linphone.org/BC/public/linphone-sdk --recursive).
Then, clone the custom belle-sip and liblinphone repositories somewhere. Checkout the branch alceo/tag/5.3.56. Delete the old belle-sip and liblinphone directories from the linphone-sdk folder, and copy the patched ones you just cloned.

	1. cmake --preset=ios-sdk -G Ninja -B build-ios -DENABLE_LIME_X3DH=OFF -DENABLE_LIME=OFF -DENABLE_ADVANCED_IM=OFF -DENABLE_VCARD=OFF -DENABLE_LDAP=OFF -DENABLE_ISAC=OFF -DENABLE_ILBC=OFF -DENABLE_SRTP=OFF -DENABLE_ZRTP=OFF
 	2. cmake --build build-ios
	3. Clone https://github.com/ALCEO-srl/linphone-iphone and checkout alceo/tag/5.2.2 branch
	4. Then "cd linphone-iphone" and give the comand PODFILE_PATH=[PATH_TO_SDK] pod install  (PODFILE_PATH is something like ...linphone-sdk/build-ios)
	5. open linphone.xcworkspace with Xcode to build and run the app.
