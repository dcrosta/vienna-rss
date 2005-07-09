//
//  AppController.m
//  Vienna
//
//  Created by Steve on Sat Jan 24 2004.
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

#import "AppController.h"
#import "PreferenceController.h"
#import "PreferenceNames.h"
#import "FoldersTree.h"
#import "Import.h"
#import "Export.h"
#import "StringExtensions.h"
#import "CalendarExtensions.h"
#import "SplitViewExtensions.h"
#import "ImageAndTextCell.h"
#import "MessageView.h"
#import "MessageListView.h"
#import "ArticleView.h"
#import "CheckForUpdates.h"
#import "SearchFolder.h"
#import "NewSubscription.h"
#import "NewGroupFolder.h"
#import "SingleConnection.h"
#import "TexturedHeader.h"
#import "FeedCredentials.h"
#import "Credentials.h"
#import "WebKit/WebPreferences.h"
#import "WebKit/WebFrame.h"
#import "WebKit/WebPolicyDelegate.h"
#import "WebKit/WebUIDelegate.h"
#import "Growl/GrowlApplicationBridge.h"
#import "Growl/GrowlDefines.h"
#import "ActivityLog.h"

// Non-class function used for sorting
int messageSortHandler(id item1, id item2, void * context);

static NSString * MA_DefaultDatabaseName = @"~/Library/Application Support/Vienna/messages.db";
static NSString * MA_FolderImagesFolder = @"~/Library/Application Support/Vienna/Images";
static NSString * MA_StylesFolder = @"~/Library/Application Support/Vienna/Styles";
static NSString * MA_DefaultStyleName = @"Default";
static NSString * RSSItemType = @"CorePasteboardFlavorType 0x52535369";

#define GROWL_NOTIFICATION_DEFAULT @"NotificationDefault"

@implementation AppController

/* initialize
 * Application initialization.
 */
+(void)initialize
{
	// Set the preference defaults
	NSMutableDictionary * defaultValues = [NSMutableDictionary dictionary];
	NSNumber * cachedFolderID = [NSNumber numberWithInt:1];
	NSData * msgListFont = [NSArchiver archivedDataWithRootObject:[NSFont fontWithName:@"Helvetica" size:12.0]];
	NSData * folderFont = [NSArchiver archivedDataWithRootObject:[NSFont fontWithName:@"Helvetica" size:12.0]];
	NSNumber * boolNo = [NSNumber numberWithBool:NO];
	NSNumber * boolYes = [NSNumber numberWithBool:YES];

	[defaultValues setObject:MA_DefaultDatabaseName forKey:MAPref_DefaultDatabase];
	[defaultValues setObject:MA_FolderImagesFolder forKey:MAPref_FolderImagesFolder];
	[defaultValues setObject:MA_StylesFolder forKey:MAPref_StylesFolder];
	[defaultValues setObject:msgListFont forKey:MAPref_MessageListFont];
	[defaultValues setObject:folderFont forKey:MAPref_FolderFont];
	[defaultValues setObject:boolNo forKey:MAPref_CheckForUpdatesOnStartup];
	[defaultValues setObject:boolYes forKey:MAPref_CheckForNewMessagesOnStartup];
	[defaultValues setObject:cachedFolderID forKey:MAPref_CachedFolderID];
	[defaultValues setObject:[NSNumber numberWithInt:1] forKey:MAPref_SortDirection];
	[defaultValues setObject:MA_Column_MessageId forKey:MAPref_SortColumn];
	[defaultValues setObject:[NSNumber numberWithInt:0] forKey:MAPref_CheckFrequency];
	[defaultValues setObject:[NSNumber numberWithInt:6] forKey:MAPref_RefreshThreads];
	[defaultValues setObject:[NSArray arrayWithObjects:nil] forKey:MAPref_MessageColumns];
	[defaultValues setObject:boolYes forKey:MAPref_AutoCollapseFolders];
	[defaultValues setObject:MA_DefaultStyleName forKey:MAPref_ActiveStyleName];
	[defaultValues setObject:[NSNumber numberWithInt:20] forKey:MAPref_BacktrackQueueSize];
	[defaultValues setObject:boolNo forKey:MAPref_ReadingPaneOnRight];

	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
}

/* awakeFromNib
 * Do all the stuff that only makes sense after our NIB has been loaded and connected.
 */
-(void)awakeFromNib
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];

	// Find out who we are. The localised info in InfoStrings.plist allow
	// changing the app name if so desired.
	NSBundle * appBundle = [NSBundle mainBundle];
	appName = nil;
	if (appBundle != nil)
	{
		NSDictionary * fileAttributes = [appBundle localizedInfoDictionary];
		appName = [fileAttributes objectForKey:@"CFBundleName"];
	}
	if (appName == nil)
		appName = @"Vienna";

	// Create a dictionary that will be used to map styles to the
	// paths where they're located.
	stylePathMappings = [[NSMutableDictionary alloc] init];
	
	// Set the delegates and title
	[mainWindow setDelegate:self];
	[mainWindow setTitle:appName];
	[textView setDelegate:self];
	[NSApp setDelegate:self];

	// Set the reading pane orientation
	readingPaneOnRight = [defaults boolForKey:MAPref_ReadingPaneOnRight];
	[splitView2 setVertical:readingPaneOnRight];

	// Register a bunch of notifications
	NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleFolderSelection:) name:@"MA_Notify_FolderSelectionChange" object:nil];
	[nc addObserver:self selector:@selector(handleMessageListFontChange:) name:@"MA_Notify_MessageListFontChange" object:nil];
	[nc addObserver:self selector:@selector(handleCheckFrequencyChange:) name:@"MA_Notify_CheckFrequencyChange" object:nil];
	[nc addObserver:self selector:@selector(handleFolderUpdate:) name:@"MA_Notify_FoldersUpdated" object:nil];
	[nc addObserver:self selector:@selector(checkForUpdatesComplete:) name:@"MA_Notify_UpdateCheckCompleted" object:nil];
	[nc addObserver:self selector:@selector(handleEditFolder:) name:@"MA_Notify_EditFolder" object:nil];
	[nc addObserver:self selector:@selector(handleConnectionCompleted:) name:@"MA_Notify_ConnectionCompleted" object:nil];
	[nc addObserver:self selector:@selector(handleGotAuthenticationForFolder:) name:@"MA_Notify_GotAuthenticationForFolder" object:nil];
	[nc addObserver:self selector:@selector(handleRequireAuthenticationForFolder:) name:@"MA_Notify_RequireAuthenticationForFolder" object:nil];
	[nc addObserver:self selector:@selector(handleCancelAuthenticationForFolder:) name:@"MA_Notify_CancelAuthenticationForFolder" object:nil];

	// Init the progress counter and status bar.
	progressCount = 0;
	persistedStatusText = nil;
	[self setStatusMessage:nil persist:NO];

	// Create a refresh array (note the initial capacity is dynamically
	// extended as needed and is not a limit).
	maximumConnections = [[defaults valueForKey:MAPref_RefreshThreads] intValue];
	totalConnections = 0;
	unreadAtBeginning = 0;
	refreshArray = [[NSMutableArray alloc] initWithCapacity:10];
	connectionsArray = [[NSMutableArray alloc] initWithCapacity:maximumConnections];
	
	// Initialize the database
	db = [[Database alloc] init];
	if (![db initDatabase:[defaults stringForKey:MAPref_DefaultDatabase]])
	{
		[NSApp terminate:nil];
		return;
	}

	// Make ourselves a date formatter. Useful for many things except stirring soup.
	extDateFormatter = [[ExtDateFormatter alloc] init];

	// Initialize the message list
	[self initTableView];

	// Initialize the Styles, Sort By and Columns menu
	[self initSortMenu];
	[self initColumnsMenu];
	[self initStylesMenu];

	// Restore the splitview layout
	[splitView1 loadLayoutWithName:@"SplitView1Positions"];
	[splitView2 loadLayoutWithName:@"SplitView2Positions"];

	// Load the conference list from the database
	[foldersTree initialiseFoldersTree:db];

	// Create a backtrack array
	isBacktracking = NO;
	selectAtEndOfReload = MA_Select_Unread;
	backtrackArray = [[BackTrackArray alloc] initWithMaximum:[defaults integerForKey:MAPref_BacktrackQueueSize]];

	// Create an authentication queue used to queue up folders that require
	// authentication during a refresh. We can only authenticate one folder at
	// a time so the queue is required to supply each folder to the authentication
	// UI in turn.
	authQueue = [[NSMutableArray alloc] init];
	
	// Set header text
	[folderHeader setStringValue:NSLocalizedString(@"Folders", nil)];
	[messageListHeader setStringValue:NSLocalizedString(@"Messages", nil)];
	
	// Make us the policy and UI delegate for the web view
	[textView setPolicyDelegate:self];
	[textView setUIDelegate:self];

	// Select the default style
	htmlTemplate = nil;
	cssStylesheet = nil;
	[self setActiveStyle:[defaults stringForKey:MAPref_ActiveStyleName] refresh:NO];
	
	// Select the first conference
	int previousFolderId = [defaults integerForKey:MAPref_CachedFolderID];
	[foldersTree selectFolder:previousFolderId];

	// Show the current unread count on the app icon
	originalIcon = [[NSApp applicationIconImage] copy];
	lastCountOfUnread = 0;
	[self showUnreadCountOnApplicationIcon];

	// Use Growl if it is installed
	growlAvailable = NO;
	[GrowlApplicationBridge setGrowlDelegate:self];

	// Start the check timer
	checkTimer = nil;
	[self handleCheckFrequencyChange:nil];
}

