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

#import "SideMenuView.h"
#import "LinphoneManager.h"
#import "PhoneMainView.h"
#import "StatusBarView.h"

@implementation SideMenuView

- (void)viewDidLoad {
	[super viewDidLoad];

#pragma deploymate push "ignored-api-availability"
	if (UIDevice.currentDevice.systemVersion.doubleValue >= 7) {
		// it's better to detect only pan from screen edges
		UIScreenEdgePanGestureRecognizer *pan =
			[[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(onLateralSwipe:)];
		pan.edges = UIRectEdgeRight;
		[self.view addGestureRecognizer:pan];
		_swipeGestureRecognizer.enabled = NO;
	}
#pragma deploymate pop

	// dms: account switch on the right of the header, the registration LED just on its left
	_accountSwitch = [[UISwitch alloc] init];
	_accountSwitch.onTintColor = LINPHONE_MAIN_COLOR;
	_accountSwitch.accessibilityLabel = NSLocalizedString(@"Account enabled", nil);
	[_accountSwitch addTarget:self action:@selector(onAccountSwitch:) forControlEvents:UIControlEventValueChanged];
	[_nameLabel.superview addSubview:_accountSwitch];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutHeader];
}

// dms: header laid out in code (the xibs use fixed frames): switch on the right and vertically centered, LED on its
// left, name and address ending before the LED. Without default account the header is hidden and the menu starts at the top.
- (void)layoutHeader {
	UIView *header = _nameLabel.superview;
	UITableView *table = _sideMenuTableViewController.tableView;
	if (!header || !table) return;

	BOOL hasDefault = [LinphoneManager isLcInitialized] && linphone_core_get_default_account(LC) != NULL;
	header.hidden = !hasDefault;
	CGFloat tableTop = hasDefault ? CGRectGetMaxY(header.frame) : header.frame.origin.y;
	CGRect tableFrame = table.frame;
	CGFloat bottom = CGRectGetMaxY(tableFrame);
	tableFrame.origin.y = tableTop;
	tableFrame.size.height = bottom - tableTop;
	table.frame = tableFrame;
	if (!hasDefault) return;

	CGFloat margin = 10;
	CGSize switchSize = _accountSwitch.intrinsicContentSize;
	CGFloat height = header.bounds.size.height;
	_accountSwitch.frame = CGRectMake(header.bounds.size.width - margin - switchSize.width,
									  (height - switchSize.height) / 2, switchSize.width, switchSize.height);
	CGRect led = _presenceImage.frame;
	led.origin.x = _accountSwitch.frame.origin.x - 5 - led.size.width;
	led.origin.y = (height - led.size.height) / 2;
	_presenceImage.frame = led;
	for (UILabel *label in @[ _nameLabel, _addressLabel ]) {
		CGRect frame = label.frame;
		frame.size.width = MAX(0, led.origin.x - 4 - frame.origin.x);
		label.frame = frame;
	}
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[_sideMenuTableViewController viewWillAppear:animated];
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(registrationUpdateEvent:)
											   name:kLinphoneRegistrationUpdate
											 object:nil];

	[self updateHeader];
	[_sideMenuTableViewController.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	_grayBackground.hidden = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	// dms: the observer is added on every viewWillAppear, remove it so that it does not pile up
	[NSNotificationCenter.defaultCenter removeObserver:self name:kLinphoneRegistrationUpdate object:nil];
	_grayBackground.hidden = YES;
	// should be better than that with alpha animation..
}

