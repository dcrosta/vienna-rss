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
#import "AboutController.h"
#import "FoldersTree.h"
#import "ArticleListView.h"
#import "Import.h"
#import "Export.h"
#import "Refresh.h"
#import "StringExtensions.h"
#import "SplitViewExtensions.h"
#import "BrowserView.h"
#import "CheckForUpdates.h"
#import "SearchFolder.h"
#import "NewSubscription.h"
#import "NewGroupFolder.h"
#import "ViennaApp.h"
#import "ActivityLog.h"
#import "Constants.h"
#import "Preferences.h"
#import "HelperFunctions.h"
#import "Growl/GrowlApplicationBridge.h"
#import "Growl/GrowlDefines.h"

@interface AppController (Private)
	-(void)handleFolderSelection:(NSNotification *)note;
	-(void)handleCheckFrequencyChange:(NSNotification *)note;
	-(void)handleFolderUpdate:(NSNotification *)nc;
	-(void)initSortMenu;
	-(void)initColumnsMenu;
	-(void)initStylesMenu;
	-(void)initScriptsMenu;
	-(void)startProgressIndicator;
	-(void)stopProgressIndicator;
	-(void)doEditFolder:(Folder *)folder;
	-(void)getMessagesOnTimer:(NSTimer *)aTimer;
	-(void)doConfirmedDelete:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
	-(void)runAppleScript:(NSString *)scriptName;
	-(void)setImageForMenuCommand:(NSImage *)image forAction:(SEL)sel;
	-(NSString *)appName;
	-(FoldersTree *)foldersTree;
	-(IBAction)endRenameFolder:(id)sender;
	-(IBAction)cancelRenameFolder:(id)sender;
@end

// Static constant strings that are typically never tweaked
static NSString * GROWL_NOTIFICATION_DEFAULT = @"NotificationDefault";

@implementation AppController

/* awakeFromNib
 * Do all the stuff that only makes sense after our NIB has been loaded and connected.
 */
-(void)awakeFromNib
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	[Preferences standardPreferences];

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

	// Create a dictionary that will be used to map scripts to the
	// paths where they're located.
	scriptPathMappings = [[NSMutableDictionary alloc] init];

	// Set the primary view of the browser view
	[browserView setPrimaryView:mainArticleView];

	// Set the delegates and title
	[mainWindow setDelegate:self];
	[mainWindow setTitle:appName];
	[NSApp setDelegate:self];

	// Register a bunch of notifications
	NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleFolderSelection:) name:@"MA_Notify_FolderSelectionChange" object:nil];
	[nc addObserver:self selector:@selector(handleCheckFrequencyChange:) name:@"MA_Notify_CheckFrequencyChange" object:nil];
	[nc addObserver:self selector:@selector(handleFolderUpdate:) name:@"MA_Notify_FoldersUpdated" object:nil];
	[nc addObserver:self selector:@selector(checkForUpdatesComplete:) name:@"MA_Notify_UpdateCheckCompleted" object:nil];
	[nc addObserver:self selector:@selector(handleEditFolder:) name:@"MA_Notify_EditFolder" object:nil];
	[nc addObserver:self selector:@selector(handleRefreshStatusChange:) name:@"MA_Notify_RefreshStatus" object:nil];

	// Init the progress counter and status bar.
	progressCount = 0;
	persistedStatusText = nil;
	[self setStatusMessage:nil persist:NO];

	// Initialize the database
	if ((db = [Database sharedDatabase]) == nil)
	{
		[NSApp terminate:nil];
		return;
	}

	// Preload dictionary of standard URLs
	NSString * pathToPList = [[NSBundle mainBundle] pathForResource:@"StandardURLs.plist" ofType:@""];
	if (pathToPList != nil)
		standardURLs = [[NSDictionary dictionaryWithContentsOfFile:pathToPList] retain];

	// Initialize the Styles, Sort By and Columns menu
	[self initSortMenu];
	[self initColumnsMenu];
	[self initStylesMenu];

	// Restore the splitview layout
	[splitView1 loadLayoutWithName:@"SplitView1Positions"];

	// Put icons in front of some menu commands.
	[self setImageForMenuCommand:[NSImage imageNamed:@"smallFolder.tiff"] forAction:@selector(newGroupFolder:)];
	[self setImageForMenuCommand:[NSImage imageNamed:@"rssFeed.tiff"] forAction:@selector(newSubscription:)];
	[self setImageForMenuCommand:[NSImage imageNamed:@"searchFolder.tiff"] forAction:@selector(newSmartFolder:)];

	// Show the current unread count on the app icon
	originalIcon = [[NSApp applicationIconImage] copy];
	lastCountOfUnread = 0;
	[self showUnreadCountOnApplicationIcon];

	// Add Scripts menu if we have any scripts
	if ([defaults boolForKey:MAPref_ShowScriptsMenu])
		[self initScriptsMenu];

	// Use Growl if it is installed
	growlAvailable = NO;
	[GrowlApplicationBridge setGrowlDelegate:self];

	// Start the check timer
	checkTimer = nil;
	[self handleCheckFrequencyChange:nil];

	// Assign the controller for the child views
	[foldersTree setController:self];
	[mainArticleView setController:self];
	
	// Do safe initialisation.
	[self doSafeInitialisation];
}

