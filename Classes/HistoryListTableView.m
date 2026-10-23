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

#import "HistoryListTableView.h"
#import "UIHistoryCell.h"
#import "LinphoneManager.h"
#import "PhoneMainView.h"
#import "Utils.h"
#import "linphoneapp-Swift.h"

@interface HistoryListTableView ()
@property(nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property(nonatomic, strong) UILabel *loadingLabel;
@property(nonatomic, assign) BOOL isLoading;
@property(nonatomic, assign) BOOL loadingOlder; // dms: one older page at a time
@end

@implementation HistoryListTableView

@synthesize missedFilter,confFilter;

#pragma mark - Lifecycle Functions

- (void)initHistoryTableViewController {
	missedFilter = false;
	confFilter = false;
}

- (id)init {
	self = [super init];
	if (self) {
		[self initHistoryTableViewController];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder {
	self = [super initWithCoder:decoder];
	if (self) {
		[self initHistoryTableViewController];
	}
	return self;
}

#pragma mark - ViewController Functions

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(loadData)
											   name:kLinphoneAddressBookUpdate
											 object:nil];

	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(loadData)
											   name:kLinphoneCallUpdate
											 object:nil];

	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(coreUpdateEvent:)
											   name:kLinphoneCoreUpdate
											 object:nil];
	// Il registro remoto è cambiato (es. nuova chiamata registrata): ricarica.
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(loadData)
											   name:@"BcsCallReportDidUpdate"
											 object:nil];
	// dms: while open, the call report follows the account registration (emptied when disabled, reloaded when enabled)
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(loadData)
											   name:kBcsRegisteredAccountChanged
											 object:nil];
	// dms: back to the foreground with the call report open: newest page read again (at most every 5 minutes)
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(applicationWillEnterForeground:)
											   name:UIApplicationWillEnterForegroundNotification
											 object:nil];
	// dms: on opening, the newest page is read again at most every 5 minutes (calls made or deleted from other
	// devices of the same user), otherwise the cache is shown without requests
	[self refreshIfOld:YES];
	NSDictionary* userInfo;
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector: @selector(receivePresenceNotification:)
											   name: @"LinphoneFriendPresenceUpdate"
											 object: userInfo];
}

-(void) receivePresenceNotification:(NSNotification*)notification
{
	if ([notification.name isEqualToString:@"LinphoneFriendPresenceUpdate"])
	{
		NSDictionary* userInfo = notification.userInfo;
		NSString* friend = (NSString*)userInfo[@"friend"];
		
		const MSList *list = linphone_core_get_call_logs(LC);
		int i = 0;
		while (list != NULL) {
			LinphoneCallLog *log = (LinphoneCallLog *)list->data;
			const char *curi = linphone_address_as_string_uri_only(linphone_call_log_get_remote_address(log));
			NSString *uri = [NSString stringWithUTF8String:curi];
			
			if([uri isEqual:friend]){
				NSIndexPath* indexPath = [NSIndexPath indexPathForRow:i inSection:0];
				NSArray* indexArray = [NSArray arrayWithObjects:indexPath, nil];
				[self.tableView reloadRowsAtIndexPaths:indexArray withRowAnimation:UITableViewRowAnimationFade];
			}
			i = i + 1;
			list = list->next;
		}
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];

	[NSNotificationCenter.defaultCenter removeObserver:self name:kLinphoneAddressBookUpdate object:nil];
	[NSNotificationCenter.defaultCenter removeObserver:self name:kLinphoneCoreUpdate object:nil];
	[NSNotificationCenter.defaultCenter removeObserver:self name:kLinphoneCallUpdate object:nil];
	[NSNotificationCenter.defaultCenter removeObserver:self name:@"BcsCallReportDidUpdate" object:nil];
	[NSNotificationCenter.defaultCenter removeObserver:self name:kBcsRegisteredAccountChanged object:nil];
	[NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"LinphoneFriendPresenceUpdate" object:nil];
    [AvatarBridge removeAllObserver];
}

#pragma mark - Event Functions

- (void)coreUpdateEvent:(NSNotification *)notif {
	@try {
		// Invalid all pointers
		[self loadData];
	}
	@catch (NSException *exception) {
		if ([exception.name isEqualToString:@"LinphoneCoreException"]) {
			LOGE(@"Core already destroyed");
			return;
		}
		LOGE(@"Uncaught exception : %@", exception.description);
		abort();
	}
}

#pragma mark - Property Functions

- (void)setMissedFilter:(BOOL)amissedFilter {
	if (missedFilter == amissedFilter) {
		return;
	}
	missedFilter = amissedFilter;
	if (missedFilter) {
		confFilter = false;
	}
	[self loadData];
}