/* readingPaneOnRight
 * Move the reading pane to the right of the message list.
 */
-(IBAction)readingPaneOnRight:(id)sender
{
	[self setReadingPaneOnRight:YES];
}

/* readingPaneOnBottom
 * Move the reading pane to the bottom of the message list.
 */
-(IBAction)readingPaneOnBottom:(id)sender
{
	[self setReadingPaneOnRight:NO];
}

/* setReadingPaneOnRight
 * Sets whether the reading pane appears on the right of the message list or
 * at the bottom of the message list.
 */
-(void)setReadingPaneOnRight:(BOOL)flag
{
	if (readingPaneOnRight != flag)
	{
		readingPaneOnRight = flag;
		[splitView2 setVertical:readingPaneOnRight];
		[splitView2 display];
		[[NSUserDefaults standardUserDefaults] setBool:readingPaneOnRight forKey:MAPref_ReadingPaneOnRight];
	}
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
		[[NSWorkspace sharedWorkspace] openURL:[request URL]];
	}
	[listener use];
}

/* setStatusText
 * Called from the webview when some JavaScript writes status text. Echo this to
 * our status bar.
 */
-(void)webView:(WebView *)sender setStatusText:(NSString *)text
{
	[self setStatusMessage:text persist:NO];
}

/* mouseDidMoveOverElement
 * Called from the webview when the user positions the mouse over an element. If it's a link
 * then echo the URL to the status bar like Safari does.
 */
-(void)webView:(WebView *)sender mouseDidMoveOverElement:(NSDictionary *)elementInformation modifierFlags:(unsigned int)modifierFlags
{
	NSURL * url = [elementInformation valueForKey:@"WebElementLinkURL"];
	[self setStatusMessage:(url ? [url absoluteString] : @"") persist:NO];
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

/* ourOpenLinkHandler
 * Handles the "Open Link in Browser" command in the web view. Previously we will
 * have primed the menu represented object with the NSURL of the link.
 */
-(IBAction)ourOpenLinkHandler:(id)sender
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	NSURL * url = [menuItem representedObject];

	if (url != nil)
		[[NSWorkspace sharedWorkspace] openURL:url];
}

/* growlIsReady
 * Called by Growl when it is loaded. We use this as a trigger to acknowledge its existence.
 */
-(void)growlIsReady
{
	if (!growlAvailable)
	{
		[GrowlApplicationBridge setGrowlDelegate:self];
		growlAvailable = YES;
	}
}

/* registrationDictionaryForGrowl
 * Called by Growl to request the notification dictionary.
 */
-(NSDictionary *)registrationDictionaryForGrowl
{
	NSMutableArray *defNotesArray = [NSMutableArray array];
	NSMutableArray *allNotesArray = [NSMutableArray array];
	
	[allNotesArray addObject:@"New Articles"];
	[defNotesArray addObject:@"New Articles"];
	
	NSDictionary *regDict = [NSDictionary dictionaryWithObjectsAndKeys:
		appName, GROWL_APP_NAME, 
		allNotesArray, GROWL_NOTIFICATIONS_ALL, 
		defNotesArray, GROWL_NOTIFICATIONS_DEFAULT,
		nil];
	growlAvailable = YES;
	return regDict;
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
	requestedMessage = 0;
	messageListFont = nil;

	// Initialize sort to default to message number
	[self setSortColumnIdentifier:[defaults stringForKey:MAPref_SortColumn]];
	sortDirection = [defaults integerForKey:MAPref_SortDirection];
	sortColumnTag = [[db fieldByIdentifier:sortColumnIdentifier] tag];

	// Initialize the message columns from saved data
	NSArray * dataArray = [defaults arrayForKey:MAPref_MessageColumns];
	Field * field;
	unsigned int index;
	
	for (index = 0; index < [dataArray count];)
	{
		NSString * identifier;
		int width = 100;
		BOOL visible = NO;

		identifier = [dataArray objectAtIndex:index++];
		if (index < [dataArray count])
			visible = [[dataArray objectAtIndex:index++] intValue] == YES;
		if (index < [dataArray count])
			width = [[dataArray objectAtIndex:index++] intValue];

		field = [db fieldByIdentifier:identifier];
		[field setVisible:visible];
		[field setWidth:width];
	}

	// Get the default list of visible columns
	[self updateVisibleColumns];
	
	// Remember the folder column state
	Field * folderField = [db fieldByIdentifier:MA_Column_MessageFolderId];
	previousFolderColumnState = [folderField visible];	

	// Set the target for double-click actions
	[messageList setDoubleAction:@selector(doubleClickRow:)];
	[messageList setAction:@selector(singleClickRow:)];
	[messageList setTarget:self];
	
	// Set the default fonts
	[self setTableViewFont];
}

/* initSortMenu
 * Create the sort popup menu.
 */
-(void)initSortMenu
{
	NSMenu * viewMenu = [[[NSApp mainMenu] itemWithTitle:@"View"] submenu];
	NSMenu * sortMenu = [[[NSMenu alloc] initWithTitle:@"Sort By"] autorelease];
	NSArray * fields = [db arrayOfFields];
	NSEnumerator * enumerator = [fields objectEnumerator];
	Field * field;

	while ((field = [enumerator nextObject]) != nil)
	{
		// Filter out columns we don't sort on. Later we should have an attribute in the
		// field object itself based on which columns we can sort on.
		if ([field tag] != MA_ID_MessageFolderId &&
			[field tag] != MA_ID_MessageParentId &&
			[field tag] != MA_ID_MessageText)
		{
			NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:[field displayName] action:@selector(doSortColumn:) keyEquivalent:@""];
			[menuItem setRepresentedObject:field];
			[sortMenu addItem:menuItem];
			[menuItem release];
		}
	}
	[[viewMenu itemWithTitle:@"Sort By"] setSubmenu:sortMenu];
}

/* initColumnsMenu
 * Create the columns popup menu.
 */
-(void)initColumnsMenu
{
	NSMenu * viewMenu = [[[NSApp mainMenu] itemWithTitle:@"View"] submenu];
	NSMenu * columnsMenu = [[[NSMenu alloc] initWithTitle:@"Columns"] autorelease];
	NSArray * fields = [db arrayOfFields];
	NSEnumerator * enumerator = [fields objectEnumerator];
	Field * field;
	
	while ((field = [enumerator nextObject]) != nil)
	{
		// Filter out columns we don't view in the message list. Later we should have an attribute in the
		// field object based on which columns are visible in the tableview.
		if ([field tag] != MA_ID_MessageText && [field tag] != MA_ID_MessageParentId)
		{
			NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:[field displayName] action:@selector(doViewColumn:) keyEquivalent:@""];
			[menuItem setRepresentedObject:field];
			[columnsMenu addItem:menuItem];
			[menuItem release];
		}
	}
	[[viewMenu itemWithTitle:@"Columns"] setSubmenu:columnsMenu];
}

/* showColumnsForFolder
 * Display the columns for the specific folder.
 */
-(void)showColumnsForFolder:(int)folderId
{
	Folder * folder = [db folderFromID:folderId];
	Field * folderField = [db fieldByIdentifier:MA_Column_MessageFolderId];
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

	// Get the bounds of the message list because we need to work out
	// when the columns spill beyond the bounds
	int widthSoFar = 0;
	int countOfResizableColumns = 0;

	// Create the new columns
	for (index = 0; index < count; ++index)
	{
		Field * field = [fields objectAtIndex:index];
		NSString * identifier = [field name];

		// Remove each column as we go.
		NSTableColumn * tableColumn = [messageList tableColumnWithIdentifier:identifier];
		if (tableColumn != nil)
		{
			if (index + 1 != count)
				[field setWidth:[tableColumn width]];
			[messageList removeTableColumn:tableColumn];
		}

		// Add to the end only those columns that are visible
		if ([field visible])
		{
			NSTableColumn * newTableColumn = [[NSTableColumn alloc] initWithIdentifier:identifier];
			NSTableHeaderCell * headerCell = [newTableColumn headerCell];
			int tag = [field tag];
			BOOL isResizable = (tag != MA_ID_MessageUnread && tag != MA_ID_MessageFlagged && tag != MA_ID_MessageComments);

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

			widthSoFar += [field width];
			if (isResizable)
				++countOfResizableColumns;
		}
	}

	// Set the extended date formatter on the Date column
	NSTableColumn * tableColumn = [messageList tableColumnWithIdentifier:MA_Column_MessageDate];
	[[tableColumn dataCell] setFormatter:extDateFormatter];
	
	// Set the images for specific header columns
	[messageList setHeaderImage:MA_Column_MessageUnread imageName:@"unread_header.tiff"];
	[messageList setHeaderImage:MA_Column_MessageFlagged imageName:@"flagged_header.tiff"];
	[messageList setHeaderImage:MA_Column_MessageComments imageName:@"comments_header.tiff"];
	
	// Initialise the sort direction
	[self showSortDirection];	
	
	// Extend the last column
	//[messageList sizeLastColumnToFit];
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
	
	// We're done
	[dataArray release];
}

/* setTableViewFont
 * Gets the font for the message list and adjusts the table view
 * row height to properly display that font.
 */