/* doSafeInitialisation
 * Do the stuff that requires that all NIBs are awoken. I can't find a notification
 * from Cocoa for this so we hack it.
 */
-(void)doSafeInitialisation
{
	[foldersTree initialiseFoldersTree];
	[mainArticleView initialiseArticleView];
}

/* applicationDidFinishLaunching
 * Handle post-load activities.
 */
-(void)applicationDidFinishLaunching:(NSNotification *)aNot
{
	Preferences * prefs = [Preferences standardPreferences];
	
	// Check for application updates silently
	if ([prefs checkForNewOnStartup])
	{
		if (!checkUpdates)
			checkUpdates = [[CheckForUpdates alloc] init];
		[checkUpdates checkForUpdate:mainWindow showUI:NO];
	}
	
	// Kick off an initial refresh
	if ([prefs refreshOnStartup])
		[self refreshAllSubscriptions:self];
}

/* applicationShouldHandleReopen
 * Handle the notification sent when the application is reopened such as when the dock icon
 * is clicked. If the main window was previously hidden, we show it again here.
 */
-(BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
	[self showMainWindow:self];
	return YES;
}

/* applicationShouldTerminate
 * This function is called when the user wants to close Vienna. First we check to see
 * if a connection or import is running and that all messages are saved.
 */
-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if ([self isConnecting])
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
	
	// Close the activity window explicitly to force it to
	// save its split bar position to the preferences.
	NSWindow * activityWindow = [activityViewer window];
	[activityWindow performClose:self];
	
	// Put back the original app icon
	[NSApp setApplicationIconImage:originalIcon];
	
	// Remember the message list column position, sizes, etc.
	[mainArticleView saveTableSettings];
	[foldersTree saveFolderSettings];
	
	if ([mainArticleView currentFolderId] != -1)
		[db flushFolder:[mainArticleView currentFolderId]];
	[db close];
}

/* openFile [delegate]
 * Called when the user opens a data file associated with Vienna.
 */
-(BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	if ([[filename pathExtension] isEqualToString:@"viennastyle"])
	{
		NSString * path = [[[NSUserDefaults standardUserDefaults] objectForKey:MAPref_StylesFolder] stringByExpandingTildeInPath];
		NSString * styleName = [[filename lastPathComponent] stringByDeletingPathExtension];
		NSString * fullPath = [path stringByAppendingPathComponent:[filename lastPathComponent]];
		
		// Make sure we actually have a Styles folder.
		NSFileManager * fileManager = [NSFileManager defaultManager];
		BOOL isDir = NO;
		
		if (![fileManager fileExistsAtPath:path isDirectory:&isDir])
		{
			if (![fileManager createDirectoryAtPath:path attributes:NULL])
			{
				runOKAlertPanel(@"Cannot create style folder title", @"Cannot create style folder body", path);
				return NO;
			}
		}
		if (![fileManager copyPath:filename toPath:fullPath handler:nil])
			[[Preferences standardPreferences] setDisplayStyle:styleName];
		else
		{
			[self initStylesMenu];
			[[Preferences standardPreferences] setDisplayStyle:styleName];
			runOKAlertPanel(@"New style title", @"New style body", styleName);
		}
		return YES;
	}
	return NO;
}

/* database
 */
-(Database *)database
{
	return db;
}

/* foldersTree
 */
-(FoldersTree *)foldersTree
{
	return foldersTree;
}

/* readingPaneOnRight
 * Move the reading pane to the right of the message list.
 */
-(IBAction)readingPaneOnRight:(id)sender
{
	[[Preferences standardPreferences] setReadingPaneOnRight:YES];
}

/* readingPaneOnBottom
 * Move the reading pane to the bottom of the message list.
 */
-(IBAction)readingPaneOnBottom:(id)sender
{
	[[Preferences standardPreferences] setReadingPaneOnRight:NO];
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
		[self openURLInBrowserWithURL:url];
}

/* openURLInBrowser
 * Open a URL in either the internal Vienna browser or an external browser depending on
 * whatever the user has opted for.
 */
-(void)openURLInBrowser:(NSString *)urlString
{
	[self openURLInBrowserWithURL:[NSURL URLWithString:urlString]];
}

/* applicationDockMenu
 * Return a menu with additional commands to be displayd on the application's
 * popup dock menu.
 */
-(NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	[appDockMenu release];
	appDockMenu = [[NSMenu alloc] initWithTitle:@"DockMenu"];
	
	// Refresh command
	NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:@"Refresh All Subscriptions" action:@selector(refreshAllSubscriptions:) keyEquivalent:@""];
	[appDockMenu addItem:menuItem];
	[menuItem release];
	
	// Done
	return appDockMenu;
}

/* openURLInBrowserWithURL
 * Open a URL in either the internal Vienna browser or an external browser depending on
 * whatever the user has opted for.
 */
-(void)openURLInBrowserWithURL:(NSURL *)url
{
	Preferences * prefs = [Preferences standardPreferences];
	if ([prefs openLinksInVienna])
	{
		// TODO: when our internal browser view is implemented, open the URL internally.
	}

	// Launch in the foreground or background as needed
	NSWorkspaceLaunchOptions lOptions = [prefs openLinksInBackground] ? NSWorkspaceLaunchWithoutActivation : NSWorkspaceLaunchDefault;
	[[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:url]
					withAppBundleIdentifier:NULL
									options:lOptions
			 additionalEventParamDescriptor:NULL
						  launchIdentifiers:NULL];
}

