//
//  ViennaApp.m
//  Vienna
//
//  Created by Steve on Tue Jul 06 2004.
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

#import "ViennaApp.h"
#import "AppController.h"
#import "Import.h"
#import "Export.h"
#import "PreferenceNames.h"
#import "FoldersTree.h"

@implementation ViennaApp

/* handleRefreshAllSubscriptions
 * Refreshes all folders.
 */
-(id)handleRefreshAllSubscriptions:(NSScriptCommand *)cmd
{
	[[self delegate] refreshAllSubscriptions:nil];
	return nil;
}

/* handleRefreshSubscription
 * Refreshes a specific folder.
 */
-(id)handleRefreshSubscription:(NSScriptCommand *)cmd
{
	NSDictionary * args = [cmd evaluatedArguments];
	Folder * folder = [args objectForKey:@"Folder"];
	if (folder != nil)
		[[self delegate] refreshSubscriptions:[NSArray arrayWithObject:folder]];
	return nil;
}

/* handleMarkAllRead
 * Mark all messages in the specified folder as read
 */
-(id)handleMarkAllRead:(NSScriptCommand *)cmd
{
	NSDictionary * args = [cmd evaluatedArguments];
	Folder * folder = [args objectForKey:@"Folder"];
	if (folder != nil)
		[[self delegate] markAllReadInArray:[NSArray arrayWithObject:folder]];
	return nil;
}

/* handleImportSubscriptions
 * Import subscriptions from a file.
 */
-(id)handleImportSubscriptions:(NSScriptCommand *)cmd
{
	NSDictionary * args = [cmd evaluatedArguments];
	[[self delegate] importFromFile:[args objectForKey:@"FileName"]];
	return nil;
}

/* handleExportSubscriptions
 * Export all or specified folders to a file.
 */
-(id)handleExportSubscriptions:(NSScriptCommand *)cmd
{
	NSDictionary * args = [cmd evaluatedArguments];
	Folder * folder = [args objectForKey:@"Folder"];
	
	// If no folder is specified, default to exporting everything.
	NSArray * array = (folder ? [NSArray arrayWithObject:folder] : [self folders]);
	[[self delegate] exportToFile:[args objectForKey:@"FileName"] from:array];
	return nil;
}

/* applicationVersion
 * Return the applications version number.
 */
-(NSString *)applicationVersion
{
	NSBundle * appBundle = [NSBundle mainBundle];
	NSDictionary * fileAttributes = [appBundle infoDictionary];
	return [fileAttributes objectForKey:@"CFBundleShortVersionString"];
}

/* folders
 * Return a flat array of all folders
 */
-(NSArray *)folders
{
	return [[self delegate] folders];
}

/* folderListFont
 * Retrieve the name of the font used in the folder list
 */
-(NSString *)folderListFont
{
	NSData * fontData = [[NSUserDefaults standardUserDefaults] objectForKey:MAPref_FolderFont];
	NSFont * font = [NSUnarchiver unarchiveObjectWithData:fontData];
	return [font fontName];
}

/* folderListFontSize
 * Retrieve the size of the font used in the folder list
 */
-(int)folderListFontSize
{
	NSData * fontData = [[NSUserDefaults standardUserDefaults] objectForKey:MAPref_FolderFont];
	NSFont * font = [NSUnarchiver unarchiveObjectWithData:fontData];
	return [font pointSize];
}

/* setFolderListFont
 * Retrieve the name of the font used in the folder list
 */
-(void)setFolderListFont:(NSString *)newFontName
{
	NSFont * fldrFont = [NSFont fontWithName:newFontName size:[self folderListFontSize]];
	[[NSUserDefaults standardUserDefaults] setObject:[NSArchiver archivedDataWithRootObject:fldrFont] forKey:MAPref_FolderFont];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_FolderFontChange" object:fldrFont];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_PreferencesUpdated" object:nil];
}

/* setFolderListFontSize
 * Changes the size of the font used in the folder list.
 */
-(void)setFolderListFontSize:(int)newFontSize
{
	NSFont * fldrFont = [NSFont fontWithName:[self folderListFont] size:newFontSize];
	[[NSUserDefaults standardUserDefaults] setObject:[NSArchiver archivedDataWithRootObject:fldrFont] forKey:MAPref_FolderFont];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_FolderFontChange" object:fldrFont];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_PreferencesUpdated" object:nil];
}

/* articleListFont
 * Retrieve the name of the font used in the article list
 */
-(NSString *)articleListFont
{
	NSData * fontData = [[NSUserDefaults standardUserDefaults] objectForKey:MAPref_MessageListFont];
	NSFont * font = [NSUnarchiver unarchiveObjectWithData:fontData];
	return [font fontName];
}

/* articleListFontSize
 * Retrieve the size of the font used in the article list
 */
-(int)articleListFontSize
{
	NSData * fontData = [[NSUserDefaults standardUserDefaults] objectForKey:MAPref_MessageListFont];
	NSFont * font = [NSUnarchiver unarchiveObjectWithData:fontData];
	return [font pointSize];
}