- (void)setConfFilter:(BOOL)aconfFilter {
	if (confFilter == aconfFilter) {
		return;
	}
	confFilter = aconfFilter;
	if (confFilter) {
		missedFilter = false;
	}
	[self loadData];
}

- (void)removeFIlters {
	confFilter = false;
	missedFilter = false;
	[self loadData];
}


#pragma mark - UITableViewDataSource Functions

- (NSDate *)dateAtBeginningOfDayForDate:(NSDate *)inputDate {
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSTimeZone *timeZone = [NSTimeZone systemTimeZone];
	[calendar setTimeZone:timeZone];
	NSDateComponents *dateComps =
		[calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:inputDate];

	dateComps.hour = dateComps.minute = dateComps.second = 0;
	return [calendar dateFromComponents:dateComps];
}

// dms: rebuilt from the cache only (filters, call updates, contacts): no request. The newest page is read only
// when the cache does not belong to the registered account (first opening, account changed).
- (void)loadData {
	BcsCallReportManager *manager = [BcsCallReportManager shared];
	if (manager.isLoaded) {
		[self rebuildSectionsWithLogs:[manager cachedCallLogs]];
		return;
	}
	[self refreshIfOld:NO];
}

- (void)refreshIfOld:(BOOL)refreshIfOld {
	BcsCallReportManager *manager = [BcsCallReportManager shared];
	if (manager.isLoaded) {
		[self rebuildSectionsWithLogs:[manager cachedCallLogs]];
	} else if (LinphoneManager.instance.isBcsAccountRegistered) {
		[self showLoadingSpinner];
	}
	[manager refreshIfOld:refreshIfOld
			   completion:^(NSError *error) {
				 [self handleFetchResult:[manager cachedCallLogs] error:error];
			   }];
}

- (void)applicationWillEnterForeground:(NSNotification *)notif {
	[self refreshIfOld:YES];
}

// Gestione del risultato del fetch dal server: errore -> messaggio d'errore; altrimenti
// ricostruisce la lista (l'eventuale stato "vuoto" è gestito da rebuildSectionsWithLogs).
- (void)handleFetchResult:(NSArray<NSValue *> *)callLogs error:(NSError *)error {
	[self hideLoadingSpinner];
	if (error && callLogs.count == 0) {
		[self rebuildSectionsWithLogs:@[]];
		[self showStatusMessage:error.localizedDescription];
	} else {
		[self rebuildSectionsWithLogs:callLogs];
	}
}

- (void)ensureStatusViews {
	if (!self.loadingSpinner) {
		self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
		self.loadingSpinner.hidesWhenStopped = YES;
		[self.view addSubview:self.loadingSpinner];
	}
	if (!self.loadingLabel) {
		self.loadingLabel = [[UILabel alloc] init];
		self.loadingLabel.textAlignment = NSTextAlignmentCenter;
		self.loadingLabel.numberOfLines = 0;
		self.loadingLabel.textColor = [UIColor grayColor];
		self.loadingLabel.font = [UIFont systemFontOfSize:15];
		[self.view addSubview:self.loadingLabel];
	}
}

- (void)positionStatusViewsWithSpinner:(BOOL)withSpinner {
	CGPoint center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
	self.loadingSpinner.center = center;
	self.loadingLabel.frame = CGRectMake(0, 0, self.view.bounds.size.width - 40, 60);
	self.loadingLabel.center = withSpinner ? CGPointMake(center.x, center.y + 30) : center;
	[self.view bringSubviewToFront:self.loadingSpinner];
	[self.view bringSubviewToFront:self.loadingLabel];
}

// Usiamo una nostra label di stato (al posto dell'empty label della xib) così possiamo
// distinguere "caricamento", "vuoto" ed "errore" e mostrarli localizzati.
- (void)showLoadingSpinner {
	self.isLoading = YES;
	self.emptyView.hidden = YES;
	[self ensureStatusViews];
	self.loadingLabel.text = NSLocalizedString(@"Loading calls...", nil);
	[self positionStatusViewsWithSpinner:YES];
	[self.loadingSpinner startAnimating];
	self.loadingLabel.hidden = NO;
}

- (void)showStatusMessage:(NSString *)text {
	self.isLoading = NO;
	self.emptyView.hidden = YES;
	[self ensureStatusViews];
	[self.loadingSpinner stopAnimating];
	self.loadingLabel.text = text;
	[self positionStatusViewsWithSpinner:NO];
	self.loadingLabel.hidden = NO;
}

