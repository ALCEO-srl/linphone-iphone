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
	// All'ingresso forziamo sempre un refresh dal server (multi-dispositivo).
	[self refreshFromServer];
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

// Ricostruzione "leggera": usa la cache se valida (es. notifiche interne), altrimenti
// scarica dal server con spinner.
- (void)loadData {
	NSArray<NSValue *> *cached = [[BcsCallReportManager shared] cachedCallLogs];
	if (cached != nil) {
		[self rebuildSectionsWithLogs:cached];
		return;
	}

	[self showLoadingSpinner];
	[[BcsCallReportManager shared] fetchCallLogsWithCompletion:^(NSArray<NSValue *> *callLogs, NSError *error) {
		[self handleFetchResult:callLogs error:error];
	}];
}

// Come Android: a ogni ingresso nella view forziamo un refresh dal server, perché
// l'utente può aver effettuato chiamate da altri dispositivi registrati. Mostriamo
// intanto la cache (se presente) per evitare il flicker, poi aggiorniamo con i dati
// freschi del server.
- (void)refreshFromServer {
	NSArray<NSValue *> *cached = [[BcsCallReportManager shared] cachedCallLogs];
	if (cached != nil) {
		[self rebuildSectionsWithLogs:cached];
	} else {
		[self showLoadingSpinner];
	}
	[[BcsCallReportManager shared] fetchCallLogsWithCompletion:^(NSArray<NSValue *> *callLogs, NSError *error) {
		[self handleFetchResult:callLogs error:error];
	}];
}

// Gestione del risultato del fetch dal server: errore -> messaggio d'errore; altrimenti
// ricostruisce la lista (l'eventuale stato "vuoto" è gestito da rebuildSectionsWithLogs).
- (void)handleFetchResult:(NSArray<NSValue *> *)callLogs error:(NSError *)error {
	[self hideLoadingSpinner];
	if (error) {
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

// Cancella una voce (e le eventuali duplicate raggruppate) dal registro remoto BCS,
// usando l'Id BCS conservato nel refKey del LinphoneCallLog sintetico.
- (void)deleteCallLogEntryOnServer:(LinphoneCallLog *)callLog {
	if (callLog == NULL) {
		return;
	}
	const char *refKey = linphone_call_log_get_ref_key(callLog);
	if (refKey != NULL) {
		NSString *itemId = [NSString stringWithUTF8String:refKey];
		[[BcsCallReportManager shared] deleteEntryWithItemId:itemId
												  completion:^(NSError *error) {
			if (error) {
				LOGE(@"[BcsCallReport] delete entry failed: %@", error.localizedDescription);
			}
		}];
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

- (void)tableView:(UITableView *)tableView
	commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
	 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		[tableView beginUpdates];
		id log = [_sections objectForKey:_sortedDays[indexPath.section]][indexPath.row];
		LinphoneCallLog *callLog = [log pointerValue];
		MSList *count = linphone_call_log_get_user_data(callLog);
		while (count) {
			[self deleteCallLogEntryOnServer:(LinphoneCallLog *)count->data];
			count = count->next;
		}
		[self deleteCallLogEntryOnServer:callLog];
		linphone_call_log_unref(callLog);
		[[_sections objectForKey:_sortedDays[indexPath.section]] removeObject:log];
		if (((NSArray *)[_sections objectForKey:_sortedDays[indexPath.section]]).count == 0) {
			[_sections removeObjectForKey:_sortedDays[indexPath.section]];
			[_sortedDays removeObjectAtIndex:indexPath.section];
			[tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section]
					 withRowAnimation:UITableViewRowAnimationFade];
		}

		[tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
						 withRowAnimation:UITableViewRowAnimationFade];
		[tableView endUpdates];
	}
}

- (void)removeSelectionUsing:(void (^)(NSIndexPath *))remover {
	[super removeSelectionUsing:^(NSIndexPath *indexPath) {
	  id log = [_sections objectForKey:_sortedDays[indexPath.section]][indexPath.row];
	  LinphoneCallLog *callLog = [log pointerValue];
	  MSList *count = linphone_call_log_get_user_data(callLog);
	  while (count) {
		  [self deleteCallLogEntryOnServer:(LinphoneCallLog *)count->data];
		  count = count->next;
	  }
	  [self deleteCallLogEntryOnServer:callLog];
	  linphone_call_log_unref(callLog);
	  [[_sections objectForKey:_sortedDays[indexPath.section]] removeObject:log];
	  if (((NSArray *)[_sections objectForKey:_sortedDays[indexPath.section]]).count == 0) {
		  [_sections removeObjectForKey:_sortedDays[indexPath.section]];
		  [_sortedDays removeObjectAtIndex:indexPath.section];
	  }
	}];
}

@end