-(void)setTableViewFont
{
	int height;
	
	[messageListFont release];
	
	NSData * fontData = [[NSUserDefaults standardUserDefaults] objectForKey:MAPref_MessageListFont];
	messageListFont = [NSUnarchiver unarchiveObjectWithData:fontData];
	
	height = [messageListFont defaultLineHeightForFont];
	[messageList setRowHeight:height + 3];
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

/* initStylesMenu
 * Populate the Styles menu with a list of built-in and external styles. (Note that in the event of
 * duplicates the styles in the external Styles folder wins. This is intended to allow the user to
 * override the built-in styles if necessary).
 */
-(void)initStylesMenu
{
	NSMenu * stylesMenu = [[[NSMenu alloc] initWithTitle:@"Style"] autorelease];

	NSString * path = [[[NSBundle mainBundle] sharedSupportPath] stringByAppendingPathComponent:@"Styles"];
	[self initStylesMenu:stylesMenu fromPath:path];

	path = [[[NSUserDefaults standardUserDefaults] objectForKey:MAPref_StylesFolder] stringByExpandingTildeInPath];
	[self initStylesMenu:stylesMenu fromPath:path];

	NSMenu * viewMenu = [[[NSApp mainMenu] itemWithTitle:@"View"] submenu];
	[[viewMenu itemWithTitle:@"Style"] setSubmenu:stylesMenu];
}

/* initStylesMenuFromPath
 * Initialises the Styles menu with the contents of the specified path.
 */
-(void)initStylesMenu:(NSMenu *)stylesMenu fromPath:(NSString *)path
{
	NSFileManager * fileManager = [NSFileManager defaultManager];
	NSArray * arrayOfStyles = [fileManager directoryContentsAtPath:path];
	if (arrayOfStyles != nil)
	{
		NSEnumerator * enumerator = [arrayOfStyles objectEnumerator];
		NSString * styleName;

		while ((styleName = [enumerator nextObject]) != nil)
		{
			BOOL isDirectory;
			if ([fileManager fileExistsAtPath:[path stringByAppendingPathComponent:styleName] isDirectory:&isDirectory] && isDirectory)
			{
				if ([stylePathMappings valueForKey:styleName] == nil)
				{
					NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:styleName action:@selector(doSelectStyle:) keyEquivalent:@""];
					[stylesMenu addItem:menuItem];
					[menuItem release];
				}
				[stylePathMappings setValue:[path stringByAppendingPathComponent:styleName] forKey:styleName];
			}
		}
	}
}

/* showUnreadCountOnApplicationIcon
 * Update the Vienna application icon to show the number of unread messages.
 */
-(void)showUnreadCountOnApplicationIcon
{
	int currentCountOfUnread = [db countOfUnread];
	if (currentCountOfUnread != lastCountOfUnread)
	{
		if (currentCountOfUnread > 0)
		{
			NSString *countdown = [NSString stringWithFormat:@"%i", currentCountOfUnread];
			NSImage * iconImageBuffer = [originalIcon copy];
			NSSize iconSize = [originalIcon size];

			// Create attributes for drawing the count. In our case, we're drawing using in
			// 26pt Helvetica bold white.
			NSDictionary * attributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSFont fontWithName:@"Helvetica-Bold" size:26],
																					 NSFontAttributeName,
																					 [NSColor whiteColor],
																					 NSForegroundColorAttributeName,
																					 nil];
			NSSize numSize = [countdown sizeWithAttributes:attributes];

			// Create a red circle in the icon large enough to hold the count.
			[iconImageBuffer lockFocus];
			[originalIcon drawAtPoint:NSMakePoint(0, 0)
							 fromRect:NSMakeRect(0, 0, iconSize.width, iconSize.height) 
							operation:NSCompositeSourceOver 
							 fraction:1.0f];
			float max = (numSize.width > numSize.height) ? numSize.width : numSize.height;
			max += 16;
			NSRect circleRect = NSMakeRect(iconSize.width - max, 0, max, max);
			NSBezierPath * bp = [NSBezierPath bezierPathWithOvalInRect:circleRect];
			[[NSColor colorWithCalibratedRed:0.8f green:0.0f blue:0.0f alpha:1.0f] set];
			[bp fill];

			// Draw the count in the red circle
			NSPoint point = NSMakePoint(NSMidX(circleRect) - numSize.width / 2.0f,  NSMidY(circleRect) - numSize.height / 2.0f + 2.0f);
			[countdown drawAtPoint:point withAttributes:attributes];

			// Now set the new app icon and clean up.
			[iconImageBuffer unlockFocus];
			[NSApp setApplicationIconImage:iconImageBuffer];
			[iconImageBuffer release];
			[attributes release];
		}
		else
			[NSApp setApplicationIconImage:originalIcon];
		lastCountOfUnread = currentCountOfUnread;
	}
}

/* showPreferencePanel
 * Display the Preference Panel.
 */
-(IBAction)showPreferencePanel:(id)sender
{
	if (!preferenceController)
		preferenceController = [[PreferenceController alloc] init];
	[preferenceController showWindow:self];
}

/* applicationShouldTerminate
 * This function is called when the user wants to close Vienna. First we check to see
 * if a connection or import is running and that all messages are saved.
 */
-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if (totalConnections > 0)
	{
		int returnCode;
		
		returnCode = NSRunAlertPanel(NSLocalizedString(@"Connect Running", nil),
									 NSLocalizedString(@"Connect Running text", nil),
									 NSLocalizedString(@"Quit", nil),
									 NSLocalizedString(@"Cancel", nil),
									 nil);
		if (returnCode == NSAlertAlternateReturn)
			return NSTerminateCancel;
	}
	return NSTerminateNow;
}

/* applicationWillTerminate
 * This is where we put the clean-up code.
 */
-(void)applicationWillTerminate:(NSNotification *)aNotification
{
	// Save the splitview layout
	[splitView1 storeLayoutWithName:@"SplitView1Positions"];
	[splitView2 storeLayoutWithName:@"SplitView2Positions"];

	// Close the activity window explicitly to force it to
	// save its split bar position to the preferences.
	NSWindow * activityWindow = [activityViewer window];
	[activityWindow performClose:self];
	
	// Remember the message list column position, sizes, etc.
	[self saveTableSettings];
	[foldersTree saveFolderSettings];

	if (currentFolderId != -1)
		[db flushFolder:currentFolderId];
	[db close];
}

/* windowWillClose
 * Handle closure of the main window. If we get applicationShouldTerminateAfterLastWindowClosed working
 * (see below) then we can remove this function.
 */
-(void)windowWillClose:(NSNotification *)notification
{
	[NSApp terminate:nil];
}

/* applicationShouldTerminateAfterLastWindowClosed
 * This is supposed to get called when the last window owned by the application is closed but
 * this isn't happening here. Not sure why but we need to debug this.
 */
-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

/* applicationDidFinishLaunching
 * Handle post-load activities.
 */
-(void)applicationDidFinishLaunching:(NSNotification *)aNot
{
	// Check for application updates silently
	if ([[NSUserDefaults standardUserDefaults] boolForKey:MAPref_CheckForUpdatesOnStartup])
	{
		if (!checkUpdates)
			checkUpdates = [[CheckForUpdates alloc] init];
		[checkUpdates checkForUpdate:mainWindow showUI:NO];
	}

	// Kick off an initial refresh
	if ([[NSUserDefaults standardUserDefaults] boolForKey:MAPref_CheckForNewMessagesOnStartup])
		[self refreshAllSubscriptions:self];
}

/* compactDatabase
 * Run the database compaction command.
 */
-(IBAction)compactDatabase:(id)sender
{
	[NSApp beginSheet:compactDatabaseWindow
	   modalForWindow:mainWindow 
		modalDelegate:nil 
	   didEndSelector:nil 
		  contextInfo:nil];

	[db compactDatabase];

	[NSApp endSheet:compactDatabaseWindow];
	[compactDatabaseWindow orderOut:self];
}

/* scrollToMessage
 * Moves the selection to the specified message. Returns YES if we found the
 * message, NO otherwise.
 */
-(BOOL)scrollToMessage:(int)number
{
	NSEnumerator * enumerator = [currentArrayOfMessages objectEnumerator];
	Message * thisMessage;
	int rowIndex = 0;
	BOOL found = NO;

	while ((thisMessage = [enumerator nextObject]) != nil)
	{
		if ([thisMessage number] == number)
		{
			[self makeRowSelectedAndVisible:rowIndex];
			found = YES;
			break;
		}
		++rowIndex;
	}
	requestedMessage = 0;
	return found;
}

/* printDocument
 * Print the current message in the message window.
 */
-(IBAction)printDocument:(id)sender
{
	NSPrintInfo * printInfo = [NSPrintInfo sharedPrintInfo];
	NSPrintOperation * printOp;
	
	[printInfo setVerticallyCentered:NO];
	printOp = [NSPrintOperation printOperationWithView:textView printInfo:printInfo];
	[printOp setShowPanels:YES];
	[printOp runOperation];
}

/* folders
 * Return the array of folders.
 */
-(NSArray *)folders
{
	return [foldersTree folders:MA_Root_Folder];
}

/* database
 * Return the active application database object.
 */
-(Database *)database
{
	return db;
}

/* appName
 * Returns's the application friendly (localized) name.
 */
-(NSString *)appName
{
	return appName;
}

/* currentFolderId
 * Return the ID of the currently selected folder whose messages are shown in
 * the message window.
 */
-(int)currentFolderId
{
	return currentFolderId;
}

/* handleRSSLink
 * Handle feed://<rss> links. If we're already subscribed to the link then make the folder
 * active. Otherwise offer to subscribe to the link.
 */
