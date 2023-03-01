//
//  ChatConversationViewModelSwift.swift
//  linphone
//
//  Created by Benoît Martins on 23/11/2022.
//

import UIKit
import Foundation
import linphonesw


class ChatConversationViewModel: ControlsViewModel {
	
	static let sharedModel = ChatConversationViewModel()
	
	let APP_GROUP_ID = "group.belledonne-communications.linphone.widget"

	var chatRoom: ChatRoom? = nil
	var chatRoomDelegate: ChatRoomDelegate? = nil
	
	var mediaCount : Int = 0
	var newMediaCount : Int = 0
	var unread_msg : Int32 = 0
	
	var address: String? = nil
	var participants: String? = nil
	var subject: String? = nil
	var shareFileMessage: String? = nil
	
	var debugEnabled = false
	var isVoiceRecording = false
	var showVoiceRecorderView = false
	var isPendingVoiceRecord = false
	var isPlayingVoiceRecording = false
	var isOneToOneChat = false
	
	var urlFile : [URL?] = []
	var mediaURLCollection : [URL] = []
	var replyURLCollection : [URL] = []
	
	var data : [Data?] = []
	var fileContext : [Data] = []
	
	var progress : [Progress] = []
	var workItem : DispatchWorkItem? = nil
	
	var replyMessage : OpaquePointer? = nil
	
	var vrRecordTimer = Timer()
	var vrPlayerTimer = Timer()
	
	var voiceRecorder : Recorder? = nil
	
	var secureLevel : UIImage?
	var imageT : [UIImage?] = []
	var mediaCollectionView : [UIImage] = []
	var replyCollectionView : [UIImage] = []
	
	var isComposing = MutableLiveData<Bool>(false)
	var messageReceived = MutableLiveData<EventLog>()
	var stateChanged = MutableLiveData<ChatRoom>()
	var secureLevelChanged = MutableLiveData<EventLog>()
	var subjectChanged = MutableLiveData<EventLog>()
	var eventLog = MutableLiveData<EventLog>()
	var indexPathVM = MutableLiveData<Int>()
	var shareFileURL = MutableLiveData<String>()
	var shareFileName = MutableLiveData<String>()
	
	override init() {
		super.init()
	}
	
	func resetViewModel(){
		chatRoom?.removeDelegate(delegate: chatRoomDelegate!)
		mediaURLCollection = []
		replyURLCollection.removeAll()
		fileContext = []
		urlFile = []
		data = []
		workItem?.cancel()
		for progressItem in progress{
			progressItem.cancel()
		}
		progress.removeAll()
	}
	