/* setImageForMenuCommand
 * Sets the image for a specified menu command.
 */
-(void)setImageForMenuCommand:(NSImage *)image forAction:(SEL)sel
{
	NSArray * arrayOfMenus = [[NSApp mainMenu] itemArray];
	int count = [arrayOfMenus count];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		NSMenu * subMenu = [[arrayOfMenus objectAtIndex:index] submenu];
		int itemIndex = [subMenu indexOfItemWithTarget:self andAction:sel];
		if (itemIndex >= 0)
		{
			[[subMenu itemAtIndex:itemIndex] setImage:image];
			return;
		}
	}
}

/* showMainWindow
 * Display the main window.
 */
-(IBAction)showMainWindow:(id)sender
{
	[mainWindow orderFront:self];
	[mainWindow setInitialFirstResponder:[mainArticleView mainView]];
}

/* closeMainWindow
 * Hide the main window.
 */
-(IBAction)closeMainWindow:(id)sender
{
	[mainWindow orderOut:self];
}

/* runAppleScript
 * Run an AppleScript script given a fully qualified path to the script.
 */
-(void)runAppleScript:(NSString *)scriptName
{
	NSDictionary * errorDictionary;

	NSURL * scriptURL = [NSURL fileURLWithPath:scriptName];
	NSAppleScript * appleScript = [[NSAppleScript alloc] initWithContentsOfURL:scriptURL error:&errorDictionary];
	[appleScript executeAndReturnError:&errorDictionary];
	[appleScript release];
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

/* growlNotificationWasClicked
 * Called when the user clicked a Growl notification balloon.
 */
-(void)growlNotificationWasClicked:(id)clickContext
{
	Folder * unreadArticles = [db folderFromName:NSLocalizedString(@"Unread Articles", nil)];
	if (unreadArticles != nil)
		[mainArticleView selectFolderAndMessage:[unreadArticles itemId] guid:nil];
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

/* initSortMenu
 * Create the sort popup menu.
 */
-(void)initSortMenu
{
	NSMenu * viewMenu = [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"View", nil)] submenu];
	NSMenu * sortMenu = [[[NSMenu alloc] initWithTitle:@"Sort By"] autorelease];
	NSArray * fields = [db arrayOfFields];
	NSEnumerator * enumerator = [fields objectEnumerator];
	Field * field;

	while ((field = [enumerator nextObject]) != nil)
	{
		// Filter out columns we don't sort on. Later we should have an attribute in the
		// field object itself based on which columns we can sort on.
		if ([field tag] != MA_FieldID_Parent &&
			[field tag] != MA_FieldID_GUID &&
			[field tag] != MA_FieldID_Deleted &&
			[field tag] != MA_FieldID_Text)
		{
			NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:[field displayName] action:@selector(doSortColumn:) keyEquivalent:@""];
			[menuItem setRepresentedObject:field];
			[sortMenu addItem:menuItem];
			[menuItem release];
		}
	}
	[[viewMenu itemWithTitle:NSLocalizedString(@"Sort By", nil)] setSubmenu:sortMenu];
}

/* initColumnsMenu
 * Create the columns popup menu.
 */
-(void)initColumnsMenu
{
	NSMenu * viewMenu = [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"View", nil)] submenu];
	NSMenu * columnsMenu = [[[NSMenu alloc] initWithTitle:@"Columns"] autorelease];
	NSArray * fields = [db arrayOfFields];
	NSEnumerator * enumerator = [fields objectEnumerator];
	Field * field;
	
	while ((field = [enumerator nextObject]) != nil)
	{
		// Filter out columns we don't view in the message list. Later we should have an attribute in the
		// field object based on which columns are visible in the tableview.
		if ([field tag] != MA_FieldID_Text && 
			[field tag] != MA_FieldID_GUID &&
			[field tag] != MA_FieldID_Deleted &&
			[field tag] != MA_FieldID_Parent &&
			[field tag] != MA_FieldID_Headlines)
		{
			NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:[field displayName] action:@selector(doViewColumn:) keyEquivalent:@""];
			[menuItem setRepresentedObject:field];
			[columnsMenu addItem:menuItem];
			[menuItem release];
		}
	}
	[[viewMenu itemWithTitle:NSLocalizedString(@"Columns", nil)] setSubmenu:columnsMenu];
}

/* initScriptsMenu
 * Look in the Scripts folder and if there are any scripts, add a Scripts menu and populate
 * it with the names of the scripts we've found.
 *
 * Note that there are two places we look for scripts: inside the app resource for scripts that
 * are bundled with the application, and in the standard Mac OSX application script folder which
 * is where the sysem-wide script menu also looks.
 */