-(void)handleRSSLink:(NSString *)linkPath
{
	Folder * folder = [db folderFromFeedURL:linkPath];
	if (folder != nil)
		[foldersTree selectFolder:[folder itemId]];
	else
	{
		if (!rssFeed)
			rssFeed = [[NewSubscription alloc] initWithDatabase:db];
		[rssFeed newSubscription:mainWindow underParent:MA_Root_Folder initialURL:linkPath];
	}
}

/* handleEditFolder
 * Respond to an edit folder notification.
 */
-(void)handleEditFolder:(NSNotification *)nc
{
	TreeNode * node = (TreeNode *)[nc object];
	Folder * folder = [db folderFromID:[node nodeId]];
	[self doEditFolder:folder];
}

/* editFolder
 * Handles the Edit command
 */
-(IBAction)editFolder:(id)sender
{
	Folder * folder = [db folderFromID:[foldersTree actualSelection]];
	[self doEditFolder:folder];
}

/* doEditFolder
 * Handles an edit action on the specified folder.
 */
-(void)doEditFolder:(Folder *)folder
{
	if (IsRSSFolder(folder))
	{
		if (!rssFeed)
			rssFeed = [[NewSubscription alloc] initWithDatabase:db];
		[rssFeed editSubscription:mainWindow folderId:[folder itemId]];
	}
	else if (IsSmartFolder(folder))
	{
		if (!smartFolder)
			smartFolder = [[SearchFolder alloc] initWithDatabase:db];
		[smartFolder loadCriteria:mainWindow folderId:[folder itemId]];
	}
}

/* handleFolderUpdate
 * Called if a folder content has changed.
 */
-(void)handleFolderUpdate:(NSNotification *)nc
{
	int folderId = [(NSNumber *)[nc object] intValue];
	if (folderId == currentFolderId)
	{
		[self setMainWindowTitle:folderId];
		[self refreshFolder:YES];
	}
}

/* handleFolderSelection
 * Called when the selection changes in the folder pane.
 */
-(void)handleFolderSelection:(NSNotification *)note
{
	TreeNode * node = (TreeNode *)[note object];
	int newFolderId = [node nodeId];

	// We only care if the selection really changed
	if (currentFolderId != newFolderId && newFolderId != 0)
	{
		// Blank out the search field
		[searchField setStringValue:@""];
		[self selectFolderWithFilter:newFolderId];
		[[NSUserDefaults standardUserDefaults] setInteger:currentFolderId forKey:MAPref_CachedFolderID];
	}
}

/* handleMessageListFontChange
 * Called when the user changes the message list font and/or size in the Preferences
 */
-(void)handleMessageListFontChange:(NSNotification *)note
{
	[self setTableViewFont];
	[messageList reloadData];
}

/* handleCheckFrequencyChange
 * Called when the frequency by which we check messages is changed.
 */
-(void)handleCheckFrequencyChange:(NSNotification *)note
{
	int newFrequency = [[NSUserDefaults standardUserDefaults] integerForKey:MAPref_CheckFrequency];

	[checkTimer invalidate];
	[checkTimer release];
	if (newFrequency > 0)
	{
		checkTimer = [[NSTimer scheduledTimerWithTimeInterval:newFrequency
													   target:self
													 selector:@selector(getMessagesOnTimer:)
													 userInfo:nil
													  repeats:YES] retain];
	}
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
	AppController * app = (AppController *)context;

	switch (app->sortColumnTag)
	{
		case MA_ID_MessageId: {
			int number1 = [item1 number];
			int number2 = [item2 number];
			if (number1 < number2)
				return NSOrderedAscending * app->sortDirection;
			if (number2 < number1)
				return NSOrderedDescending * app->sortDirection;
			return NSOrderedSame;
		}

		case MA_ID_MessageFolderId: {
			Folder * folder1 = [app->db folderFromID:[item1 folderId]];
			Folder * folder2 = [app->db folderFromID:[item2 folderId]];
			return [[folder1 name] caseInsensitiveCompare:[folder2 name]] * app->sortDirection;
		}
			
		case MA_ID_MessageUnread: {
			BOOL n1 = [item1 isRead];
			BOOL n2 = [item2 isRead];
			return (n1 < n2) * app->sortDirection;
		}

		case MA_ID_MessageFlagged: {
			BOOL n1 = [item1 isFlagged];
			BOOL n2 = [item2 isFlagged];
			return (n1 < n2) * app->sortDirection;
		}

		case MA_ID_MessageComments: {
			BOOL n1 = [item1 hasComments];
			BOOL n2 = [item2 hasComments];
			return (n1 < n2) * app->sortDirection;
		}
			
		case MA_ID_MessageDate: {
			NSDate * n1 = [[item1 messageData] objectForKey:MA_Column_MessageDate];
			NSDate * n2 = [[item2 messageData] objectForKey:MA_Column_MessageDate];
			return [n1 compare:n2] * app->sortDirection;
		}
			
		case MA_ID_MessageFrom: {
			NSString * n1 = [[item1 messageData] objectForKey:MA_Column_MessageFrom];
			NSString * n2 = [[item2 messageData] objectForKey:MA_Column_MessageFrom];
			return [n1 caseInsensitiveCompare:n2] * app->sortDirection;
		}
			
		case MA_ID_MessageTitle: {
			NSString * n1 = [[item1 messageData] objectForKey:MA_Column_MessageTitle];
			NSString * n2 = [[item2 messageData] objectForKey:MA_Column_MessageTitle];
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
		[self refreshMessageAtRow:rowIndex];
	else
	{
		[messageList selectRow:rowIndex byExtendingSelection:NO];
		[self centerSelectedRow];
	}
}

/* centerSelectedRow
 * Center the selected row in the table view.
 */
-(void)centerSelectedRow
{
	int rowIndex = [messageList selectedRow];
	int pageSize = [messageList rowsInRect:[messageList visibleRect]].length;
	int lastRow = [messageList numberOfRows] - 1;
	int visibleRow = rowIndex + (pageSize / 2);
	
	if (visibleRow > lastRow)
		visibleRow = lastRow;
	[messageList scrollRowToVisible:rowIndex];
	[messageList scrollRowToVisible:visibleRow];
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
	Field * field = [db fieldByIdentifier:[tableColumn identifier]];
	int oldWidth = [[[notification userInfo] objectForKey:@"NSOldWidth"] intValue];

	if (oldWidth != [tableColumn width])
	{
		[field setWidth:[tableColumn width]];
		[self saveTableSettings];
	}
}

/* doViewColumn
 * Toggle whether or not a specified column is visible.
 */
-(void)doViewColumn:(id)sender;
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	Field * field = [menuItem representedObject];

	[field setVisible:![field visible]];
	[self updateVisibleColumns];
	[self saveTableSettings];
}

/* doSortColumn
 * Handle the user picking an item from the Sort By submenu
 */
-(void)doSortColumn:(id)sender
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	Field * field = [menuItem representedObject];

	NSAssert1(field, @"Somehow got a nil representedObject for Sort sub-menu item '%@'", [menuItem title]);
	[self sortByIdentifier:[field name]];
}

/* doSelectStyle
 * Handle a selection from the Style menu.
 */
-(IBAction)doSelectStyle:(id)sender
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	[self setActiveStyle:[menuItem title] refresh:YES];
}

/* setActiveStyle
 * Sets the active style used for rendering messages.
 */
-(void)setActiveStyle:(NSString *)newStyleName refresh:(BOOL)refresh
{
	NSString * path = [stylePathMappings objectForKey:newStyleName];
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

				// OK, now save the new style name and record it in the prefs.
				[newStyleName retain];
				[selectedStyle release];
				selectedStyle = newStyleName;
				[[NSUserDefaults standardUserDefaults] setValue:selectedStyle forKey:MAPref_ActiveStyleName];

				// Refresh the UI if asked to do so.
				if (refresh)
					[self updateMessageText];
			}
			[handle closeFile];
		}
	}
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
		sortColumnTag = [[db fieldByIdentifier:sortColumnIdentifier] tag];
		[[NSUserDefaults standardUserDefaults] setObject:sortColumnIdentifier forKey:MAPref_SortColumn];
	}
	[[NSUserDefaults standardUserDefaults] setInteger:sortDirection forKey:MAPref_SortDirection];
	[self showSortDirection];
	[self refreshFolder:NO];
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
	Message * theRecord;

	NSParameterAssert(rowIndex >= 0 && rowIndex < (int)[currentArrayOfMessages count]);
	theRecord = [currentArrayOfMessages objectAtIndex:rowIndex];
	if ([[aTableColumn identifier] isEqualToString:MA_Column_MessageFolderId])
	{
		Folder * folder = [db folderFromID:[theRecord folderId]];
		return [folder name];
	}
	if ([[aTableColumn identifier] isEqualToString:MA_Column_MessageUnread])
	{
		if (![theRecord isRead])
			return [NSImage imageNamed:@"unread.tiff"];
		return [NSImage imageNamed:@"alphaPixel.tiff"];
	}
	if ([[aTableColumn identifier] isEqualToString:MA_Column_MessageFlagged])
	{
		if ([theRecord isFlagged])
			return [NSImage imageNamed:@"flagged.tiff"];
		return [NSImage imageNamed:@"alphaPixel.tiff"];
	}
	if ([[aTableColumn identifier] isEqualToString:MA_Column_MessageComments])
	{
		if ([theRecord hasComments])
			return [NSImage imageNamed:@"flagged.tiff"];
		return [NSImage imageNamed:@"alphaPixel.tiff"];
	}
	return [[theRecord messageData] objectForKey:[aTableColumn identifier]];
}

/* tableViewSelectionDidChange [delegate]
 * Handle the selection changing in the table view.
 */