	func createChatConversation(){
		chatRoomDelegate = ChatRoomDelegateStub(
			onIsComposingReceived: { (room: ChatRoom, remoteAddress: Address, isComposing: Bool) -> Void in
				self.on_chat_room_is_composing_received(room, remoteAddress, isComposing)
			}, onChatMessageReceived: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_chat_message_received(room, event)
			}, onChatMessageSending: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_event_log(room, event)
			}, onParticipantAdded: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_secure_level(room, event)
			}, onParticipantRemoved: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_secure_level(room, event)
			}, onParticipantAdminStatusChanged: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_event_log(room, event)
			}, onStateChanged: { (room: ChatRoom, state: ChatRoom.State) -> Void in
				self.on_chat_room_state_changed(room)
			}, onSecurityEvent: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_secure_level(room, event)
			}, onSubjectChanged: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_subject_changed(room, event)
			}, onConferenceJoined: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_event_log(room, event)
			}, onConferenceLeft: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_event_log(room, event)
			}
		)
		chatRoom?.addDelegate(delegate: chatRoomDelegate!)
		
		workItem = DispatchWorkItem {
			let indexPath = IndexPath(row: self.mediaCollectionView.count, section: 0)
			self.mediaURLCollection.append(self.urlFile[indexPath.row]!)
			self.mediaCollectionView.append(self.imageT[indexPath.row]!)
			
			self.fileContext.append(self.data[indexPath.row]!)
			if(self.mediaCount + self.newMediaCount <= indexPath.row+1){
				self.indexPathVM.value = indexPath.row
			}
		}
	}
	
	func on_chat_room_is_composing_received(_ cr: ChatRoom?, _ remoteAddr: Address?, _ isComposingBool: Bool) {
		isComposing.value = (linphone_chat_room_is_remote_composing(cr?.getCobject) != 0) || bctbx_list_size(linphone_chat_room_get_composing_addresses(cr?.getCobject)) > 0
	}

	func on_chat_room_chat_message_received(_ cr: ChatRoom?, _ event_log: EventLog?) {
		let chat = event_log?.chatMessage
		if chat == nil {
			return
		}
		
		var hasFile = false
		// if auto_download is available and file is downloaded
		if (linphone_core_get_max_size_for_auto_download_incoming_files(LinphoneManager.getLc()) > -1) && (chat?.fileTransferInformation != nil) {
			hasFile = true
		}
		
		var returnValue = false;
		chat?.contents.forEach({ content in
			if !content.isFileTransfer && !content.isText && !content.isVoiceRecording && !hasFile {
				returnValue = true
			}
		})
		
		if returnValue {
			return
		}
		
		let from = chat?.fromAddress
		if from == nil {
			return
		}
		
		messageReceived.value = event_log
		unread_msg = linphone_chat_room_get_unread_messages_count(cr?.getCobject)
	}
	
	func on_chat_room_state_changed(_ cr: ChatRoom?) {
		isOneToOneChat = chatRoom!.hasCapability(mask: Int(LinphoneChatRoomCapabilitiesOneToOne.rawValue))
		secureLevel = FastAddressBook.image(for: linphone_chat_room_get_security_level(cr?.getCobject))
		stateChanged.value = cr
	}
	
	func on_chat_room_subject_changed(_ cr: ChatRoom?, _ event_log: EventLog?) {
		subject = event_log?.subject != nil ? event_log?.subject : cr?.subject
		subjectChanged.value = event_log
	}
	
	func on_chat_room_secure_level(_ cr: ChatRoom?, _ event_log: EventLog?) {
		secureLevel = FastAddressBook.image(for: linphone_chat_room_get_security_level(cr?.getCobject))
		secureLevelChanged.value = event_log
	}
	
	func on_chat_room_event_log(_ cr: ChatRoom?, _ event_log: EventLog?) {
		eventLog.value = event_log
	}
	
	func nsDataRead() -> Data? {
		let groupName = "group.\(Bundle.main.bundleIdentifier ?? "").linphoneExtension"
		let path = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)?.path
		let fullCacheFilePathPath = "\(path ?? "")/\("nsData")"
		return NSData(contentsOfFile: fullCacheFilePathPath) as Data?
	}
	
	func sendMessage(message: String?, withExterlBodyUrl externalUrl: URL?, rootMessage: ChatMessage?) -> Bool {
		if chatRoom == nil {
			return false
		}
		
		let msg = rootMessage
		let basic = isBasicChatRoom(chatRoom?.getCobject)
		let params = linphone_account_get_params(linphone_core_get_default_account(LinphoneManager.getLc()))
		let cpimEnabled = linphone_account_params_cpim_in_basic_chat_room_enabled(params)
		
		if (!basic || (cpimEnabled != 0)) && (message != nil) && message!.count > 0 {
			linphone_chat_message_add_utf8_text_content(msg?.getCobject, message)
		}
		
		if (externalUrl != nil) {
			linphone_chat_message_set_external_body_url(msg?.getCobject, externalUrl!.absoluteString)
		}
		
		let contentList = linphone_chat_message_get_contents(msg?.getCobject)
		if bctbx_list_size(contentList) > 0 {
			linphone_chat_message_send(msg?.getCobject)
		}
		
		if basic && (cpimEnabled == 0) && (message != nil) && message!.count > 0 {
			linphone_chat_message_send(linphone_chat_room_create_message_from_utf8(chatRoom?.getCobject, message))
		}
		
		return true
	}
	
	func isBasicChatRoom(_ room: OpaquePointer?) -> Bool {
		if room == nil {
			return true
		}
		
		let charRoomBasic = ChatRoom.getSwiftObject(cObject: room!)
		let isBasic = charRoomBasic.hasCapability(mask: Int(LinphoneChatRoomCapabilitiesBasic.rawValue))
		return isBasic
	}
	
	func startUploadData(_ data: Data?, withType type: String?, withName name: String?, andMessage message: String?, rootMessage: ChatMessage?){
		let fileTransfer = FileTransferDelegate.init()
		if let message {
			fileTransfer.text = message
		}
		var resultType = "file"
		var key = "localfile"
		if type == "file_video_default" {
			resultType = "video"
			key = "localvideo"
		} else if type == "file_picture_default" {
			resultType = "image"
			key = "localimage"
		}
		fileTransfer.uploadData(data, for: chatRoom?.getCobject, type: resultType, subtype: resultType, name: name, key: key, rootMessage: rootMessage?.getCobject)
	}
	
	func startFileUpload(_ data: Data?, withName name: String?, rootMessage: ChatMessage?){
		let fileTransfer = FileTransferDelegate()
		fileTransfer.uploadFile(data, for: ChatConversationViewModel.sharedModel.chatRoom?.getCobject, withName: name, rootMessage: rootMessage?.getCobject)
	}
	
	func shareFile() {
		let groupName = "group.\(Bundle.main.bundleIdentifier ?? "").linphoneExtension"
		let defaults = UserDefaults(suiteName: groupName)
		let dict = defaults?.value(forKey: "photoData") as? [AnyHashable : Any]
		let dictFile = defaults?.value(forKey: "icloudData") as? [AnyHashable : Any]
		let dictUrl = defaults?.value(forKey: "url") as? [AnyHashable : Any]
		if let dict {
			//file shared from photo lib
			shareFileMessage = dict["message"] as? String
			shareFileName.value = dict["url"] as? String
			defaults?.removeObject(forKey: "photoData")
		} else if let dictFile {
			shareFileMessage = dict?["message"] as? String
			shareFileName.value = dictFile["url"] as? String
			defaults?.removeObject(forKey: "icloudData")
		} else if let dictUrl {
			shareFileMessage = dict?["message"] as? String
			shareFileURL.value = dictUrl["url"] as? String
			defaults?.removeObject(forKey: "url")
		}
	}
	
	func getImageFrom(_ content: OpaquePointer?, filePath: String?, forReplyBubble: Bool) -> UIImage? {
		var filePath = filePath
		let type = String(utf8String: linphone_content_get_type(content))
		let name = String(utf8String: linphone_content_get_name(content))
		if filePath == nil {
			filePath = LinphoneManager.validFilePath(name)
		}

		var image: UIImage? = nil
		if type == "video" {
			image = UIChatBubbleTextCell.getImageFromVideoUrl(URL(fileURLWithPath: filePath ?? ""))
		} else if type == "image" {
			let data = NSData(contentsOfFile: filePath ?? "") as Data?
			if let data {
				image = UIImage(data: data)
			}
		}
		if let image {
			return image
		} else {
			return getImageFromFileName(name, forReplyBubble: forReplyBubble)
		}
	}
	
	func getImageFromFileName(_ fileName: String?, forReplyBubble forReplyBubbble: Bool) -> UIImage? {
		let `extension` = fileName?.lowercased().components(separatedBy: ".").last
		var image: UIImage?
		var text = fileName
		if fileName?.contains("voice-recording") ?? false {
			image = UIImage(named: "file_voice_default")
			text = recordingDuration(LinphoneManager.validFilePath(fileName))
		} else {
			if `extension` == "pdf" {
				image = UIImage(named: "file_pdf_default")
			} else if ["png", "jpg", "jpeg", "bmp", "heic"].contains(`extension` ?? "") {
				image = UIImage(named: "file_picture_default")
			} else if ["mkv", "avi", "mov", "mp4"].contains(`extension` ?? "") {
				image = UIImage(named: "file_video_default")
			} else if ["wav", "au", "m4a"].contains(`extension` ?? "") {
				image = UIImage(named: "file_audio_default")
			} else {
				image = UIImage(named: "file_default")
			}
		}

		return SwiftUtil.textToImage(drawText: text!, inImage: image!, forReplyBubble: forReplyBubbble)
	}
	
	func recordingDuration(_ _voiceRecordingFile: String?) -> String? {
		let core = Core.getSwiftObject(cObject: LinphoneManager.getLc())
		var result = ""
		do{
			let linphonePlayer = try core.createLocalPlayer(soundCardName: nil, videoDisplayName: nil, windowId: nil)
			try linphonePlayer.open(filename: _voiceRecordingFile!)
			result = formattedDuration(linphonePlayer.duration)!
			linphonePlayer.close()
		}catch{
			print(error)
		}
		return result
	}
	
	func formattedDuration(_ valueMs: Int) -> String? {
		return String(format: "%02ld:%02ld", valueMs / 60000, (valueMs % 60000) / 1000)
	}
	
	func writeMediaToGalleryFromName(_ name: String?, fileType: String?) {
		let filePath = LinphoneManager.validFilePath(name)
		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: filePath!) {
			let data = NSData(contentsOfFile: filePath!) as Data?
			let block: (() -> Void)? = {
				if fileType == "image" {
					// we're finished, save the image and update the message
					let image = UIImage(data: data!)
					if image == nil {
						ChatConversationViewSwift.showFileDownloadError()
						return
					}
					var placeHolder: PHObjectPlaceholder? = nil
					PHPhotoLibrary.shared().performChanges({
						let request = PHAssetCreationRequest.creationRequestForAsset(from: image!)
						placeHolder = request.placeholderForCreatedAsset
					}) { success, error in
						DispatchQueue.main.async(execute: {
							if error != nil {
								Log.e("Cannot save image data downloaded \(error!.localizedDescription)")
								let errView = UIAlertController(
									title: NSLocalizedString("Transfer error", comment: ""),
									message: NSLocalizedString("Cannot write image to photo library", comment: ""),
									preferredStyle: .alert)

								let defaultAction = UIAlertAction(
									title: "OK",
									style: .default,
									handler: { action in
									})

								errView.addAction(defaultAction)
								PhoneMainView.instance()!.present(errView, animated: true)
							} else {
								Log.i("Image saved to \(placeHolder!.localIdentifier)")
							}
						})
					}
				} else if fileType == "video" {
				var placeHolder: PHObjectPlaceholder?
				PHPhotoLibrary.shared().performChanges({
					let request = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: filePath!))
					placeHolder = request?.placeholderForCreatedAsset
					}) { success, error in
						DispatchQueue.main.async(execute: {
							if error != nil {
								Log.e("Cannot save video data downloaded \(error!.localizedDescription)")
								let errView = UIAlertController(
									title: NSLocalizedString("Transfer error", comment: ""),
									message: NSLocalizedString("Cannot write video to photo library", comment: ""),
									preferredStyle: .alert)
								let defaultAction = UIAlertAction(
									title: "OK",
									style: .default,
									handler: { action in
									})

								errView.addAction(defaultAction)
								PhoneMainView.instance()!.present(errView, animated: true)
							} else {
								Log.i("video saved to \(placeHolder!.localIdentifier)")
							}
						})
					}
				}
			}
			if PHPhotoLibrary.authorizationStatus() == .authorized {
				block!()
			} else {
				PHPhotoLibrary.requestAuthorization({ status in
					DispatchQueue.main.async(execute: {
						if PHPhotoLibrary.authorizationStatus() == .authorized {
							block!()
						} else {
							UIAlertView(title: NSLocalizedString("Photo's permission", comment: ""), message: NSLocalizedString("Photo not authorized", comment: ""), delegate: nil, cancelButtonTitle: "", otherButtonTitles: "Continue").show()
						}
					})
				})
			}
		}
	}
	
	func createCollectionViewItem(urlFile: URL?, type: String) {
		if let url = urlFile {
			do {
				if(type == "public.image"){
					let dataResult = try Data(contentsOf: url)
					ChatConversationViewModel.sharedModel.data.append(dataResult)
					if let image = UIImage(data: dataResult) {
						ChatConversationViewModel.sharedModel.imageT.append(image)
					}else{
						ChatConversationViewModel.sharedModel.imageT.append(UIImage(named: "chat_error"))
					}
				}else if(type == "public.movie"){
					ChatConversationViewModel.sharedModel.data.append(try Data(contentsOf: url))
					var tmpImage = ChatConversationViewModel.sharedModel.createThumbnailOfVideoFromFileURL(videoURL: url.relativeString)
					if tmpImage == nil { tmpImage = UIImage(named: "chat_error")}
					ChatConversationViewModel.sharedModel.imageT.append(tmpImage)
				}else{
					
					ChatConversationViewModel.sharedModel.data.append(try Data(contentsOf: url))
					let otherFile = FileType.init(url.pathExtension)
					let otherFileImage = otherFile!.getImageFromFile()
					ChatConversationViewModel.sharedModel.imageT.append(otherFileImage)
				}
				ChatConversationViewModel.sharedModel.urlFile.append(url)
				DispatchQueue.main.async(execute: ChatConversationViewModel.sharedModel.workItem!)
			}catch let error{
				print(error.localizedDescription)
			}
		}
	}
	
	
	func createCollectionViewItemForReply(urlFile: URL?, type: String) -> UIImage {
		if urlFile != nil {
			do {
				if(type == "public.image"){
					let dataResult = try Data(contentsOf: urlFile!)
					if let image = UIImage(data: dataResult) {
						return image
					}else{
						return UIImage(named: "chat_error")!
					}
				}else if(type == "public.movie"){
					var tmpImage = ChatConversationViewModel.sharedModel.createThumbnailOfVideoFromFileURL(videoURL: urlFile!.relativeString)
					if tmpImage == nil { tmpImage = UIImage(named: "chat_error")}
					return tmpImage!
				}else{
					let otherFile = FileType.init(urlFile!.pathExtension)
					let otherFileImage = otherFile!.getImageFromFile()
					return otherFileImage!
				}
			}catch let error{
				print(error.localizedDescription)
			}
		}
		return UIImage(named: "chat_error")!
	}

	func createThumbnailOfVideoFromFileURL(videoURL: String) -> UIImage? {
		let asset = AVAsset(url: URL(string: videoURL)!)
		let assetImgGenerate = AVAssetImageGenerator(asset: asset)
		assetImgGenerate.appliesPreferredTrackTransform = true
		do {
			let img = try assetImgGenerate.copyCGImage(at: CMTimeMake(value: 1, timescale: 10), actualTime: nil)
			let thumbnail = UIImage(cgImage: img)
			return thumbnail
		} catch _{
			return nil
		}
	}
	
	//Voice recoder and player
	func createVoiceRecorder() {
		let core = Core.getSwiftObject(cObject: LinphoneManager.getLc())
		do{
			let p = try core.createRecorderParams()
			p.fileFormat = RecorderFileFormat.Mkv
			ChatConversationViewModel.sharedModel.voiceRecorder = try core.createRecorder(params: p)
		}catch{
			print(error)
		}
	}
	
	func startVoiceRecording() {
		UIApplication.shared.isIdleTimerDisabled = true
		if (voiceRecorder == nil) {
			createVoiceRecorder()
		}
		CallManager.instance().activateAudioSession()

		showVoiceRecorderView = true
		isVoiceRecording = true

		switch linphone_recorder_get_state(voiceRecorder?.getCobject) {
		case LinphoneRecorderClosed:
			let filename = "\(String(describing: LinphoneManager.imagesDirectory()))/voice-recording-\(UUID().uuidString).mkv"
			linphone_recorder_open(voiceRecorder?.getCobject, filename)
			linphone_recorder_start(voiceRecorder?.getCobject)
			print("[Chat Message Sending] Recorder is closed opening it with \(filename)")
		case LinphoneRecorderRunning:
			print("[Chat Message Sending] Recorder is already recording")
		case LinphoneRecorderPaused:
			print("[Chat Message Sending] Recorder isn't closed, resuming recording")
			linphone_recorder_start(voiceRecorder?.getCobject)
		default:
			break
		}
	}
	
	func stopVoiceRecording() {
		UIApplication.shared.isIdleTimerDisabled = false
		if (ChatConversationViewModel.sharedModel.voiceRecorder != nil) && linphone_recorder_get_state(ChatConversationViewModel.sharedModel.voiceRecorder?.getCobject) == LinphoneRecorderRunning {
			print("[Chat Message Sending] Pausing / closing voice recorder")
			linphone_recorder_pause(ChatConversationViewModel.sharedModel.voiceRecorder?.getCobject)
			linphone_recorder_close(ChatConversationViewModel.sharedModel.voiceRecorder?.getCobject)
		}
		isVoiceRecording = false
		vrRecordTimer.invalidate()
		isPendingVoiceRecord = linphone_recorder_get_duration(ChatConversationViewModel.sharedModel.voiceRecorder?.getCobject) > 0
	}
	
	func initSharedPlayer() {
		AudioPlayer.initSharedPlayer()
	}
	
	func startSharedPlayer(_ path: String?) {
		AudioPlayer.startSharedPlayer(path)
		AudioPlayer.sharedModel.fileChanged.value = path
	}
	
	func cancelVoiceRecordingVM() {
		UIApplication.shared.isIdleTimerDisabled = false
		showVoiceRecorderView = false
		isPendingVoiceRecord = false
		isVoiceRecording = false
		if (voiceRecorder != nil) && linphone_recorder_get_state(voiceRecorder?.getCobject) != LinphoneRecorderClosed {
			AudioPlayer.cancelVoiceRecordingVM(voiceRecorder)
		}
	}
	
	func stopSharedPlayer() {
		AudioPlayer.stopSharedPlayer()
	}
}
