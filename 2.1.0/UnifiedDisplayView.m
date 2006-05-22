//
//  UnifiedDisplayView.m
//  Vienna
//
//  Created by Steve on 5/5/06.
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

#import "UnifiedDisplayView.h"
#import "ArticleController.h"
#import "AppController.h"
#import "Database.h"
#import "ArticleView.h"
#import "ArticleFilter.h"
#import "Preferences.h"
#import "Constants.h"
#import "StringExtensions.h"
#import "WebKit/WebUIDelegate.h"
#import "WebKit/WebDataSource.h"
#import "WebKit/WebBackForwardList.h"

@interface UnifiedDisplayView (Private)
	-(void)refreshArticlePane;
	-(void)setArticleListHeader;
@end

@implementation UnifiedDisplayView

/* awakeFromNib
 * Called when the view is loaded from the NIB file.
 */
-(void)awakeFromNib
{
	// Register to be notified when folders are added or removed
	NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleFolderNameChange:) name:@"MA_Notify_FolderNameChanged" object:nil];
	[nc addObserver:self selector:@selector(handleFilterChange:) name:@"MA_Notify_FilteringChange" object:nil];
	[nc addObserver:self selector:@selector(handleRefreshArticle:) name:@"MA_Notify_ArticleViewChange" object:nil];

	// Make us the frame load and UI delegate for the web view
	[unifiedText setUIDelegate:self];
	[unifiedText setFrameLoadDelegate:self];
	[unifiedText setOpenLinksInNewBrowser:YES];
	[unifiedText setController:controller];
	
	// Set the filters popup menu
	[controller initFiltersMenu:filtersPopupMenu];
	
	// Disable caching
	[unifiedText setMaintainsBackForwardList:NO];
	[[unifiedText backForwardList] setPageCacheSize:0];
}

/* ensureSelectedArticle
 * Ensure that there is a selected article and that it is visible.
 */
-(void)ensureSelectedArticle:(BOOL)singleSelection
{
}

/* selectFolderAndArticle
 * Select a folder. In unified view, we currently disregard the article but
 * we could potentially try and highlight the article in the text in the future.
 */
-(void)selectFolderAndArticle:(int)folderId guid:(NSString *)guid
{
	if (folderId != [articleController currentFolderId])
		[foldersTree selectFolder:folderId];
}	

/* selectFolderWithFilter
 * Switches to the specified folder and displays articles filtered by whatever is in
 * the search field.
 */
-(void)selectFolderWithFilter:(int)newFolderId
{
	Folder * folder = [[Database sharedDatabase] folderFromID:[articleController currentFolderId]];
	[self setArticleListHeader];
	[articleController reloadArrayOfArticles];
	[articleController sortArticles];
	[articleController markAllReadByArray:[NSArray arrayWithObject:folder] withUndo:YES withRefresh:NO];
	[articleController addBacktrack:nil];
	[self refreshArticlePane];
}

/* handleRefreshArticle
 * Respond to the notification to refresh the current article pane.
 */
-(void)handleRefreshArticle:(NSNotification *)nc
{
	[self refreshArticlePane];
}

/* handleFolderNameChange
 * Some folder metadata changed. Update the article list header and the
 * current article with a possible name change.
 */
-(void)handleFolderNameChange:(NSNotification *)nc
{
	int folderId = [(NSNumber *)[nc object] intValue];
	if (folderId == [articleController currentFolderId])
	{
		[self setArticleListHeader];
		[self refreshArticlePane];
	}
}

/* sortByIdentifier
 * Sort by the column indicated by the specified column name.
 */
-(void)sortByIdentifier:(NSString *)columnName
{
	[self refreshArticlePane];
}	

/* createWebViewWithRequest
 * Called when the browser wants to create a new window. The request is opened in a new tab.
 */
-(WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
	[controller openURL:[request URL] inPreferredBrowser:YES];
	// Change this to handle modifier key?
	// Is this covered by the webView policy?
	return nil;
}

/* setStatusText
 * Called from the webview when some JavaScript writes status text. Echo this to
 * our status bar.
 */
-(void)webView:(WebView *)sender setStatusText:(NSString *)text
{
	[controller setStatusMessage:text persist:NO];
}

/* mouseDidMoveOverElement
 * Called from the webview when the user positions the mouse over an element. If it's a link
 * then echo the URL to the status bar like Safari does.
 */
-(void)webView:(WebView *)sender mouseDidMoveOverElement:(NSDictionary *)elementInformation modifierFlags:(unsigned int)modifierFlags
{
	NSURL * url = [elementInformation valueForKey:@"WebElementLinkURL"];
	[controller setStatusMessage:(url ? [url absoluteString] : @"") persist:NO];
}

