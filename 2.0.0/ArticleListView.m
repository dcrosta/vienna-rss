//
//  ArticleListView.m
//  Vienna
//
//  Created by Steve on 8/27/05.
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

#import "ArticleListView.h"
#import "Preferences.h"
#import "Constants.h"
#import "AppController.h"
#import "SplitViewExtensions.h"
#import "MessageListView.h"
#import "ArticleView.h"
#import "FoldersTree.h"
#import "CalendarExtensions.h"
#import "StringExtensions.h"
#import "HelperFunctions.h"
#import "WebKit/WebPreferences.h"
#import "WebKit/WebFrame.h"
#import "WebKit/WebPolicyDelegate.h"
#import "WebKit/WebUIDelegate.h"
#import "WebKit/WebDataSource.h"
#import "WebKit/WebFrameView.h"

// Private functions
@interface ArticleListView (Private)
	-(void)setMessageListHeader;
	-(void)initTableView;
	-(BOOL)initForStyle:(NSString *)styleName;
	-(BOOL)copyTableSelection:(NSArray *)rows toPasteboard:(NSPasteboard *)pboard;
	-(void)showColumnsForFolder:(int)folderId;
	-(void)setTableViewFont;
	-(void)showSortDirection;
	-(void)setSortColumnIdentifier:(NSString *)str;
	-(void)selectMessageAfterReload;
	-(void)handleMinimumFontSizeChange:(NSNotification *)nc;
	-(void)handleStyleChange:(NSNotificationCenter *)nc;
	-(void)handleReadingPaneChange:(NSNotificationCenter *)nc;
	-(BOOL)scrollToMessage:(NSString *)guid;
	-(void)selectFirstUnreadInFolder;
	-(void)makeRowSelectedAndVisible:(int)rowIndex;
	-(BOOL)viewNextUnreadInCurrentFolder:(int)currentRow;
	-(void)loadMinimumFontSize;
	-(void)markCurrentRead:(NSTimer *)aTimer;
	-(void)refreshMessageAtRow:(int)theRow markRead:(BOOL)markReadFlag;
	-(void)reloadArrayOfMessages;
	-(void)updateMessageText;
	-(void)updateMessageListRowHeight;
	-(void)setOrientation:(BOOL)flag;
	-(void)printDocument;
@end

// Non-class function used for sorting
static int messageSortHandler(id item1, id item2, void * context);

// Static constant strings that are typically never tweaked
static NSString * RSSItemType = @"CorePasteboardFlavorType 0x52535369";

@implementation ArticleListView

/* initWithFrame
 * Initialise our view.
 */
-(id)initWithFrame:(NSRect)frame
{
    if (([super initWithFrame:frame]) != nil)
	{
		db = nil;
		isBacktracking = NO;
		guidOfMessageToSelect = nil;
		stylePathMappings = nil;
		markReadTimer = nil;
		htmlTemplate = nil;
		cssStylesheet = nil;
    }
    return self;
}

/* awakeFromNib
 * Do things that only make sense once the NIB is loaded.
 */
-(void)awakeFromNib
{
	// Register to be notified when folders are added or removed
	NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleFolderFontChange:) name:@"MA_Notify_FolderFontChange" object:nil];
	[nc addObserver:self selector:@selector(handleArticleListFontChange:) name:@"MA_Notify_ArticleListFontChange" object:nil];
	[nc addObserver:self selector:@selector(handleMinimumFontSizeChange:) name:@"MA_Notify_MinimumFontSizeChange" object:nil];
	[nc addObserver:self selector:@selector(handleStyleChange:) name:@"MA_Notify_StyleChange" object:nil];
	[nc addObserver:self selector:@selector(handleReadingPaneChange:) name:@"MA_Notify_ReadingPaneChange" object:nil];

	// We're the delegate for the article view
	[textView setDelegate:self];

	// Create condensed view attribute dictionaries
	selectionDict = [[NSMutableDictionary alloc] init];
	topLineDict = [[NSMutableDictionary alloc] init];
	bottomLineDict = [[NSMutableDictionary alloc] init];
	
	// Create a backtrack array
	Preferences * prefs = [Preferences standardPreferences];
	backtrackArray = [[BackTrackArray alloc] initWithMaximum:[prefs backTrackQueueSize]];

	// Set header text
	[messageListHeader setStringValue:NSLocalizedString(@"Articles", nil)];
	
	// Make us the policy and UI delegate for the web view
	[textView setPolicyDelegate:self];
	[textView setUIDelegate:self];
	[textView setFrameLoadDelegate:self];
	
	// Handle minimum font size
	defaultWebPrefs = [[textView preferences] retain];
	[self loadMinimumFontSize];

	// Restore the split bar position
	[splitView2 loadLayoutWithName:@"SplitView2Positions"];
	
	// Do safe initialisation
	[controller doSafeInitialisation];
}

/* setController
 * Sets the controller used by this view.
 */
-(void)setController:(AppController *)theController
{
	controller = theController;
	db = [[controller database] retain];
}

/* initialiseArticleView
 * Do the things to initialise the article view from the database. This is the
 * only point during initialisation where the database is guaranteed to be
 * ready for use.
 */
-(void)initialiseArticleView
{
	// Mark the start of the init phase
	isAppInitialising = YES;
	
	// Set the reading pane orientation
	[self setOrientation:[[Preferences standardPreferences] readingPaneOnRight]];

	// Initialise the article list view
	[self initTableView];
	
	// Select the default style
	Preferences * prefs = [Preferences standardPreferences];
	if (![self initForStyle:[prefs displayStyle]])
		[prefs setDisplayStyle:@"Default"];
	
	// Select the first conference
	int previousFolderId = [[NSUserDefaults standardUserDefaults] integerForKey:MAPref_CachedFolderID];
	[self selectFolderAndMessage:previousFolderId guid:nil];
	
	// Done initialising
	isAppInitialising = NO;
}

/* decidePolicyForNavigationAction
 * Called by the web view to get our policy on handling navigation actions. Since we want links clicked in the
 * web view to open in an external browser, we trap the link clicked action and launch the URL ourselves.
 */
-(void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
	int navType = [[actionInformation valueForKey:WebActionNavigationTypeKey] intValue];
	if (navType == WebNavigationTypeLinkClicked)
	{
		[listener ignore];
		[controller openURLInBrowserWithURL:[request URL]];
	}
	[listener use];
}

/* decidePolicyForNewWindowAction
 * Called by the web view to get our policy on handling actions that would open a new window. Since we want links clicked in the
 * web view to open in an external browser, we trap the link clicked action and launch the URL ourselves.
 */