/* setArticleListFont
 * Retrieve the name of the font used in the article list
 */
-(void)setArticleListFont:(NSString *)newFontName
{
	NSFont * fldrFont = [NSFont fontWithName:newFontName size:[self articleListFontSize]];
	[[NSUserDefaults standardUserDefaults] setObject:[NSArchiver archivedDataWithRootObject:fldrFont] forKey:MAPref_MessageListFont];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_MessageListFontChange" object:fldrFont];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_PreferencesUpdated" object:nil];
}

/* setArticleListFontSize
 * Changes the size of the font used in the article list.
 */
-(void)setArticleListFontSize:(int)newFontSize
{
	NSFont * fldrFont = [NSFont fontWithName:[self articleListFont] size:newFontSize];
	[[NSUserDefaults standardUserDefaults] setObject:[NSArchiver archivedDataWithRootObject:fldrFont] forKey:MAPref_MessageListFont];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_MessageListFontChange" object:fldrFont];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_PreferencesUpdated" object:nil];
}

/* isRefreshing
 * Return whether or not Vienna is in the process of connecting.
 */
-(BOOL)isRefreshing
{
	return [[self delegate] isConnecting];
}

/* unreadCount
 * Return the number of unread messages.
 */
-(int)unreadCount
{
	Database * db = [[self delegate] database];
	return [db countOfUnread];
}

/* displayStyle
 * Retrieves the name of the current article display style.
 */
-(NSString *)displayStyle
{
	return [[NSUserDefaults standardUserDefaults] valueForKey:MAPref_ActiveStyleName];
}

/* setDisplayStyle
 * Changes the style used for displaying articles
 */
-(void)setDisplayStyle:(NSString *)newStyleName
{
	[[self delegate] setActiveStyle:newStyleName refresh:YES];
}

/* checkForNewOnStartup
 * Returns whether or not Vienna checks for new versions when it starts.
 */
-(BOOL)checkForNewOnStartup
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:MAPref_CheckForUpdatesOnStartup];
}

/* setCheckForNewOnStartup
 * Changes whether or not Vienna checks for new versions when it starts.
 */
-(void)setCheckForNewOnStartup:(BOOL)flag
{
	[self internalChangeCheckOnStartup:flag];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_PreferencesUpdated" object:nil];
}

/* internalChangeCheckOnStartup
 * Changes whether or not Vienna checks for new versions when it starts.
 */
-(void)internalChangeCheckOnStartup:(BOOL)flag
{
	NSNumber * boolFlag = [NSNumber numberWithBool:flag];
	[[NSUserDefaults standardUserDefaults] setObject:boolFlag forKey:MAPref_CheckForUpdatesOnStartup];
}

/* refreshOnStartup
 * Returns whether or not Vienna refreshes all subscriptions when it starts.
 */
-(BOOL)refreshOnStartup
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:MAPref_CheckForNewMessagesOnStartup];
}

/* setRefreshOnStartup
 * Changes whether or not Vienna refreshes all subscriptions when it starts.
 */
-(void)setRefreshOnStartup:(BOOL)flag
{
	[self internalChangeRefreshOnStartup:flag];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_PreferencesUpdated" object:nil];
}

/* internalChangeRefreshOnStartup
 * Changes whether or not Vienna refreshes all subscriptions when it starts.
 */
-(void)internalChangeRefreshOnStartup:(BOOL)flag
{
	NSNumber * boolFlag = [NSNumber numberWithBool:flag];
	[[NSUserDefaults standardUserDefaults] setObject:boolFlag forKey:MAPref_CheckForNewMessagesOnStartup];
}

/* currentFolder
 * Retrieves the current folder
 */
-(Folder *)currentFolder
{
	Database * db = [[self delegate] database];
	return [db folderFromID:[[self delegate] currentFolderId]];
}

/* readingPaneOnRight
 * Returns whether the reading pane is on the right or at the bottom of the article list.
 */
-(BOOL)readingPaneOnRight
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:MAPref_ReadingPaneOnRight];
}

/* setReadingPaneOnRight
 * Changes where the reading pane appears relative to the article list.
 */
-(void)setReadingPaneOnRight:(BOOL)flag
{
	[[self delegate] setReadingPaneOnRight:flag];
}

/* refreshFrequency
 * Return the frequency with which we refresh all subscriptions
 */
-(int)refreshFrequency
{
	return [[NSUserDefaults standardUserDefaults] integerForKey:MAPref_CheckFrequency];
}

/* setRefreshFrequency
 * Updates the refresh frequency and then updates the preferences.
 */
-(void)setRefreshFrequency:(int)newFrequency
{
	[self internalSetRefreshFrequency:newFrequency];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_PreferencesUpdated" object:nil];
}

/* internalSetRefreshFrequency
 * Updates the refresh frequency.
 */
-(void)internalSetRefreshFrequency:(int)newFrequency
{
	[[NSUserDefaults standardUserDefaults] setInteger:newFrequency forKey:MAPref_CheckFrequency];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_CheckFrequencyChange" object:nil];
}
@end
