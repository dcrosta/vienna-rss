//
//  BrowserView.h
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

#import <Cocoa/Cocoa.h>
#import "BaseView.h"

@class BrowserTab;
@interface BrowserView : NSView
{
	BrowserTab * activeTab;
	NSMutableArray * allTabs;
	NSImage * closeButton;
	NSImage * highlightedCloseButton;
	NSImage * pressedCloseButton;
	NSSize closeButtonSize;
	BrowserTab * trackingTab;
	NSMutableDictionary * titleAttributes;
	NSColor * borderColor;
	NSColor * inactiveTabBackgroundColor;
}

// Accessors
-(BrowserTab *)setPrimaryTabView:(NSView *)newPrimaryView;
-(BrowserTab *)primaryTab;
-(BrowserTab *)activeTab;
-(void)setTabTitle:(BrowserTab *)tab title:(NSString *)newTitle;
-(NSView<BaseView> *)activeTabView;
-(NSView<BaseView> *)primaryTabView;
-(void)setActiveTabToPrimaryTab;
-(void)setActiveTab:(BrowserTab *)newActiveTab;
-(void)closeTab:(BrowserTab *)theTab;
-(void)closeAllTabs;
-(int)countOfTabs;
-(BrowserTab *)createNewTabWithView:(NSView<BaseView> *)newTabView makeKey:(BOOL)keyIt;
-(void)makeTabActive:(BrowserTab *)theTab;
-(void)showTab:(BrowserTab *)theTab;
-(void)showPreviousTab;
-(void)showNextTab;
-(void)saveOpenTabs;
@end
