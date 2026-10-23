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

#import "HistoryDetailsTableView.h"
#import "LinphoneManager.h"
#import "Utils.h"
#import "linphoneapp-Swift.h"

@implementation HistoryDetailsTableView

- (void)loadDataForAddress:(const LinphoneAddress *)peer {
	if (callLogs == nil) {
		callLogs = [[NSMutableArray alloc] init];
	} else {
		[callLogs removeAllObjects];
	}

	if (peer) {
		LinphoneAccount *acc = linphone_core_get_default_account(LC);
		if (acc) {
			const bctbx_list_t *logs = linphone_account_get_call_logs_for_address(acc, peer);
			while (logs != NULL) {
				LinphoneCallLog *log = (LinphoneCallLog *)logs->data;
				if (linphone_address_weak_equal(linphone_call_log_get_remote_address(log), peer)) {
					[callLogs addObject:[NSValue valueWithPointer:log]];
				}
				logs = bctbx_list_next(logs);
			}
		}
	}
	[[self tableView] reloadData];
}

- (void)loadDataForCallLog:(LinphoneCallLog *)log {
	if (callLogs == nil) {
		callLogs = [[NSMutableArray alloc] init];
	} else {
		[callLogs removeAllObjects];
	}
	if (log != NULL) {
		// Voce "testa" del gruppo + tutte le chiamate consecutive raggruppate (conservate
		// nel user_data del log), così il dettaglio le mostra tutte come Android.
		[callLogs addObject:[NSValue valueWithPointer:log]];
		MSList *grouped = linphone_call_log_get_user_data(log);
		while (grouped) {
			[callLogs addObject:[NSValue valueWithPointer:(LinphoneCallLog *)grouped->data]];
			grouped = grouped->next;
		}
	}
	[[self tableView] reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [callLogs count];
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
	tempLabel.textColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"color_E.png"]];
	tempLabel.text = NSLocalizedString(@"Calls", nil);
	tempLabel.textAlignment = NSTextAlignmentCenter;
	tempLabel.font = [UIFont boldSystemFontOfSize:17];
	tempLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[tempView addSubview:tempLabel];

	return tempView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *kCellId = @"UITableViewCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] init];
	}

	LinphoneCallLog *log = [[callLogs objectAtIndex:[indexPath row]] pointerValue];
	int duration = linphone_call_log_get_duration(log);
	time_t callTime = linphone_call_log_get_start_date(log);
	BOOL outgoing = (linphone_call_log_get_dir(log) == LinphoneCallOutgoing);
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	// dms: "ven 23 ott, 16:11 · 1 min 5 s": duration with its units, the outcome instead of a zero duration
	NSString *date = [LinphoneUtils timeToString:callTime withFormat:LinphoneDateHistoryDetails];
	NSString *detail = (duration > 0) ? [LinphoneUtils durationToText:duration] : [self outcomeOfCallLog:log outgoing:outgoing];
	cell.textLabel.text = detail ? [NSString stringWithFormat:@"%@ · %@", date, detail] : date;

	if ([SwiftUtil isCallLogMissedWithCLog:log]) {
		cell.imageView.image = [UIImage imageNamed:@"call_missed.png"];
	} else if (outgoing) {
		cell.imageView.image = [UIImage imageNamed:@"call_outgoing.png"];
	} else {
		cell.imageView.image = [UIImage imageNamed:@"call_incoming.png"];
	}
	cell.contentView.userInteractionEnabled =  false;

	return cell;
}

// dms: outcome of a call without duration, nil for a successful one
- (NSString *)outcomeOfCallLog:(LinphoneCallLog *)log outgoing:(BOOL)outgoing {
	if ([SwiftUtil isCallLogMissedWithCLog:log])
		return NSLocalizedString(@"Missed", nil);
	switch (linphone_call_log_get_status(log)) {
		case LinphoneCallDeclined:
			return NSLocalizedString(@"Declined", nil);
		case LinphoneCallAborted:
		case LinphoneCallEarlyAborted:
		case LinphoneCallMissed:
			return outgoing ? NSLocalizedString(@"No answer", nil) : NSLocalizedString(@"Missed", nil);
		case LinphoneCallAcceptedElsewhere:
			return NSLocalizedString(@"Answered elsewhere", nil);
		case LinphoneCallDeclinedElsewhere:
			return NSLocalizedString(@"Declined elsewhere", nil);
		default:
			return nil;
	}
}

@end