-(void)webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request newFrameName:(NSString *)frameName decisionListener:(id<WebPolicyDecisionListener>)listener
{
	int navType = [[actionInformation valueForKey:WebActionNavigationTypeKey] intValue];
	if (navType == WebNavigationTypeLinkClicked)
	{
		[listener ignore];
		[controller openURLInBrowserWithURL:[request URL]];
	}
	[listener use];
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
 * Creates a new context menu for our web view. The main change is for the menu that is shown when
 * the user right or Ctrl clicks on links. We replace "Open Link in New Window" with "Open Link in Browser"
 * which is more representative of what exactly happens. Similarly we replace "Copy Link" to make it clear
 * where the copy goes to. All other items are removed.
 */
-(NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems
{
	NSURL * urlLink = [element valueForKey:WebElementLinkURLKey];
	if (urlLink != nil)
	{
		NSMutableArray * newDefaultMenu = [[NSMutableArray alloc] initWithArray:defaultMenuItems];
		int count = [newDefaultMenu count];
		int index;
		
		for (index = count - 1; index >= 0; --index)
		{
			NSMenuItem * menuItem = [newDefaultMenu objectAtIndex:index];
			switch ([menuItem tag])
			{
				case WebMenuItemTagOpenLinkInNewWindow:
					[menuItem setTitle:NSLocalizedString(@"Open Link in Browser", nil)];
					[menuItem setTarget:self];
					[menuItem setAction:@selector(ourOpenLinkHandler:)];
					[menuItem setRepresentedObject:urlLink];
					break;
					
				case WebMenuItemTagCopyLinkToClipboard:
					[menuItem setTitle:NSLocalizedString(@"Copy Link to Clipboard", nil)];
					break;
					
				default:
					[newDefaultMenu removeObjectAtIndex:index];
					break;
			}
		}
		return [newDefaultMenu autorelease];
	}
	return nil;
}

/* initTableView
 * Do all the initialization for the message list table view control
 */
-(void)initTableView
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	
	// Variable initialization here
	currentFolderId = -1;
	currentArrayOfMessages = nil;
	currentSelectedRow = -1;
	messageListFont = nil;
	
	// Pre-set sort to what was saved in the preferences
	[self setSortColumnIdentifier:[defaults stringForKey:MAPref_SortColumn]];
	sortDirection = [defaults integerForKey:MAPref_SortDirection];
	sortColumnTag = [[db fieldByName:sortColumnIdentifier] tag];
	
	// Initialize the message columns from saved data
	NSArray * dataArray = [defaults arrayForKey:MAPref_MessageColumns];
	Field * field;
	unsigned int index;
	
	for (index = 0; index < [dataArray count];)
	{
		NSString * name;
		int width = 100;
		BOOL visible = NO;
		
		name = [dataArray objectAtIndex:index++];
		if (index < [dataArray count])
			visible = [[dataArray objectAtIndex:index++] intValue] == YES;
		if (index < [dataArray count])
			width = [[dataArray objectAtIndex:index++] intValue];
		
		field = [db fieldByName:name];
		[field setVisible:visible];
		[field setWidth:width];
	}
	
	// Get the default list of visible columns
	[self updateVisibleColumns];
	
	// Remember the folder column state
	Field * folderField = [db fieldByName:MA_Field_Folder];
	previousFolderColumnState = [folderField visible];	
	
	// Set the target for double-click actions
	[messageList setDoubleAction:@selector(doubleClickRow:)];
	[messageList setAction:@selector(singleClickRow:)];
	[messageList setDelegate:self];
	[messageList setDataSource:self];
	[messageList setTarget:self];

	// Set the default fonts
	[self setTableViewFont];
}

/* singleClickRow
 * Handle a single click action. If the click was in the read or flagged column then
 * treat it as an action to mark the message read/unread or flagged/unflagged. Later
 * trap the comments column and expand/collapse.
 */
-(IBAction)singleClickRow:(id)sender
{
	int row = [messageList clickedRow];
	int column = [messageList clickedColumn];
	if (row >= 0 && row < (int)[currentArrayOfMessages count])
	{
		NSArray * columns = [messageList tableColumns];
		if (column >= 0 && column < (int)[columns count])
		{
			Message * theArticle = [currentArrayOfMessages objectAtIndex:row];
			NSString * columnName = [(NSTableColumn *)[columns objectAtIndex:column] identifier];
			if ([columnName isEqualToString:MA_Field_Read])
			{
				[self markReadByArray:[NSArray arrayWithObject:theArticle] readFlag:![theArticle isRead]];
				return;
			}
			if ([columnName isEqualToString:MA_Field_Flagged])
			{
				[self markFlaggedByArray:[NSArray arrayWithObject:theArticle] flagged:![theArticle isFlagged]];
				return;
			}
		}
	}
}

/* doubleClickRow
 * Handle double-click on the selected message. Open the original feed item in
 * the default browser.
 */
-(IBAction)doubleClickRow:(id)sender
{
	if (currentSelectedRow != -1)
	{
		Message * theArticle = [currentArrayOfMessages objectAtIndex:currentSelectedRow];
		[controller openURLInBrowser:[theArticle link]];
	}
}

/* showColumnsForFolder
 * Display the columns for the specific folder.
 */
-(void)showColumnsForFolder:(int)folderId
{
	Folder * folder = [db folderFromID:folderId];
	Field * folderField = [db fieldByName:MA_Field_Folder];
	BOOL showFolderColumn;
	
	if (folder && (IsSmartFolder(folder) || IsGroupFolder(folder)))
	{
		previousFolderColumnState = [folderField visible];
		showFolderColumn = YES;
	}
	else
		showFolderColumn = previousFolderColumnState;
	
	if ([folderField visible] != showFolderColumn)
	{
		[folderField setVisible:showFolderColumn];
		[self updateVisibleColumns];
	}
}

/* updateVisibleColumns
 * Iterates through the array of visible columns and makes them
 * visible or invisible as needed.
 */
-(void)updateVisibleColumns
{
	NSArray * fields = [db arrayOfFields];
	int count = [fields count];
	int index;
	
	// Create the new columns
	for (index = 0; index < count; ++index)
	{
		Field * field = [fields objectAtIndex:index];
		NSString * identifier = [field name];
		BOOL showField;
		
		// Remove each column as we go.
		NSTableColumn * tableColumn = [messageList tableColumnWithIdentifier:identifier];
		if (tableColumn != nil)
		{
			if (index + 1 != count)
				[field setWidth:[tableColumn width]];
			[messageList removeTableColumn:tableColumn];
		}
		
		// Handle condensed layout vs. table layout
		if (tableLayout == MA_Table_Layout)
			showField = [field visible] && [field tag] != MA_FieldID_Headlines;
		else
		{
			showField = [field tag] == MA_FieldID_Headlines ||
			[field tag] == MA_FieldID_Read ||
			[field tag] == MA_FieldID_Flagged ||
			[field tag] == MA_FieldID_Comments;
		}
		
		// Add to the end only those columns that are visible
		if (showField)
		{
			NSTableColumn * newTableColumn = [[NSTableColumn alloc] initWithIdentifier:identifier];
			NSTableHeaderCell * headerCell = [newTableColumn headerCell];
			int tag = [field tag];
			BOOL isResizable = (tag != MA_FieldID_Read && tag != MA_FieldID_Flagged && tag != MA_FieldID_Comments);
			
			// Fix for bug where tableviews with alternating background rows lose their "colour".
			// Only text cells are affected.
			if ([[newTableColumn dataCell] isKindOfClass:[NSTextFieldCell class]])
				[[newTableColumn dataCell] setDrawsBackground:NO];
			
			[headerCell setTitle:[field displayName]];
			[newTableColumn setEditable:NO];
			[newTableColumn setResizable:isResizable];
			[newTableColumn setMinWidth:10];
			[newTableColumn setMaxWidth:1000];
			[newTableColumn setWidth:[field width]];
			[messageList addTableColumn:newTableColumn];
			[newTableColumn release];
		}
	}
	
	// Set the extended date formatter on the Date column
	NSTableColumn * tableColumn = [messageList tableColumnWithIdentifier:MA_Field_Date];
	if (tableColumn != nil)
	{
		if (extDateFormatter == nil)
			extDateFormatter = [[ExtDateFormatter alloc] init];
		[[tableColumn dataCell] setFormatter:extDateFormatter];
	}

	// Set the images for specific header columns
	[messageList setHeaderImage:MA_Field_Read imageName:@"unread_header.tiff"];
	[messageList setHeaderImage:MA_Field_Flagged imageName:@"flagged_header.tiff"];
	[messageList setHeaderImage:MA_Field_Comments imageName:@"comments_header.tiff"];
	
	// Initialise the sort direction
	[self showSortDirection];	
	
	// In condensed mode, the summary field takes up the whole space
	if (tableLayout == MA_Condensed_Layout)
	{
		[messageList sizeLastColumnToFit];
		[messageList setNeedsDisplay];
	}
}

/* saveTableSettings
 * Save the table column settings, specifically the visibility and width.
 */
-(void)saveTableSettings
{
	NSArray * fields = [db arrayOfFields];
	NSEnumerator * enumerator = [fields objectEnumerator];
	Field * field;
	
	// An array we need for the settings
	NSMutableArray * dataArray = [[NSMutableArray alloc] init];
	
	// Create the new columns
	while ((field = [enumerator nextObject]) != nil)
	{
		[dataArray addObject:[field name]];
		[dataArray addObject:[NSNumber numberWithBool:[field visible]]];
		[dataArray addObject:[NSNumber numberWithInt:[field width]]];
	}
	
	// Save these to the preferences
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:dataArray forKey:MAPref_MessageColumns];
	[defaults synchronize];

	// Save the split bar position
	[splitView2 storeLayoutWithName:@"SplitView2Positions"];

	// We're done
	[dataArray release];
}