-(void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	currentSelectedRow = [messageList selectedRow];
	[self refreshMessageAtRow:currentSelectedRow];
}

/* refreshMessageAtRow
 * Refreshes the message at the specified row.
 */
-(void)refreshMessageAtRow:(int)theRow
{
	requestedMessage = 0;
	if (currentSelectedRow < 0)
		[[textView mainFrame] loadHTMLString:@"<HTML></HTML>" baseURL:nil];
	else
	{
		NSAssert(currentSelectedRow < (int)[currentArrayOfMessages count], @"Out of range row index received");
		[self updateMessageText];

		// Add this to the backtrack list
		if (!isBacktracking)
		{
			int messageId = [[currentArrayOfMessages objectAtIndex:currentSelectedRow] number];
			[backtrackArray addToQueue:currentFolderId messageNumber:messageId];
		}
	}
}

/* forwardTrackMessage
 * Forward track through the list of messages displayed
 */
-(IBAction)forwardTrackMessage:(id)sender
{
	int folderId;
	int messageNumber;

	if ([backtrackArray nextItemAtQueue:&folderId messageNumber:&messageNumber])
	{
		isBacktracking = YES;
		[self selectFolderAndMessage:folderId messageNumber:messageNumber];
		isBacktracking = NO;
	}
}

/* backTrackMessage
 * Back track through the list of messages displayed
 */
-(IBAction)backTrackMessage:(id)sender
{
	int folderId;
	int messageNumber;
	
	if ([backtrackArray previousItemAtQueue:&folderId messageNumber:&messageNumber])
	{
		isBacktracking = YES;
		[self selectFolderAndMessage:folderId messageNumber:messageNumber];
		isBacktracking = NO;
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
		case 0x7F:
			[self backTrackMessage:self];
			return YES;

		case 'f':
		case 'F':
			[mainWindow makeFirstResponder:searchField];
			return YES;

		case 'm':
		case 'M':
			[self markFlagged:self];
			return YES;
			
		case 'r':
		case 'R':
			[self markRead:self];
			return YES;

		case '\r': //ENTER
			[self viewNextUnread:self];
			return YES;

		case ' ': //SPACE
			{
			// Advance one page in the message.
			[textView scrollPageDown:self];
			return YES;
			}
	}
	return NO;
}

/* willDisplayCell [delegate]
 * Catch the table view before it displays a cell.
 */
-(void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if ([[aTableColumn identifier] isEqualToString:MA_Column_MessageId])
	{
		[aCell setImage:nil];
	}
	if (![aCell isKindOfClass:[NSImageCell class]])
	{
		[aCell setTextColor:[NSColor blackColor]];
		[aCell setFont:messageListFont];
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
		Message * theRecord = [currentArrayOfMessages objectAtIndex:currentSelectedRow];
		Folder * folder = [db folderFromID:[theRecord folderId]];

		// Cache values for things we're going to be plugging into the template and set
		// defaults for things that are missing.
		NSString * messageText = [db messageText:[theRecord folderId] messageId:[theRecord number]];
		NSString * messageDate = [[[theRecord date] dateWithCalendarFormat:nil timeZone:nil] friendlyDescription];
		NSString * messageLink = [theRecord link] ? [theRecord link] : @"";
		NSString * messageAuthor = [theRecord author] ? [theRecord author] : @"";
		NSString * messageTitle = [theRecord title] ? [theRecord title] : @"";
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
		[[textView mainFrame] loadHTMLString:htmlMessage baseURL:(cssStylesheet ? [NSURL URLWithString:cssStylesheet] : nil)];
		[htmlMessage release];
	}
}

/* isConnecting
 * Returns whether or not 
 */
-(BOOL)isConnecting
{
	return totalConnections > 0;
}

/* getMessagesOnTimer
 * Each time the check timer fires, we see if a connect is not
 * running and then kick one off.
 */
-(void)getMessagesOnTimer:(NSTimer *)aTimer
{
	[self refreshAllSubscriptions:self];
}

/* newSubscription
 * Display the pane for a new RSS subscription.
 */
-(IBAction)newSubscription:(id)sender
{
	if (!rssFeed)
		rssFeed = [[NewSubscription alloc] initWithDatabase:db];
	[rssFeed newSubscription:mainWindow underParent:[foldersTree groupParentSelection] initialURL:nil];
}

/* newSmartFolder
 * Create a new smart folder.
 */
-(IBAction)newSmartFolder:(id)sender
{
	if (!smartFolder)
		smartFolder = [[SearchFolder alloc] initWithDatabase:db];
	[smartFolder newCriteria:mainWindow underParent:[foldersTree groupParentSelection]];
}

/* newGroupFolder
 * Display the pane for a new group folder.
 */
-(IBAction)newGroupFolder:(id)sender
{
	if (!groupFolder)
		groupFolder = [[NewGroupFolder alloc] initWithDatabase:db];
	[groupFolder newGroupFolder:mainWindow underParent:[foldersTree groupParentSelection]];
}

/* refreshAllSubscriptions
 * Get new messages from the service.
 */
-(IBAction)refreshAllSubscriptions:(id)sender
{
	if (totalConnections == 0)
		[self refreshSubscriptions:[db arrayOfRSSFolders]];
}

/* refreshSelectedSubscriptions
 * Refresh one or more subscriptions selected from the folders list. The selection we obtain
 * may include non-RSS folders so these have to be trimmed out first.
 */
-(IBAction)refreshSelectedSubscriptions:(id)sender
{
	NSMutableArray * selectedFolders = [NSMutableArray arrayWithArray:[foldersTree selectedFolders]];
	int count = [selectedFolders count];
	int index;

	// For group folders, add all sub-groups to the array. The array we get back
	// from selectedFolders may include groups but will not include the folders within
	// those groups if they weren't selected. So we need to grab those folders here.
	for (index = 0; index < count; ++index)
	{
		Folder * folder = [selectedFolders objectAtIndex:index];
		if (IsGroupFolder(folder))
			[selectedFolders addObjectsFromArray:[db arrayOfFolders:[folder itemId]]];
	}

	// Trim the array to remove non-RSS folders that can't be refreshed.
	for (index = count - 1; index >= 0; --index)
	{
		Folder * folder = [selectedFolders objectAtIndex:index];
		if (!IsRSSFolder(folder))
			[selectedFolders removeObjectAtIndex:index];
	}
	
	// Hopefully what is left is refreshable.
	if ([selectedFolders count] > 0)
		[self refreshSubscriptions:selectedFolders];
}

/* refreshSubscriptions
 * Add the folders specified in the foldersArray to the refreshArray, removing any
 * duplicates, then call the refreshPumper to kick off a refresh if needed.
 */
-(void)refreshSubscriptions:(NSArray *)foldersArray
{
	int count = [foldersArray count];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		Folder * folder = [foldersArray objectAtIndex:index];
		if (![refreshArray containsObject:folder])
			[refreshArray addObject:folder];
	}
	[self refreshPumper];
}

/* handleConnectionCompleted
 * Called from the connection object when it has completed. The object itself is
 * passed as a parameter so we can remove it from the connections array.
 */
-(void)handleConnectionCompleted:(NSNotification *)nc
{
	NSURLConnection * theConnection = [nc object];
	int index = [connectionsArray indexOfObject:theConnection];
	if (index != NSNotFound)
	{
		[connectionsArray removeObjectAtIndex:index];
		--totalConnections;
	}
	[theConnection release];
	[self refreshPumper];
	if (totalConnections == 0)
	{
		[self setStatusMessage:NSLocalizedString(@"Refresh completed", nil) persist:YES];
		[self stopProgressIndicator];
		[self handleEndOfRefresh];
	}
}

/* getCredentialsForFolder
 * Initiate the UI to request the credentials for the specified folder.
 */
-(void)getCredentialsForFolder
{
	if (credentialsController == nil)
		credentialsController = [[FeedCredentials alloc] initWithDatabase:db];
	
	// Pull next folder out of the queue. The UI will post a
	// notification when it is done and we can move on to the
	// next one.
	if ([authQueue count] > 0 && ![[credentialsController window] isVisible])
	{
		Folder * folder = [authQueue objectAtIndex:0];
		[credentialsController credentialsForFolder:mainWindow folder:folder];
	}
}

/* handleRequireAuthenticationForFolder [delegate]
 * Called when somewhere requires us to provide authentication for the specified
 * folder.
 */
-(void)handleRequireAuthenticationForFolder:(NSNotification *)nc
{
	Folder * folder = (Folder *)[nc object];
	if (![authQueue containsObject:folder])
		[authQueue addObject:folder];
	[self getCredentialsForFolder];
}

/* handleCancelAuthenticationForFolder
 * Called when somewhere cancelled our request to authenticate the specified
 * folder.
 */
-(void)handleCancelAuthenticationForFolder:(NSNotification *)nc
{
	Folder * folder = (Folder *)[nc object];
	[authQueue removeObject:folder];

	// Get the next one in the queue, if any
	[self getCredentialsForFolder];
}

/* handleGotAuthenticationForFolder [delegate]
 * Called when somewhere just provided us the needed authentication for the specified
 * folder. Note that we don't know if the authentication is valid yet - just that a
 * user name and password has been provided.
 */
-(void)handleGotAuthenticationForFolder:(NSNotification *)nc
{
	Folder * folder = (Folder *)[nc object];
	[folder clearFlag:MA_FFlag_NeedCredentials];
	[authQueue removeObject:folder];
	[self refreshSubscriptions:[NSArray arrayWithObject:folder]];

	// Get the next one in the queue, if any
	[self getCredentialsForFolder];
}