-(void)initScriptsMenu
{
	NSMenu * scriptsMenu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:@"Scripts"];
    NSMenuItem * scriptsMenuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"Scripts" action:NULL keyEquivalent:@""];

	// Set menu image
	[scriptsMenuItem setImage:[NSImage imageNamed:@"scriptMenu.tiff"]];
	
	// Add scripts within the app resource
	NSString * path = [[[NSBundle mainBundle] sharedSupportPath] stringByAppendingPathComponent:@"Scripts"];
	loadMapFromPath(path, scriptPathMappings, NO);

	// Add scripts that the user created and stored in the scripts folder
	path = [[[NSUserDefaults standardUserDefaults] objectForKey:MAPref_ScriptsFolder] stringByExpandingTildeInPath];
	loadMapFromPath(path, scriptPathMappings, NO);

	// Add the contents of the scriptsPathMappings dictionary keys to the menu sorted
	// by key name.
	NSArray * sortedMenuItems = [[scriptPathMappings allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	int count = [sortedMenuItems count];
	int index;

	for (index = 0; index < count; ++index)
	{
		NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:[sortedMenuItems objectAtIndex:index]
														   action:@selector(doSelectScript:)
													keyEquivalent:@""];
		[scriptsMenu addItem:menuItem];
		[menuItem release];
	}

	// Insert the Scripts menu to the left of the Help menu only if
	// we actually have any scripts. The last item in the menu is a command to
	// open the Vienna scripts folder.
	if (count > 0)
	{
		[scriptsMenu addItem:[NSMenuItem separatorItem]];
		NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Open Scripts Folder", nil)
														   action:@selector(doOpenScriptsFolder:)
													keyEquivalent:@""];
		[scriptsMenu addItem:menuItem];
		[menuItem release];

		// The Help menu is always assumed to be the last menu in the list. This is probably
		// the easiest, localisable, way to look for it.
		int helpMenuIndex = [[NSApp mainMenu] numberOfItems] - 1;
		[scriptsMenuItem setSubmenu:scriptsMenu];
		[[NSApp mainMenu] insertItem:scriptsMenuItem atIndex:helpMenuIndex];
	}
	[scriptsMenu release];
	[scriptsMenuItem release];
}

/* initStylesMenu
 * Populate the Styles menu with a list of built-in and external styles. (Note that in the event of
 * duplicates the styles in the external Styles folder wins. This is intended to allow the user to
 * override the built-in styles if necessary).
 */
-(void)initStylesMenu
{
	NSMenu * stylesMenu = [[[NSMenu alloc] initWithTitle:@"Style"] autorelease];

	// Reinitialise the styles map
	NSDictionary * stylesMap = [mainArticleView initStylesMap];
	
	// Add the contents of the stylesPathMappings dictionary keys to the menu sorted
	// by key name.
	NSArray * sortedMenuItems = [[stylesMap allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	int count = [sortedMenuItems count];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:[sortedMenuItems objectAtIndex:index] action:@selector(doSelectStyle:) keyEquivalent:@""];
		[stylesMenu addItem:menuItem];
		[menuItem release];
	}

	// Append a link to More Styles...
	[stylesMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"More Styles...", nil) action:@selector(moreStyles:) keyEquivalent:@""];
	[stylesMenu addItem:menuItem];
	[menuItem release];
	
	NSMenu * viewMenu = [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"View", nil)] submenu];
	[[viewMenu itemWithTitle:NSLocalizedString(@"Style", nil)] setSubmenu:stylesMenu];
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

/* handleAbout
 * Display our About Vienna... window.
 */
-(IBAction)handleAbout:(id)sender
{
	if (!aboutController)
		aboutController = [[AboutController alloc] init];
	[aboutController showWindow:self];
}

/* emptyTrash
 * Delete all messages from the Trash folder.
 */
-(IBAction)emptyTrash:(id)sender
{
	[db deleteDeletedMessages];
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

/* compactDatabase
 * Run the database compaction command.
 */
-(IBAction)compactDatabase:(id)sender
{
	[db compactDatabase];
}

/* printDocument
 * Print the current message in the message window.
 */
-(IBAction)printDocument:(id)sender
{
	[[browserView activeView] printDocument];
}

/* folders
 * Return the array of folders.
 */
-(NSArray *)folders
{
	return [foldersTree folders:MA_Root_Folder];
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
	return [mainArticleView currentFolderId];
}

/* selectFolder
 * Select the specified folder.
 */
-(BOOL)selectFolder:(int)folderId
{
	return [mainArticleView selectFolderAndMessage:folderId guid:nil];
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
		[self createNewSubscription:linkPath underFolder:MA_Root_Folder];
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
	if (folderId == [mainArticleView currentFolderId])
	{
		[self setMainWindowTitle:folderId];
		[mainArticleView refreshFolder:YES];
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
	if ([mainArticleView currentFolderId] != newFolderId && newFolderId != 0)
	{
		// Blank out the search field
		[searchField setStringValue:@""];
		[mainArticleView selectFolderWithFilter:newFolderId];
		[[NSUserDefaults standardUserDefaults] setInteger:[mainArticleView currentFolderId] forKey:MAPref_CachedFolderID];
	}
}

/* handleCheckFrequencyChange
 * Called when the frequency by which we check messages is changed.
 */
-(void)handleCheckFrequencyChange:(NSNotification *)note
{
	int newFrequency = [[Preferences standardPreferences] refreshFrequency];

	[checkTimer invalidate];
	[checkTimer release];
	checkTimer = nil;
	if (newFrequency > 0)
	{
		checkTimer = [[NSTimer scheduledTimerWithTimeInterval:newFrequency
													   target:self
													 selector:@selector(getMessagesOnTimer:)
													 userInfo:nil
													  repeats:YES] retain];
	}
}

/* doViewColumn
 * Toggle whether or not a specified column is visible.
 */
-(IBAction)doViewColumn:(id)sender;
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	Field * field = [menuItem representedObject];

	[field setVisible:![field visible]];
	[mainArticleView updateVisibleColumns];
	[mainArticleView saveTableSettings];
}

/* doSortColumn
 * Handle the user picking an item from the Sort By submenu
 */
-(IBAction)doSortColumn:(id)sender
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	Field * field = [menuItem representedObject];

	NSAssert1(field, @"Somehow got a nil representedObject for Sort sub-menu item '%@'", [menuItem title]);
	[mainArticleView sortByIdentifier:[field name]];
}