/* setTableViewFont
 * Gets the font for the message list and adjusts the table view
 * row height to properly display that font.
 */
-(void)setTableViewFont
{
	[messageListFont release];
	
	Preferences * prefs = [Preferences standardPreferences];
	messageListFont = [NSFont fontWithName:[prefs articleListFont] size:[prefs articleListFontSize]];
	
	[topLineDict setObject:messageListFont forKey:NSFontAttributeName];
	[topLineDict setObject:[NSColor blackColor] forKey:NSForegroundColorAttributeName];
	
	[bottomLineDict setObject:messageListFont forKey:NSFontAttributeName];
	[bottomLineDict setObject:[NSColor grayColor] forKey:NSForegroundColorAttributeName];
	
	[selectionDict setObject:messageListFont forKey:NSFontAttributeName];
	[selectionDict setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
	
	[self updateMessageListRowHeight];
}

/* updateMessageListRowHeight
 */
-(void)updateMessageListRowHeight
{
	int height = [messageListFont defaultLineHeightForFont];
	int numberOfRowsInCell = (tableLayout == MA_Table_Layout) ? 1: 2;
	[messageList setRowHeight:(height + 3) * numberOfRowsInCell];
}

/* showSortDirection
 * Shows the current sort column and direction in the table.
 */
-(void)showSortDirection
{
	NSTableColumn * sortColumn = [messageList tableColumnWithIdentifier:sortColumnIdentifier];
	NSString * imageName = (sortDirection < 0) ? @"NSDescendingSortIndicator" : @"NSAscendingSortIndicator";
	[messageList setHighlightedTableColumn:sortColumn];
	[messageList setIndicatorImage:[NSImage imageNamed:imageName] inTableColumn:sortColumn];
}

/* sortByIdentifier
 * Sort by the column indicated by the specified column name.
 */
-(void)sortByIdentifier:(NSString *)columnName
{
	if ([sortColumnIdentifier isEqualToString:columnName])
		sortDirection *= -1;
	else
	{
		[messageList setIndicatorImage:nil inTableColumn:[messageList tableColumnWithIdentifier:sortColumnIdentifier]];
		[self setSortColumnIdentifier:columnName];
		sortDirection = 1;
		sortColumnTag = [[db fieldByName:sortColumnIdentifier] tag];
		[[NSUserDefaults standardUserDefaults] setObject:sortColumnIdentifier forKey:MAPref_SortColumn];
	}
	[[NSUserDefaults standardUserDefaults] setInteger:sortDirection forKey:MAPref_SortDirection];
	[self showSortDirection];
	[self refreshFolder:NO];
}

/* scrollToMessage
 * Moves the selection to the specified message. Returns YES if we found the
 * message, NO otherwise.
 */
-(BOOL)scrollToMessage:(NSString *)guid
{
	NSEnumerator * enumerator = [currentArrayOfMessages objectEnumerator];
	Message * thisMessage;
	int rowIndex = 0;
	BOOL found = NO;
	
	while ((thisMessage = [enumerator nextObject]) != nil)
	{
		if ([[thisMessage guid] isEqualToString:guid])
		{
			[self makeRowSelectedAndVisible:rowIndex];
			found = YES;
			break;
		}
		++rowIndex;
	}
	return found;
}

/* initStylesMap
 * Initialise the stylePathMappings.
 */
-(NSDictionary *)initStylesMap
{
	if (stylePathMappings == nil)
		stylePathMappings = [[NSMutableDictionary alloc] init];

	NSString * path = [[[NSBundle mainBundle] sharedSupportPath] stringByAppendingPathComponent:@"Styles"];
	loadMapFromPath(path, stylePathMappings, YES);
	
	path = [[[NSUserDefaults standardUserDefaults] objectForKey:MAPref_StylesFolder] stringByExpandingTildeInPath];
	loadMapFromPath(path, stylePathMappings, YES);
	
	return stylePathMappings;
}

/* stylePathMappings
 */
-(NSDictionary *)stylePathMappings
{
	if (stylePathMappings == nil)
		[self initStylesMap];
	return stylePathMappings;
}

/* handleStyleChange
 * Updates the article pane when the active display style has been changed.
 */
-(void)handleStyleChange:(NSNotificationCenter *)nc
{
	[self initForStyle:[[Preferences standardPreferences] displayStyle]];
}

/* initForStyle
 * Initialise the template and stylesheet for the specified display style if it can be
 * found. Otherwise the existing template and stylesheet are not changed.
 */
-(BOOL)initForStyle:(NSString *)styleName
{
	NSString * path = [[self stylePathMappings] objectForKey:styleName];
	if (path != nil)
	{
		NSString * filePath = [path stringByAppendingPathComponent:@"template.html"];
		NSFileHandle * handle = [NSFileHandle fileHandleForReadingAtPath:filePath];
		if (handle != nil)
		{
			// Sanity check the file. Obviously anything bigger than 0 bytes but smaller than a valid template
			// format is a problem but we'll worry about that later. There's only so much rope we can give.
			NSData * fileData = [handle readDataToEndOfFile];
			if ([fileData length] > 0)
			{
				[htmlTemplate release];
				[cssStylesheet release];
				htmlTemplate = [[NSString stringWithCString:[fileData bytes] length:[fileData length]] retain];
				cssStylesheet = [[@"file://localhost" stringByAppendingString:[path stringByAppendingPathComponent:@"stylesheet.css"]] retain];

				if (!isAppInitialising)
					[self updateMessageText];

				[handle closeFile];
				return YES;
			}
			[handle closeFile];
		}
	}
	return NO;
}

/* handleMinimumFontSizeChange
 * Called when the minimum font size for articles is enabled or disabled, or changed.
 */
-(void)handleMinimumFontSizeChange:(NSNotification *)nc
{
	[self loadMinimumFontSize];
	[self updateMessageText];
}

/* loadMinimumFontSize
 * Sets up the web preferences for a minimum font size.
 */
-(void)loadMinimumFontSize
{
	Preferences * prefs = [Preferences standardPreferences];
	if (![prefs enableMinimumFontSize])
		[defaultWebPrefs setMinimumFontSize:1];
	else
	{
		int size = [prefs minimumFontSize];
		[defaultWebPrefs setMinimumFontSize:size];
	}
}

/* mainView
 * Return the primary view of this view.
 */
-(NSView *)mainView
{
	return messageList;
}

/* getTrackIndex
 */
-(int)getTrackIndex
{
	if ([backtrackArray isAtStartOfQueue])
		return MA_Track_AtStart;
	if ([backtrackArray isAtEndOfQueue])
		return MA_Track_AtEnd;
	return 0;
}

/* trackMessage
 * Move backward or forward through the backtrack queue.
 */
-(void)trackMessage:(int)trackFlag
{
	int folderId;
	NSString * guid;

	if (trackFlag == MA_Track_Forward)
	{
		if ([backtrackArray nextItemAtQueue:&folderId messageNumber:&guid])
		{
			isBacktracking = YES;
			[self selectFolderAndMessage:folderId guid:guid];
			isBacktracking = NO;
		}
	}
	if (trackFlag == MA_Track_Back)
	{
		if ([backtrackArray previousItemAtQueue:&folderId messageNumber:&guid])
		{
			isBacktracking = YES;
			[self selectFolderAndMessage:folderId guid:guid];
			isBacktracking = NO;
		}
	}
}

/* handleKeyDown [delegate]
 * Support special key codes. If we handle the key, return YES otherwise
 * return NO to allow the framework to pass it on for default processing.
 */
-(BOOL)handleKeyDown:(unichar)keyChar withFlags:(unsigned int)flags
{
	switch (keyChar)
	{
		case ' ': //SPACE
		{
			NSView * theView = [[[textView mainFrame] frameView] documentView];
			NSRect visibleRect;
			
			visibleRect = [theView visibleRect];
			if (visibleRect.origin.y + visibleRect.size.height >= [theView frame].size.height)
				[controller viewNextUnread:self];
			else
				[[[textView mainFrame] webView] scrollPageDown:self];
			return YES;
		}
	}
	return NO;
}

/* selectedArticle
 * Returns the selected article, or nil if no article is selected.
 */
-(Message *)selectedArticle
{
	return (currentSelectedRow >= 0) ? [currentArrayOfMessages objectAtIndex:currentSelectedRow] : nil;
}

/* printDocument
 * Print the active article.
 */
-(void)printDocument
{
	NSPrintInfo * printInfo = [NSPrintInfo sharedPrintInfo];
	NSPrintOperation * printOp;
	
	[printInfo setVerticallyCentered:NO];
	printOp = [NSPrintOperation printOperationWithView:textView printInfo:printInfo];
	[printOp setShowPanels:YES];
	[printOp runOperation];
}	

/* handleArticleListFontChange
 * Called when the user changes the message list font and/or size in the Preferences
 */
-(void)handleArticleListFontChange:(NSNotification *)note
{
	[self setTableViewFont];
	[messageList reloadData];
}

/* handleReadingPaneChange
 * Respond to the change to the reading pane orientation.
 */
-(void)handleReadingPaneChange:(NSNotificationCenter *)nc
{
	[self setOrientation:[[Preferences standardPreferences] readingPaneOnRight]];
	[self updateMessageListRowHeight];
	[self updateVisibleColumns];
	[messageList reloadData];
}

/* setOrientation
 * Adjusts the article view orientation and updates the message list row
 * height to accommodate the summary view
 */
-(void)setOrientation:(BOOL)flag
{
	tableLayout = flag ? MA_Condensed_Layout : MA_Table_Layout;
	[splitView2 setVertical:flag];
	[splitView2 display];
}

/* tableLayout
 * Returns the active table layout.
 */
-(int)tableLayout
{
	return tableLayout;
}

/* sortColumnIdentifier
 */
-(NSString *)sortColumnIdentifier
{
	return sortColumnIdentifier;
}

/* setSortColumnIdentifier
 */
-(void)setSortColumnIdentifier:(NSString *)str
{
	[str retain];
	[sortColumnIdentifier release];
	sortColumnIdentifier = str;
}

/* sortMessages
 * Re-orders the messages in currentArrayOfMessages by the current sort order
 */
-(void)sortMessages
{
	NSArray * sortedArrayOfMessages;
	
	sortedArrayOfMessages = [currentArrayOfMessages sortedArrayUsingFunction:messageSortHandler context:self];
	NSAssert([sortedArrayOfMessages count] == [currentArrayOfMessages count], @"Lost messages from currentArrayOfMessages during sort");
	[currentArrayOfMessages release];
	currentArrayOfMessages = [[NSArray arrayWithArray:sortedArrayOfMessages] retain];
}

/* messageSortHandler
 */
int messageSortHandler(Message * item1, Message * item2, void * context)
{
	ArticleListView * app = (ArticleListView *)context;
	switch (app->sortColumnTag)
	{
		case MA_FieldID_Folder: {
			Folder * folder1 = [app->db folderFromID:[item1 folderId]];
			Folder * folder2 = [app->db folderFromID:[item2 folderId]];
			return [[folder1 name] caseInsensitiveCompare:[folder2 name]] * app->sortDirection;
		}
			
		case MA_FieldID_Read: {
			BOOL n1 = [item1 isRead];
			BOOL n2 = [item2 isRead];
			return (n1 < n2) * app->sortDirection;
		}
			
		case MA_FieldID_Flagged: {
			BOOL n1 = [item1 isFlagged];
			BOOL n2 = [item2 isFlagged];
			return (n1 < n2) * app->sortDirection;
		}
			
		case MA_FieldID_Comments: {
			BOOL n1 = [item1 hasComments];
			BOOL n2 = [item2 hasComments];
			return (n1 < n2) * app->sortDirection;
		}
			
		case MA_FieldID_Date: {
			NSDate * n1 = [[item1 messageData] objectForKey:MA_Field_Date];
			NSDate * n2 = [[item2 messageData] objectForKey:MA_Field_Date];
			return [n1 compare:n2] * app->sortDirection;
		}
			
		case MA_FieldID_Author: {
			NSString * n1 = [[item1 messageData] objectForKey:MA_Field_Author];
			NSString * n2 = [[item2 messageData] objectForKey:MA_Field_Author];
			return [n1 caseInsensitiveCompare:n2] * app->sortDirection;
		}
			
		case MA_FieldID_Headlines:
		case MA_FieldID_Subject: {
			NSString * n1 = [[item1 messageData] objectForKey:MA_Field_Subject];
			NSString * n2 = [[item2 messageData] objectForKey:MA_Field_Subject];
			return [n1 caseInsensitiveCompare:n2] * app->sortDirection;
		}
	}
	return NSOrderedSame;
}

/* makeRowSelectedAndVisible
 * Selects the specified row in the table and makes it visible by
 * scrolling it to the center of the table.
 */
-(void)makeRowSelectedAndVisible:(int)rowIndex
{
	if (rowIndex == currentSelectedRow)
	{
		[messageList selectRow:rowIndex byExtendingSelection:NO];
		[self refreshMessageAtRow:rowIndex markRead:NO];
	}
	else
	{
		[messageList selectRow:rowIndex byExtendingSelection:NO];
		
		int pageSize = [messageList rowsInRect:[messageList visibleRect]].length;
		int lastRow = [messageList numberOfRows] - 1;
		int visibleRow = currentSelectedRow + (pageSize / 2);
		
		if (visibleRow > lastRow)
			visibleRow = lastRow;
		[messageList scrollRowToVisible:currentSelectedRow];
		[messageList scrollRowToVisible:visibleRow];
	}
}

/* displayNextUnread
 * Locate the next unread article from the current article onward.
 */
-(void)displayNextUnread
{
	// Mark the current message read
	[self markCurrentRead:nil];

	// Scan the current folder from the selection forward. If nothing found, try
	// other folders until we come back to ourselves.
	if (![self viewNextUnreadInCurrentFolder:currentSelectedRow])
	{
		int nextFolderWithUnread = [foldersTree nextFolderWithUnread:currentFolderId];
		if (nextFolderWithUnread != -1)
		{
			if (nextFolderWithUnread == currentFolderId)
				[self viewNextUnreadInCurrentFolder:-1];
			else
			{
				guidOfMessageToSelect = nil;
				[foldersTree selectFolder:nextFolderWithUnread];
				[[NSApp mainWindow] makeFirstResponder:messageList];
			}
		}
	}
}

/* viewNextUnreadInCurrentFolder
 * Select the next unread message in the current folder after currentRow.
 */
-(BOOL)viewNextUnreadInCurrentFolder:(int)currentRow
{
	int totalRows = [currentArrayOfMessages count];
	if (currentRow < totalRows - 1)
	{
		Message * theArticle;
		
		do {
			theArticle = [currentArrayOfMessages objectAtIndex:++currentRow];
			if (![theArticle isRead])
			{
				[self makeRowSelectedAndVisible:currentRow];
				return YES;
			}
		} while (currentRow < totalRows - 1);
	}
	return NO;
}

/* selectFirstUnreadInFolder
 * Moves the selection to the first unread message in the current message list or the
 * last message if the folder has no unread messages.
 */
-(void)selectFirstUnreadInFolder
{
	if (![self viewNextUnreadInCurrentFolder:-1])
	{
		int count = [currentArrayOfMessages count];
		if (count == 0)
			[[NSApp mainWindow] makeFirstResponder:[foldersTree mainView]];
		else
			[self makeRowSelectedAndVisible:(sortDirection < 0) ? 0 : count - 1];
	}
}

/* selectFolderAndMessage
 * Select a folder and select a specified message within the folder.
 */
-(BOOL)selectFolderAndMessage:(int)folderId guid:(NSString *)guid
{
	// If we're in the right folder, easy enough.
	if (folderId == currentFolderId)
		return [self scrollToMessage:guid];
	
	// Otherwise we force the folder to be selected and seed guidOfMessageToSelect
	// so that after handleFolderSelection has been invoked, it will select the
	// requisite message on our behalf.
	[guidOfMessageToSelect release];
	guidOfMessageToSelect = [guid retain];
	[foldersTree selectFolder:folderId];
	return YES;
}

/* search
 * Implement the search action.
 */
-(void)search
{
	[self refreshFolder:YES];
}

/* refreshFolder
 * Refreshes the current folder by applying the current sort or thread
 * logic and redrawing the message list. The selected message is preserved
 * and restored on completion of the refresh.
 */
-(void)refreshFolder:(BOOL)reloadData
{
	NSString * guid = nil;
	
	if (currentSelectedRow >= 0)
		guid = [[[currentArrayOfMessages objectAtIndex:currentSelectedRow] guid] retain];
	if (reloadData)
		[self reloadArrayOfMessages];
	[self setMessageListHeader];
	[self sortMessages];
	[self showSortDirection];
	[messageList reloadData];
	if (guid != nil)
	{
		if (![self scrollToMessage:guid])
			currentSelectedRow = -1;
		else
			[self updateMessageText];
	}
	[guid release];
}

/* setMessageListHeader
 * Set the message list header caption to the name of the current folder.
 */
-(void)setMessageListHeader
{
	Folder * folder = [db folderFromID:currentFolderId];
	[messageListHeader setStringValue:[folder name]];
}

/* reloadArrayOfMessages
 * Reload the currentArrayOfMessages from the current folder.
 */
-(void)reloadArrayOfMessages
{
	[currentArrayOfMessages release];
	currentArrayOfMessages = [[db arrayOfMessages:currentFolderId filterString:[controller searchString]] retain];
}

/* selectMessageAfterReload
 * Sets the selection in the message list after the list is reloaded. The value of guidOfMessageToSelect
 * is either MA_Select_None, meaning no selection, MA_Select_Unread meaning select the first unread
 * message from the beginning (after sorting is applied) or it is the ID of a specific message to be
 * selected.
 */
-(void)selectMessageAfterReload
{
	if (guidOfMessageToSelect == nil)
		[self selectFirstUnreadInFolder];
	else
		[self scrollToMessage:guidOfMessageToSelect];
	[guidOfMessageToSelect release];
	guidOfMessageToSelect = nil;
}

/* currentFolderId
 * Return the ID of the folder being displayed in the list.
 */
-(int)currentFolderId
{
	return currentFolderId;
}

/* selectFolderWithFilter
 * Switches to the specified folder and displays messages filtered by whatever is in
 * the search field.
 */
-(void)selectFolderWithFilter:(int)newFolderId
{
	[controller setMainWindowTitle:newFolderId];
	[db flushFolder:currentFolderId];
	[messageList deselectAll:self];
	[controller clearUndoStack];
	currentFolderId = newFolderId;
	[self setMessageListHeader];
	[self showColumnsForFolder:currentFolderId];
	[self reloadArrayOfMessages];
	[self sortMessages];
	[messageList reloadData];
	[self selectMessageAfterReload];
}

/* refreshMessageAtRow
 * Refreshes the message at the specified row.
 */
-(void)refreshMessageAtRow:(int)theRow markRead:(BOOL)markReadFlag
{
	if (currentSelectedRow < 0)
		[[textView mainFrame] loadHTMLString:@"<HTML></HTML>" baseURL:nil];
	else
	{
		NSAssert(currentSelectedRow < (int)[currentArrayOfMessages count], @"Out of range row index received");
		[self updateMessageText];
		
		// If we mark read after an interval, start the timer here.
		[markReadTimer invalidate];
		[markReadTimer release];
		markReadTimer = nil;
		
		float interval = [[Preferences standardPreferences] markReadInterval];
		if (interval > 0 && markReadFlag)
			markReadTimer = [[NSTimer scheduledTimerWithTimeInterval:(double)interval
															  target:self
															selector:@selector(markCurrentRead:)
															userInfo:nil
															 repeats:NO] retain];
		
		// Add this to the backtrack list
		if (!isBacktracking)
		{
			NSString * guid = [[currentArrayOfMessages objectAtIndex:currentSelectedRow] guid];
			[backtrackArray addToQueue:currentFolderId messageNumber:guid];
		}
	}
}

/* updateMessageText
 * Updates the message text for the current selected message possibly because
 * some of the message attributes have changed.
 */
-(void)updateMessageText
{
	if (currentSelectedRow >= 0)
	{
		Message * theArticle = [currentArrayOfMessages objectAtIndex:currentSelectedRow];
		Folder * folder = [db folderFromID:[theArticle folderId]];
		
		// Cache values for things we're going to be plugging into the template and set
		// defaults for things that are missing.
		NSString * messageText = [db messageText:[theArticle folderId] guid:[theArticle guid]];
		NSString * messageDate = [[[theArticle date] dateWithCalendarFormat:nil timeZone:nil] friendlyDescription];
		NSString * messageLink = [theArticle link] ? [theArticle link] : @"";
		NSString * messageAuthor = [theArticle author] ? [theArticle author] : @"";
		NSString * messageTitle = [theArticle title] ? [theArticle title] : @"";
		NSString * folderTitle = [folder name] ? [folder name] : @"";
		NSString * folderLink = [folder homePage] ? [folder homePage] : @"";
		
		// Load the selected HTML template for the current view style and plug in the current
		// message values and style sheet setting. If no template has been set, we use a
		// predefined one with no styles.
		//
		NSMutableString * htmlMessage = nil;
		NSString * ourTemplate = htmlTemplate;
		if (ourTemplate == nil)
			ourTemplate = @"<html><head><title>$ArticleTitle$</title></head>"
				"<body><strong><a href=\"$ArticleLink$\">$ArticleTitle$</a></strong><br><br>$ArticleBody$<br><br>"
				"<a href=\"$FeedLink$\">$FeedTitle$</a></span> "
				"<span>$ArticleDate$</span>"
				"</body></html>";
		
		htmlMessage = [[NSMutableString alloc] initWithString:ourTemplate];
		if (cssStylesheet != nil)
			[htmlMessage replaceString:@"$CSSFilePath$" withString:cssStylesheet];
		[htmlMessage replaceString:@"$ArticleLink$" withString:messageLink];
		[htmlMessage replaceString:@"$ArticleTitle$" withString:messageTitle];
		[htmlMessage replaceString:@"$ArticleBody$" withString:messageText];
		[htmlMessage replaceString:@"$ArticleAuthor$" withString:messageAuthor];
		[htmlMessage replaceString:@"$ArticleDate$" withString:messageDate];
		[htmlMessage replaceString:@"$FeedTitle$" withString:folderTitle];
		[htmlMessage replaceString:@"$FeedLink$" withString:folderLink];
		
		// Here we ask the webview to do all the hard work. Note that we pass the path to the
		// stylesheet as the base URL. There's an idiosyncracy in loadHTMLString:baseURL: that it
		// requires a URL to an actual file as the second parameter or it won't work.
		//
		[[textView mainFrame] loadHTMLString:htmlMessage baseURL:[NSURL URLWithString:[folder feedURL]]];
		[htmlMessage release];
	}
}

/* markCurrentRead
 * Mark the current message as read.
 */
-(void)markCurrentRead:(NSTimer *)aTimer
{
	if (currentSelectedRow != -1 && ![db readOnly])
	{
		Message * theArticle = [currentArrayOfMessages objectAtIndex:currentSelectedRow];
		if (![theArticle isRead])
			[self markReadByArray:[NSArray arrayWithObject:theArticle] readFlag:YES];
	}
}

/* numberOfRowsInTableView [datasource]
 * Datasource for the table view. Return the total number of rows we'll display which
 * is equivalent to the number of messages in the current folder.
 */
-(int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [currentArrayOfMessages count];
}

/* objectValueForTableColumn [datasource]
 * Called by the table view to obtain the object at the specified column and row. This is
 * called often so it needs to be fast.
 */
-(id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	Message * theArticle;
	
	NSParameterAssert(rowIndex >= 0 && rowIndex < (int)[currentArrayOfMessages count]);
	theArticle = [currentArrayOfMessages objectAtIndex:rowIndex];
	if ([[aTableColumn identifier] isEqualToString:MA_Field_Folder])
	{
		Folder * folder = [db folderFromID:[theArticle folderId]];
		return [folder name];
	}
	if ([[aTableColumn identifier] isEqualToString:MA_Field_Read])
	{
		if (![theArticle isRead])
			return [NSImage imageNamed:@"unread.tiff"];
		return [NSImage imageNamed:@"alphaPixel.tiff"];
	}
	if ([[aTableColumn identifier] isEqualToString:MA_Field_Flagged])
	{
		if ([theArticle isFlagged])
			return [NSImage imageNamed:@"flagged.tiff"];
		return [NSImage imageNamed:@"alphaPixel.tiff"];
	}
	if ([[aTableColumn identifier] isEqualToString:MA_Field_Comments])
	{
		if ([theArticle hasComments])
			return [NSImage imageNamed:@"comments.tiff"];
		return [NSImage imageNamed:@"alphaPixel.tiff"];
	}
	if ([[aTableColumn identifier] isEqualToString:MA_Field_Headlines])
	{
		NSMutableAttributedString * theAttributedString = [[NSMutableAttributedString alloc] init];
		BOOL isSelectedRow = [aTableView isRowSelected:rowIndex] && ([[NSApp mainWindow] firstResponder] == aTableView);
		NSDictionary * topLineDictPtr = (isSelectedRow ? selectionDict : topLineDict);
		NSDictionary * bottomLineDictPtr = (isSelectedRow ? selectionDict : bottomLineDict);
		
		NSAttributedString * topString = [[NSAttributedString alloc] initWithString:[theArticle title] attributes:topLineDictPtr];
		[theAttributedString appendAttributedString:topString];
		[topString release];

		// Create the summary line that appears below the title.
		Folder * folder = [db folderFromID:[theArticle folderId]];
		NSCalendarDate * anDate = [[theArticle date] dateWithCalendarFormat:nil timeZone:nil];
		NSMutableString * summaryString = [NSMutableString stringWithFormat:@"\n%@ - %@", [folder name], [anDate friendlyDescription]];
		if (![[theArticle author] isBlank])
			[summaryString appendFormat:@" - %@", [theArticle author]];
		
		NSAttributedString * bottomString = [[NSAttributedString alloc] initWithString:summaryString attributes:bottomLineDictPtr];
		[theAttributedString appendAttributedString:bottomString];
		[bottomString release];
		return [theAttributedString autorelease];
	}
	return [[theArticle messageData] objectForKey:[aTableColumn identifier]];
}

/* willDisplayCell [delegate]
 * Catch the table view before it displays a cell.
 */
-(void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if (![aCell isKindOfClass:[NSImageCell class]])
	{
		[aCell setTextColor:[NSColor blackColor]];
		[aCell setFont:messageListFont];
	}
}

/* tableViewSelectionDidChange [delegate]
 * Handle the selection changing in the table view.
 */
-(void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	currentSelectedRow = [messageList selectedRow];
	[self refreshMessageAtRow:currentSelectedRow markRead:!isAppInitialising];
}

/* didClickTableColumns
 * Handle the user click in the column header to sort by that column.
 */
-(void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{
	NSString * columnName = [tableColumn identifier];
	[self sortByIdentifier:columnName];
}

/* tableViewColumnDidResize
 * This notification is called when the user completes resizing a column. We obtain the
 * new column size and save the settings.
 */
-(void)tableViewColumnDidResize:(NSNotification *)notification
{
	NSTableColumn * tableColumn = [[notification userInfo] objectForKey:@"NSTableColumn"];
	Field * field = [db fieldByName:[tableColumn identifier]];
	int oldWidth = [[[notification userInfo] objectForKey:@"NSOldWidth"] intValue];
	
	if (oldWidth != [tableColumn width])
	{
		[field setWidth:[tableColumn width]];
		[self saveTableSettings];
	}
}

/* writeRows
 * Called to initiate a drag from MessageListView. Use the common copy selection code to copy to
 * the pasteboard.
 */
-(BOOL)tableView:(NSTableView *)tv writeRows:(NSArray *)rows toPasteboard:(NSPasteboard *)pboard
{
	return [self copyTableSelection:rows toPasteboard:pboard];
}

/* copyTableSelection
 * This is the common copy selection code. We build an array of dictionary entries each of
 * which include details of each selected message in the standard RSS item format defined by
 * Ranchero NetNewsWire. See http://ranchero.com/netnewswire/rssclipboard.php for more details.
 */
-(BOOL)copyTableSelection:(NSArray *)rows toPasteboard:(NSPasteboard *)pboard
{
	NSMutableArray * arrayOfArticles = [[NSMutableArray alloc] init];
	NSMutableString * fullHTMLText = [[NSMutableString alloc] init];
	NSMutableString * fullPlainText = [[NSMutableString alloc] init];
	int count = [rows count];
	int index;
	
	// Set up the pasteboard
	[pboard declareTypes:[NSArray arrayWithObjects:RSSItemType, NSStringPboardType, NSHTMLPboardType, nil] owner:self];
	
	// Open the HTML string
	[fullHTMLText appendString:@"<html><body>"];
	
	// Get all the messages that are being dragged
	for (index = 0; index < count; ++index)
	{
		int msgIndex = [[rows objectAtIndex:index] intValue];
		Message * thisMessage = [currentArrayOfMessages objectAtIndex:msgIndex];
		Folder * folder = [db folderFromID:[thisMessage folderId]];
		NSString * msgText = [db messageText:[thisMessage folderId] guid:[thisMessage guid]];
		NSString * msgTitle = [thisMessage title];
		NSString * msgLink = [thisMessage link];
		
		NSMutableDictionary * articleDict = [[NSMutableDictionary alloc] init];
		[articleDict setValue:msgTitle forKey:@"rssItemTitle"];
		[articleDict setValue:msgLink forKey:@"rssItemLink"];
		[articleDict setValue:msgText forKey:@"rssItemDescription"];
		[articleDict setValue:[folder name] forKey:@"sourceName"];
		[articleDict setValue:[folder homePage] forKey:@"sourceHomeURL"];
		[articleDict setValue:[folder feedURL] forKey:@"sourceRSSURL"];
		[arrayOfArticles addObject:articleDict];
		[articleDict release];
		
		// Plain text
		[fullPlainText appendFormat:@"%@\n%@\n\n", msgTitle, msgText];
		
		// Add HTML version too.
		[fullHTMLText appendFormat:@"<a href=\"%@\">%@</a><br />%@<br /><br />", msgLink, msgTitle, msgText];
	}
	
	// Close the HTML string
	[fullHTMLText appendString:@"</body></html>"];
	
	// Put string on the pasteboard for external drops.
	[pboard setPropertyList:arrayOfArticles forType:RSSItemType];
	[pboard setString:fullHTMLText forType:NSHTMLPboardType];
	[pboard setString:fullPlainText forType:NSStringPboardType];
	
	[arrayOfArticles release];
	[fullHTMLText release];
	[fullPlainText release];
	return YES;
}

/* allMessages
 * Return an array of all articles in the list.
 */
-(NSArray *)allMessages
{
	return currentArrayOfMessages;
}

/* markedMessageRange
 * Retrieve an array of selected articles.
 */
-(NSArray *)markedMessageRange
{
	NSArray * messageArray = nil;
	if ([messageList numberOfSelectedRows] > 0)
	{
		NSEnumerator * enumerator = [messageList selectedRowEnumerator];
		NSMutableArray * newArray = [[NSMutableArray alloc] init];
		NSNumber * rowIndex;
		
		while ((rowIndex = [enumerator nextObject]) != nil)
			[newArray addObject:[currentArrayOfMessages objectAtIndex:[rowIndex intValue]]];
		messageArray = [newArray retain];
		[newArray release];
	}
	return messageArray;
}

/* markDeletedUndo
 * Undo handler to restore a series of deleted messages.
 */
-(void)markDeletedUndo:(id)anObject
{
	[self markDeletedByArray:(NSArray *)anObject deleteFlag:NO];
}

/* markUndeletedUndo
 * Undo handler to delete a series of messages.
 */
-(void)markUndeletedUndo:(id)anObject
{
	[self markDeletedByArray:(NSArray *)anObject deleteFlag:YES];
}

/* markDeletedByArray
 * Helper function. Takes as an input an array of messages and deletes or restores
 * the messages.
 */
-(void)markDeletedByArray:(NSArray *)messageArray deleteFlag:(BOOL)deleteFlag
{
	NSEnumerator * enumerator = [messageArray objectEnumerator];
	Message * theArticle;
	
	// Set up to undo this action
	NSUndoManager * undoManager = [[NSApp mainWindow] undoManager];
	SEL markDeletedUndoAction = deleteFlag ? @selector(markDeletedUndo:) : @selector(markUndeletedUndo:);
	[undoManager registerUndoWithTarget:self selector:markDeletedUndoAction object:messageArray];
	[undoManager setActionName:NSLocalizedString(@"Delete", nil)];
	
	// We will make a new copy of the currentArrayOfMessages with the selected messages removed.
	NSMutableArray * arrayCopy = [[NSMutableArray alloc] initWithArray:currentArrayOfMessages];
	BOOL needFolderRedraw = NO;
	
	// Iterate over every selected message in the table and set the deleted
	// flag on the message while simultaneously removing it from our copy of
	// currentArrayOfMessages.
	[db beginTransaction];
	while ((theArticle = [enumerator nextObject]) != nil)
	{
		if (![theArticle isRead])
			needFolderRedraw = YES;
		[db markMessageDeleted:[theArticle folderId] guid:[theArticle guid] isDeleted:deleteFlag];
		if (deleteFlag)
		{
			if ([theArticle folderId] == currentFolderId)
				[arrayCopy removeObject:theArticle];
		}
		else
		{
			if ([theArticle folderId] == currentFolderId)
				[arrayCopy addObject:theArticle];
		}
	}
	[db commitTransaction];
	[currentArrayOfMessages release];
	currentArrayOfMessages = arrayCopy;
	
	// If we've added messages back to the array, we need to resort to put
	// them back in the right place.
	if (!deleteFlag)
		[self sortMessages];
	
	// If any of the messages we deleted were unread then the
	// folder's unread count just changed.
	if (needFolderRedraw)
		[foldersTree updateFolder:currentFolderId recurseToParents:YES];
	
	// Compute the new place to put the selection
	if (currentSelectedRow >= (int)[currentArrayOfMessages count])
		currentSelectedRow = [currentArrayOfMessages count] - 1;
	[self makeRowSelectedAndVisible:currentSelectedRow];
	[messageList reloadData];
	
	// Read and/or unread count may have changed
	if (needFolderRedraw)
		[controller showUnreadCountOnApplicationIcon];
}

/* deleteMessages
 * Physically delete all selected messages in the article list.
 */
-(void)deleteSelectedMessages
{		
	// Make a new copy of the currentArrayOfMessages with the selected message removed.
	NSMutableArray * arrayCopy = [[NSMutableArray alloc] initWithArray:currentArrayOfMessages];
	BOOL needFolderRedraw = NO;
	
	// Iterate over every selected message in the table and remove it from
	// the database.
	NSEnumerator * enumerator = [messageList selectedRowEnumerator];
	NSNumber * rowIndex;

	[db beginTransaction];
	while ((rowIndex = [enumerator nextObject]) != nil)
	{
		Message * theArticle = [currentArrayOfMessages objectAtIndex:[rowIndex intValue]];
		if (![theArticle isRead])
			needFolderRedraw = YES;
		if ([db deleteMessage:[theArticle folderId] guid:[theArticle guid]])
			[arrayCopy removeObject:theArticle];
	}
	[db commitTransaction];
	[currentArrayOfMessages release];
	currentArrayOfMessages = arrayCopy;
	
	// Blow away the undo stack here since undo actions may refer to
	// articles that have been deleted. This is a bit of a cop-out but
	// it's the easiest approach for now.
	[controller clearUndoStack];
	
	// If any of the messages we deleted were unread then the
	// folder's unread count just changed.
	if (needFolderRedraw)
		[foldersTree updateFolder:currentFolderId recurseToParents:YES];
	
	// Compute the new place to put the selection
	if (currentSelectedRow >= (int)[currentArrayOfMessages count])
		currentSelectedRow = [currentArrayOfMessages count] - 1;
	[self makeRowSelectedAndVisible:currentSelectedRow];
	[messageList reloadData];
	
	// Read and/or unread count may have changed
	if (needFolderRedraw)
		[controller showUnreadCountOnApplicationIcon];
}

/* markUnflagUndo
 * Undo handler to un-flag an array of articles.
 */
-(void)markUnflagUndo:(id)anObject
{
	[self markFlaggedByArray:(NSArray *)anObject flagged:NO];
}

/* markFlagUndo
 * Undo handler to flag an array of articles.
 */
-(void)markFlagUndo:(id)anObject
{
	[self markFlaggedByArray:(NSArray *)anObject flagged:YES];
}

/* markFlaggedByArray
 * Mark the specified messages in messageArray as flagged.
 */
-(void)markFlaggedByArray:(NSArray *)messageArray flagged:(BOOL)flagged
{
	NSEnumerator * enumerator = [messageArray objectEnumerator];
	Message * theArticle;
	
	// Set up to undo this action
	NSUndoManager * undoManager = [[NSApp mainWindow] undoManager];
	SEL markFlagUndoAction = flagged ? @selector(markUnflagUndo:) : @selector(markFlagUndo:);
	[undoManager registerUndoWithTarget:self selector:markFlagUndoAction object:messageArray];
	[undoManager setActionName:NSLocalizedString(@"Flag", nil)];
	
	[db beginTransaction];
	while ((theArticle = [enumerator nextObject]) != nil)
	{
		[theArticle markFlagged:flagged];
		[db markMessageFlagged:[theArticle folderId] guid:[theArticle guid] isFlagged:flagged];
	}
	[db commitTransaction];
	[messageList reloadData];
}

/* markUnreadUndo
 * Undo handler to mark an array of articles unread.
 */
-(void)markUnreadUndo:(id)anObject
{
	[self markReadByArray:(NSArray *)anObject readFlag:NO];
}

/* markReadUndo
 * Undo handler to mark an array of articles read.
 */
-(void)markReadUndo:(id)anObject
{
	[self markReadByArray:(NSArray *)anObject readFlag:YES];
}

/* markReadByArray
 * Helper function. Takes as an input an array of messages and marks those messages read or unread.
 */
-(void)markReadByArray:(NSArray *)messageArray readFlag:(BOOL)readFlag
{
	NSEnumerator * enumerator = [messageArray objectEnumerator];
	Message * theArticle;
	int lastFolderId = -1;
	int folderId;
	
	// Set up to undo this action
	NSUndoManager * undoManager = [[NSApp mainWindow] undoManager];
	SEL markReadUndoAction = readFlag ? @selector(markUnreadUndo:) : @selector(markReadUndo:);
	[undoManager registerUndoWithTarget:self selector:markReadUndoAction object:messageArray];
	[undoManager setActionName:NSLocalizedString(@"Mark Read", nil)];
	
	[markReadTimer invalidate];
	[markReadTimer release];
	markReadTimer = nil;
	
	[db beginTransaction];
	while ((theArticle = [enumerator nextObject]) != nil)
	{
		folderId = [theArticle folderId];
		[db markMessageRead:folderId guid:[theArticle guid] isRead:readFlag];
		if (folderId != currentFolderId)
		{
			[theArticle markRead:readFlag];
			[db flushFolder:folderId];
		}
		if (folderId != lastFolderId && lastFolderId != -1)
			[foldersTree updateFolder:lastFolderId recurseToParents:YES];
		lastFolderId = folderId;
	}
	[db commitTransaction];
	[messageList reloadData];
	
	if (lastFolderId != -1)
		[foldersTree updateFolder:lastFolderId recurseToParents:YES];
	[foldersTree updateFolder:currentFolderId recurseToParents:YES];
	
	// The info bar has a count of unread messages so we need to
	// update that.
	[controller showUnreadCountOnApplicationIcon];
}

/* dealloc
 * Clean up behind ourself.
 */
-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[db release];
	[stylePathMappings release];
	[cssStylesheet release];
	[htmlTemplate release];
	[extDateFormatter release];
	[markReadTimer release];
	[currentArrayOfMessages release];
	[backtrackArray release];
	[messageListFont release];
	[defaultWebPrefs release];
	[guidOfMessageToSelect release];
	[selectionDict release];
	[topLineDict release];
	[bottomLineDict release];
	[super dealloc];
}
@end