/* refreshPumper
 * This is the heart of the refresh code. We manage the refreshArray by creating a
 * connection for each item in the array up to a maximum number of simultaneous
 * connections as defined in the maximumConnections variable.
 */
-(void)refreshPumper
{
	while (totalConnections < maximumConnections)
	{
		// Exit now if the refresh queue is empty
		if ([refreshArray count] == 0)
			return;
		
		// If this folder needs credentials, add the folder to the list requiring authentication
		// and since we can't progress without it, skip this folder on the connection
		Folder * folder = [refreshArray objectAtIndex:0];
		if ([folder flags] & MA_FFlag_NeedCredentials)
		{
			[authQueue addObject:folder];
			[refreshArray removeObjectAtIndex:0];
			[self getCredentialsForFolder];
			continue;
		}
		
		// The activity log name we use depends on whether or not this folder has a real name.
		NSString * name = [[folder name] isEqualToString:[db untitledFeedFolderName]] ? [folder feedURL] : [folder name];
		ActivityItem * aItem = [[ActivityLog defaultLog] itemByName:name];

		SingleConnection * handler = [[SingleConnection alloc] initWithDatabase:db folder:folder log:aItem];
		if (handler != nil)
		{
			NSURL * url = [NSURL URLWithString:[folder feedURL]];
			NSMutableURLRequest * theRequest = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.0];
			
			// If the folder has a valid last modified string, use it to ensure that
			// we don't re-request needlessly.
			if (![[folder lastUpdateString] isBlank])
				[theRequest addValue:[folder lastUpdateString] forHTTPHeaderField:@"If-Modified-Since"];
			
			// Accept GZIP
			[theRequest addValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];

			// Seed the activity log for this feed.
			[aItem clearDetails];
			[aItem setStatus:NSLocalizedString(@"Retrieving articles", nil)];

			// Additional detail for the log
			[aItem appendDetail:[NSString stringWithFormat:NSLocalizedString(@"Connecting to %@", nil), [folder feedURL]]];

			// Start progress spinner running
			if (totalConnections == 0)
			{
				unreadAtBeginning = [db countOfUnread];
				[self startProgressIndicator];
				[self setStatusMessage:NSLocalizedString(@"Refreshing subscriptions...", nil) persist:YES];
			}

			// Do a pre-flight check
			if (![NSURLConnection canHandleRequest:theRequest])
				[aItem setStatus:NSLocalizedString(@"Error", nil)];
			else
			{
				NSURLConnection * theConnection = [[NSURLConnection alloc] initWithRequest:theRequest delegate:handler];
				if (theConnection == nil)
					[aItem setStatus:NSLocalizedString(@"Error", nil)];
				else
				{
					[connectionsArray addObject:theConnection];
					++totalConnections;
				}
			}
			[handler release];
		}
		[refreshArray removeObjectAtIndex:0];
	}
}

/* cancelAllRefreshes
 * Used to kill all active refresh connections and empty the queue of folders due to
 * be refreshed.
 */
-(IBAction)cancelAllRefreshes:(id)sender
{
	[refreshArray removeAllObjects];
	while (totalConnections > 0)
	{
		NSURLConnection * theConnection = [connectionsArray objectAtIndex:0];
		[theConnection cancel];
		[theConnection release];
		[connectionsArray removeObjectAtIndex:0];
		--totalConnections;
	}
	[self handleEndOfRefresh];
}

/* handleEndOfRefresh
 * Do the things that come at the end of a refresh, whether or not the refresh
 * was successful.
 */
-(void)handleEndOfRefresh
{	
	[self showUnreadCountOnApplicationIcon];
	int newUnread = [db countOfUnread] - unreadAtBeginning;
	if (growlAvailable && newUnread > 0)
	{
		NSNumber * defaultValue = [NSNumber numberWithBool:YES];
		NSNumber * stickyValue = [NSNumber numberWithBool:NO];
		NSString * msgText = [NSString stringWithFormat:NSLocalizedString(@"Growl description", nil), newUnread];
		
		NSDictionary *aNuDict = [NSDictionary dictionaryWithObjectsAndKeys:
			NSLocalizedString(@"Growl notification name", nil), GROWL_NOTIFICATION_NAME,
			NSLocalizedString(@"Growl notification title", nil), GROWL_NOTIFICATION_TITLE,
			msgText, GROWL_NOTIFICATION_DESCRIPTION,
			appName, GROWL_APP_NAME,
			defaultValue, GROWL_NOTIFICATION_DEFAULT,
			stickyValue, GROWL_NOTIFICATION_STICKY,
			nil];
		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:GROWL_NOTIFICATION 
																	   object:nil 
																	 userInfo:aNuDict
														   deliverImmediately:YES];
	}
}

/* deleteMessage
 * Delete the current message
 */
-(IBAction)deleteMessage:(id)sender
{
	if (currentSelectedRow >= 0)
		NSBeginCriticalAlertSheet(NSLocalizedString(@"Delete selected message", nil),
								  NSLocalizedString(@"Delete", nil),
								  NSLocalizedString(@"Cancel", nil),
								  nil, [NSApp mainWindow], self,
								  @selector(doConfirmedDelete:returnCode:contextInfo:), nil, nil,
								  NSLocalizedString(@"Delete selected message text", nil));
}

/* doConfirmedDelete
 * This function is called after the user has dismissed
 * the confirmation sheet.
 */
-(void)doConfirmedDelete:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSAlertDefaultReturn)
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
			Message * theRecord = [currentArrayOfMessages objectAtIndex:[rowIndex intValue]];
			if (![theRecord isRead])
				needFolderRedraw = YES;
			if ([db deleteMessage:[theRecord folderId] messageNumber:[theRecord number]])
				[arrayCopy removeObject:theRecord];
		}
		[db commitTransaction];
		[currentArrayOfMessages release];
		currentArrayOfMessages = [arrayCopy retain];
		[arrayCopy release];

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
		[self showUnreadCountOnApplicationIcon];
	}
}

/* toggleActivityViewer
 * Toggle display of the activity viewer windows.
 */
-(IBAction)toggleActivityViewer:(id)sender
{	
	if (activityViewer == nil)
		activityViewer = [[ActivityViewer alloc] init];
	if (activityViewer != nil)
	{
		NSWindow * activityWindow = [activityViewer window];
		if (![activityWindow isVisible])
			[activityViewer showWindow:self];
		else
			[activityWindow performClose:self];
	}
}

/* viewNextUnread
 * Moves the selection to the next unread message.
 */