/* doOpenScriptsFolder
 * Open the standard Vienna scripts folder.
 */
-(IBAction)doOpenScriptsFolder:(id)sender
{
	NSString * path = [[[NSUserDefaults standardUserDefaults] objectForKey:MAPref_ScriptsFolder] stringByExpandingTildeInPath];
	[[NSWorkspace sharedWorkspace] openFile:path];
}

/* doSelectScript
 * Run a script selected from the Script menu.
 */
-(IBAction)doSelectScript:(id)sender
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	NSString * scriptPath = [scriptPathMappings valueForKey:[menuItem title]];
	if (scriptPath != nil)
		[self runAppleScript:scriptPath];
}

/* doSelectStyle
 * Handle a selection from the Style menu.
 */
-(IBAction)doSelectStyle:(id)sender
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	[[Preferences standardPreferences] setDisplayStyle:[menuItem title]];
}

/* handleRefreshStatusChange
 * Handle a change of the refresh status.
 */
-(void)handleRefreshStatusChange:(NSNotification *)nc
{
	if ([NSApp isRefreshing])
	{
		[self startProgressIndicator];
		[self setStatusMessage:NSLocalizedString(@"Refreshing subscriptions...", nil) persist:YES];
	}
	else
	{
		[self setStatusMessage:NSLocalizedString(@"Refresh completed", nil) persist:YES];
		[self stopProgressIndicator];

		[self showUnreadCountOnApplicationIcon];

		int newUnread = [[RefreshManager sharedManager] countOfNewArticles];
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
				[NSNumber numberWithInt:newUnread], GROWL_NOTIFICATION_CLICK_CONTEXT,
				nil];
			[[NSDistributedNotificationCenter defaultCenter] postNotificationName:GROWL_NOTIFICATION 
																		   object:nil 
																		 userInfo:aNuDict
															   deliverImmediately:YES];
		}
	}
}	

/* moreStyles
 * Display the web page where the user can download additional styles.
 */
-(IBAction)moreStyles:(id)sender
{
	NSString * stylesPage = [standardURLs valueForKey:@"ViennaMoreStylesPage"];
	if (stylesPage != nil)
		[self openURLInBrowser:stylesPage];
}

/* viewArticlePage
 * Display the article in the browser.
 */
-(IBAction)viewArticlePage:(id)sender
{
	Message * theArticle = [mainArticleView selectedArticle];
	if (theArticle && ![[theArticle link] isBlank])
		[self openURLInBrowser:[theArticle link]];
}

/* forwardTrackMessage
 * Forward track through the list of messages displayed
 */
-(IBAction)forwardTrackMessage:(id)sender
{
	[mainArticleView trackMessage:MA_Track_Forward];
}

/* backTrackMessage
 * Back track through the list of messages displayed
 */
-(IBAction)backTrackMessage:(id)sender
{
	[mainArticleView trackMessage:MA_Track_Back];
}

/* handleKeyDown [delegate]
 * Support special key codes. If we handle the key, return YES otherwise
 * return NO to allow the framework to pass it on for default processing.
 */
-(BOOL)handleKeyDown:(unichar)keyChar withFlags:(unsigned int)flags
{
	switch (keyChar)
	{
		case NSLeftArrowFunctionKey:
			if (!(flags & NSCommandKeyMask))
				if ([mainWindow firstResponder] == [mainArticleView mainView])
				{
					[mainWindow makeFirstResponder:[foldersTree mainView]];
					return YES;
				}
			return NO;

		case NSRightArrowFunctionKey:
			if (!(flags & NSCommandKeyMask))
				if ([mainWindow firstResponder] == [foldersTree mainView])
				{
					[mainWindow makeFirstResponder:[mainArticleView mainView]];
					return YES;
				}
			return NO;
			
		case 'f':
		case 'F':
			[mainWindow makeFirstResponder:searchField];
			return YES;

		case '>':
			[self forwardTrackMessage:self];
			return YES;

		case '<':
			[self backTrackMessage:self];
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
			[self viewArticlePage:self];
			return YES;
	}
	return [[browserView activeView] handleKeyDown:keyChar withFlags:flags];
}

/* isConnecting
 * Returns whether or not 
 */
-(BOOL)isConnecting
{
	return [[RefreshManager sharedManager] totalConnections] > 0;
}

/* getMessagesOnTimer
 * Each time the check timer fires, we see if a connect is not
 * running and then kick one off.
 */
-(void)getMessagesOnTimer:(NSTimer *)aTimer
{
	[self refreshAllSubscriptions:self];
}

/* createNewSubscription
 * Create a new subscription for the specified URL under the given parent folder.
 */