- (void)hideStatusMessage {
	self.isLoading = NO;
	[self.loadingSpinner stopAnimating];
	self.loadingLabel.hidden = YES;
}

- (void)hideLoadingSpinner {
	self.isLoading = NO;
	[self.loadingSpinner stopAnimating];
}

// Il controller base (UICheckBoxTableView) in viewDidAppear ri-mostra l'empty label della
// xib in base al numero di righe: la teniamo sempre nascosta perché gestiamo noi lo stato.
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	self.emptyView.hidden = YES;
}

- (void)rebuildSectionsWithLogs:(NSArray<NSValue *> *)callLogs {
	// Rilascia i ref UI dei log della ricostruzione precedente (può essere chiamata più
	// volte di seguito: cache + refresh dal server). Libera anche le liste dei duplicati
	// raggruppati conservate nel user_data.
	for (id day in self.sections.allKeys) {
		for (id log in self.sections[day]) {
			LinphoneCallLog *head = [log pointerValue];
			bctbx_list_t *grouped = linphone_call_log_get_user_data(head);
			for (bctbx_list_t *it = grouped; it != NULL; it = it->next) {
				linphone_call_log_unref((LinphoneCallLog *)it->data);
			}
			if (grouped) {
				bctbx_list_free(grouped);
				linphone_call_log_set_user_data(head, NULL);
			}
			linphone_call_log_unref(head);
		}
	}
	self.sections = [NSMutableDictionary dictionary];
	for (NSValue *value in callLogs) {
		LinphoneCallLog *log = (LinphoneCallLog *)[value pointerValue];
		if (log == NULL) {
			continue;
		}
		BOOL keepIt = (!missedFilter || [SwiftUtil isCallLogMissedWithCLog:log]) && (!confFilter||linphone_call_log_was_conference(log)) ;
		if (keepIt) {
			NSDate *startDate = [self
				dateAtBeginningOfDayForDate:[NSDate
												dateWithTimeIntervalSince1970:linphone_call_log_get_start_date(log)]];
			NSMutableArray *eventsOnThisDay = [self.sections objectForKey:startDate];
			if (eventsOnThisDay == nil) {
				eventsOnThisDay = [NSMutableArray array];
				[self.sections setObject:eventsOnThisDay forKey:startDate];
			}

			linphone_call_log_set_user_data(log, NULL);

			// if this contact was already the previous entry, do not add it twice
			LinphoneCallLog *prev = [eventsOnThisDay lastObject] ? [[eventsOnThisDay lastObject] pointerValue] : NULL;
			const LinphoneAddress *prevAddr = prev ? linphone_call_log_get_remote_address(prev) : NULL;
			const LinphoneAddress *logAddr = linphone_call_log_get_remote_address(log);
			if (!linphone_call_log_was_conference(log) && prev && prevAddr && logAddr &&
				linphone_address_weak_equal(prevAddr, logAddr)) {
				bctbx_list_t *list = linphone_call_log_get_user_data(prev);
				list = bctbx_list_append(list, linphone_call_log_ref(log));
				linphone_call_log_set_user_data(prev, list);
			} else {
				[eventsOnThisDay addObject:[NSValue valueWithPointer:linphone_call_log_ref(log)]];
			}
		}
	}

	[self computeSections];

	[super loadData];
	// Gestiamo noi lo stato vuoto (label localizzata) al posto dell'empty label della xib.
	self.emptyView.hidden = YES;
	if (!self.isLoading) {
		if (_sortedDays.count == 0) {
			[self showStatusMessage:NSLocalizedString(@"No call in your history", nil)];
		} else {
			[self hideStatusMessage];
		}
	}

	if (IPAD) {
		if (![self selectFirstRow]) {
			HistoryDetailsView *view = VIEW(HistoryDetailsView);
			[view setCallLogId:nil];
		}
	}
}