-(IBAction)viewNextUnread:(id)sender
{
	// Mark the current message read
	if ([messageList selectedRow] != -1 && ![db readOnly])
	{
		Message * theRecord = [currentArrayOfMessages objectAtIndex:[messageList selectedRow]];
		[self markReadByArray:[NSArray arrayWithObject:theRecord] readFlag:YES];
	}
	
	// Scan the current folder from the selection forward. If nothing found, try
	// other folders until we come back to ourselves.
	if (![self viewNextUnreadInCurrentFolder:[messageList selectedRow]])
	{
		int nextFolderWithUnread = [foldersTree nextFolderWithUnread:currentFolderId];
		if (nextFolderWithUnread != -1)
		{
			if (nextFolderWithUnread != currentFolderId)
			{
				selectAtEndOfReload = MA_Select_Unread;
				[foldersTree selectFolder:nextFolderWithUnread];
				[mainWindow makeFirstResponder:messageList];
			}
			else
			{
				if (![self viewNextUnreadInCurrentFolder:-1])
					[self runOKAlertSheet:NSLocalizedString(@"No more unread messages", nil) 
									 text:NSLocalizedString(@"No more unread body", nil)];
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
		Message * theRecord;
		
		do {
			theRecord = [currentArrayOfMessages objectAtIndex:++currentRow];
			if (![theRecord isRead])
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
		[self makeRowSelectedAndVisible:[currentArrayOfMessages count] - 1];
}

/* selectFolderAndMessage
 */
-(BOOL)selectFolderAndMessage:(int)folderId messageNumber:(int)messageNumber
{
	if (folderId == currentFolderId)
		return [self scrollToMessage:messageNumber];

	// OK, it gets a little harder here.
	selectAtEndOfReload = messageNumber;
	[foldersTree selectFolder:folderId];
	return [self scrollToMessage:messageNumber];
}

/* refreshFolder
 * Refreshes the current folder by applying the current sort or thread
 * logic and redrawing the message list. The selected message is preserved
 * and restored on completion of the refresh.
 */
-(void)refreshFolder:(BOOL)reloadData
{
	int messageNumber = -1;

	if (currentSelectedRow >= 0)
		messageNumber = [[currentArrayOfMessages objectAtIndex:currentSelectedRow] number];
	if (reloadData)
		[self reloadArrayOfMessages];
	[self sortMessages];
	[self showSortDirection];
	[messageList reloadData];
	if (requestedMessage > 0)
		messageNumber = requestedMessage;
	if (messageNumber >= 0)
	{
		if (![self scrollToMessage:messageNumber])
			currentSelectedRow = -1;
		else
			[self updateMessageText];
	}
}

/* selectFolderWithFilter
 * Switches to the specified folder and displays messages filtered by whatever is in
 * the search field.
 */
-(void)selectFolderWithFilter:(int)newFolderId
{
	[self setMainWindowTitle:newFolderId];
	[db flushFolder:currentFolderId];
	[messageList deselectAll:self];
	currentFolderId = newFolderId;
	[self showColumnsForFolder:currentFolderId];
	[self reloadArrayOfMessages];
	[self sortMessages];
	[messageList reloadData];
	[self selectMessageAfterReload];
}

/* reloadArrayOfMessages
 * Reload the currentArrayOfMessages from the current folder.
 */
-(void)reloadArrayOfMessages
{
	[currentArrayOfMessages release];
	currentArrayOfMessages = [[db arrayOfMessages:currentFolderId filterString:[searchField stringValue]] retain];
}

/* setMainWindowTitle
 * Updates the main window title bar.
 */
-(void)setMainWindowTitle:(int)folderId
{
	if (folderId > 0)
	{
		Folder * folder = [db folderFromID:folderId];
		[messageListHeader setStringValue:[folder name]];
	}
}

/* selectMessageAfterReload
 * Sets the selection in the message list after the list is reloaded. The value of selectAtEndOfReload
 * is either MA_Select_None, meaning no selection, MA_Select_Unread meaning select the first unread
 * message from the beginning (after sorting is applied) or it is the ID of a specific message to be
 * selected.
 */
-(void)selectMessageAfterReload
{
	if (selectAtEndOfReload != MA_Select_None)
	{
		if (selectAtEndOfReload == MA_Select_Unread)
			[self selectFirstUnreadInFolder];
		else
			[self scrollToMessage:selectAtEndOfReload];
	}
	selectAtEndOfReload = MA_Select_Unread;
}

/* markAllRead
 * Mark all messages read in the selected folders.
 */
-(IBAction)markAllRead:(id)sender
{
	[self markAllReadInArray:[foldersTree selectedFolders]];
}

/* markAllReadInArray
 * Given an array of folders, mark all the messages in those folders as read.
 */
-(void)markAllReadInArray:(NSArray *)folderArray
{
	NSEnumerator * enumerator = [folderArray objectEnumerator];
	Folder * folder;

	while ((folder = [enumerator nextObject]) != nil)
	{
		int folderId = [folder itemId];
		[db markFolderRead:folderId];

		[foldersTree updateFolder:folderId recurseToParents:YES];
		if (folderId == currentFolderId)
			[messageList reloadData];
	}

	// The app icon has a count of unread messages so we need to
	// update that.
	[self showUnreadCountOnApplicationIcon];
}

/* markedMessageRange
 * Retrieve an array of messages to be used by the mark functions.
 *
 * If just one message is selected, we return that message and all child threads.
 * If a range of messages are selected, we return all the selected messages.
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

/* markRead
 * Toggle the read/unread state of the selected message
 */
-(IBAction)markRead:(id)sender
{
	if ([messageList selectedRow] != -1 && ![db readOnly])
	{
		Message * theRecord = [currentArrayOfMessages objectAtIndex:[messageList selectedRow]];
		NSArray * messageArray = [self markedMessageRange];
		[self markReadByArray:messageArray readFlag:![theRecord isRead]];
		[messageArray release];
	}
}

/* markReadByArray
 * Helper function. Takes as an input an array of messages and marks those messages read or unread.
 */
-(void)markReadByArray:(NSArray *)messageArray readFlag:(BOOL)readFlag
{
	NSEnumerator * enumerator = [messageArray objectEnumerator];
	Message * theRecord;
	int lastFolderId = -1;
	int folderId;

	[db beginTransaction];
	while ((theRecord = [enumerator nextObject]) != nil)
	{
		folderId = [theRecord folderId];
		[db markMessageRead:folderId messageId:[theRecord number] isRead:readFlag];
		if (folderId != currentFolderId)
		{
			[theRecord markRead:readFlag];
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
	[self showUnreadCountOnApplicationIcon];
}

/* markFlagged
 * Toggle the flagged/unflagged state of the selected message
 */
-(IBAction)markFlagged:(id)sender
{
	if ([messageList selectedRow] != -1 && ![db readOnly])
	{
		Message * theRecord = [currentArrayOfMessages objectAtIndex:[messageList selectedRow]];
		NSArray * messageArray = [self markedMessageRange];
		[self markFlaggedByArray:messageArray flagged:![theRecord isFlagged]];
		[messageArray release];
	}
}

/* markFlaggedByArray
 * Mark the specified messages in messageArray as flagged.
 */
-(void)markFlaggedByArray:(NSArray *)messageArray flagged:(BOOL)flagged
{
	NSEnumerator * enumerator = [messageArray objectEnumerator];
	Message * theRecord;

	[db beginTransaction];
	while ((theRecord = [enumerator nextObject]) != nil)
	{
		[theRecord markFlagged:flagged];
		[db markMessageFlagged:[theRecord folderId] messageId:[theRecord number] isFlagged:flagged];
	}
	[db commitTransaction];
	[messageList reloadData];
}

/* renameFolder
 * Renames the current folder
 */
-(IBAction)renameFolder:(id)sender
{
	Folder * folder = [db folderFromID:[foldersTree actualSelection]];

	// Initialise field
	[renameField setStringValue:[folder name]];
	[renameWindow makeFirstResponder:renameField];

	[NSApp beginSheet:renameWindow
	   modalForWindow:mainWindow 
		modalDelegate:self 
	   didEndSelector:nil 
		  contextInfo:nil];
}

/* endRenameFolder
 * Called when the user OK's the Rename Folder sheet
 */
-(IBAction)endRenameFolder:(id)sender
{
	[renameWindow orderOut:sender];
	[NSApp endSheet:renameWindow returnCode:1];
	[db setFolderName:currentFolderId newName:[[renameField stringValue] trim]];
}

/* cancelRenameFolder
 * Called when the user cancels the Rename Folder sheet
 */
-(IBAction)cancelRenameFolder:(id)sender
{
	[renameWindow orderOut:sender];
	[NSApp endSheet:renameWindow returnCode:0];
}

/* deleteFolder
 * Delete the current folder.
 */
-(IBAction)deleteFolder:(id)sender
{
	NSMutableArray * selectedFolders = [NSMutableArray arrayWithArray:[foldersTree selectedFolders]];
	int count = [selectedFolders count];
	int index;
	
	// Show a different prompt depending on whether we're deleting one folder or a
	// collection of them.
	NSString * alertBody = nil;
	NSString * alertTitle = nil;

	if (count == 1)
	{
		Folder * folder = [selectedFolders objectAtIndex:0];
		if (IsSmartFolder(folder))
		{
			alertBody = [NSString stringWithFormat:NSLocalizedString(@"Delete smart folder text", nil), [folder name]];
			alertTitle = NSLocalizedString(@"Delete smart folder", nil);
		}
		else if (IsRSSFolder(folder))
		{
			alertBody = [NSString stringWithFormat:NSLocalizedString(@"Delete RSS feed text", nil), [folder name]];
			alertTitle = NSLocalizedString(@"Delete RSS feed", nil);
		}
		else if (IsGroupFolder(folder))
		{
			alertBody = [NSString stringWithFormat:NSLocalizedString(@"Delete group folder text", nil), [folder name]];
			alertTitle = NSLocalizedString(@"Delete group folder", nil);
		}
		else
			NSAssert1(false, @"Unhandled folder type in deleteFolder: %@", [folder name]);
	}
	else
	{
		alertBody = [NSString stringWithFormat:NSLocalizedString(@"Delete multiple folders text", nil), count];
		alertTitle = NSLocalizedString(@"Delete multiple folders", nil);
	}

	// Get confirmation first
	int returnCode;
	returnCode = NSRunAlertPanel(alertTitle, alertBody, NSLocalizedString(@"Delete", nil), NSLocalizedString(@"Cancel", nil), nil);
	if (returnCode == NSAlertAlternateReturn)
		return;

	// Prompt for each folder for now
	for (index = 0; index < count; ++index)
	{
		Folder * folder = [selectedFolders objectAtIndex:index];

		// Create a status string
		NSString * deleteStatusMsg = [NSString stringWithFormat:NSLocalizedString(@"Delete folder status", nil), [folder name]];
		[self setStatusMessage:deleteStatusMsg persist:NO];

		// Now call the database to delete the folder.
		[db deleteFolder:[folder itemId]];
	}

	// Unread count may have changed
	[self setStatusMessage:nil persist:NO];
	[self showUnreadCountOnApplicationIcon];
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
			Message * theRecord = [currentArrayOfMessages objectAtIndex:row];
			NSString * columnName = [(NSTableColumn *)[columns objectAtIndex:column] identifier];
			if ([columnName isEqualToString:MA_Column_MessageUnread])
			{
				[self markReadByArray:[NSArray arrayWithObject:theRecord] readFlag:![theRecord isRead]];
				return;
			}
			if ([columnName isEqualToString:MA_Column_MessageFlagged])
			{
				[self markFlaggedByArray:[NSArray arrayWithObject:theRecord] flagged:![theRecord isFlagged]];
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
		Message * theRecord = [currentArrayOfMessages objectAtIndex:currentSelectedRow];
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[theRecord link]]];
	}
}

/* viewSourceHomePage
 * Display the web site associated with this feed, if there is one.
 */
-(IBAction)viewSourceHomePage:(id)sender
{
	int folderId = [foldersTree actualSelection];
	Folder * folder = [db folderFromID:folderId];

	if (folder && ![[folder homePage] isBlank])
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[folder homePage]]];
}

/* showViennaHomePage
 * Open the Vienna home page in the default browser.
 */
-(IBAction)showViennaHomePage:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.opencommunity.co.uk"]];
}

/* showAcknowledgements
 * Display the acknowledgements document in a browser.
 */
-(IBAction)showAcknowledgements:(id)sender
{
	NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];
	NSString * pathToAckFile = [thisBundle pathForResource:@"Acknowledgements.rtf" ofType:@""];
	if (pathToAckFile != nil)
	{
		NSURL * acknowledgementURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", pathToAckFile]];
		[[NSWorkspace sharedWorkspace] openURL:acknowledgementURL];
	}
}