-(void)createNewSubscription:(NSString *)urlString underFolder:(int)parentId
{
	// Replace feed:// with http:// if necessary
	if ([urlString hasPrefix:@"feed://"])
		urlString = [NSString stringWithFormat:@"http://%@", [urlString substringFromIndex:7]];

	// Create then select the new folder.
	int folderId = [db addRSSFolder:[db untitledFeedFolderName] underParent:parentId subscriptionURL:urlString];
	[mainArticleView selectFolderAndMessage:folderId guid:nil];

	if (isAccessible(urlString))
	{
		Folder * folder = [db folderFromID:folderId];
		[[RefreshManager sharedManager] refreshSubscriptions:[NSArray arrayWithObject:folder]];
	}
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
		groupFolder = [[NewGroupFolder alloc] init];
	[groupFolder newGroupFolder:mainWindow underParent:[foldersTree groupParentSelection]];
}

/* deleteMessage
 * Delete the current message. If we're in the Trash folder, this represents a permanent
 * delete. Otherwise we just move the message to the trash folder.
 */
-(IBAction)deleteMessage:(id)sender
{
	if ([mainArticleView selectedArticle] != nil && ![db readOnly])
	{
		Folder * folder = [db folderFromID:[mainArticleView currentFolderId]];
		if (!IsTrashFolder(folder))
		{
			NSArray * messageArray = [mainArticleView markedMessageRange];
			[mainArticleView markDeletedByArray:messageArray deleteFlag:YES];
			[messageArray release];
		}
		else
		{
			NSBeginCriticalAlertSheet(NSLocalizedString(@"Delete selected message", nil),
									  NSLocalizedString(@"Delete", nil),
									  NSLocalizedString(@"Cancel", nil),
									  nil, [NSApp mainWindow], self,
									  @selector(doConfirmedDelete:returnCode:contextInfo:), nil, nil,
									  NSLocalizedString(@"Delete selected message text", nil));
		}
	}
}

/* doConfirmedDelete
 * This function is called after the user has dismissed
 * the confirmation sheet.
 */
-(void)doConfirmedDelete:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSAlertDefaultReturn)
		[mainArticleView deleteSelectedMessages];
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
	[mainArticleView displayNextUnread];
}

/* clearUndoStack
 * Clear the undo stack for instances when the last action invalidates
 * all previous undoable actions.
 */
-(void)clearUndoStack
{
	[[mainWindow undoManager] removeAllActions];
}

/* setMainWindowTitle
 * Updates the main window title bar.
 */
-(void)setMainWindowTitle:(int)folderId
{
	if (folderId > 0)
	{
		Folder * folder = [db folderFromID:folderId];
		[[searchField cell] setPlaceholderString:[NSString stringWithFormat:NSLocalizedString(@"Search in %@", nil), [folder name]]];
	}
}

/* markAllRead
 * Mark all messages read in the selected folders.
 */
-(IBAction)markAllRead:(id)sender
{
	[self markAllReadInArray:[foldersTree selectedFolders]];
	[self showUnreadCountOnApplicationIcon];
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
		if (IsGroupFolder(folder))
		{
			[self markAllReadInArray:[db arrayOfFolders:folderId]];
			if (folderId == [mainArticleView currentFolderId])
				[mainArticleView refreshFolder:YES];
		}
		else if (!IsSmartFolder(folder))
		{
			[db markFolderRead:folderId];
			[foldersTree updateFolder:folderId recurseToParents:YES];
			if (folderId == [mainArticleView currentFolderId])
				[mainArticleView refreshFolder:NO];
		}
		else
		{
			// For smart folders, we only mark all read the current folder to
			// simplify things.
			if (folderId == [mainArticleView currentFolderId])
				[mainArticleView markReadByArray:[mainArticleView allMessages] readFlag:YES];
		}
	}
}

/* markRead
 * Toggle the read/unread state of the selected messages
 */
-(IBAction)markRead:(id)sender
{
	Message * theArticle = [mainArticleView selectedArticle];
	if (theArticle != nil && ![db readOnly])
	{
		NSArray * messageArray = [mainArticleView markedMessageRange];
		[mainArticleView markReadByArray:messageArray readFlag:![theArticle isRead]];
		[messageArray release];
	}
}

/* markFlagged
 * Toggle the flagged/unflagged state of the selected message
 */