/* contextMenuItemsForElement
 * Creates a new context menu for our web view.
 */
-(NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems
{
	NSURL * urlLink = [element valueForKey:WebElementLinkURLKey];
	return (urlLink != nil) ? [controller contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:defaultMenuItems] : nil;
}

/* setArticleListHeader
 * Set the article list header caption to the name of the current folder.
 */
-(void)setArticleListHeader
{
	Folder * folder = [[Database sharedDatabase] folderFromID:[articleController currentFolderId]];
	ArticleFilter * filter = [ArticleFilter filterByTag:[[Preferences standardPreferences] filterMode]];
	NSString * captionString = [NSString stringWithFormat: NSLocalizedString(@"%@ (Filtered: %@)", nil), [folder name], NSLocalizedString([filter name], nil)];
	[unifiedListHeader setStringValue:captionString];
}

/* refreshFolder
 * Refreshes the current folder by applying the current sort or thread
 * logic and redrawing the article list. The selected article is preserved
 * and restored on completion of the refresh.
 */
-(void)refreshFolder:(int)refreshFlag
{
	if (refreshFlag == MA_Refresh_ReloadFromDatabase)
		[articleController reloadArrayOfArticles];
	if (refreshFlag != MA_Refresh_RedrawList)
		[articleController sortArticles];
	[self setArticleListHeader];
	[self refreshArticlePane];
}

/* handleFilterChange
 * Update the list of articles when the user changes the filter.
 */
-(void)handleFilterChange:(NSNotification *)nc
{
	[articleController refilterArrayOfArticles];
	[self refreshFolder:MA_Refresh_RedrawList];
}

/* displayNextUnread
 * Find the next folder that has unread articles and switch to that.
 */
-(void)displayNextUnread
{
	int nextFolderWithUnread = [foldersTree nextFolderWithUnread:[articleController currentFolderId]];
	if (nextFolderWithUnread != -1)
		[foldersTree selectFolder:nextFolderWithUnread];
}

/* refreshArticlePane
 * Updates the article pane for the current selected articles.
 */
-(void)refreshArticlePane
{
	NSArray * msgArray = [articleController allArticles];
	if ([msgArray count] == 0)
		[unifiedText setHTML:@"<HTML></HTML>" withBase:@""];
	else
	{
		NSString * htmlText = [unifiedText articleTextFromArray:msgArray];
		Article * firstArticle = [msgArray objectAtIndex:0];
		Folder * folder = [[Database sharedDatabase] folderFromID:[firstArticle folderId]];
		[unifiedText setHTML:htmlText withBase:SafeString([folder feedURL])];
	}
}

/* selectedArticle
 * Unified view doesn't yet support single article selections.
 */
-(Article *)selectedArticle
{
	return nil;
}

/* performFindPanelAction
 * Implement the search action.
 */
-(void)performFindPanelAction:(int)actionTag
{
}

/* printDocument
 * Print the active article.
 */
-(void)printDocument:(id)sender
{
	[unifiedText printDocument:sender];
}

/* handleGoForward
 * Move forward through the backtrack queue.
 */
-(IBAction)handleGoForward:(id)sender
{
	[articleController goForward];
}

/* handleGoBack
 * Move backward through the backtrack queue.
 */
-(IBAction)handleGoBack:(id)sender
{
	[articleController goBack];
}

/* viewLink
 * There's no view link address for unified display views.
 */
-(NSString *)viewLink
{
	return nil;
}

/* canGoForward
 * Return TRUE if we can go forward in the backtrack queue.
 */
-(BOOL)canGoForward
{
	return [articleController canGoForward];
}

/* canGoBack
 * Return TRUE if we can go backward in the backtrack queue.
 */
-(BOOL)canGoBack
{
	return [articleController canGoBack];
}

/* mainView
 * Return the primary view of this view.
 */
-(NSView *)mainView
{
	return unifiedText;
}

/* webView
 * Return the web view of this view.
 */
-(WebView *)webView
{
	return unifiedText;
}

/* handleKeyDown [delegate]
 * Support special key codes. If we handle the key, return YES otherwise
 * return NO to allow the framework to pass it on for default processing.
 */
-(BOOL)handleKeyDown:(unichar)keyChar withFlags:(unsigned int)flags
{
	return [controller handleKeyDown:keyChar withFlags:flags];
}

/* dealloc
 * Clean up behind ourself.
 */
-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}
@end