/* writeRows
 * Called to initiate a drag from MessageListView. We build an array of dictionary entries each of
 * which include details of each selected message in the standard RSS item format defined by
 * Ranchero NetNewsWire. See http://ranchero.com/netnewswire/rssclipboard.php for more details.
 */
-(BOOL)tableView:(NSTableView *)tv writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard
{
	NSMutableArray * arrayOfArticles = [[NSMutableArray alloc] init];
	int count = [rows count];
	int index;

	// Set up the pasteboard
	[pboard declareTypes:[NSArray arrayWithObjects:RSSItemType, nil] owner:self];

	// Get all the messages that are being dragged
	for (index = 0; index < count; ++index)
	{
		int msgIndex = [[rows objectAtIndex:index] intValue];
		Message * thisMessage = [currentArrayOfMessages objectAtIndex:msgIndex];
		Folder * folder = [db folderFromID:[thisMessage folderId]];
		NSString * msgText = [db messageText:[thisMessage folderId] messageId:[thisMessage number]];

		NSMutableDictionary * articleDict = [[NSMutableDictionary alloc] init];
		[articleDict setValue:[thisMessage title] forKey:@"rssItemTitle"];
		[articleDict setValue:[thisMessage link] forKey:@"rssItemLink"];
		[articleDict setValue:msgText forKey:@"rssItemDescription"];
		[articleDict setValue:[folder name] forKey:@"sourceName"];
		[articleDict setValue:[folder homePage] forKey:@"sourceHomeURL"];
		[articleDict setValue:[folder feedURL] forKey:@"sourceRSSURL"];
		[arrayOfArticles addObject:articleDict];
		[articleDict release];
	}

	// Put string on the pasteboard for external drops.
	[pboard setPropertyList:arrayOfArticles forType:RSSItemType];
	[arrayOfArticles release];
	return YES;
}

/* searchUsingToolbarTextField
 * Executes a search using the search field on the toolbar.
 */
-(IBAction)searchUsingToolbarTextField:(id)sender
{
	[self selectFolderWithFilter:currentFolderId];
}

/* runOKAlertSheet
 * Displays an alert sheet with just an OK button.
 */
-(void)runOKAlertSheet:(NSString *)titleString text:(NSString *)bodyText, ...
{
	NSString * fullBodyText;
	va_list arguments;

	va_start(arguments, bodyText);
	fullBodyText = [[NSString alloc] initWithFormat:NSLocalizedString(bodyText, nil) arguments:arguments];
	NSBeginAlertSheet(NSLocalizedString(titleString, nil),
					  NSLocalizedString(@"OK", nil),
					  nil,
					  nil,
					  mainWindow,
					  self,
					  nil,
					  nil, nil,
					  fullBodyText);
	[fullBodyText release];
	va_end(arguments);
}

/* setStatusMessage
 * Sets a new status message for the info bar then updates the view. To remove
 * any existing status message, pass nil as the value.
 */
-(void)setStatusMessage:(NSString *)newStatusText persist:(BOOL)persistenceFlag
{
	if (persistenceFlag)
	{
		[newStatusText retain];
		[persistedStatusText release];
		persistedStatusText = newStatusText;
	}
	if (newStatusText == nil || [newStatusText isBlank])
		newStatusText = persistedStatusText;
	[statusText setStringValue:(newStatusText ? newStatusText : @"")];
}

/* startProgressIndicator
 * Gets the progress indicator on the info bar running. Because this can be called
 * nested, we use progressCount to make sure we remove it at the right time.
 */
-(void)startProgressIndicator
{
	if (progressCount++ == 0)
		[spinner startAnimation:self];
}

/* stopProgressIndicator
 * Stops the progress indicator on the info bar running
 */
-(void)stopProgressIndicator
{
	NSAssert(progressCount > 0, @"Called stopProgressIndicator without a matching startProgressIndicator");
	if (--progressCount < 1)
	{
		[spinner stopAnimation:self];
		progressCount = 0;
	}
}

/* validateMenuItem
 * This is our override where we handle item validation for the
 * commands that we own.
 */
-(BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	SEL	theAction = [menuItem action];
	if (theAction == @selector(printDocument:))
	{
		return ([messageList selectedRow] >= 0);
	}
	else if (theAction == @selector(backTrackMessage:))
	{
		return ![backtrackArray isAtStartOfQueue];
	}
	else if (theAction == @selector(forwardTrackMessage:))
	{
		return ![backtrackArray isAtEndOfQueue];
	}
	else if (theAction == @selector(newSubscription:))
	{
		return ![db readOnly];
	}
	else if (theAction == @selector(newSmartFolder:))
	{
		return ![db readOnly];
	}
	else if (theAction == @selector(viewNextUnread:))
	{
		return [db countOfUnread] > 0;
	}
	else if (theAction == @selector(refreshAllSubscriptions:))
	{
		return totalConnections == 0 && ![db readOnly];
	}
	else if (theAction == @selector(doViewColumn:))
	{
		Field * field = [menuItem representedObject];
		[menuItem setState:[field visible] ? NSOnState : NSOffState];
	}
	else if (theAction == @selector(doSelectStyle:))
	{
		NSString * styleName = [menuItem title];
		[menuItem setState:[styleName isEqualToString:selectedStyle] ? NSOnState : NSOffState];
	}
	else if (theAction == @selector(doSortColumn:))
	{
		Field * field = [menuItem representedObject];
		if ([[field name] isEqualToString:sortColumnIdentifier])
			[menuItem setState:NSOnState];
		else
			[menuItem setState:NSOffState];
	}
	else if (theAction == @selector(deleteFolder:))
	{
		return [foldersTree actualSelection] != -1 && ![db readOnly];
	}
	else if (theAction == @selector(refreshSelectedSubscriptions:))
	{
		Folder * folder = [db folderFromID:[foldersTree actualSelection]];
		return (IsRSSFolder(folder) || IsGroupFolder(folder)) && ![db readOnly];
	}
	else if (theAction == @selector(renameFolder:))
	{
		return ![db readOnly];
	}
	else if (theAction == @selector(markAllRead:))
	{
		int folderId = [foldersTree actualSelection];
		return !IsSmartFolder([db folderFromID:folderId]) && ![db readOnly];
	}
	else if (theAction == @selector(importSubscriptions:))
	{
		return ![db readOnly];
	}
	else if (theAction == @selector(newGroupFolder:))
	{
		return ![db readOnly];
	}
	else if (theAction == @selector(cancelAllRefreshes:))
	{
		return totalConnections > 0;
	}
	else if (theAction == @selector(viewSourceHomePage:))
	{
		int folderId = [foldersTree actualSelection];
		Folder * folder = [db folderFromID:folderId];
		return ([folder homePage] && ![[folder homePage] isBlank]);
	}
	else if (theAction == @selector(compactDatabase:))
	{
		return totalConnections == 0 && ![db readOnly];
	}
	else if (theAction == @selector(editFolder:))
	{
		int folderId = [foldersTree actualSelection];
		Folder * folder = [db folderFromID:folderId];
		return (IsSmartFolder(folder) || IsRSSFolder(folder)) && ![db readOnly];
	}
	else if (theAction == @selector(deleteMessage:))
	{
		return [messageList selectedRow] != -1 && ![db readOnly];
	}
	else if (theAction == @selector(readingPaneOnRight:))
	{
		[menuItem setState:(readingPaneOnRight ? NSOnState : NSOffState)];
		return YES;
	}
	else if (theAction == @selector(readingPaneOnBottom:))
	{
		[menuItem setState:(readingPaneOnRight ? NSOffState : NSOnState)];
		return YES;
	}
	else if (theAction == @selector(markFlagged:))
	{
		int rowIndex = [messageList selectedRow];
		if (rowIndex != -1)
		{
			Message * thisMessage = [currentArrayOfMessages objectAtIndex:rowIndex];
			if ([thisMessage isFlagged])
				[menuItem setTitle:NSLocalizedString(@"Mark Unflagged", nil)];
			else
				[menuItem setTitle:NSLocalizedString(@"Mark Flagged", nil)];
		}
		return (rowIndex != -1 && ![db readOnly]);
	}
	else if (theAction == @selector(markRead:))
	{
		int rowIndex = [messageList selectedRow];
		if (rowIndex != -1)
		{
			Message * thisMessage = [currentArrayOfMessages objectAtIndex:rowIndex];
			if ([thisMessage isRead])
				[menuItem setTitle:NSLocalizedString(@"Mark Unread", nil)];
			else
				[menuItem setTitle:NSLocalizedString(@"Mark Read", nil)];
		}
		return (rowIndex != -1 && ![db readOnly]);
	}
	return YES;
}

/* dealloc
 * Clean up and release resources.
 */
-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[persistedStatusText release];
	[connectionsArray release];
	[refreshArray release];
	[stylePathMappings release];
	[cssStylesheet release];
	[htmlTemplate release];
	[originalIcon release];
	[extDateFormatter release];
	[smartFolder release];
	[rssFeed release];
	[groupFolder release];
	[checkUpdates release];
	[preferenceController release];
	[credentialsController release];
	[activityViewer release];
	[currentArrayOfMessages release];
	[backtrackArray release];
	[checkTimer release];
	[messageListFont release];
	[authQueue release];
	[db release];
	[super dealloc];
}
@end