-(IBAction)markFlagged:(id)sender
{
	Message * theArticle = [mainArticleView selectedArticle];
	if (theArticle != nil && ![db readOnly])
	{
		NSArray * messageArray = [mainArticleView markedMessageRange];
		[mainArticleView markFlaggedByArray:messageArray flagged:![theArticle isFlagged]];
		[messageArray release];
	}
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

/* renameUndo
 * Undo a folder rename action. Also create a redo action to reapply the original
 * change back again.
 */
-(void)renameUndo:(id)anObject
{
	NSDictionary * undoAttributes = (NSDictionary *)anObject;
	Folder * folder = [undoAttributes objectForKey:@"Folder"];
	NSString * oldName = [undoAttributes objectForKey:@"Name"];

	NSMutableDictionary * redoAttributes = [NSMutableDictionary dictionary];

	[redoAttributes setValue:[folder name] forKey:@"Name"];
	[redoAttributes setValue:folder forKey:@"Folder"];

	NSUndoManager * undoManager = [mainWindow undoManager];
	[undoManager registerUndoWithTarget:self selector:@selector(renameUndo:) object:redoAttributes];
	[undoManager setActionName:NSLocalizedString(@"Rename", nil)];

	[db setFolderName:[folder itemId] newName:oldName];
}

/* endRenameFolder
 * Called when the user OK's the Rename Folder sheet
 */
-(IBAction)endRenameFolder:(id)sender
{
	NSString * newName = [[renameField stringValue] trim];
	if ([db folderFromName:newName] != nil)
		runOKAlertPanel(@"Cannot rename folder", @"A folder with that name already exists");
	else
	{
		[renameWindow orderOut:sender];
		[NSApp endSheet:renameWindow returnCode:1];
		
		Folder * folder = [db folderFromID:[mainArticleView currentFolderId]];
		NSMutableDictionary * renameAttributes = [NSMutableDictionary dictionary];
		
		[renameAttributes setValue:[folder name] forKey:@"Name"];
		[renameAttributes setValue:folder forKey:@"Folder"];
		
		NSUndoManager * undoManager = [mainWindow undoManager];
		[undoManager registerUndoWithTarget:self selector:@selector(renameUndo:) object:renameAttributes];
		[undoManager setActionName:NSLocalizedString(@"Rename", nil)];
		
		[db setFolderName:[mainArticleView currentFolderId] newName:newName];
	}
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

	// Clear undo stack for this action
	[self clearUndoStack];

	// Prompt for each folder for now
	for (index = 0; index < count; ++index)
	{
		Folder * folder = [selectedFolders objectAtIndex:index];
		if (!IsTrashFolder(folder))
		{
			// Create a status string
			NSString * deleteStatusMsg = [NSString stringWithFormat:NSLocalizedString(@"Delete folder status", nil), [folder name]];
			[self setStatusMessage:deleteStatusMsg persist:NO];

			// Now call the database to delete the folder.
			[db deleteFolder:[folder itemId]];
		}
	}

	// Unread count may have changed
	[self setStatusMessage:nil persist:NO];
	[self showUnreadCountOnApplicationIcon];
}

/* validateFeed
 * Call the feed validator on the selected subscription feed.
 */
-(IBAction)validateFeed:(id)sender
{
	int folderId = [foldersTree actualSelection];
	Folder * folder = [db folderFromID:folderId];

	if (IsRSSFolder(folder))
	{
		NSString * validatorPage = [standardURLs valueForKey:@"FeedValidatorTemplate"];
		if (validatorPage != nil)
		{
			NSString * validatorURL = [NSString stringWithFormat:validatorPage, [folder feedURL]];
			[self openURLInBrowser:validatorURL];
		}
	}
}

/* viewSourceHomePage
 * Display the web site associated with this feed, if there is one.
 */
-(IBAction)viewSourceHomePage:(id)sender
{
	Message * thisArticle = [mainArticleView selectedArticle];
	if (thisArticle != nil)
	{
		Folder * folder = [db folderFromID:[thisArticle folderId]];
		[self openURLInBrowser:[folder homePage]];
	}
}

/* showViennaHomePage
 * Open the Vienna home page in the default browser.
 */
-(IBAction)showViennaHomePage:(id)sender
{
	NSString * homePage = [standardURLs valueForKey:@"ViennaHomePage"];
	if (homePage != nil)
		[self openURLInBrowser:homePage];
}

/* showAcknowledgements
 * Display the acknowledgements document in a browser.
 */
-(IBAction)showAcknowledgements:(id)sender
{
	NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];
	NSString * pathToAckFile = [thisBundle pathForResource:@"Acknowledgements.rtf" ofType:@""];
	if (pathToAckFile != nil)
		[self openURLInBrowser:[NSString stringWithFormat:@"file://%@", pathToAckFile]];
}

/* searchString
 * Return the contents of the search field.
 */
-(NSString *)searchString
{
	return [searchField stringValue];
}

/* searchUsingToolbarTextField
 * Executes a search using the search field on the toolbar.
 */
-(IBAction)searchUsingToolbarTextField:(id)sender
{
	[[browserView activeView] search];
}

/* refreshAllSubscriptions
 * Get new articles from all subscriptions.
 */
-(IBAction)refreshAllSubscriptions:(id)sender
{
	if (![self isConnecting])
		[[RefreshManager sharedManager] refreshSubscriptions:[db arrayOfRSSFolders]];
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
		[[RefreshManager sharedManager] refreshSubscriptions:selectedFolders];
}

/* cancelAllRefreshes
 * Used to kill all active refresh connections and empty the queue of folders due to
 * be refreshed.
 */