- (void)updateHeader {
	LinphoneAccount *default_account = linphone_core_get_default_account(LC);

	if (default_account != NULL) {
		const LinphoneAddress *addr = linphone_account_params_get_identity_address(linphone_account_get_params(default_account));
		[ContactDisplay setDisplayNameLabel:_nameLabel forAddress:addr];
		char *str = addr ? linphone_address_as_string(addr) : nil;
		_addressLabel.text = str ? [NSString stringWithUTF8String:str] : NSLocalizedString(@"No address", nil);
		if (str) ms_free(str);
		// dms: LED from the real registration state (it was always green), switch from registerEnabled
		_presenceImage.image = [StatusBarView imageForState:linphone_account_get_state(default_account)];
		_accountSwitch.on = linphone_account_params_register_enabled(linphone_account_get_params(default_account));
	} else {
		MSList *accounts = [LinphoneManager.instance createAccountsNotHiddenList];
		_nameLabel.text = accounts ? NSLocalizedString(@"No default account", nil) : NSLocalizedString(@"No account", nil);
		bctbx_free(accounts);
		// display direct IP:port address so that we can be reached
		LinphoneAddress *addr = linphone_core_get_primary_contact_parsed(LC);
		if (addr) {
			char *as_string = linphone_address_as_string(addr);
			_addressLabel.text = [NSString stringWithFormat:@"%s", as_string];
			ms_free(as_string);
			linphone_address_unref(addr);
		} else {
			_addressLabel.text = NSLocalizedString(@"No address", nil);
		}
		_presenceImage.image = nil;
	}
	_avatarImage.image = [LinphoneUtils selfAvatar];
	[self.view setNeedsLayout]; // dms: header shown / hidden with the default account
}

// dms: enabling is immediate; when disabling the switch stays off while the confirmation is shown,
// "Cancel" turns it back on, "Disable" leaves it off (as in the account settings)
- (void)onAccountSwitch:(UISwitch *)sender {
	LinphoneAccount *account = linphone_core_get_default_account(LC);
	if (!account) return;
	if (sender.on) {
		[LinphoneManager.instance setAccount:account registerEnabled:YES];
		return;
	}
	[LinphoneManager.instance confirmDisableAccountWithCompletion:^(BOOL confirmed) {
	  if (!confirmed) {
		  [sender setOn:YES animated:YES];
		  return;
	  }
	  LinphoneAccount *current = linphone_core_get_default_account(LC);
	  if (!current) return;
	  [LinphoneManager.instance setAccount:current registerEnabled:NO];
	  // dms: the registration state may not change (account not registered), update the switch anyway
	  [self updateHeader];
	}];
}

#pragma deploymate push "ignored-api-availability"
- (void)onLateralSwipe:(UIScreenEdgePanGestureRecognizer *)pan {
	[PhoneMainView.instance.mainViewController hideSideMenu:YES];
}
#pragma deploymate pop

- (IBAction)onHeaderClick:(id)sender {
	// dms: the account in the header opens its own settings, not the settings list
	SettingsView *view = VIEW(SettingsView);
	view.openDefaultAccount = YES;
	[PhoneMainView.instance changeCurrentView:SettingsView.compositeViewDescription];
	[PhoneMainView.instance.mainViewController hideSideMenu:YES];
}

- (IBAction)onAvatarClick:(id)sender {
	// Cambio avatar dalla galleria disabilitato: il tap sull'avatar apre le impostazioni
	// account, come il tap sul nome (onHeaderClick).
	[self onHeaderClick:sender];
}

- (IBAction)onBackgroundClicked:(id)sender {
	[PhoneMainView.instance.mainViewController hideSideMenu:YES];
}

- (void)registrationUpdateEvent:(NSNotification *)notif {
	[self updateHeader];
	// dms: an account added or removed changes the entries (assistant only without account)
	[_sideMenuTableViewController updateEntries];
	[_sideMenuTableViewController.tableView reloadData];
}

#pragma mark - Image picker delegate

- (void)imagePickerDelegateImage:(UIImage *)image info:(NSString *)phAssetId {
	// When getting image from the camera, it may be 90° rotated due to orientation
	// (image.imageOrientation = UIImageOrientationRight). Just rotate it to be face up.
	if (image.imageOrientation != UIImageOrientationUp) {
		UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale);
		[image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
		image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	}
    
    [LinphoneManager.instance lpConfigSetString:phAssetId forKey:@"avatar"];
    _avatarImage.image = [LinphoneUtils selfAvatar];
    [LinphoneManager.instance loadAvatar];

	// Dismiss popover on iPad
	if (IPAD) {
		[VIEW(ImagePickerView).popoverController dismissPopoverAnimated:TRUE];
	} else {
		[PhoneMainView.instance.mainViewController hideSideMenu:NO];
	}
}

- (void)imagePickerDelegateVideo:(NSURL*)url info:(NSDictionary *)info {
	return; // Avatar video not supported (yet ;) )
}

@end
