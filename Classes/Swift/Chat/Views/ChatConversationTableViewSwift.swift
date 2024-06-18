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
import QuickLook
import SwipeCellKit

class ChatConversationTableViewSwift: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, QLPreviewControllerDelegate, QLPreviewControllerDataSource, SwipeCollectionViewCellDelegate {
	
	static let compositeDescription = UICompositeViewDescription(ChatConversationTableViewSwift.self, statusBar: StatusBarView.self, tabBar: nil, sideMenu: SideMenuView.self, fullscreen: false, isLeftFragment: false,fragmentWith: nil)
	
	static func compositeViewDescription() -> UICompositeViewDescription! { return compositeDescription }
	
	func compositeViewDescription() -> UICompositeViewDescription! { return type(of: self).compositeDescription }
	
	lazy var collectionView: UICollectionView = {
		let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
		return collectionView
	}()
	
	var menu: DropDown? = nil
	
	var basic :Bool = false
	
	var floatingScrollButton : UIButton?
	var scrollBadge : UILabel?
	var floatingScrollBackground : UIButton?
	
	var previewItems : [QLPreviewItem?] = []
	var afterPreviewIndex = -1
	
	override func viewDidLoad() {
		super.viewDidLoad()
		

		self.initView()
		
		UIDeviceBridge.displayModeSwitched.readCurrentAndObserve { _ in
			self.collectionView.backgroundColor = VoipTheme.backgroundWhiteBlack.get()
			self.collectionView.reloadData()
		}
        
        ChatConversationTableViewModel.sharedModel.refreshIndexPath.observe { index in
            self.collectionView.reloadData()
        }
		
		ChatConversationTableViewModel.sharedModel.onClickIndexPath.observe { index in
			self.onGridClick(indexMessage: ChatConversationTableViewModel.sharedModel.onClickMessageIndexPath, index: index!)
		}
		
		ChatConversationTableViewModel.sharedModel.editModeOn.observe { mode in
			self.collectionView.reloadData()
		}
		
		collectionView.isUserInteractionEnabled = true
		collectionView.keyboardDismissMode = .interactive
	}
	
	deinit {
		 NotificationCenter.default.removeObserver(self)
	}
	
	func initView(){
		basic = isBasicChatRoom(ChatConversationTableViewModel.sharedModel.chatRoom?.getCobject)
		
		view.addSubview(collectionView)
		collectionView.contentInsetAdjustmentBehavior = .always
		collectionView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
		
		collectionView.translatesAutoresizingMaskIntoConstraints = false
		collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
		collectionView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
		collectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
		collectionView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 0).isActive = true
		
		collectionView.dataSource = self
		collectionView.delegate = self
		collectionView.register(MultilineMessageCell.self, forCellWithReuseIdentifier: MultilineMessageCell.reuseId)
		
		(collectionView.collectionViewLayout as! UICollectionViewFlowLayout).estimatedItemSize = UICollectionViewFlowLayout.automaticSize
		(collectionView.collectionViewLayout as! UICollectionViewFlowLayout).minimumLineSpacing = 2
		
		collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)
	}
	
	override func viewDidAppear(_ animated: Bool) {
		createFloatingButton()
		if ChatConversationTableViewModel.sharedModel.getNBMessages() > 0 {
			scrollToBottom(animated: false)
		}
		
		NotificationCenter.default.addObserver(self, selector: #selector(self.receivePresenceNotification(notification:)), name: Notification.Name("LinphoneFriendPresenceUpdate"), object: nil)
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		if ChatConversationTableViewModel.sharedModel.getNBMessages() > 0 {
			scrollToBottom(animated: false, async:false)
		}
		NotificationCenter.default.removeObserver(self, name: Notification.Name("LinphoneFriendPresenceUpdate"), object: nil)
		NotificationCenter.default.removeObserver(self)
	}
	
	@objc func receivePresenceNotification(notification: NSNotification) {
		if (notification.name.rawValue == "LinphoneFriendPresenceUpdate"){
			collectionView.reloadData()
		}
 	}
    
    func scrollToMessage(message: ChatMessage){
        let messageIndex = ChatConversationTableViewModel.sharedModel.getIndexMessage(message: message)
        self.collectionView.scrollToItem(at: IndexPath(row: messageIndex, section: 0), at: .bottom, animated: false)
    }
	
	func scrollToBottom(animated: Bool, async: Bool = true){
		if (async) {
			DispatchQueue.main.async{
				self.collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: animated)
			}
		} else {
			self.collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: animated)
		}
		ChatConversationViewSwift.markAsRead(ChatConversationViewModel.sharedModel.chatRoom?.getCobject)
		if self.floatingScrollButton != nil && self.floatingScrollBackground != nil {
			self.floatingScrollButton!.isHidden = true
   			self.floatingScrollBackground!.isHidden = true
		}
		if scrollBadge != nil {
			scrollBadge!.text = "0"
		}
	}
	
	func refreshDataAfterForeground(){
		DispatchQueue.main.async {
			self.collectionView.reloadData()
		}
	}
	
	func refreshData(isOutgoing: Bool){
		if (ChatConversationTableViewModel.sharedModel.getNBMessages() > 1){
			let isDisplayingBottomOfTable = collectionView.contentOffset.y <= 20

			if  ChatConversationTableViewModel.sharedModel.getNBMessages() < 4 {
                collectionView.reloadData()
                ChatConversationViewSwift.markAsRead(ChatConversationViewModel.sharedModel.chatRoom?.getCobject)
			} else if isDisplayingBottomOfTable {
				if self.collectionView.numberOfItems(inSection: 0) > 2 {
					self.collectionView.scrollToItem(at: IndexPath(item: 1, section: 0), at: .top, animated: false)
				}
                collectionView.reloadData()
                self.scrollToBottom(animated: true)
			} else if !isOutgoing {
				if !collectionView.indexPathsForVisibleItems.isEmpty {
					let selectedCellIndex = collectionView.indexPathsForVisibleItems.sorted().first!
					let selectedCell = collectionView.cellForItem(at: selectedCellIndex)
					let visibleRect = collectionView.convert(collectionView.bounds, to: selectedCell)
					
					UIView.performWithoutAnimation {
						collectionView.reloadData()
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
							let newSelectedCell = self.collectionView.cellForItem(at: IndexPath(row: selectedCellIndex.row + 1, section: 0))
							let updatedVisibleRect = self.collectionView.convert(self.collectionView.bounds, to: newSelectedCell)

							var contentOffset = self.collectionView.contentOffset
							contentOffset.y = contentOffset.y + (visibleRect.origin.y - updatedVisibleRect.origin.y)
							self.collectionView.contentOffset = contentOffset
						}
					}
					scrollBadge!.isHidden = false
					scrollBadge!.text = "\(ChatConversationViewModel.sharedModel.chatRoom?.unreadMessagesCount ?? 0)"
				}
			} else {
                collectionView.reloadData()
                self.scrollToBottom(animated: false)
			}
			
			if ChatConversationTableViewModel.sharedModel.editModeOn.value! {
				ChatConversationTableViewModel.sharedModel.messageListSelected.value!.insert(false, at: 0)
			}
		}else{
			collectionView.reloadData()
			if(ChatConversationViewModel.sharedModel.chatRoom != nil){
				ChatConversationViewSwift.markAsRead(ChatConversationViewModel.sharedModel.chatRoom?.getCobject)
			}
		}
	}
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let contentOffsetY = scrollView.contentOffset.y
        if contentOffsetY <= 20{
			if floatingScrollButton != nil && floatingScrollBackground != nil {
				floatingScrollButton?.isHidden = true
				floatingScrollBackground?.isHidden = true
				scrollBadge?.text = "0"
				ChatConversationViewSwift.markAsRead(ChatConversationViewModel.sharedModel.chatRoom?.getCobject)
			}
        } else {
			if floatingScrollButton != nil && floatingScrollBackground != nil {
				floatingScrollButton?.isHidden = false
				floatingScrollBackground?.isHidden = false;
				if(scrollBadge?.text ==  "0"){
					scrollBadge?.isHidden = true
				}
			}
        }
    }
	
	// MARK: - UICollectionViewDataSource -
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MultilineMessageCell.reuseId, for: indexPath) as! MultilineMessageCell
		cell.delegate = self
		if let event = ChatConversationTableViewModel.sharedModel.getMessage(index: indexPath.row){
			if(ChatConversationTableViewModel.sharedModel.editModeOn.value! && indexPath.row >= ChatConversationTableViewModel.sharedModel.messageListSelected.value!.count){
				for _ in ChatConversationTableViewModel.sharedModel.messageListSelected.value!.count...indexPath.row {
					ChatConversationTableViewModel.sharedModel.messageListSelected.value!.append(false)
				}
			}
			
			cell.configure(event: event, selfIndexPathConfigure: indexPath, editMode: ChatConversationTableViewModel.sharedModel.editModeOn.value!, selected: ChatConversationTableViewModel.sharedModel.editModeOn.value! ? ChatConversationTableViewModel.sharedModel.messageListSelected.value![indexPath.row] : false)
			
			if (event.chatMessage != nil && ChatConversationViewModel.sharedModel.chatRoom != nil){
				cell.onLongClickOneClick {
					if(cell.chatMessage != nil && ChatConversationViewModel.sharedModel.chatRoom != nil){
						self.initDataSource(message: cell.chatMessage!)
						self.tapChooseMenuItemMessage(contentViewBubble: cell.contentViewBubble, event: cell.eventMessage!, preContentSize: cell.preContentViewBubble.frame.size.height)
					}
				}
			}
			
			if (!cell.replyContent.isHidden && event.chatMessage?.replyMessage != nil){
				cell.replyContent.onClick {
					self.scrollToMessage(message: (cell.chatMessage?.replyMessage)!)
				}
			}
			
			cell.imageViewBubble.onClick {
				if (!cell.imageViewBubble.isHidden || !cell.imageVideoViewBubble.isHidden) && cell.chatMessage != nil && !cell.chatMessage!.isFileTransferInProgress {
					self.onImageClick(chatMessage: cell.chatMessage!, index: indexPath.row)
				}
			}
			cell.imageVideoViewBubble.onClick {
				if (!cell.imageViewBubble.isHidden || !cell.imageVideoViewBubble.isHidden) && cell.chatMessage != nil && !cell.chatMessage!.isFileTransferInProgress {
					self.onImageClick(chatMessage: cell.chatMessage!, index: indexPath.row)
				}
			}
		}
		cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
		return cell
	}
	
	func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
		let customCell = cell as! MultilineMessageCell
		
		if customCell.isPlayingVoiceRecording {
			AudioPlayer.stopSharedPlayer()
		}
		
		if customCell.ephemeralTimer != nil {
			customCell.ephemeralTimer?.invalidate()
		}
		
		if customCell.chatMessageDelegate != nil {
			customCell.chatMessage?.removeDelegate(delegate: customCell.chatMessageDelegate!)
		}
	}
	
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return ChatConversationTableViewModel.sharedModel.getNBMessages()
	}
	
	func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
		let message = ChatConversationTableViewModel.sharedModel.getMessage(index: indexPath.row)
		if orientation == .left {
			if message?.chatMessage != nil {
				let replyAction = SwipeAction(style: .default, title: "Reply") { action, indexPath in
					self.replyMessage(message: (message?.chatMessage)!)
				}
				return [replyAction]
			} else {
				return nil
			}
		} else {
			let deleteAction = SwipeAction(style: .destructive, title: "Delete") { action, indexPath in
				self.deleteMessage(message: message!)
			}
			return [deleteAction]
		}
	}
	
	func collectionView(_ collectionView: UICollectionView, editActionsOptionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> SwipeOptions {
		var options = SwipeOptions()
		if orientation == .left {
			options.expansionStyle = .selection
		}
		return options
	}
	
	func isBasicChatRoom(_ room: OpaquePointer?) -> Bool {
		if room == nil {
			return true
		}
		
		let charRoomBasic = ChatRoom.getSwiftObject(cObject: room!)
		let isBasic = charRoomBasic.hasCapability(mask: Int(LinphoneChatRoomCapabilitiesBasic.rawValue))
		return isBasic
	}
	
    func tapChooseMenuItemMessage(contentViewBubble: UIView, event: EventLog, preContentSize: CGFloat) {
        

	}
	
    func initDataSource(message: ChatMessage) {

	}
    
    func resendMessage(message: ChatMessage){
        if ((linphone_core_is_network_reachable(LinphoneManager.getLc()) == 0)) {
            PhoneMainView.instance().present(LinphoneUtils.networkErrorView("send a message"), animated: true)
            return;
        }else{
            message.send()
        }
    }
    
    func copyMessage(message: ChatMessage){
        UIPasteboard.general.string = message.utf8Text
    }
    
    func forwardMessage(message: ChatMessage){
        let view: ChatConversationViewSwift = self.VIEW(ChatConversationViewSwift.compositeViewDescription())
        view.pendingForwardMessage = message.getCobject
        let viewtoGo: ChatsListView = self.VIEW(ChatsListView.compositeViewDescription())
        PhoneMainView.instance().changeCurrentView(viewtoGo.compositeViewDescription())
    }
    
    func replyMessage(message: ChatMessage){
        let view: ChatConversationViewSwift = self.VIEW(ChatConversationViewSwift.compositeViewDescription())
		if (view.contentMessageView.messageView.messageText.textColor == UIColor.lightGray && view.contentMessageView.stackView.arrangedSubviews[3].isHidden && view.contentMessageView.stackView.arrangedSubviews[4].isHidden){
			view.contentMessageView.messageView.messageText.becomeFirstResponder()
		}
        view.initiateReplyView(forMessage: message.getCobject)
    }
    
    func infoMessage(event: EventLog){
        let view: ChatConversationImdnView = self.VIEW(ChatConversationImdnView.compositeViewDescription())
		view.event = event.getCobject
        PhoneMainView.instance().changeCurrentView(view.compositeViewDescription())
    }
    
    func addToContacts(message: ChatMessage) {
        let addr = message.fromAddress
        addr?.clean()
        if let lAddress = addr?.asStringUriOnly() {
            var normSip = String(utf8String: lAddress)
            normSip = normSip?.hasPrefix("sip:") ?? false ? (normSip as NSString?)?.substring(from: 4) : normSip
            normSip = normSip?.hasPrefix("sips:") ?? false ? (normSip as NSString?)?.substring(from: 5) : normSip
            ContactSelection.setAddAddress(normSip)
            ContactSelection.setSelectionMode(ContactSelectionModeEdit)
            ContactSelection.enableSipFilter(false)
            PhoneMainView.instance().changeCurrentView(ContactsListView.compositeViewDescription())
        }
    }
	
	func deleteMessage(message: EventLog){
		let messageChat = message.chatMessage
		if messageChat != nil {
			if ChatConversationTableViewModel.sharedModel.editModeOn.value! {
				let indexDeletedMessage = ChatConversationTableViewModel.sharedModel.getIndexMessage(message: messageChat!)
				ChatConversationTableViewModel.sharedModel.messageListSelected.value!.remove(at: indexDeletedMessage)
				ChatConversationTableViewModel.sharedModel.messageSelected.value! -= 1
			}
			let chatRoom = ChatConversationViewModel.sharedModel.chatRoom
			if chatRoom != nil {
				chatRoom!.deleteMessage(message: messageChat!)
			}
		} else {
			message.deleteFromDatabase()
		}
		collectionView.reloadData()
	}
	
	func getPreviewItem(filePath: String) -> NSURL{
		let url = NSURL(fileURLWithPath: filePath)
		
		return url
	}
	
	func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
		return previewItems.count
	}
	
	func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
		return (previewItems[index] as QLPreviewItem?)!
	}
	
	func previewControllerDidDismiss(_ controller: QLPreviewController) {
		collectionView.scrollToItem(at: IndexPath(item: afterPreviewIndex, section: 0), at: .centeredVertically, animated: false)
		afterPreviewIndex = -1
	}
	
	func onImageClick(chatMessage: ChatMessage, index: Int) {

		let state = chatMessage.state
		if (state.rawValue == LinphoneChatMessageStateNotDelivered.rawValue) {
			Log.i("Messsage not delivered")
		} else {
			if (VFSUtil.vfsEnabled(groupName: kLinphoneMsgNotificationAppGroupId) || ConfigManager.instance().lpConfigBoolForKey(key: "use_in_app_file_viewer_for_non_encrypted_files", section: "app")){
				
				var viewer: MediaViewer = VIEW(MediaViewer.compositeViewDescription())
				
				var image = UIImage()
				if chatMessage.contents.filter({$0.isFile}).first!.type == "image" {
					if VFSUtil.vfsEnabled(groupName: kLinphoneMsgNotificationAppGroupId) {
						var plainFile = chatMessage.contents.filter({$0.isFile}).first!.exportPlainFile()
						
						image = UIImage(contentsOfFile: plainFile)!
						
						ChatConversationViewModel.sharedModel.removeTmpFile(filePath: plainFile)
						plainFile = ""
						
					}else {
						image = UIImage(contentsOfFile: chatMessage.contents.filter({$0.isFile}).first!.filePath!)!
					}
				}
				
				viewer.imageViewer = image
				viewer.imageNameViewer = (chatMessage.contents.filter({$0.isFile}).first!.name!.isEmpty ? "" : chatMessage.contents.filter({$0.isFile}).first!.name)!
				
				viewer.imagePathViewer = chatMessage.contents.filter({$0.isFile}).first!.exportPlainFile()
				viewer.contentType = chatMessage.contents.filter({$0.isFile}).first!.type
				PhoneMainView.instance().changeCurrentView(viewer.compositeViewDescription())

			} else {
				let previewController = QLPreviewController()
				self.previewItems = []
				
				if VFSUtil.vfsEnabled(groupName: kLinphoneMsgNotificationAppGroupId) {
					var plainFile = chatMessage.contents.filter({$0.isFile}).first?.exportPlainFile()
					
					self.previewItems.append(self.getPreviewItem(filePath: plainFile!))
					
					ChatConversationViewModel.sharedModel.removeTmpFile(filePath: plainFile)
					plainFile = ""
				}else if chatMessage.contents.filter({$0.isFile}).first?.filePath != nil {
					self.previewItems.append(self.getPreviewItem(filePath: (chatMessage.contents.filter({$0.isFile}).first?.filePath)!))
				}
				
				afterPreviewIndex = index
				
				previewController.currentPreviewItemIndex = 0
				previewController.dataSource = self
				previewController.delegate = self
				previewController.reloadData()
				PhoneMainView.instance().mainViewController.present(previewController, animated: true, completion: nil)
			}
		}
	}
	
	func onGridClick(indexMessage: Int, index: Int) {
		let chatMessage = ChatConversationTableViewModel.sharedModel.getMessage(index: indexMessage)?.chatMessage
		let state = chatMessage!.state
		if (state.rawValue == LinphoneChatMessageStateNotDelivered.rawValue) {
			Log.i("Messsage not delivered")
		} else {
			if (VFSUtil.vfsEnabled(groupName: kLinphoneMsgNotificationAppGroupId) || ConfigManager.instance().lpConfigBoolForKey(key: "use_in_app_file_viewer_for_non_encrypted_files", section: "app")){
				
				var text = ""
				var filePathString = VFSUtil.vfsEnabled(groupName: kLinphoneMsgNotificationAppGroupId) ? chatMessage!.contents.filter({$0.isFile})[index].exportPlainFile() : chatMessage!.contents.filter({$0.isFile})[index].filePath
				if let urlEncoded = filePathString!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed){
					if !urlEncoded.isEmpty {
						if let urlFile = URL(string: "file://" + urlEncoded){
							do {
								text = try String(contentsOf: urlFile, encoding: .utf8)
								let viewer: TextViewer = VIEW(TextViewer.compositeViewDescription())
								
								if chatMessage != nil {
									
									viewer.textViewer = text
									viewer.textNameViewer = (chatMessage!.contents.filter({$0.isFile})[index].name!.isEmpty ? "" : chatMessage!.contents.filter({$0.isFile})[index].name)!
									PhoneMainView.instance().changeCurrentView(viewer.compositeViewDescription())
								}

							} catch {
								var extensionFile = ""
								if chatMessage!.contents.filter({$0.isFile})[index].name != nil {
									extensionFile = chatMessage!.contents.filter({$0.isFile})[index].name!.lowercased().components(separatedBy: ".").last ?? ""
								}
								
								if text == "" && (chatMessage!.contents.filter({$0.isFile})[index].type == "image" || chatMessage!.contents.filter({$0.isFile})[index].type == "video" || chatMessage!.contents.filter({$0.isFile})[index].name!.lowercased().components(separatedBy: ".").last == "pdf" || (["mkv", "avi", "mov", "mp4"].contains(extensionFile))){
									let viewer: MediaViewer = VIEW(MediaViewer.compositeViewDescription())
									
									var image = UIImage()
									if chatMessage != nil {
										if chatMessage!.contents.filter({$0.isFile})[index].type == "image" {
											if VFSUtil.vfsEnabled(groupName: kLinphoneMsgNotificationAppGroupId) {
												var plainFile = chatMessage!.contents.filter({$0.isFile})[index].exportPlainFile()
												
												image = UIImage(contentsOfFile: plainFile)!
												
												ChatConversationViewModel.sharedModel.removeTmpFile(filePath: plainFile)
												plainFile = ""
												
											}else {
												image = UIImage(contentsOfFile: chatMessage!.contents.filter({$0.isFile})[index].filePath!)!
											}
										}
										
										viewer.imageViewer = image
										viewer.imageNameViewer = (chatMessage!.contents.filter({$0.isFile})[index].name!.isEmpty ? "" : chatMessage!.contents.filter({$0.isFile})[index].name)!
										viewer.imagePathViewer = chatMessage!.contents.filter({$0.isFile})[index].exportPlainFile()
										viewer.contentType = chatMessage!.contents.filter({$0.isFile})[index].type
										PhoneMainView.instance().changeCurrentView(viewer.compositeViewDescription())
									}
								} else {
									let exportView = UIAlertController(
										title: VoipTexts.chat_message_cant_open_file_in_app_dialog_title,
										message: VoipTexts.chat_message_cant_open_file_in_app_dialog_message,
										preferredStyle: .alert)
									
									let cancelAction = UIAlertAction(
										title: VoipTexts.cancel,
										style: .default,
										handler: { action in
										})
									
									let exportAction = UIAlertAction(
										title: VoipTexts.chat_message_cant_open_file_in_app_dialog_export_button,
										style: .destructive,
										handler: { action in
											let previewController = QLPreviewController()
											self.previewItems = []
											
											self.previewItems.append(self.getPreviewItem(filePath: filePathString!))
											
											
											self.afterPreviewIndex = indexMessage
											
											previewController.dataSource = self
											previewController.currentPreviewItemIndex = index
											previewController.delegate = self
											PhoneMainView.instance().mainViewController.present(previewController, animated: true, completion: nil)
										})

									exportView.addAction(cancelAction)
									exportView.addAction(exportAction)
									PhoneMainView.instance()!.present(exportView, animated: true)
								}
							}
						}
					}
				}
				/*
				if VFSUtil.vfsEnabled(groupName: kLinphoneMsgNotificationAppGroupId) {
					ChatConversationViewModel.sharedModel.removeTmpFile(filePath: filePathString)
					filePathString = ""
				}
				 */
			} else {
				let previewController = QLPreviewController()
				self.previewItems = []
				chatMessage?.contents.forEach({ content in
					if(content.isFile && !content.isVoiceRecording){
						if VFSUtil.vfsEnabled(groupName: kLinphoneMsgNotificationAppGroupId) {
							var plainFile = content.exportPlainFile()
							
							self.previewItems.append(self.getPreviewItem(filePath: plainFile))
							
							ChatConversationViewModel.sharedModel.removeTmpFile(filePath: plainFile)
							plainFile = ""
							
						}else {
							self.previewItems.append(self.getPreviewItem(filePath: (content.filePath!)))
						}
					}
				})
				
				afterPreviewIndex = indexMessage
				
				previewController.dataSource = self
				previewController.currentPreviewItemIndex = index
				previewController.delegate = self
				PhoneMainView.instance().mainViewController.present(previewController, animated: true, completion: nil)
			}
		}
	}
}