-(IBAction)cancelAllRefreshes:(id)sender
{
	[[RefreshManager sharedManager] cancelAll];
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
	BOOL isMainWindowVisible = [mainWindow isVisible];
	
	if (theAction == @selector(printDocument:))
	{
		return ([mainArticleView selectedArticle] != nil && isMainWindowVisible);
	}
	else if (theAction == @selector(backTrackMessage:))
	{
		return [mainArticleView getTrackIndex] != MA_Track_AtStart && isMainWindowVisible;
	}
	else if (theAction == @selector(forwardTrackMessage:))
	{
		return [mainArticleView getTrackIndex] != MA_Track_AtEnd && isMainWindowVisible;
	}
	else if (theAction == @selector(newSubscription:))
	{
		return ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(newSmartFolder:))
	{
		return ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(newGroupFolder:))
	{
		return ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(viewNextUnread:))
	{
		return [db countOfUnread] > 0;
	}
	else if (theAction == @selector(refreshAllSubscriptions:))
	{
		return ![self isConnecting] && ![db readOnly];
	}
	else if (theAction == @selector(doViewColumn:))
	{
		Field * field = [menuItem representedObject];
		[menuItem setState:[field visible] ? NSOnState : NSOffState];
		return isMainWindowVisible && ([mainArticleView tableLayout] == MA_Table_Layout);
	}
	else if (theAction == @selector(doSelectStyle:))
	{
		NSString * styleName = [menuItem title];
		[menuItem setState:[styleName isEqualToString:[[Preferences standardPreferences] displayStyle]] ? NSOnState : NSOffState];
		return isMainWindowVisible;
	}
	else if (theAction == @selector(doSortColumn:))
	{
		Field * field = [menuItem representedObject];
		if ([[field name] isEqualToString:[mainArticleView sortColumnIdentifier]])
			[menuItem setState:NSOnState];
		else
			[menuItem setState:NSOffState];
		return isMainWindowVisible;
	}
	else if (theAction == @selector(deleteFolder:))
	{
		Folder * folder = [db folderFromID:[foldersTree actualSelection]];
		return folder && !IsTrashFolder(folder) && ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(refreshSelectedSubscriptions:))
	{
		Folder * folder = [db folderFromID:[foldersTree actualSelection]];
		return folder && (IsRSSFolder(folder) || IsGroupFolder(folder)) && ![db readOnly];
	}
	else if (theAction == @selector(renameFolder:))
	{
		Folder * folder = [db folderFromID:[foldersTree actualSelection]];
		return folder && ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(markAllRead:))
	{
		Folder * folder = [db folderFromID:[foldersTree actualSelection]];
		return folder && !IsTrashFolder(folder) && ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(importSubscriptions:))
	{
		return ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(cancelAllRefreshes:))
	{
		return [self isConnecting];
	}
	else if (theAction == @selector(viewSourceHomePage:))
	{
		Message * thisMessage = [mainArticleView selectedArticle];
		if (thisMessage != nil)
		{
			Folder * folder = [db folderFromID:[thisMessage folderId]];
			return folder && ([folder homePage] && ![[folder homePage] isBlank] && isMainWindowVisible);
		}
		return NO;
	}
	else if (theAction == @selector(viewArticlePage:))
	{
		Message * thisMessage = [mainArticleView selectedArticle];
		if (thisMessage != nil)
			return ([thisMessage link] && ![[thisMessage link] isBlank] && isMainWindowVisible);
		return NO;
	}
	else if (theAction == @selector(exportSubscriptions:))
	{
		return isMainWindowVisible;
	}
	else if (theAction == @selector(runPageLayout:))
	{
		return isMainWindowVisible;
	}
	else if (theAction == @selector(compactDatabase:))
	{
		return ![self isConnecting] && ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(editFolder:))
	{
		Folder * folder = [db folderFromID:[foldersTree actualSelection]];
		return folder && (IsSmartFolder(folder) || IsRSSFolder(folder)) && ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(validateFeed:))
	{
		int folderId = [foldersTree actualSelection];
		Folder * folder = [db folderFromID:folderId];
		return IsRSSFolder(folder) && isMainWindowVisible;
	}
	else if (theAction == @selector(deleteMessage:))
	{
		return [mainArticleView selectedArticle] != nil && ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(emptyTrash:))
	{
		return ![db readOnly];
	}
	else if (theAction == @selector(closeMainWindow:))
	{
		return isMainWindowVisible;
	}
	else if (theAction == @selector(readingPaneOnRight:))
	{
		[menuItem setState:([[Preferences standardPreferences] readingPaneOnRight] ? NSOnState : NSOffState)];
		return isMainWindowVisible;
	}
	else if (theAction == @selector(readingPaneOnBottom:))
	{
		[menuItem setState:([[Preferences standardPreferences] readingPaneOnRight] ? NSOffState : NSOnState)];
		return isMainWindowVisible;
	}
	else if (theAction == @selector(markFlagged:))
	{
		Message * thisMessage = [mainArticleView selectedArticle];
		if (thisMessage != nil)
		{
			if ([thisMessage isFlagged])
				[menuItem setTitle:NSLocalizedString(@"Mark Unflagged", nil)];
			else
				[menuItem setTitle:NSLocalizedString(@"Mark Flagged", nil)];
		}
		return (thisMessage != nil && ![db readOnly] && isMainWindowVisible);
	}
	else if (theAction == @selector(markRead:))
	{
		Message * thisMessage = [mainArticleView selectedArticle];
		if (thisMessage != nil)
		{
			if ([thisMessage isRead])
				[menuItem setTitle:NSLocalizedString(@"Mark Unread", nil)];
			else
				[menuItem setTitle:NSLocalizedString(@"Mark Read", nil)];
		}
		return (thisMessage != nil && ![db readOnly] && isMainWindowVisible);
	}
	return YES;
}

/* dealloc
 * Clean up and release resources.
 */
-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[standardURLs release];
	[persistedStatusText release];
	[scriptPathMappings release];
	[originalIcon release];
	[smartFolder release];
	[rssFeed release];
	[groupFolder release];
	[checkUpdates release];
	[preferenceController release];
	[activityViewer release];
	[checkTimer release];
	[appDockMenu release];
	[db release];
	[super dealloc];
}
@end
