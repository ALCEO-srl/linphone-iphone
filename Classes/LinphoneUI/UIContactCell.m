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

#import "UIContactCell.h"
#import "ContactsListTableView.h"
#import "FastAddressBook.h"
#import "PhoneMainView.h"
#import "UILabel+Boldify.h"
#import "Utils.h"

@implementation UIContactCell

#pragma mark - Lifecycle Functions

- (id)initWithIdentifier:(NSString *)identifier {
	if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier]) != nil) {
		NSArray *arrayOfViews =
			[[NSBundle mainBundle] loadNibNamed:NSStringFromClass(self.class) owner:self options:nil];

		// resize cell to match .nib size. It is needed when resized the cell to
		// correctly adapt its height too
		UIView *sub = ((UIView *)[arrayOfViews objectAtIndex:0]);
		[self setFrame:CGRectMake(0, 0, sub.frame.size.width, sub.frame.size.height)];
		[self addSubview:sub];
		_contact = NULL;
		// Sections are wider on iPad and overlap linphone image - let's move it a bit
		if (IPAD) {
			CGRect frame = _linphoneImage.frame;
			frame.origin.x -= frame.size.width / 2;
			_linphoneImage.frame = frame;
		}

		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(onPresenceForUriOrTelChanged:)
												   name:kLinphoneNotifyPresenceReceivedForUriOrTel
												 object:nil];
        //dms
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(onPresenceChanged:)
                                                   name:kLinphoneNotifyPresenceReceived
                                                 object:nil];
    }
	return self;
}

- (void)dealloc {
	self.contact = NULL;
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Notif

//
- (void)onPresenceForUriOrTelChanged:(NSNotification *)k {
    LinphoneFriend *f = [[k.userInfo valueForKey:@"friend"] pointerValue];
    // only consider event if it's about us when not in ContactsListView
    if (_contact && (PhoneMainView.instance.currentView == ContactsListView.compositeViewDescription || _nameLabel.text == PhoneMainView.instance.currentName)) {
        if (!_contact.friend || f != _contact.friend) {
            return;
        }
        [self setContact:_contact];
    }
}

#pragma mark - Property Functions

//dms ********************
- (void)onPresenceChanged:(NSNotification *)k {
    LinphoneFriend *f = [[k.userInfo valueForKey:@"friend"] pointerValue];
    
    NSLog(@"####################  onPresenceChanged track=1");
    // only consider event if it's about us when not in ContactsListView
    if (_contact && (PhoneMainView.instance.currentView == ContactsListView.compositeViewDescription || _nameLabel.text == PhoneMainView.instance.currentName)) {
        if (!_contact.friend || f != _contact.friend) {
            return;
        }
        NSLog(@"#################### onPresenceChanged track=2");
        [self setContact:_contact];
    }
}


- (NSString *) getPresenceIconAsString:(LinphonePresenceModel *) presenceModel {
    
    
    LinphonePresenceBasicStatus basicStatus = linphone_presence_model_get_basic_status(presenceModel);
    LinphonePresenceActivity *activity = nil; //linphone_presence_model_get_activity(presenceModel);
    
    NSMutableSet *activityTypesSet = [NSMutableSet set];
    
    unsigned int count =  linphone_presence_model_get_nb_activities(presenceModel);
    
    for (int i = 0; i < count; i++) {
      activity = linphone_presence_model_get_nth_activity(presenceModel, i);
      LinphonePresenceActivityType activityType = linphone_presence_activity_get_type(activity);
        
      [activityTypesSet addObject:@(activityType)];
        
    }
    LINPHONE_PUBLIC LinphonePresenceActivity *linphone_presence_model_get_nth_activity(const LinphonePresenceModel *model,
                                                                                       unsigned int index);
    
    if (basicStatus == LinphonePresenceBasicStatusOpen) {
        if (count == 0) {
            NSLog(@"######### getPresenceIconAsString On-Line");
            return @"contact_presence_open";
        } else {
            LinphonePresenceActivityType activityType = linphone_presence_activity_get_type(activity);
                       
            switch (activityType) {
                case LinphonePresenceActivityBusy:{
                    LinphonePresenceActivityType typeToCheck = LinphonePresenceActivityAppointment;
                    if ([activityTypesSet containsObject:@(typeToCheck)])
                        return @"contact_presence_closed_appointment";
                    else
                      return @"contact_presence_closed_busy";
                }
                case LinphonePresenceActivityAway:
                    return @"contact_presence_open_away";
                case LinphonePresenceActivityOnThePhone:
                    return @"contact_presence_open_onthephone";
                case LinphonePresenceActivityAppointment:{
                    LinphonePresenceActivityType typeToCheck = LinphonePresenceActivityBusy;
                    if ([activityTypesSet containsObject:@(typeToCheck)])
                        return @"contact_presence_closed_appointment";
                    else
                        return @"contact_presence_open_appointment";
                }
                    
                default:
                    return @"contact_presence_open";
            }
        }
    } else {
        NSLog(@"######### getPresenceIconAsString Off-Line");
        
        if (!activity) {
            NSLog(@"######### getPresenceIconAsString On-Line");
            return @"contact_presence_closed";
        } else {
            LinphonePresenceActivityType activityType = linphone_presence_activity_get_type(activity);
                       
            switch (activityType) {
                case LinphonePresenceActivityBusy:
                    return @"contact_presence_closed_busy";
                    
                case LinphonePresenceActivityOther: {
                    const char * desc = linphone_presence_activity_get_description(activity);
                   
                    if (strstr(desc, "out-of-office")) return @"contact_presence_open_outofoffice";
                    else return @"contact_presence_closed";
                }
                 case LinphonePresenceActivityAppointment:
                    return @"contact_presence_closed_appointment";
                default:
                    return @"contact_presence_closed";
            }
        }
        
    }
}
//dms ********************

- (void)setContact:(Contact *)acontact {
	_contact = acontact;
	_linphoneImage.hidden = FALSE; //dms
    
    UIImage *image = [UIImage imageNamed:@"presence_offline"];
    
    _linphoneImage.image = image;
    
	if(_contact) {
		[ContactDisplay setDisplayNameLabel:_nameLabel forContact:_contact];
		_organizationLabel.text = [FastAddressBook ogrganizationForContact:_contact];
        
        const LinphonePresenceModel *presenceModel = linphone_friend_get_presence_model(_contact.friend);
        if (presenceModel) _linphoneImage.image = [UIImage imageNamed: [self getPresenceIconAsString: presenceModel]];
	}
}

#pragma mark -

- (void)touchUp:(id)sender {
	[self setHighlighted:true animated:true];
}

- (void)touchDown:(id)sender {
	[self setHighlighted:false animated:true];
}

- (NSString *)accessibilityLabel {
	return _nameLabel.text;
}

- (void)setEditing:(BOOL)editing {
	[self setEditing:editing animated:FALSE];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
	if (animated) {
		[UIView beginAnimations:nil context:nil];
		[UIView setAnimationDuration:0.3];
	}
	_linphoneImage.alpha = editing ? 0 : 1;
	if (animated) {
		[UIView commitAnimations];
	}
}

@end
