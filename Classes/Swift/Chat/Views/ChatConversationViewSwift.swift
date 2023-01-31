/*
 * Copyright (c) 2010-2020 Belledonne Communications SARL.
 *
 * This file is part of linphone-iphone
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */


import UIKit
import Foundation
import linphonesw
import DropDown
import PhotosUI
import AVFoundation

@objc class ChatConversationViewSwift: BackActionsNavigationView, PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UICompositeViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UIImagePickerControllerDelegate & UINavigationControllerDelegate{ // Replaces ChatConversationView
	
	let controlsView = ControlsView(showVideo: true, controlsViewModel: ChatConversationViewModel.sharedModel)
	
	static let compositeDescription = UICompositeViewDescription(ChatConversationViewSwift.self, statusBar: StatusBarView.self, tabBar: nil, sideMenu: SideMenuView.self, fullscreen: false, isLeftFragment: false,fragmentWith: nil)
	
	static func compositeViewDescription() -> UICompositeViewDescription! { return compositeDescription }
	
	func compositeViewDescription() -> UICompositeViewDescription! { return type(of: self).compositeDescription }
	
	let APP_GROUP_ID = "group.belledonne-communications.linphone.widget"
	var debugEnabled = false
	
	var chatRoom: ChatRoom? = nil
	var chatRoomDelegate: ChatRoomDelegate? = nil
	var address: String? = nil
	var participants: String? = nil
	
	var activeAlertController = CustomAlertController()
	
	@objc let tableController = ChatConversationTableView()
	let refreshControl = UIRefreshControl()
	
	var mediaCollectionView : [UIImage] = []
	var mediaURLCollection : [URL] = []
	
