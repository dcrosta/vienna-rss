//
//  BrowserView.m
//  Vienna
//
//  Created by Steve on 8/26/05.
//  Copyright (c) 2004-2005 Steve Palmer. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "BrowserView.h"
#import "Preferences.h"
#import "Constants.h"
#import <PSMTabBarControl/PSMTabBarControl.h>

@interface NSTabView (BrowserViewAdditions)
- (NSTabViewItem *)tabViewItemWithIdentifier:(id)identifier;
@end

@implementation NSTabView (BrowserViewAdditions)
- (NSTabViewItem *)tabViewItemWithIdentifier:(id)identifier
{
	int i = [self indexOfTabViewItemWithIdentifier:identifier];
	return (i != NSNotFound ? [self tabViewItemAtIndex:i] : nil);
}
@end

@implementation BrowserView

- (void)awakeFromNib
{
	//Remove the junk tab view item that we start with, since IB won't let us have no items initially
	[tabView removeTabViewItem:[tabView tabViewItemAtIndex:0]];
}

/* stringForToolTip
 * Returns the tooltip for the tab specified by the userData object. This is the tab's full title which
 * may have been truncated for display.
//XXX Not being used...
 */
-(NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)userData
{
	return [[tabView tabViewItemWithIdentifier:(NSView *)userData] label];
}

/* setPrimaryTabItemView
 * Sets the primary tab view. This is the view that is always displayed and
 * occupies the first tab position.
 */
-(void)setPrimaryTabItemView:(NSView *)newPrimaryTabItemView
{
	//Remove the old one if there is one
	if ([tabView tabViewItemWithIdentifier:primaryTabItemView]) {
		[tabView removeTabViewItem:[tabView tabViewItemWithIdentifier:primaryTabItemView]];
	}
	[primaryTabItemView release];

	[self createNewTabWithView:newPrimaryTabItemView makeKey:YES];
	primaryTabItemView = [newPrimaryTabItemView retain];
}

/* activeTabItemView
 * Returns the view associated with the active tab.
 */
-(NSView<BaseView> *)activeTabItemView
{
	return [[tabView selectedTabViewItem] identifier];
}

/* setActiveTabToPrimaryTab
 * Make the primary tab the active tab.
 */
-(void)setActiveTabToPrimaryTab
{
	[self showTabItemView:primaryTabItemView];
}

/* primaryTabItemView
 * Return the primary tab view.
 */
-(NSView<BaseView> *)primaryTabItemView
{
	return primaryTabItemView;
}

/* createNewTabWithView
 * Create a new tab with the specified view. If makeKey is YES then the new tab is
 * made active, otherwise the current tab stays active.
 */
-(void)createNewTabWithView:(NSView<BaseView> *)newTabView makeKey:(BOOL)keyIt
{
	NSTabViewItem *tabViewItem = [[NSTabViewItem alloc] initWithIdentifier:newTabView];
	[tabViewItem setView:newTabView];
	[tabView addTabViewItem:tabViewItem];
	[tabViewItem release];

	if (keyIt) [self showTabItemView:newTabView];
}

/* setTabTitle
 * Sets the title of the specified tab then redraws the tab bar.
 */
-(void)setTabItemViewTitle:(NSView *)inTabView title:(NSString *)newTitle
{
	[[tabView tabViewItemWithIdentifier:inTabView] setLabel:newTitle];
}

/* tabTitle
 * Returns the title of the specified tab. May be an empty string.
 */
-(NSString *)tabItemViewTitle:(NSView *)tabItemView
{
	return [[tabView tabViewItemWithIdentifier:tabItemView] label];
}

/* closeAllTabs
 * Close all tabs.
 */
-(void)closeAllTabs
{
	int count = [tabView numberOfTabViewItems];
	int i;
	for ((i = (count - 1)); i > 0; i--) {
		[tabView removeTabViewItem:[tabView tabViewItemAtIndex:i]];
	}
}

/* closeTab
 * Close the specified tab unless it is the primary tab, in which case
 * we do nothing.
 */
-(void)closeTabItemView:(NSView *)tabItemView
{
	if (tabItemView != primaryTabItemView) {
		[tabView removeTabViewItem:[tabView tabViewItemWithIdentifier:tabItemView]];
	}
}

/* countOfTabs
 * Returns the total number of tabs.
 */
-(int)countOfTabs
{
	return [tabView numberOfTabViewItems];
}

/* showTabVew
 * Makes the specified tab active if not already and post a notification.
 */
-(void)showTabItemView:(NSView *)theTabView
{
	if ([tabView tabViewItemWithIdentifier:theTabView]) {
		[tabView selectTabViewItemWithIdentifier:theTabView];
	}
}

/* showPreviousTab
 * Switch to the previous tab in the view order. Wrap round to the end
 * if we're at the beginning.
 */
-(void)showPreviousTab
{
	[tabView selectPreviousTabViewItem:self];
}

/* showNextTab
 * Switch to the next tab in the tab order. Wrap round to the beginning
 * if we're at the end.
 */
-(void)showNextTab
{
	[tabView selectNextTabViewItem:self];
}

- (void)tabView:(NSTabView *)inTabView didSelectTabViewItem:(NSTabViewItem *)inTabViewItem
{
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_TabChanged" object:[inTabViewItem identifier]];	
}

/* saveOpenTabs
 * Persist the URLs of each open tab to the preferences so they can be
 * restored when we reload.
 */
-(void)saveOpenTabs
{
	NSMutableArray *tabLinks = [[NSMutableArray alloc] initWithCapacity:[self countOfTabs]];
	NSEnumerator *enumerator = [[tabView tabViewItems] objectEnumerator];
	NSTabViewItem *tabViewItem;
	
	while ((tabViewItem = [enumerator nextObject])) {
		NSView<BaseView> * theView = [tabViewItem identifier];
		NSString * tabLink = [theView viewLink];
		if (tabLink != nil)
			[tabLinks addObject:tabLink];			
	}

	[[Preferences standardPreferences] setObject:tabLinks forKey:MAPref_TabList];
	[tabLinks release];

	[[Preferences standardPreferences] savePreferences];
}

/* dealloc
 * Clean up behind ourselves.
 */
-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[super dealloc];
}
@end