- (void)computeSections {
	NSArray *unsortedDays = [self.sections allKeys];
	_sortedDays = [[NSMutableArray alloc]
		initWithArray:[unsortedDays sortedArrayUsingComparator:^NSComparisonResult(NSDate *d1, NSDate *d2) {
		  return [d2 compare:d1]; // reverse order
		}]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return _sortedDays.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSArray *logs = [_sections objectForKey:_sortedDays[section]];
	return logs.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	CGRect frame = CGRectMake(0, 0, tableView.frame.size.width, 44);
	UIView *tempView = [[UIView alloc] initWithFrame:frame];
	if (@available(iOS 13, *)) {
		tempView.backgroundColor = [UIColor systemBackgroundColor];
	} else {
		tempView.backgroundColor = [UIColor whiteColor];
	}

	UILabel *tempLabel = [[UILabel alloc] initWithFrame:frame];
	tempLabel.backgroundColor = [UIColor clearColor];
	tempLabel.textColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"color_A.png"]];
	NSDate *eventDate = _sortedDays[section];
	NSDate *currentDate = [self dateAtBeginningOfDayForDate:[NSDate date]];
	if ([eventDate isEqualToDate:currentDate]) {
		tempLabel.text = NSLocalizedString(@"TODAY", nil);
	} else if ([eventDate isEqualToDate:[currentDate dateByAddingTimeInterval:-3600 * 24]]) {
		tempLabel.text = NSLocalizedString(@"YESTERDAY", nil);
	} else {
		tempLabel.text = [LinphoneUtils timeToString:eventDate.timeIntervalSince1970 withFormat:LinphoneDateHistoryList]
							 .uppercaseString;
	}
	tempLabel.textAlignment = NSTextAlignmentCenter;
	tempLabel.font = [UIFont boldSystemFontOfSize:17];
	tempLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[tempView addSubview:tempLabel];

	return tempView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *kCellId = @"UIHistoryCell";
	UIHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId];
	if (cell == nil) {
		cell = [[UIHistoryCell alloc] initWithIdentifier:kCellId];
	}

	id logId = [_sections objectForKey:_sortedDays[indexPath.section]][indexPath.row];
	LinphoneCallLog *log = [logId pointerValue];
	[cell setCallLog:log];
	[super accessoryForCell:cell atPath:indexPath];
	cell.contentView.userInteractionEnabled = false;
	return cell;
}

#pragma mark - UITableViewDelegate Functions

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[super tableView:tableView didSelectRowAtIndexPath:indexPath];
	if (![self isEditing]) {
		id log = [_sections objectForKey:_sortedDays[indexPath.section]][indexPath.row];
		LinphoneCallLog *callLog = [log pointerValue];
		if (callLog != NULL) {
			if (IPAD) {
				UIHistoryCell *cell = (UIHistoryCell *)[self tableView:tableView cellForRowAtIndexPath:indexPath];
				[cell onDetails:self];
			} else {
				if (linphone_call_log_was_conference(callLog)) {
					LinphoneConferenceInfo *confInfo = linphone_call_log_get_conference_info(callLog);
					if (linphone_conference_info_get_state(confInfo) == LinphoneConferenceInfoStateCancelled) {
						[ConferenceViewModelBridge showCancelledMeetingWithCConferenceInfo:confInfo];
						return;
					}
					ConferenceWaitingRoomView *view = VIEW(ConferenceWaitingRoomView);
					[view setDetailsWithSubject:[NSString stringWithUTF8String:linphone_conference_info_get_subject(confInfo)] url:[NSString stringWithUTF8String:linphone_address_as_string(linphone_conference_info_get_uri(confInfo))] conferenceInfo:(confInfo)];
					[PhoneMainView.instance changeCurrentView:ConferenceWaitingRoomView.compositeViewDescription];
				} else {
					// Come Android: il tap su una voce apre il dettaglio (non avvia la
					// chiamata). La chiamata si avvia dal dettaglio.
					[tableView deselectRowAtIndexPath:indexPath animated:NO];
					HistoryDetailsView *view = VIEW(HistoryDetailsView);
					[view setCallLog:callLog];
					[PhoneMainView.instance changeCurrentView:HistoryDetailsView.compositeViewDescription];
				}
			}
		}
	}
}

// dms: single entries are not deleted (only "Delete all", as on Android): no swipe / selection delete
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return NO;
}

// dms: older calls loaded while scrolling, when about 10 rows are left; the rows already shown stay still (same
// call log instances, only the group across two pages changes)
- (void)tableView:(UITableView *)tableView
	  willDisplayCell:(UITableViewCell *)cell
	forRowAtIndexPath:(NSIndexPath *)indexPath {
	BcsCallReportManager *manager = [BcsCallReportManager shared];
	if (!manager.hasOlder || _loadingOlder) {
		return;
	}
	NSInteger remaining = 0;
	for (NSInteger section = indexPath.section; section < (NSInteger)_sortedDays.count; section++) {
		remaining += [self tableView:tableView numberOfRowsInSection:section];
	}
	remaining -= indexPath.row + 1;
	if (remaining > 10) {
		return;
	}
	_loadingOlder = YES;
	[manager loadOlderWithCompletion:^(BOOL added) {
	  self->_loadingOlder = NO;
	  if (added) {
		  [self rebuildSectionsWithLogs:[manager cachedCallLogs]];
	  }
	}];
}

@end