	var collectionView: UICollectionView = {
		let top_bar_height = 66.0
		let width = UIScreen.main.bounds.width * 0.9
		let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
		layout.itemSize = CGSize(width: top_bar_height*2-8, height: top_bar_height*2-8)

		layout.sectionInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
		layout.scrollDirection = .horizontal
		layout.minimumLineSpacing = 4
		layout.minimumInteritemSpacing = 20

		let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: top_bar_height*2), collectionViewLayout: layout)
		collectionView.translatesAutoresizingMaskIntoConstraints = false
		collectionView.backgroundColor = UIColor(white: 1, alpha: 0.5)
		return collectionView
	}()
	
	let loadingView = UIView()
	let loading = RotatingSpinner(color: VoipTheme.primary_color)
	let loadingText = StyledLabel(VoipTheme.chat_conversation_operation_in_progress_wait)
	
	let menu: DropDown = {
		let menu = DropDown()
		menu.dataSource = [""]
		var images = [
			"contact_add_default.png",
			"contacts_all_default.png",
			"menu_voip_meeting_schedule",
			"menu_security_default.png",
			"ephemeral_messages_default.png",
			"menu_notifications_off.png",
			"menu_notifications_on.png",
			"delete_default.png",
			"chat_group_informations.png"
		]
		menu.cellNib = UINib(nibName: "DropDownCell", bundle: nil)
		menu.customCellConfiguration = { index, title, cell in
			guard let cell = cell as? MyCell else {
				return
			}
			if(index < images.count){
				switch menu.dataSource[index] {
				case VoipTexts.dropdown_menu_chat_conversation_add_to_contact:
					cell.myImageView.image = UIImage(named: images[0])
				case VoipTexts.dropdown_menu_chat_conversation_go_to_contact:
					cell.myImageView.image = UIImage(named: images[1])
				case VoipTexts.conference_schedule_start:
					cell.myImageView.image = UIImage(named: images[2])
				case VoipTexts.dropdown_menu_chat_conversation_conversation_device:
					cell.myImageView.image = UIImage(named: images[3])
				case VoipTexts.dropdown_menu_chat_conversation_ephemeral_messages:
					cell.myImageView.image = UIImage(named: images[4])
				case VoipTexts.dropdown_menu_chat_conversation_mute_notifications:
					cell.myImageView.image = UIImage(named: images[5])
				case VoipTexts.dropdown_menu_chat_conversation_unmute_notifications:
					cell.myImageView.image = UIImage(named: images[6])
				case VoipTexts.dropdown_menu_chat_conversation_delete_messages:
					cell.myImageView.image = UIImage(named: images[7])
				default:
					cell.myImageView.image = UIImage(named: images[8])
				}
			}
		}
		return menu
	}()
	
	var fileContext : [Data] = []
	var workItem : DispatchWorkItem? = nil
	var progress : [Progress] = []
	
	var urlFile : [URL?] = []
	var imageT : [UIImage?] = []
	var data : [Data?] = []
	var mediaCount : Int = 0
	var newMediaCount : Int = 0
	@objc var pendingForwardMessage : OpaquePointer? = nil
	
	var replyViewOriginY = 0.0
	var replyViewHeight = 0.0
	var showReplyView = false
	
	
	override func viewDidLoad() {
		super.viewDidLoad(
			backAction: {
				self.goBackChatListView()
			},
			action1: {
				self.onCallClick(cChatRoom: self.chatRoom?.getCobject)
			},
			action2: {
				self.tapChooseMenuItem(self.action2Button)
			},
			action3: {
				self.alertActionGoToDevicesList()
			},
			action4: {
				(LinphoneManager.instance().lpConfigInt(forKey: "debugenable_preference") == 1) ? self.showAddressAndIdentityPopup() : self.tapChooseMenuItem(self.action2Button)
			},
			title: address ?? "Error",
			participants: participants ?? "Error"
		)
		setupViews()
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		topBar.backgroundColor = VoipTheme.voipToolbarBackgroundColor.get()
		self.contentView.addSubview(tableController.tableView)
		tableController.chatRoom = chatRoom?.getCobject
		refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
		tableController.refreshControl = refreshControl
		tableController.toggleSelectionButton = action1SelectAllButton
		messageView.sendButton.onClickAction = onSendClick
		messageView.pictureButton.onClickAction = alertAction
		
		
		chatRoomDelegate = ChatRoomDelegateStub(
			onIsComposingReceived: { (room: ChatRoom, remoteAddress: Address, isComposing: Bool) -> Void in
				self.on_chat_room_is_composing_received(room, remoteAddress, isComposing)
			}, onChatMessageReceived: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_chat_message_received(room, event)
			},
			onChatMessageSending: { (room: ChatRoom, event: EventLog) -> Void in
				self.on_chat_room_chat_message_sending(room, event)
			}
		)
		
		chatRoom?.addDelegate(delegate: chatRoomDelegate!)
		tableController.tableView.separatorColor = .clear
		
		workItem = DispatchWorkItem {
			let indexPath = IndexPath(row: self.mediaCollectionView.count, section: 0)
			self.mediaURLCollection.append(self.urlFile[indexPath.row]!)
			self.mediaCollectionView.append(self.imageT[indexPath.row]!)
			self.collectionView.insertItems(at: [indexPath])
			self.fileContext.append(self.data[indexPath.row]!)
			if(self.mediaCount + self.newMediaCount <= indexPath.row+1){
				if(self.mediaCollectionView.count > 0){
					self.messageView.sendButton.isEnabled = true
				}
				self.loadingView.isHidden = true
				self.messageView.isLoading = false
				self.loading.stopRotation()
				
				self.messageView.sendButton.isEnabled = true
				self.messageView.pictureButton.isEnabled = true
			}
		}
		
		self.handlePendingTransferIfAny()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		chatRoom?.removeDelegate(delegate: chatRoomDelegate!)
		editModeOff()
	}
	
	override func viewDidAppear(_ animated: Bool) {
		tableController.reloadData()
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		
		if(self.isComposingView.isHidden == false){
			self.isComposingView.isHidden = true
		}
		if(self.mediaSelector.isHidden == false){
			self.mediaSelector.isHidden = true
		}
		if(self.replyBubble.isHidden == false){
			self.replyBubble.isHidden = true
		}

		self.mediaCollectionView = []
		self.mediaURLCollection = []
		self.fileContext = []
		self.messageView.fileContext = false
		self.urlFile = []
		self.imageT = []
		self.data = []
		self.collectionView.reloadData()
		if self.messageView.messageText.text.isEmpty{
			self.messageView.sendButton.isEnabled = false
		} else {
			self.messageView.sendButton.isEnabled = true
		}
		self.messageView.pictureButton.isEnabled = true
		
		workItem?.cancel()
		for progressItem in progress{
			progressItem.cancel()
		}
		progress.removeAll()
	}
	
	func goBackChatListView() {
		PhoneMainView.instance().pop(toView: ChatsListView.compositeViewDescription())
	}
	
	func tapChooseMenuItem(_ sender: UIButton) {
		menu.anchorView = sender
		menu.bottomOffset = CGPoint(x: -UIScreen.main.bounds.width * 0.6, y: sender.frame.size.height)
		menu.show()
		menu.selectionAction = { [weak self] (index: Int, item: String) in
			guard let _ = self else { return }
			print(item)
			switch item {
			case VoipTexts.dropdown_menu_chat_conversation_add_to_contact:
				self!.addOrGoToContact()
			case VoipTexts.dropdown_menu_chat_conversation_go_to_contact:
				self!.addOrGoToContact()
			case VoipTexts.conference_schedule_start:
				self!.conferenceSchedule()
			case VoipTexts.dropdown_menu_chat_conversation_group_infos:
				self!.displayGroupInfo()
			case VoipTexts.dropdown_menu_chat_conversation_conversation_device:
				self!.goToDevicesList()
			case VoipTexts.dropdown_menu_chat_conversation_ephemeral_messages:
				self!.goToEphemeralSettings()
			case VoipTexts.dropdown_menu_chat_conversation_mute_notifications:
				self!.mute_unmute_notifications()
				self?.menu.dataSource[index] = VoipTexts.dropdown_menu_chat_conversation_unmute_notifications
			case VoipTexts.dropdown_menu_chat_conversation_unmute_notifications:
				self!.mute_unmute_notifications()
				self?.menu.dataSource[index] = VoipTexts.dropdown_menu_chat_conversation_mute_notifications
			case VoipTexts.dropdown_menu_chat_conversation_delete_messages:
				self!.onEditionChangeClick()
			default:
				self!.showAddressAndIdentityPopup()
			}
			self!.menu.clearSelection()
		}
	}
	
	func goToDevicesList() {
		let view: DevicesListView = self.VIEW(DevicesListView.compositeViewDescription())
		view.room = chatRoom?.getCobject
		PhoneMainView.instance().changeCurrentView(view.compositeViewDescription())
	}
	
	func addOrGoToContact() {
		let firstParticipant = chatRoom?.participants.first
		let addr = (firstParticipant != nil) ? linphone_participant_get_address(firstParticipant?.getCobject) : linphone_chat_room_get_peer_address(chatRoom?.getCobject)
		
		let contact = FastAddressBook.getContactWith(addr)
		
		if let contact {
			let view: ContactDetailsView = self.VIEW(ContactDetailsView.compositeViewDescription())
			ContactSelection.setSelectionMode(ContactSelectionModeNone)
			MagicSearchSingleton.instance().currentFilter = ""
			view.contact = contact
			PhoneMainView.instance().changeCurrentView(view.compositeViewDescription())
		} else {
			
			let lAddress = linphone_address_as_string_uri_only(addr)
			if let lAddress {
				var normSip = String(utf8String: lAddress)
				normSip = normSip?.hasPrefix("sip:") ?? false ? (normSip as NSString?)?.substring(from: 4) : normSip
				normSip = normSip?.hasPrefix("sips:") ?? false ? (normSip as NSString?)?.substring(from: 5) : normSip
				ContactSelection.setAddAddress(normSip)
				ContactSelection.setSelectionMode(ContactSelectionModeEdit)
				ContactSelection.enableSipFilter(false)
				PhoneMainView.instance().changeCurrentView(ContactsListView.compositeViewDescription())
			}
		}
	}
	
	func displayGroupInfo() {
		let contactsArray: NSMutableArray = []
		let admins: NSMutableArray = []
		let participants = chatRoom?.participants
		participants?.forEach{ participant in
			let curi = linphone_address_as_string_uri_only(linphone_participant_get_address(participant.getCobject))
			let uri = String(utf8String: curi!)
			contactsArray.add(uri!)
			if (linphone_participant_is_admin(participant.getCobject) != 0) {
				admins.add(uri!)
			}
		}
		
		let view: ChatConversationInfoView = self.VIEW(ChatConversationInfoView.compositeViewDescription())
		view.create = false
		view.contacts = contactsArray
		view.oldContacts = contactsArray
		view.admins = admins
		view.oldAdmins = admins
		view.oldSubject = String(utf8String: linphone_chat_room_get_subject(chatRoom?.getCobject)) ?? LINPHONE_DUMMY_SUBJECT
		view.room = chatRoom?.getCobject
		
		let localAddress = linphone_address_as_string(linphone_chat_room_get_local_address(chatRoom?.getCobject))
		let peerAddress = linphone_address_as_string(linphone_chat_room_get_peer_address(chatRoom?.getCobject))
		view.peerAddress = UnsafePointer(peerAddress)
		view.localAddress = UnsafePointer(localAddress)
		PhoneMainView.instance().changeCurrentView(view.compositeViewDescription())
	}
	
	func goToEphemeralSettings(){
		let view: EphemeralSettingsView = self.VIEW(EphemeralSettingsView.compositeViewDescription())
		view.room = chatRoom?.getCobject
		PhoneMainView.instance().changeCurrentView(view.compositeViewDescription())
	}
	
	func conferenceSchedule(){
		ConferenceViewModelBridge.scheduleFromGroupChat(cChatRoom: (chatRoom?.getCobject)!)
		PhoneMainView.instance().pop(toView: ConferenceSchedulingView.compositeViewDescription())
	}
	
	func mute_unmute_notifications(){
		LinphoneManager.setChatroomPushEnabled(chatRoom?.getCobject, withPushEnabled: !LinphoneManager.getChatroomPushEnabled(chatRoom?.getCobject))
	}
	
	func onEditionChangeClick() {
		editModeOn()
	}
	
	func showAddressAndIdentityPopup() {
		
		let localAddress = String(utf8String: linphone_address_as_string(linphone_chat_room_get_local_address(chatRoom?.getCobject)))
		let peerAddress = String(utf8String: linphone_address_as_string(linphone_chat_room_get_peer_address(chatRoom?.getCobject)))
		
		var infoMsg: String? = nil
		if let peerAddress, let localAddress {
			infoMsg = "Chat room id:\n\(peerAddress)\nLocal account:\n\(localAddress)"
		}
		
		let popupView = UIAlertController(title: NSLocalizedString("Chatroom debug infos", comment: ""), message: infoMsg, preferredStyle: .alert)
		
		let defaultAction = UIAlertAction(
			title: NSLocalizedString("Copy to clipboard", comment: ""),
			style: .default,
			handler: { action in
				let pasteboard = UIPasteboard.general
				pasteboard.string = infoMsg
			})
		popupView.addAction(defaultAction)
		present(popupView, animated: true, completion:{
			popupView.view.superview?.isUserInteractionEnabled = true
			popupView.view.superview?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dismissOnTapOutsideOrCancel)))
		})
		
	}
	
	func initDataSource(groupeChat: Bool, secureLevel: Bool, cChatRoom: OpaquePointer) {
		menu.dataSource.removeAll()
		
		if(groupeChat){
			menu.dataSource.append(VoipTexts.conference_schedule_start)
			menu.dataSource.append(VoipTexts.dropdown_menu_chat_conversation_group_infos)
		}else{
			var contact: Contact? = nil
			let firstParticipant = chatRoom?.participants.first
			let addr = (firstParticipant != nil) ? linphone_participant_get_address(firstParticipant?.getCobject) : linphone_chat_room_get_peer_address(cChatRoom)
			
			contact = FastAddressBook.getContactWith(addr)
			
			if (contact == nil) {
				menu.dataSource.append(VoipTexts.dropdown_menu_chat_conversation_add_to_contact)
			} else {
				menu.dataSource.append(VoipTexts.dropdown_menu_chat_conversation_go_to_contact)
			}
		}
		if(secureLevel){
			menu.dataSource.append(VoipTexts.dropdown_menu_chat_conversation_conversation_device)
			menu.dataSource.append(VoipTexts.dropdown_menu_chat_conversation_ephemeral_messages)
		}
		if(LinphoneManager.getChatroomPushEnabled(chatRoom?.getCobject)){
			menu.dataSource.append(VoipTexts.dropdown_menu_chat_conversation_mute_notifications)
		}else{
			menu.dataSource.append(VoipTexts.dropdown_menu_chat_conversation_unmute_notifications)
		}
		menu.dataSource.append(VoipTexts.dropdown_menu_chat_conversation_delete_messages)
		
		messageView.ephemeralIndicator.isHidden = (linphone_chat_room_ephemeral_enabled(chatRoom?.getCobject) == 0)
	}
	
	@objc func initChatRoom(cChatRoom:OpaquePointer) {
		chatRoom = ChatRoom.getSwiftObject(cObject: cChatRoom)
		PhoneMainView.instance().currentRoom = cChatRoom
		address = chatRoom?.peerAddress?.asString()
		
		var changeIcon = false
		let isOneToOneChat = chatRoom!.hasCapability(mask: Int(LinphoneChatRoomCapabilitiesOneToOne.rawValue))
		
		if (isOneToOneChat) {
			
			let firstParticipant = chatRoom?.participants.first
			let addr = (firstParticipant != nil) ? linphone_participant_get_address(firstParticipant?.getCobject) : linphone_chat_room_get_peer_address(cChatRoom);
			address = FastAddressBook.displayName(for: addr) ?? "unknow"
			changeIcon = false
			titleParticipants.isHidden = true
			
		} else {
			address = chatRoom?.subject
			changeIcon = true
			
			titleParticipants.isHidden = false
			
			let participants = chatRoom?.participants
			participantsGroupLabel.text = ""
			participants?.forEach{ participant in
				if participantsGroupLabel.text != "" {
					participantsGroupLabel.text = participantsGroupLabel.text! + ", "
				}
				participantsGroupLabel.text = participantsGroupLabel.text! + FastAddressBook.displayName(for: linphone_participant_get_address(participant.getCobject))
			}
			
		}
		
		changeTitle(titleString: address ?? "Error")
		changeCallIcon(groupChat: changeIcon)
		
		let secureLevel = FastAddressBook.image(for: linphone_chat_room_get_security_level(cChatRoom))
		changeSecureLevel(secureLevel: secureLevel != nil, imageBadge: secureLevel)
		initDataSource(groupeChat: !isOneToOneChat, secureLevel: secureLevel != nil, cChatRoom: cChatRoom)
	}
	
	func onCallClick(cChatRoom: OpaquePointer?) {
		let firstParticipant = chatRoom?.participants.first
		let addr = (firstParticipant != nil) ? linphone_participant_get_address(firstParticipant?.getCobject) : linphone_chat_room_get_peer_address(cChatRoom);
		
		let isOneToOneChat = chatRoom!.hasCapability(mask: Int(LinphoneChatRoomCapabilitiesOneToOne.rawValue))
		
		if (!isOneToOneChat) {
			alertActionConferenceCall(cChatRoom: cChatRoom)
		} else {
			LinphoneManager.instance().call(addr)
		}
	}
	
	func alertActionConferenceCall(cChatRoom: OpaquePointer?) {
		
		let alertController = CustomAlertController(title: VoipTexts.conference_start_group_call_dialog_message, message: nil, preferredStyle: .alert)
		
		alertController.setBackgroundColor(color: .darkGray)
		alertController.setTitle(font: nil, color: .white)
		alertController.setTint(color: .white)
		alertController.setMaxWidth(alert: alertController)
		
		alertController.addButtonsAlertController(alertController: alertController, buttonsViewHeightV: 60, buttonsAlertHeightV: 40)
		
		activeAlertController = alertController
		
		self.present(alertController, animated: true, completion:{
			alertController.view.superview?.isUserInteractionEnabled = true
			alertController.view.superview?.subviews[0].addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dismissOnTapOutsideOrCancel)))
		})
		
		
		alertController.ok_button_alert.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onTapOkStartGroupCall)))
		
	}
	
	@objc func alertActionGoToDevicesList() {
		
		let notAskAgain = ConfigManager.instance().lpConfigBoolForKey(key: "confirmation_dialog_before_sas_call_not_ask_again");
		if(!notAskAgain){
			let alertController = CustomAlertController(title: VoipTexts.alert_dialog_secure_badge_button_chat_conversation_title, message: nil, preferredStyle: .alert)
			
			alertController.setBackgroundColor(color: .darkGray)
			alertController.setTitle(font: nil, color: .white)
			alertController.setTint(color: .white)
			alertController.setMaxWidth(alert: alertController)
			
			alertController.addButtonsAlertController(alertController: alertController, buttonsViewHeightV: 60, checkboxViewHeightV: 50, buttonsAlertHeightV: 40)
			
			activeAlertController = alertController
			
			self.present(alertController, animated: true, completion:{
				alertController.view.superview?.isUserInteractionEnabled = true
				alertController.view.superview?.subviews[0].addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dismissOnTapOutsideOrCancel)))
			})
			
			alertController.ok_button_alert.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onTapOkGoToDevicesList)))
		}else{
			let view: DevicesListView = self.VIEW(DevicesListView.compositeViewDescription())
			view.room = chatRoom?.getCobject
			PhoneMainView.instance().changeCurrentView(view.compositeViewDescription())
		}
		
	}
	
	@objc func onTapOkStartGroupCall(){
		self.dismiss(animated: true, completion: nil)
		ConferenceViewModelBridge.startGroupCall(cChatRoom: (chatRoom?.getCobject)!)
	}
	
	@objc func onTapOkGoToDevicesList() {
		self.dismiss(animated: true, completion: nil)
		if(activeAlertController.isChecked){
			ConfigManager.instance().lpConfigSetBool(value: activeAlertController.isChecked, key: "confirmation_dialog_before_sas_call_not_ask_again")
		}
		let view: DevicesListView = self.VIEW(DevicesListView.compositeViewDescription())
		view.room = chatRoom?.getCobject
		PhoneMainView.instance().changeCurrentView(view.compositeViewDescription())
	}
	
	@objc func dismissOnTapOutsideOrCancel(){
		self.dismiss(animated: true, completion: nil)
	}
	
	@objc func refreshData() {
		tableController.refreshData()
		refreshControl.endRefreshing()
		if tableController.totalNumberOfItems() == 0 {
			return
		}
		tableController.loadData()
		tableController.tableView.scrollToRow(
			at: IndexPath(row: tableController.currentIndex, section: 0),
			at: .top,
			animated: false)
	}
	
	override func editModeOn(){
		super.editModeOn()
		tableController.setEditing(true, animated: false)
	}
	
	override func editModeOff(){
		super.editModeOff()
		tableController.setEditing(false, animated: false)
	}
	
	override func selectDeselectAll(){
		super.selectDeselectAll()
		if(action1SelectAllButton.isHidden){
			tableController.onSelectionToggle(action1SelectAllButton)
		}else{
			tableController.onSelectionToggle(action1SelectAllButton)
		}
	}
	
	override func deleteSelected(){
		super.deleteSelected()
		onDeleteClick()
	}
	
	func onDeleteClick() {
		let msg = NSLocalizedString("Do you want to delete the selected messages?", comment: "")
		UIConfirmationDialog.show(
			withMessage: msg,
			cancelMessage: nil,
			confirmMessage: nil,
			onCancelClick: { [self] in
				onEditionChangeClick()},
			onConfirmationClick: {
				self.tableController.removeSelection(nil)
				self.editModeOff()
				self.tableController.loadData()
			}
		)
	}
	
	func sendMessage(message: String?, withExterlBodyUrl externalUrl: URL?, rootMessage: ChatMessage?) -> Bool {
		if chatRoom == nil {
			return false
		}
		
		let msg = rootMessage
		let basic = ChatConversationView.isBasicChatRoom(chatRoom?.getCobject)
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
	
	func sendMessageInMessageField(rootMessage: ChatMessage?) {
		if sendMessage(message: messageView.messageText.text, withExterlBodyUrl: nil, rootMessage: rootMessage) {
			messageView.messageText.text = ""
			messageView.isComposing = false
		}
	}
	
	func onSendClick() {
		//let rootMessage = replyBubble ? linphone_chat_room_create_reply_message(chatRoom?.getCobject, replyBubble.message) : linphone_chat_room_create_empty_message(chatRoom?.getCobject)
		let rootMessage = linphone_chat_room_create_empty_message(chatRoom?.getCobject)
		/*
		 if replyBubble != nil {
		 closePendingReply()
		 }
		 if isPendingVoiceRecord && voiceRecorder && linphone_recorder_get_file(voiceRecorder) {
		 let voiceContent = linphone_recorder_create_content(voiceRecorder)
		 isPendingVoiceRecord = false
		 cancelVoiceRecording()
		 stopVoiceRecordPlayer()
		 linphone_chat_message_add_content(rootMessage, voiceContent)
		 }
		 */
		if fileContext.count > 0 {
			let conference = chatRoom!.hasCapability(mask: Int(LinphoneChatRoomCapabilitiesConference.rawValue))
			if (linphone_chat_room_get_capabilities(chatRoom?.getCobject) != 0) && conference {
				let result = ChatMessage.getSwiftObject(cObject: rootMessage!)
				startMultiFilesUpload(result)
			} else {
				for i in 0..<(fileContext.count) {
					startUploadData(fileContext[i], withType: FileType.init(mediaURLCollection[i].pathExtension)?.getGroupTypeFromFile(), withName: mediaURLCollection[i].lastPathComponent, andMessage: nil, rootMessage: nil)
				}
				if messageView.messageText.text != "" {
					let result = ChatMessage.getSwiftObject(cObject: rootMessage!)
					sendMessageInMessageField(rootMessage: result)
				}
			}
			
			fileContext = []
			messageView.fileContext = false
			self.mediaCollectionView = []
			self.mediaURLCollection = []
	 		return
 		}
		if(self.mediaSelector.isHidden == false){
			self.mediaSelector.isHidden = true
		}
		if(self.replyBubble.isHidden == false){
			self.replyBubble.isHidden = true
		}
		let result = ChatMessage.getSwiftObject(cObject: rootMessage!)
		sendMessageInMessageField(rootMessage: result)
	}
	
	func startMultiFilesUpload(_ rootMessage: ChatMessage?) -> Bool {
		let fileTransfer = FileTransferDelegate()
		fileTransfer.text = messageView.messageText.text
		fileTransfer.uploadFileContent(forSwift: fileContext, urlList: mediaURLCollection, for: chatRoom?.getCobject, rootMessage: rootMessage?.getCobject)
		messageView.messageText.text = ""
		tableController.scroll(toBottom: true)
		return true
	}
	
	@objc class func writeFileInImagesDirectory(_ data: Data?, name: String?) {
		let filePath = URL(fileURLWithPath: LinphoneManager.imagesDirectory()).appendingPathComponent(name ?? "").path
		if name != nil || (name == "") {
			print("try to write file in \(filePath)")
		}
		FileManager.default.createFile(
			atPath: filePath,
			contents: data,
			attributes: nil)
	}
	
	func startUploadData(_ data: Data?, withType type: String?, withName name: String?, andMessage message: String?, rootMessage: ChatMessage?) -> Bool {
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
		tableController.scroll(toBottom: true)
		return true
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
		
		let isDisplayingBottomOfTable = tableController.tableView.indexPathsForVisibleRows?.last?.row == (tableController.totalNumberOfItems() ) - 1
		tableController.addEventEntry(event_log?.getCobject)
		
		if isDisplayingBottomOfTable {
			tableController.scroll(toBottom: true)
			tableController.scrollBadge!.text = nil
			tableController.scrollBadge!.isHidden = true
		} else {
			tableController.scrollBadge!.isHidden = false
			let unread_msg = linphone_chat_room_get_unread_messages_count(cr?.getCobject)
			tableController.scrollBadge!.text = "\(unread_msg)"
		}
	}
	
	func on_chat_room_chat_message_sending(_ cr: ChatRoom?, _ event_log: EventLog?) {
		tableController.addEventEntry(event_log?.getCobject)
		tableController.scroll(toBottom: true)
	}
	
	func on_chat_room_is_composing_received(_ cr: ChatRoom?, _ remoteAddr: Address?, _ isComposing: Bool) {
		let composing = (linphone_chat_room_is_remote_composing(cr?.getCobject) != 0) || bctbx_list_size(linphone_chat_room_get_composing_addresses(cr?.getCobject)) > 0
		if((composing && self.isComposingView.isHidden)||(!composing && !self.isComposingView.isHidden)){
			setComposingVisible(composing, withDelay: 0.3)
		}
	}
	
	func setComposingVisible(_ visible: Bool, withDelay delay: CGFloat) {
		if visible {
			let addresses = chatRoom!.composingAddresses
			var composingAddresses : String? = ""
			if addresses.count == 1 {

				composingAddresses = FastAddressBook.displayName(for: addresses.first?.getCobject)
				isComposingTextView.text = String.localizedStringWithFormat(NSLocalizedString("%@ is writing...", comment: ""), composingAddresses!)
			} else {
				addresses.forEach({ addressItem in
					if composingAddresses != "" {
						composingAddresses = composingAddresses! + ", "
					}
					composingAddresses = composingAddresses! + FastAddressBook.displayName(for: addressItem.getCobject)
				})

				isComposingTextView.text = String.localizedStringWithFormat(NSLocalizedString("%@ are writing...", comment: ""), composingAddresses!)
			}
		}
		var isBottomOfView = false
		if (tableController.tableView.contentOffset.y + 1) >= (tableController.tableView.contentSize.height - tableController.tableView.frame.size.height) {
			isBottomOfView = true
		}
		UIView.animate(withDuration: 0.3, animations: {
			self.isComposingView.isHidden = !self.isComposingView.isHidden
	   	})
		if(isBottomOfView){
			tableController.scroll(toBottom: false)
		}
	}
	
	func selectionMedia() {
		var isBottomOfView = false
		if (tableController.tableView.contentOffset.y + 1) >= (tableController.tableView.contentSize.height - tableController.tableView.frame.size.height) {
			isBottomOfView = true
		}
		UIView.animate(withDuration: 0.3, animations: {
			self.mediaSelector.isHidden = !self.mediaSelector.isHidden
		})
		if(isBottomOfView){
			tableController.scroll(toBottom: false)
		}
	}
	
	func initReplyView() {
		var isBottomOfView = false
		if (tableController.tableView.contentOffset.y + 1) >= (tableController.tableView.contentSize.height - tableController.tableView.frame.size.height) {
			isBottomOfView = true
	   	}
		UIView.animate(withDuration: 0.3, animations: {
			self.replyBubble.isHidden = !self.replyBubble.isHidden
	   	})
		if(isBottomOfView){
			tableController.scroll(toBottom: false)
		}
	}
	
	@objc class func getKeyFromFileType(_ fileType: String?, fileName name: String?) -> String? {
		if fileType == "video" {
			return "localvideo"
		} else if (fileType == "image") || name?.hasSuffix("JPG") ?? false || name?.hasSuffix("PNG") ?? false || name?.hasSuffix("jpg") ?? false || name?.hasSuffix("png") ?? false {
			return "localimage"
		}
		return "localfile"
	}
	
	@objc class func writeMediaToGalleryFromName(_ name: String?, fileType: String?) {
		let filePath = LinphoneManager.validFilePath(name)
		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: filePath!) {
			let data = NSData(contentsOfFile: filePath!) as Data?
			let block: (() -> Void)? = {
				if fileType == "image" {
					// we're finished, save the image and update the message
					let image = UIImage(data: data!)
					if image == nil {
						showFileDownloadError()
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
	
	class func showFileDownloadError() {
		let errView = UIAlertController(
			title: NSLocalizedString("File download error", comment: ""),
			message: NSLocalizedString(
				"""
					Error while downloading the file.\n\
					The file is probably encrypted.\n\
					Please retry to download this file after activating LIME.
					""",
				comment: ""),
			preferredStyle: .alert)

		let defaultAction = UIAlertAction(
			title: "OK",
			style: .default,
			handler: { action in
			})

		errView.addAction(defaultAction)
		PhoneMainView.instance()!.present(errView, animated: true)
	}
	
	
	func alertAction() {

		let alertController = UIAlertController(title: VoipTexts.image_picker_view_alert_action_title, message: nil, preferredStyle: .actionSheet)
		
		let alert_action_camera = UIAlertAction(title: VoipTexts.image_picker_view_alert_action_camera, style: .default, handler: { (action) -> Void in
			self.imageCamera()
		})
		let alert_action_photo_library = UIAlertAction(title: VoipTexts.image_picker_view_alert_action_photo_library, style: .default, handler: { (action) -> Void in
			self.pickPhotos()
		})
		let alert_action_document = UIAlertAction(title: VoipTexts.image_picker_view_alert_action_document, style: .default, handler: { (action) -> Void in
			self.openDocumentPicker()
		})
		
		let cancel = UIAlertAction(title: VoipTexts.cancel, style: .cancel) { (action) -> Void in
		}
		
		
		alertController.addAction(cancel)
		alertController.addAction(alert_action_camera)
		alertController.addAction(alert_action_photo_library)
		alertController.addAction(alert_action_document)
		
		alertController.popoverPresentationController?.sourceView = PhoneMainView.instance().mainViewController.statusBarView
		PhoneMainView.instance().mainViewController.present(alertController, animated: true)
	}
	
	func imageCamera(){
		let imagePicker = UIImagePickerController()
		imagePicker.sourceType = .camera
		imagePicker.mediaTypes = ["public.image", "public.movie"]
		imagePicker.modalPresentationStyle = .overFullScreen
		imagePicker.delegate = self
		PhoneMainView.instance().mainViewController.present(imagePicker, animated: true)
			
	}
	
	func pickPhotos()
	{
		if #available(iOS 14.0, *) {
			var config = PHPickerConfiguration()
			config.selectionLimit = 0
			let pickerViewController = PHPickerViewController(configuration: config)
			pickerViewController.delegate = self
			PhoneMainView.instance().mainViewController.present(pickerViewController, animated: true)
		} else {
			let imagePicker = UIImagePickerController()
			imagePicker.sourceType = .photoLibrary
			imagePicker.mediaTypes = ["public.image", "public.movie"]
			imagePicker.delegate = self
			PhoneMainView.instance().mainViewController.present(imagePicker, animated: true)
		}
	}
	
	func openDocumentPicker() {
		let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.jpeg","com.compuserve.gif","public.url","public.movie","com.apple.mapkit.map-item","com.adobe.pdf","public.png","public.image", "public.data", "public.text"], in: .import)
		   	documentPicker.delegate = self
		   	documentPicker.modalPresentationStyle = .overFullScreen
			documentPicker.allowsMultipleSelection = true
		   	PhoneMainView.instance().mainViewController.present(documentPicker, animated: true)
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
	
	func setupViews() {
		mediaSelector.addSubview(collectionView)
		collectionView.dataSource = self
		collectionView.delegate = self
		collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
		
		
		loadingView.backgroundColor = UIColor(red: 0.77, green: 0.77, blue: 0.77, alpha: 0.80)
		mediaSelector.addSubview(loadingView)
		loadingView.matchParentEdges().done()
		
		loadingText.text = VoipTexts.operation_in_progress_wait
		loadingView.addSubview(loading)
		loadingView.addSubview(loadingText)
		loadingText.alignParentLeft(withMargin: 10).alignParentRight(withMargin: 10).alignParentBottom(withMargin: 30).alignVerticalCenterWith(loadingView).done()
		loading.square(Int(top_bar_height)).alignVerticalCenterWith(loadingView).alignParentTop(withMargin: 20).done()
	}

	@objc func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return mediaCollectionView.count
	}

	@objc(collectionView:cellForItemAtIndexPath:) func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
		let viewCell: UIView = UIView(frame: cell.contentView.frame)
		cell.addSubview(viewCell)
		
		let deleteButton = CallControlButton(width: 22, height: 22, buttonTheme:VoipTheme.nav_black_button("reply_cancel"))
		
		deleteButton.onClickAction = {
			self.collectionView.deleteItems(at: [indexPath])
			self.mediaCollectionView.remove(at: indexPath.row)
			self.mediaURLCollection.remove(at: indexPath.row)
			self.fileContext.remove(at: indexPath.row)
			self.urlFile.remove(at: indexPath.row)
			self.imageT.remove(at: indexPath.row)
			self.data.remove(at: indexPath.row)
			if(self.mediaCollectionView.count == 0){
				self.messageView.fileContext = false
				self.selectionMedia()
				if self.messageView.messageText.text.isEmpty{
					self.messageView.sendButton.isEnabled = false
				} else {
					self.messageView.sendButton.isEnabled = true
				}
			}
		}
		
		let imageCell = mediaCollectionView[indexPath.row]
		var myImageView = UIImageView()
		
		if(FileType.init(mediaURLCollection[indexPath.row].pathExtension)?.getGroupTypeFromFile() == FileType.file_picture_default.rawValue || FileType.init(mediaURLCollection[indexPath.row].pathExtension)?.getGroupTypeFromFile() == FileType.file_video_default.rawValue){
			myImageView = UIImageView(image: imageCell)
		}else{
			let fileNameText = mediaURLCollection[indexPath.row].lastPathComponent
			let fileName = SwiftUtil.textToImage(drawText:fileNameText, inImage:imageCell, forReplyBubble:false)
			myImageView = UIImageView(image: fileName)
		}
		
		myImageView.size(w: (viewCell.frame.width * 0.9)-2, h: (viewCell.frame.height * 0.9)-2).done()
		viewCell.addSubview(myImageView)
		myImageView.alignParentBottom(withMargin: 4).alignParentLeft(withMargin: 4).done()
		
		if(FileType.init(mediaURLCollection[indexPath.row].pathExtension)?.getGroupTypeFromFile() == FileType.file_video_default.rawValue){
			var imagePlay = UIImage()
			if #available(iOS 13.0, *) {
				imagePlay = (UIImage(named: "vr_play")!.withTintColor(.white))
			} else {
				imagePlay = UIImage(named: "vr_play")!
			}
			let myImagePlayView = UIImageView(image: imagePlay)
			viewCell.addSubview(myImagePlayView)
			myImagePlayView.size(w: viewCell.frame.width/4, h: viewCell.frame.height/4).done()
			myImagePlayView.alignHorizontalCenterWith(viewCell).alignVerticalCenterWith(viewCell).done()
		}
		myImageView.contentMode = .scaleAspectFill
		myImageView.clipsToBounds = true

		viewCell.addSubview(deleteButton)
		deleteButton.alignParentRight().done()
		
		return cell
	}
	
	@available(iOS 14.0, *)
	func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
		initListMedia(sequenceCount: results.count)
		
		
		picker.dismiss(animated: true, completion: nil)
		let itemProviders = results.map(\.itemProvider)
		for item in itemProviders {
			if item.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
				progress.append(item.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { urlFile, error in
					if(self.workItem!.isCancelled){
						return
					} else {
						self.createCollectionViewItem(urlFile: urlFile, type: "public.image")
					}
				})
			}else if item.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
				progress.append(item.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { urlFile, error in
					if(self.workItem!.isCancelled){
						return
					} else {
						self.createCollectionViewItem(urlFile: urlFile, type: "public.movie")
					}
				})
			}
		}
	}
	
	func createCollectionViewItem(urlFile: URL?, type: String){
		if let url = urlFile {
			do {
				if(type == "public.image"){
					let dataResult = try Data(contentsOf: url)
					self.data.append(dataResult)
					if let image = UIImage(data: dataResult) {
						self.imageT.append(image)
					}else{
						self.imageT.append(UIImage(named: "chat_error"))
					}
				}else if(type == "public.movie"){
					self.data.append(try Data(contentsOf: url))
					var tmpImage = self.createThumbnailOfVideoFromFileURL(videoURL: url.relativeString)
					if tmpImage == nil { tmpImage = UIImage(named: "chat_error")}
					self.imageT.append(tmpImage)
				}else{
					
					self.data.append(try Data(contentsOf: url))
					let otherFile = FileType.init(url.pathExtension)
					let otherFileImage = otherFile!.getImageFromFile()
					self.imageT.append(otherFileImage)
				}
				self.urlFile.append(url)
				DispatchQueue.main.async(execute: self.workItem!)
			}catch let error{
				print(error.localizedDescription)
			}
		}
	}
	
	func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
	  picker.dismiss(animated: true, completion: nil)
	}
	
	func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
		initListMedia(sequenceCount: 1)
		let mediaType = info[UIImagePickerController.InfoKey.mediaType] as! String
		switch mediaType {
		case "public.image":
			let image = info[UIImagePickerController.InfoKey.originalImage] as! UIImage
			let date = Date()
			let df = DateFormatter()
			df.dateFormat = "yyyy-MM-dd-HHmmss"
			let dateString = df.string(from: date)
			
			let fileUrl = URL(string: dateString + ".jpeg")
			
			let data  = image.jpegData(compressionQuality: 1)
			
			self.data.append(data)
			if let image = UIImage(data: data!) {
				self.imageT.append(image)
			}else{
				self.imageT.append(UIImage(named: "chat_error"))
			}
			
			self.urlFile.append(fileUrl)
			DispatchQueue.main.async(execute: self.workItem!)
  		case "public.movie":
			let videoUrl = info[UIImagePickerController.InfoKey.mediaURL] as! URL
			
			self.createCollectionViewItem(urlFile: videoUrl, type: "public.movie")
		default:
			print("Mismatched type: \(mediaType)")
	  	}
	  	picker.dismiss(animated: true, completion: nil)
	}
	
	public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
		controller.dismiss(animated: true)
	}
	
	
	public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		initListMedia(sequenceCount: urls.count)
		
		if(controller.documentPickerMode == .import){
			urls.forEach { url in
				let imageExtension = ["png", "jpg", "jpeg", "bmp", "heic"]
				let videoExtension = ["mkv", "avi", "mov", "mp4"]
				if(imageExtension.contains(url.pathExtension.lowercased())){
					self.createCollectionViewItem(urlFile: url, type: "public.image")
				}else if(videoExtension.contains(url.pathExtension.lowercased())){
					self.createCollectionViewItem(urlFile: url, type: "public.movie")
				}else{
					self.createCollectionViewItem(urlFile: url, type: "public.data")
			   	}
			}
		}
		
		controller.dismiss(animated: true)
	}
	
	public func initListMedia(sequenceCount : Int){
		if(self.mediaCollectionView.count == 0 && sequenceCount >= 1){
			self.selectionMedia()
			self.messageView.sendButton.isEnabled = !messageView.isLoading
			self.messageView.fileContext = true
			self.urlFile = []
			self.imageT = []
			self.data = []
		}
		if(self.mediaCollectionView.count > 0){
			self.messageView.sendButton.isEnabled = !messageView.isLoading
		}
		
		if(sequenceCount >= 1){
			loadingView.isHidden = false
			messageView.isLoading = true
			loading.startRotation()
			
			self.messageView.sendButton.isEnabled = false
			self.messageView.pictureButton.isEnabled = false
			
			self.mediaCount = mediaCollectionView.count
			self.newMediaCount = sequenceCount
		}
	}
	
	func handlePendingTransferIfAny() {
		if (pendingForwardMessage != nil) {
			let message = pendingForwardMessage
			pendingForwardMessage = nil
			let d = UIConfirmationDialog.show(
				withMessage: NSLocalizedString("Transfer this message to this conversation ?", comment: ""),
				cancelMessage: nil,
				confirmMessage: NSLocalizedString("TRANSFER", comment: ""),
				onCancelClick: {
				},
				onConfirmationClick: {
					linphone_chat_message_send(linphone_chat_room_create_forward_message(self.chatRoom?.getCobject, message))

				})
			d?.forwardImage.isHidden = false
			d?.setSpecialColor()
		}
	}
	
	/*
	func closePendingReply() {
		if replyBubble != nil {
			showReplyView = false
			replyBubble!.view.removeFromSuperview()
			updateFramesInclRecordingAndReplyView()
			replyBubble = nil
		}
	}
  	*/
	
	@objc func initiateReplyView(forMessage: OpaquePointer?) {
		/*
		if replyBubble != nil {
			closePendingReply()
		}
		replyBubble = UIChatReplyBubbleView(nibName: "UIChatReplyBubbleView", bundle: nil)
		addChild(replyBubble)
		replyView.addSubview(replyBubble.view)
		replyBubble.didMove(toParent: self)
		replyBubble.configure(for: message, withDimissBlock: { [self] in
			closePendingReply()
		}, hideDismiss: false) {
		}
		showReplyView = true
		updateFramesInclRecordingAndReplyView()
		tableController.scroll(to: message?.getCobject)
		messageView.messageText.becomeFirstResponder()
		 */
		initReplyView()
	}
}