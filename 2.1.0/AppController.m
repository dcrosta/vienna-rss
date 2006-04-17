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
#import "NewPreferencesController.h"
#import "FoldersTree.h"
#import "ArticleListView.h"
#import "Import.h"
#import "Export.h"
#import "RefreshManager.h"
#import "StringExtensions.h"
#import "SplitViewExtensions.h"
#import "BrowserView.h"
#import "CheckForUpdates.h"
#import "SearchFolder.h"
#import "NewSubscription.h"
#import "NewGroupFolder.h"
#import "RenameFolder.h"
#import "ViennaApp.h"
#import "ActivityLog.h"
#import "BrowserPaneTemplate.h"
#import "Constants.h"
#import "ArticleView.h"
#import "BrowserPane.h"
#import "Preferences.h"
#import "DownloadManager.h"
#import "HelperFunctions.h"
#import "ArticleFilter.h"
#import "WebKit/WebFrame.h"
#import "WebKit/WebUIDelegate.h"
#import "Growl/GrowlDefines.h"
#include <mach/mach_port.h>
#include <mach/mach_interface.h>
#include <mach/mach_init.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOMessage.h>

@interface AppController (Private)
	-(void)installSleepHandler;
	-(void)installScriptsFolderWatcher;
	-(void)handleTabChange:(NSNotification *)nc;
	-(void)handleFolderSelection:(NSNotification *)nc;
	-(void)handleCheckFrequencyChange:(NSNotification *)nc;
	-(void)handleFolderNameChange:(NSNotification *)nc;
	-(void)handleDidBecomeKeyWindow:(NSNotification *)nc;
	-(void)handleReloadPreferences:(NSNotification *)nc;
	-(void)localiseMenus:(NSArray *)arrayOfMenus;
	-(void)initSortMenu;
	-(void)initColumnsMenu;
	-(void)initStylesMenu;
	-(void)initFiltersMenu;
	-(void)initScriptsMenu;
	-(void)startProgressIndicator;
	-(void)stopProgressIndicator;
	-(void)doEditFolder:(Folder *)folder;
	-(void)refreshOnTimer:(NSTimer *)aTimer;
	-(void)doConfirmedDelete:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
	-(void)doConfirmedEmptyTrash:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
	-(void)runAppleScript:(NSString *)scriptName;
	-(void)setImageForMenuCommand:(NSImage *)image forAction:(SEL)sel;
	-(NSString *)appName;
	-(void)updateAlternateMenuTitle;
	-(void)updateSearchPlaceholder;
	-(FoldersTree *)foldersTree;
	-(void)updateCloseCommands;
	-(void)loadOpenTabs;
	-(NSDictionary *)registrationDictionaryForGrowl;
@end

// Static constant strings that are typically never tweaked
static const int MA_Minimum_Folder_Pane_Width = 80;
static const int MA_Minimum_BrowserView_Pane_Width = 200;

// Awake from sleep
static io_connect_t root_port;
static void MySleepCallBack(void * x, io_service_t y, natural_t messageType, void * messageArgument);

@implementation AppController

/* init
 * Class instance initialisation.
 */
-(id)init
{
	if ((self = [super init]) != nil)
	{
		scriptPathMappings = [[NSMutableDictionary alloc] init];
		progressCount = 0;
		persistedStatusText = nil;
		lastCountOfUnread = 0;
		growlAvailable = NO;
		scriptsMenuItem = nil;
		checkTimer = nil;
	}
	return self;
}

/* awakeFromNib
 * Do all the stuff that only makes sense after our NIB has been loaded and connected.
 */
-(void)awakeFromNib
{
	Preferences * prefs = [Preferences standardPreferences];

	// Set the primary view of the browser view
	BrowserTab * primaryTab = [browserView setPrimaryTabView:mainArticleView];
	[browserView setTabTitle:primaryTab title:NSLocalizedString(@"Articles", nil)];

	// Localise the menus
	[self localiseMenus:[[NSApp mainMenu] itemArray]];

	// Set the delegates and title
	[mainWindow setDelegate:self];
	[mainWindow setTitle:[self appName]];
	[NSApp setDelegate:self];

	// Register a bunch of notifications
	NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleFolderSelection:) name:@"MA_Notify_FolderSelectionChange" object:nil];
	[nc addObserver:self selector:@selector(handleCheckFrequencyChange:) name:@"MA_Notify_CheckFrequencyChange" object:nil];
	[nc addObserver:self selector:@selector(checkForUpdatesComplete:) name:@"MA_Notify_UpdateCheckCompleted" object:nil];
	[nc addObserver:self selector:@selector(handleEditFolder:) name:@"MA_Notify_EditFolder" object:nil];
	[nc addObserver:self selector:@selector(handleRefreshStatusChange:) name:@"MA_Notify_RefreshStatus" object:nil];
	[nc addObserver:self selector:@selector(handleTabChange:) name:@"MA_Notify_TabChanged" object:nil];
	[nc addObserver:self selector:@selector(handleFolderNameChange:) name:@"MA_Notify_FolderNameChanged" object:nil];
	[nc addObserver:self selector:@selector(handleDidBecomeKeyWindow:) name:NSWindowDidBecomeKeyNotification object:nil];
	[nc addObserver:self selector:@selector(handleReloadPreferences:) name:@"MA_Notify_PreferenceChange" object:nil];
	
	// Init the progress counter and status bar.
	[self setStatusMessage:nil persist:NO];
	
	// Initialize the database
	if ((db = [Database sharedDatabase]) == nil)
	{
		[NSApp terminate:nil];
		return;
	}
	
	// Run the auto-expire now
	[db purgeArticlesOlderThanDays:[prefs autoExpireDuration] sendNotification:NO];
	
	// Preload dictionary of standard URLs
	NSString * pathToPList = [[NSBundle mainBundle] pathForResource:@"StandardURLs.plist" ofType:@""];
	if (pathToPList != nil)
		standardURLs = [[NSDictionary dictionaryWithContentsOfFile:pathToPList] retain];
	
	// Initialize the Styles, Sort By and Columns menu
	[self initSortMenu];
	[self initColumnsMenu];
	[self initStylesMenu];
	[self initFiltersMenu];

	// Restore the splitview layout
	[splitView1 setLayout:[[Preferences standardPreferences] objectForKey:@"SplitView1Positions"]];	
	[splitView1 setDelegate:self];
	
	// Show the current unread count on the app icon
	originalIcon = [[NSApp applicationIconImage] copy];
	[self showUnreadCountOnApplicationIconAndWindowTitle];
	
	// Set alternate in main menu for opening pages, and check for correct title of menu item
	// This is a hack, because Interface Builder refuses to set alternates with only the shift key as modifier.
	NSMenuItem * alternateItem = menuWithAction(@selector(viewSourceHomePageInAlternateBrowser:));
	if (alternateItem != nil)
	{
		[alternateItem setKeyEquivalentModifierMask:NSShiftKeyMask];
		[alternateItem setAlternate:YES];
	}
	alternateItem = menuWithAction(@selector(viewArticlePageInAlternateBrowser:));
	if (alternateItem != nil)
	{
		[alternateItem setKeyEquivalentModifierMask:NSShiftKeyMask];
		[alternateItem setAlternate:YES];
	}
	[self updateAlternateMenuTitle];
	
	// Create a menu for the search field
	// The menu title doesn't appear anywhere so we don't localise it. The titles of each
	// item is localised though.
	NSMenu * cellMenu = [[NSMenu alloc] initWithTitle:@"Search Menu"];
	
    NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Recent Searches", nil) action:NULL keyEquivalent:@""];
    [item setTag:NSSearchFieldRecentsTitleMenuItemTag];
	[cellMenu insertItem:item atIndex:0];
    [item release];
	
	item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Recents", nil) action:NULL keyEquivalent:@""];
    [item setTag:NSSearchFieldRecentsMenuItemTag];
    [cellMenu insertItem:item atIndex:1];
    [item release];
	
    item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Clear", nil) action:NULL keyEquivalent:@""];
    [item setTag:NSSearchFieldClearRecentsMenuItemTag];
    [cellMenu insertItem:item atIndex:2];
    [item release];
	
    [[searchField cell] setSearchMenuTemplate:cellMenu];
	[cellMenu release];

	// Tooltips
	[filtersPopupMenu setToolTip:NSLocalizedString(@"Filter articles", nil)];
	
	// Add Scripts menu if we have any scripts
	if ([prefs boolForKey:MAPref_ShowScriptsMenu] || !hasOSScriptsMenu())
		[self initScriptsMenu];
	
	// Use Growl if it is installed
	[GrowlApplicationBridge setGrowlDelegate:self];
	
	// Start the check timer
	[self handleCheckFrequencyChange:nil];
	
	// Register to be informed when the system awakes from sleep
	[self installSleepHandler];
	
	// Register to be notified when the scripts folder changes.
	if ([prefs boolForKey:MAPref_ShowScriptsMenu] || !hasOSScriptsMenu())
		[self installScriptsFolderWatcher];
	
	// Assign the controller for the child views
	[foldersTree setController:self];
	[mainArticleView setController:self];

	// Fix up the Close commands
	[self updateCloseCommands];

	// Do safe initialisation. 	 
	[self doSafeInitialisation];
}

/* doSafeInitialisation
 * Do the stuff that requires that all NIBs are awoken. I can't find a notification
 * from Cocoa for this so we hack it.
 */
-(void)doSafeInitialisation
{
	static BOOL doneSafeInit = NO;
	if (!doneSafeInit)
	{
		[foldersTree initialiseFoldersTree];
		[mainArticleView initialiseArticleView];
		[self loadOpenTabs];
		doneSafeInit = YES;
	}
}

/* localiseMenus
 * As of 2.0.1, the menu localisation is now done through the Localizable.strings file rather than
 * the NIB file due to the effort in managing localised NIBs for an increasing number of languages.
 * Also, note care is taken not to localise those commands that were added by the OS. If there is
 * no equivalent in the Localizable.strings file, we do nothing.
 */
-(void)localiseMenus:(NSArray *)arrayOfMenus
{
	int count = [arrayOfMenus count];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		NSMenuItem * menuItem = [arrayOfMenus objectAtIndex:index];
		if (menuItem != nil && ![menuItem isSeparatorItem])
		{
			NSString * localisedMenuTitle = NSLocalizedString([menuItem title], nil);
			if ([menuItem submenu])
			{
				NSMenu * subMenu = [menuItem submenu];
				if (localisedMenuTitle != nil)
					[subMenu setTitle:localisedMenuTitle];
				[self localiseMenus:[subMenu itemArray]];
			}
			if (localisedMenuTitle != nil)
				[menuItem setTitle:localisedMenuTitle];
		}
	}
}

#pragma mark IORegisterForSystemPower

/* MySleepCallBack
 * Called in response to an I/O event that we established via IORegisterForSystemPower. The
 * messageType parameter allows us to distinguish between which event occurred.
 */
static void MySleepCallBack(void * refCon, io_service_t service, natural_t messageType, void * messageArgument)
{
	if (messageType == kIOMessageSystemHasPoweredOn)
	{
		AppController * app = (AppController *)[NSApp delegate];
		Preferences * prefs = [Preferences standardPreferences];
		if ([prefs refreshFrequency] > 0)
			[app refreshAllSubscriptions:app];
	}
	else if (messageType == kIOMessageCanSystemSleep)
	{
		// Idle sleep is about to kick in. Allow it otherwise the system
		// will wait 30 seconds then go to sleep.
		IOAllowPowerChange(root_port, (long)messageArgument);
	}
	else if (messageType == kIOMessageSystemWillSleep)
	{
		// The system WILL go to sleep. Allow it otherwise the system will
		// wait 30 seconds then go to sleep.
		IOAllowPowerChange(root_port, (long)messageArgument);
	}
}

/* installSleepHandler
 * Registers our handler to be notified when the system awakes from sleep. We use this to kick
 * off a refresh if necessary.
 */
-(void)installSleepHandler
{
    IONotificationPortRef notify;
    io_object_t anIterator;
	
    root_port = IORegisterForSystemPower(self, &notify, MySleepCallBack, &anIterator);
    if (root_port != 0)
		CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notify), kCFRunLoopCommonModes);
}

/* MyScriptsFolderWatcherCallBack
 * This is the callback function which is invoked when the file system detects changes in the Scripts
 * folder. We use this to trigger a refresh of the scripts menu.
 */
static void MyScriptsFolderWatcherCallBack(FNMessage message, OptionBits flags, void * refcon, FNSubscriptionRef subscription)
{
	AppController * app = (AppController *)refcon;
	[app initScriptsMenu];
}

/* installScriptsFolderWatcher
 * Install a handler to notify of changes in the scripts folder.
 */
-(void)installScriptsFolderWatcher
{
	NSString * path = [[Preferences standardPreferences] scriptsFolder];
	FNSubscriptionRef refCode;
	
	FNSubscribeByPath((const UInt8 *)[path UTF8String], MyScriptsFolderWatcherCallBack, self, kNilOptions, &refCode);
}

#pragma mark Application Delegate

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
 * if a connection or import is running and that all articles are saved.
 */
-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	int returnCode;
	
	if ([[DownloadManager sharedInstance] activeDownloads] > 0)
	{
		returnCode = NSRunAlertPanel(NSLocalizedString(@"Downloads Running", nil),
									 NSLocalizedString(@"Downloads Running text", nil),
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
	Preferences * prefs = [Preferences standardPreferences];
	[prefs setObject:[splitView1 layout] forKey:@"SplitView1Positions"];

	// Close the activity window explicitly to force it to
	// save its split bar position to the preferences.
	NSWindow * activityWindow = [activityViewer window];
	[activityWindow performClose:self];
	
	// Put back the original app icon
	[NSApp setApplicationIconImage:originalIcon];
	
	// Save the open tabs
	[browserView saveOpenTabs];

	// Remember the article list column position, sizes, etc.
	[mainArticleView saveTableSettings];
	[foldersTree saveFolderSettings];
	
	if ([mainArticleView currentFolderId] != -1)
		[db flushFolder:[mainArticleView currentFolderId]];
	[db close];
	
	// Finally save preferences
	[prefs savePreferences];
}

/* openFile [delegate]
 * Called when the user opens a data file associated with Vienna.
 */
-(BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	Preferences * prefs = [Preferences standardPreferences];
	if ([[filename pathExtension] isEqualToString:@"viennastyle"])
	{
		NSString * path = [prefs stylesFolder];
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
		[fileManager removeFileAtPath:fullPath handler:nil];
		if (![fileManager copyPath:filename toPath:fullPath handler:nil])
			[[Preferences standardPreferences] setDisplayStyle:styleName];
		else
		{
			Preferences * prefs = [Preferences standardPreferences];
			[self initStylesMenu];
			[prefs setDisplayStyle:styleName];
			if ([[prefs displayStyle] isEqualToString:styleName])
				runOKAlertPanel(@"New style title", @"New style body", styleName);
		}
		return YES;
	}
	if ([[filename pathExtension] isEqualToString:@"scpt"])
	{
		NSString * path = [prefs scriptsFolder];
		NSString * fullPath = [path stringByAppendingPathComponent:[filename lastPathComponent]];
		
		// Make sure we actually have a Scripts folder.
		NSFileManager * fileManager = [NSFileManager defaultManager];
		BOOL isDir = NO;
		
		if (![fileManager fileExistsAtPath:path isDirectory:&isDir])
		{
			if (![fileManager createDirectoryAtPath:path attributes:NULL])
			{
				runOKAlertPanel(@"Cannot create scripts folder title", @"Cannot create scripts folder body", path);
				return NO;
			}
		}
		[fileManager removeFileAtPath:fullPath handler:nil];
		if ([fileManager copyPath:filename toPath:fullPath handler:nil])
		{
			if ([prefs boolForKey:MAPref_ShowScriptsMenu] || !hasOSScriptsMenu())
				[self initScriptsMenu];
		}
	}
	return NO;
}

/* database
 */
-(Database *)database
{
	return db;
}

/* browserView
 */
-(BrowserView *)browserView
{
	return browserView;
}

/* foldersTree
 */
-(FoldersTree *)foldersTree
{
	return foldersTree;
}

/* constrainMinCoordinate
 * Make sure the folder width isn't shrunk beyond a minimum width. Otherwise it looks
 * untidy.
 */
-(float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedMin ofSubviewAt:(int)offset
{
	return (sender == splitView1 && offset == 0) ? MA_Minimum_Folder_Pane_Width : proposedMin;
}

/* constrainMaxCoordinate
 * Make sure that the browserview isn't shrunk beyond a minimum size otherwise the splitview
 * or controls within it start resizing odd.
 */
-(float)splitView:(NSSplitView *)sender constrainMaxCoordinate:(float)proposedMax ofSubviewAt:(int)offset
{
	if (sender == splitView1 && offset == 0)
	{
		NSRect mainFrame = [[splitView1 superview] frame];
		return mainFrame.size.width - MA_Minimum_BrowserView_Pane_Width;
	}
	return proposedMax;
}

/* resizeSubviewsWithOldSize
 * Constrain the folder pane to a fixed width.
 */
-(void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
	float dividerThickness = [sender dividerThickness];
	id sv1 = [[sender subviews] objectAtIndex:0];
	id sv2 = [[sender subviews] objectAtIndex:1];
	NSRect leftFrame = [sv1 frame];
	NSRect rightFrame = [sv2 frame];
	NSRect newFrame = [sender frame];
	
	if (sender == splitView1)
	{
		leftFrame.size.height = newFrame.size.height;
		leftFrame.origin = NSMakePoint(0, 0);
		rightFrame.size.width = newFrame.size.width - leftFrame.size.width - dividerThickness;
		rightFrame.size.height = newFrame.size.height;
		rightFrame.origin.x = leftFrame.size.width + dividerThickness;
		
		[sv1 setFrame:leftFrame];
		[sv2 setFrame:rightFrame];
	}
}

/* readingPaneOnRight
 * Move the reading pane to the right of the article list.
 */
-(IBAction)readingPaneOnRight:(id)sender
{
	[[Preferences standardPreferences] setReadingPaneOnRight:YES];
}

/* readingPaneOnBottom
 * Move the reading pane to the bottom of the article list.
 */
-(IBAction)readingPaneOnBottom:(id)sender
{
	[[Preferences standardPreferences] setReadingPaneOnRight:NO];
}

#pragma mark Dock Menu

/* applicationDockMenu
 * Return a menu with additional commands to be displayd on the application's
 * popup dock menu.
 */
-(NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	[appDockMenu release];
	appDockMenu = [[NSMenu alloc] initWithTitle:@"DockMenu"];
	[appDockMenu addItem:copyOfMenuWithAction(@selector(refreshAllSubscriptions:))];
	[appDockMenu addItem:copyOfMenuWithAction(@selector(markAllSubscriptionsRead:))];
	return appDockMenu;
}

/* contextMenuItemsForElement
 * Creates a new context menu for our web pane.
 */
-(NSArray *)contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems
{
	NSMutableArray * newDefaultMenu = [[NSMutableArray alloc] initWithArray:defaultMenuItems];
	NSURL * urlLink = [element valueForKey:WebElementLinkURLKey];
	NSURL * imageURL;
	NSString * defaultBrowser = getDefaultBrowser();
	if (defaultBrowser == nil)
		defaultBrowser = NSLocalizedString(@"External Browser", nil);
	NSMenuItem * newMenuItem;
	int count = [newDefaultMenu count];
	int index;
	
	// Note: this is only safe to do if we're going from [count..0] when iterating
	// over newDefaultMenu. If we switch to the other direction, this will break.
	for (index = count - 1; index >= 0; --index)
	{
		NSMenuItem * menuItem = [newDefaultMenu objectAtIndex:index];
		switch ([menuItem tag])
		{
			case WebMenuItemTagOpenImageInNewWindow:
				imageURL = [element valueForKey:WebElementImageURLKey];
				if (imageURL != nil)
				{
					[menuItem setTitle:NSLocalizedString(@"Open Image in New Tab", nil)];
					[menuItem setTarget:self];
					[menuItem setAction:@selector(openWebElementInNewTab:)];
					[menuItem setRepresentedObject:imageURL];
					[menuItem setTag:WebMenuItemTagOther];
					newMenuItem = [[NSMenuItem alloc] init];
					if (newMenuItem != nil)
					{
						[newMenuItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Open Image in %@", nil), defaultBrowser]];
						[newMenuItem setTarget:self];
						[newMenuItem setAction:@selector(openWebElementInDefaultBrowser:)];
						[newMenuItem setRepresentedObject:imageURL];
						[newMenuItem setTag:WebMenuItemTagOther];
						[newDefaultMenu insertObject:newMenuItem atIndex:index + 1];
					}
					[newMenuItem release];
				}
					break;
				
			case WebMenuItemTagOpenFrameInNewWindow:
				[menuItem setTitle:NSLocalizedString(@"Open Frame", nil)];
				break;
				
			case WebMenuItemTagOpenLinkInNewWindow:
				[menuItem setTitle:NSLocalizedString(@"Open Link in New Tab", nil)];
				[menuItem setTarget:self];
				[menuItem setAction:@selector(openWebElementInNewTab:)];
				[menuItem setRepresentedObject:urlLink];
				[menuItem setTag:WebMenuItemTagOther];
				newMenuItem = [[NSMenuItem alloc] init];
				if (newMenuItem != nil)
				{
					[newMenuItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Open Link in %@", nil), defaultBrowser]];
					[newMenuItem setTarget:self];
					[newMenuItem setAction:@selector(openWebElementInDefaultBrowser:)];
					[newMenuItem setRepresentedObject:urlLink];
					[newMenuItem setTag:WebMenuItemTagOther];
					[newDefaultMenu insertObject:newMenuItem atIndex:index + 1];
				}
					[newMenuItem release];
				break;
				
			case WebMenuItemTagCopyLinkToClipboard:
				[menuItem setTitle:NSLocalizedString(@"Copy Link to Clipboard", nil)];
				break;
		}
	}
	
	if (urlLink == nil)
	{
		// Separate our new commands from the existing ones.
		[newDefaultMenu addObject:[NSMenuItem separatorItem]];
		
		// Add command to open the current page in the external browser
		newMenuItem = [[NSMenuItem alloc] init];
		if (newMenuItem != nil)
		{
			[newMenuItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Open Page in %@", nil), defaultBrowser]];
			[newMenuItem setTarget:self];
			[newMenuItem setAction:@selector(openPageInBrowser:)];
			[newMenuItem setTag:WebMenuItemTagOther];
			[newDefaultMenu addObject:newMenuItem];
		}
		[newMenuItem release];
		
		// Add command to copy the URL of the current page to the clipboard
		newMenuItem = [[NSMenuItem alloc] init];
		if (newMenuItem != nil)
		{
			[newMenuItem setTitle:NSLocalizedString(@"Copy Page Link to Clipboard", nil)];
			[newMenuItem setTarget:self];
			[newMenuItem setAction:@selector(copyPageURLToClipboard:)];
			[newMenuItem setTag:WebMenuItemTagOther];
			[newDefaultMenu addObject:newMenuItem];
		}
		[newMenuItem release];
	}
	
	return [newDefaultMenu autorelease];
}

/* openPageInBrowser
 * Open the current web page in the browser.
 */
-(IBAction)openPageInBrowser:(id)sender
{
	NSView<BaseView> * theView = [browserView activeTabView];
	if ([theView isKindOfClass:[BrowserPane class]])
	{
		BrowserPane * webPane = (BrowserPane *)theView;
		NSURL * url = [webPane url];
		if (url != nil)
			[self openURLInDefaultBrowser:url];
	}
}

/* copyPageURLToClipboard
 * Copy the URL of the current web page to the clipboard.
 */
-(IBAction)copyPageURLToClipboard:(id)sender
{
	NSView<BaseView> * theView = [browserView activeTabView];
	if ([theView isKindOfClass:[BrowserPane class]])
	{
		BrowserPane * webPane = (BrowserPane *)theView;
		NSURL * url = [webPane url];
		if (url != nil)
		{
			NSPasteboard * pboard = [NSPasteboard generalPasteboard];
			[pboard declareTypes:[NSArray arrayWithObjects:NSStringPboardType, NSURLPboardType, nil] owner:self];
			[url writeToPasteboard:pboard];
			[pboard setString:[url description] forType:NSStringPboardType];
		}
	}
}

/* openWebElementInNewTab
 * Open the specified element in a new tab
 */
-(IBAction)openWebElementInNewTab:(id)sender
{
	if ([sender isKindOfClass:[NSMenuItem class]])
	{
		NSMenuItem * item = (NSMenuItem *)sender;
		Preferences * prefs = [Preferences standardPreferences];
		[self createNewTab:[item representedObject] inBackground:[prefs openLinksInBackground]];
	}
}

/* openWebElementInDefaultBrowser
 * Open the specified element in an external browser
 */
-(IBAction)openWebElementInDefaultBrowser:(id)sender
{
	if ([sender isKindOfClass:[NSMenuItem class]])
	{
		NSMenuItem * item = (NSMenuItem *)sender;
		[self openURLInDefaultBrowser:[item representedObject]];
	}
}

/* openWebLocation
 * Puts the focus in the address bar of the web browser tab. If one isn't open,
 * we create an empty one.
 */
-(IBAction)openWebLocation:(id)sender
{
	NSView<BaseView> * theView = [browserView activeTabView];
	[self showMainWindow:self];
	if (![theView isKindOfClass:[BrowserPane class]])
	{
		[self createNewTab:nil inBackground:NO];
		theView = [browserView activeTabView];
	}
	if ([theView isKindOfClass:[BrowserPane class]])
	{
		BrowserPane * browserPane = (BrowserPane *)theView;
		[browserPane activateAddressBar];
	}
}

/* openURLFromString
 * Open a URL in either the internal Vienna browser or an external browser depending on
 * whatever the user has opted for.
 */
-(void)openURLFromString:(NSString *)urlString inPreferredBrowser:(BOOL)openInPreferredBrowserFlag
{
	[self openURL:[NSURL URLWithString:urlString] inPreferredBrowser:openInPreferredBrowserFlag];
}

/* openURL
 * Open a URL in either the internal Vienna browser or an external browser depending on
 * whatever the user has opted for.
 */
-(void)openURL:(NSURL *)url inPreferredBrowser:(BOOL)openInPreferredBrowserFlag
{
	Preferences * prefs = [Preferences standardPreferences];
	BOOL openURLInVienna = [prefs openLinksInVienna];
	if (!openInPreferredBrowserFlag)
		openURLInVienna = (!openURLInVienna);
	if (openURLInVienna)
		[self createNewTab:url inBackground:[prefs openLinksInBackground]];
	else
		[self openURLInDefaultBrowser:url];
}

/* createNewTab
 * Open the specified URL in a new tab.
 */
-(void)createNewTab:(NSURL *)url inBackground:(BOOL)openInBackgroundFlag
{
	BrowserPaneTemplate * newBrowserTemplate = [[BrowserPaneTemplate alloc] init];
	if (newBrowserTemplate)
	{
		BrowserPane * newBrowserPane = [newBrowserTemplate mainView];
		BrowserTab * tab = [browserView createNewTabWithView:newBrowserPane makeKey:!openInBackgroundFlag];
		[newBrowserPane setController:self];
		[newBrowserPane setTab:tab];
		if (url != nil)
			[newBrowserPane loadURL:url inBackground:openInBackgroundFlag];
		[newBrowserPane release];
		[newBrowserTemplate release];
	}
}

/* openURLInDefaultBrowser
 * Open the specified URL in whatever the user has registered as their
 * default system browser.
 */
-(void)openURLInDefaultBrowser:(NSURL *)url
{
	Preferences * prefs = [Preferences standardPreferences];
	
	// This line is a workaround for OS X bug rdar://4450641
	if ([prefs openLinksInBackground])
		[mainWindow orderFront:self];
	
	// Launch in the foreground or background as needed
	NSWorkspaceLaunchOptions lOptions = [prefs openLinksInBackground] ? NSWorkspaceLaunchWithoutActivation : NSWorkspaceLaunchDefault;
	[[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:url]
					withAppBundleIdentifier:NULL
									options:lOptions
			 additionalEventParamDescriptor:NULL
						  launchIdentifiers:NULL];
}

/* loadOpenTabs
 * Opens separate tabs for each of the URLs persisted to the TabList preference.
 */
-(void)loadOpenTabs
{
	NSArray * tabLinks = [[Preferences standardPreferences] arrayForKey:MAPref_TabList];
	NSEnumerator * enumerator = [tabLinks objectEnumerator];
	NSString * tabLink;
	
	while ((tabLink = [enumerator nextObject]) != nil)
		[self createNewTab:[NSURL URLWithString:tabLink] inBackground:YES];
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
	[mainWindow makeKeyAndOrderFront:self];
}

/* runAppleScript
 * Run an AppleScript script given a fully qualified path to the script.
 */
-(void)runAppleScript:(NSString *)scriptName
{
	NSDictionary * errorDictionary;
	
	NSURL * scriptURL = [NSURL fileURLWithPath:scriptName];
	NSAppleScript * appleScript = [[NSAppleScript alloc] initWithContentsOfURL:scriptURL error:&errorDictionary];
	if (appleScript == nil)
	{
		NSString * baseScriptName = [[scriptName lastPathComponent] stringByDeletingPathExtension];
		runOKAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Error loading script '%@'", nil), baseScriptName],
						[errorDictionary valueForKey:NSAppleScriptErrorMessage]);
	}
	else
	{
		NSAppleEventDescriptor * resultEvent = [appleScript executeAndReturnError:&errorDictionary];
		[appleScript release];
		if (resultEvent == nil)
		{
			NSString * baseScriptName = [[scriptName lastPathComponent] stringByDeletingPathExtension];
			runOKAlertPanel([NSString stringWithFormat:NSLocalizedString(@"AppleScript Error in '%@' script", nil), baseScriptName],
							[errorDictionary valueForKey:NSAppleScriptErrorMessage]);
		}
	}
}

#pragma mark Growl Delegate

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
	[NSApp activateIgnoringOtherApps:YES];
	[self showMainWindow:self];
	Folder * unreadArticles = [db folderFromName:NSLocalizedString(@"Unread Articles", nil)];
	if (unreadArticles != nil)
		[mainArticleView selectFolderAndArticle:[unreadArticles itemId] guid:nil];
}

/* registrationDictionaryForGrowl
 * Called by Growl to request the notification dictionary.
 */
-(NSDictionary *)registrationDictionaryForGrowl
{
	NSMutableArray *defNotesArray = [NSMutableArray array];
	NSMutableArray *allNotesArray = [NSMutableArray array];
	
	[allNotesArray addObject:NSLocalizedString(@"Growl notification name", nil)];
	[defNotesArray addObject:NSLocalizedString(@"Growl notification name", nil)];
	
	NSDictionary *regDict = [NSDictionary dictionaryWithObjectsAndKeys:
		[self appName], GROWL_APP_NAME, 
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
			[field tag] != MA_FieldID_Comments &&
			[field tag] != MA_FieldID_Deleted &&
			[field tag] != MA_FieldID_Text)
		{
			NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:[field displayName] action:@selector(doSortColumn:) keyEquivalent:@""];
			[menuItem setRepresentedObject:field];
			[sortMenu addItem:menuItem];
			[menuItem release];
		}
	}
	[sortByMenu setSubmenu:sortMenu];
}

/* initColumnsMenu
 * Create the columns popup menu.
 */
-(void)initColumnsMenu
{
	NSMenu * columnsSubMenu = [[[NSMenu alloc] initWithTitle:@"Columns"] autorelease];
	NSArray * fields = [db arrayOfFields];
	NSEnumerator * enumerator = [fields objectEnumerator];
	Field * field;
	
	while ((field = [enumerator nextObject]) != nil)
	{
		// Filter out columns we don't view in the article list. Later we should have an attribute in the
		// field object based on which columns are visible in the tableview.
		if ([field tag] != MA_FieldID_Text && 
			[field tag] != MA_FieldID_GUID &&
			[field tag] != MA_FieldID_Comments &&
			[field tag] != MA_FieldID_Deleted &&
			[field tag] != MA_FieldID_Parent &&
			[field tag] != MA_FieldID_Headlines)
		{
			NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:[field displayName] action:@selector(doViewColumn:) keyEquivalent:@""];
			[menuItem setRepresentedObject:field];
			[columnsSubMenu addItem:menuItem];
			[menuItem release];
		}
	}
	[columnsMenu setSubmenu:columnsSubMenu];
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
	
	// Valid script file extensions
	NSArray * exts = [NSArray arrayWithObjects:@"scpt", nil];
	
	// Dump the current mappings
	[scriptPathMappings removeAllObjects];
	
	// Add scripts within the app resource
	NSString * path = [[[NSBundle mainBundle] sharedSupportPath] stringByAppendingPathComponent:@"Scripts"];
	loadMapFromPath(path, scriptPathMappings, NO, exts);
	
	// Add scripts that the user created and stored in the scripts folder
	path = [[Preferences standardPreferences] scriptsFolder];
	loadMapFromPath(path, scriptPathMappings, NO, exts);
	
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
	// we actually have any scripts.
	if (count > 0)
	{
		[scriptsMenu addItem:[NSMenuItem separatorItem]];
		NSMenuItem * menuItem;
		
		menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Open Scripts Folder", nil) action:@selector(doOpenScriptsFolder:) keyEquivalent:@""];
		[scriptsMenu addItem:menuItem];
		[menuItem release];
		
		menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"More Scripts...", nil) action:@selector(moreScripts:) keyEquivalent:@""];
		[scriptsMenu addItem:menuItem];
		[menuItem release];
		
		// If this is the first call to initScriptsMenu, create the scripts menu. Otherwise we just
		// update the one we have.
		if (scriptsMenuItem != nil)
		{
			[[NSApp mainMenu] removeItem:scriptsMenuItem];
			[scriptsMenuItem release];
		}
		
		scriptsMenuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"Scripts" action:NULL keyEquivalent:@""];
		[scriptsMenuItem setImage:[NSImage imageNamed:@"scriptMenu.tiff"]];
		
		int helpMenuIndex = [[NSApp mainMenu] numberOfItems] - 1;
		[[NSApp mainMenu] insertItem:scriptsMenuItem atIndex:helpMenuIndex];
		[scriptsMenuItem setSubmenu:scriptsMenu];
	}
	[scriptsMenu release];
}

/* initStylesMenu
 * Populate the Styles menu with a list of built-in and external styles. (Note that in the event of
 * duplicates the styles in the external Styles folder wins. This is intended to allow the user to
 * override the built-in styles if necessary).
 */
-(void)initStylesMenu
{
	NSMenu * stylesSubMenu = [[[NSMenu alloc] initWithTitle:@"Style"] autorelease];
	
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
		[stylesSubMenu addItem:menuItem];
		[menuItem release];
	}
	
	// Append a link to More Styles...
	[stylesSubMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"More Styles...", nil) action:@selector(moreStyles:) keyEquivalent:@""];
	[stylesSubMenu addItem:menuItem];
	[menuItem release];
	
	// Add it to the Style menu
	[stylesMenu setSubmenu:stylesSubMenu];
}

/* initFiltersMenu
 * Populate both the Filters submenu on the View menu and the Filters popup menu on the Filter
 * button in the article list. We need separate menus since the latter is eventually configured
 * to use a smaller font than the former.
 */
-(void)initFiltersMenu
{
	NSMenu * filterSubMenu = [[[NSMenu alloc] initWithTitle:@"Filter By"] autorelease];
	NSMenu * filterPopupMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];

	NSArray * filtersArray = [ArticleFilter arrayOfFilters];
	int count = [filtersArray count];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		ArticleFilter * filter = [filtersArray objectAtIndex:index];

		NSMenuItem * menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString([filter name], nil) action:@selector(changeFiltering:) keyEquivalent:@""];
		[menuItem setTag:[filter tag]];
		[filterSubMenu addItem:menuItem];
		[menuItem release];

		menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString([filter name], nil) action:@selector(changeFiltering:) keyEquivalent:@""];
		[menuItem setTag:[filter tag]];
		[filterPopupMenu addItem:menuItem];
		[menuItem release];
	}
	
	// Add it to the Filters menu
	[filtersPopupMenu setMenu:filterPopupMenu];
	[filtersPopupMenu setSmallMenu:YES];

	[filtersMenu setSubmenu:filterSubMenu];
}

/* showUnreadCountOnApplicationIconAndWindowTitle
 * Update the Vienna application icon to show the number of unread articles.
 */
-(void)showUnreadCountOnApplicationIconAndWindowTitle
{
	int currentCountOfUnread = [db countOfUnread];
	if (currentCountOfUnread == lastCountOfUnread)
		return;
	
	// Don't show a count if there are no unread articles
	lastCountOfUnread = currentCountOfUnread;
	if (currentCountOfUnread <= 0)
	{
		[NSApp setApplicationIconImage:originalIcon];
		[mainWindow setTitle:[self appName]];
		return;	
	}	
	
	[mainWindow setTitle:[[NSString stringWithFormat:@"%@ -", [self appName]]
		stringByAppendingString:[NSString stringWithFormat:
			NSLocalizedString(@" (%d unread)", nil), currentCountOfUnread]]];
	
	NSString * countdown = [NSString stringWithFormat:@"%i", currentCountOfUnread];
	NSImage * iconImageBuffer = [originalIcon copy];
	NSSize iconSize = [originalIcon size];
	
	// Create attributes for drawing the count. In our case, we're drawing using in
	// 26pt Helvetica bold white.
	NSDictionary * attributes = [[NSDictionary alloc] 
		initWithObjectsAndKeys:[NSFont fontWithName:@"Helvetica-Bold" size:25], NSFontAttributeName,
		[NSColor whiteColor], NSForegroundColorAttributeName, nil];
	NSSize numSize = [countdown sizeWithAttributes:attributes];
	
	// Create a red circle in the icon large enough to hold the count.
	[iconImageBuffer lockFocus];
	[originalIcon drawAtPoint:NSMakePoint(0, 0)
					 fromRect:NSMakeRect(0, 0, iconSize.width, iconSize.height) 
					operation:NSCompositeSourceOver 
					 fraction:1.0f];
	
	float max = (numSize.width > numSize.height) ? numSize.width : numSize.height;
	max += 21;
	NSRect circleRect = NSMakeRect(iconSize.width - max, iconSize.height - max, max, max);
	
	// Draw the star image and scale it so the unread count will fit inside.
	NSImage * starImage = [NSImage imageNamed:@"unreadStar1.tiff"];
	[starImage setScalesWhenResized:YES];
	[starImage setSize:circleRect.size];
	[starImage compositeToPoint:circleRect.origin operation:NSCompositeSourceOver];
	
	// Draw the count in the red circle
	NSPoint point = NSMakePoint(NSMidX(circleRect) - numSize.width / 2.0f + 2.0f,  NSMidY(circleRect) - numSize.height / 2.0f + 2.0f);
	[countdown drawAtPoint:point withAttributes:attributes];
	
	// Now set the new app icon and clean up.
	[iconImageBuffer unlockFocus];
	[NSApp setApplicationIconImage:iconImageBuffer];
	[iconImageBuffer release];
	[attributes release];
}

/* handleAbout
 * Display our About Vienna... window.
 */
-(IBAction)handleAbout:(id)sender
{
	NSDictionary * fileAttributes = [[NSBundle mainBundle] infoDictionary];
	NSString * version = [fileAttributes objectForKey:@"CFBundleShortVersionString"];
	NSString * versionString = [NSString stringWithFormat:NSLocalizedString(@"Version %@", nil), version];
	NSDictionary * d = [NSDictionary dictionaryWithObjectsAndKeys:versionString, @"ApplicationVersion", @"", @"Version", nil, nil];
	[NSApp orderFrontStandardAboutPanelWithOptions:d];
}

/* emptyTrash
 * Delete all articles from the Trash folder.
 */
-(IBAction)emptyTrash:(id)sender
{
	NSBeginCriticalAlertSheet(NSLocalizedString(@"Empty Trash message", nil),
							  NSLocalizedString(@"Empty", nil),
							  NSLocalizedString(@"Cancel", nil),
							  nil, [NSApp mainWindow], self,
							  @selector(doConfirmedEmptyTrash:returnCode:contextInfo:), nil, nil,
							  NSLocalizedString(@"Empty Trash message text", nil));
}

/* doConfirmedEmptyTrash
 * This function is called after the user has dismissed
 * the confirmation sheet.
 */
-(void)doConfirmedEmptyTrash:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSAlertDefaultReturn)
	{
		[self clearUndoStack];
		[db purgeDeletedArticles];
	}
}

/* showPreferencePanel
 * Display the Preference Panel.
 */
-(IBAction)showPreferencePanel:(id)sender
{
	if (!preferenceController)
		preferenceController = [[NewPreferencesController alloc] init];
	[preferenceController showWindow:self];
}

/* printDocument
 * Print the selected articles in the article window.
 */
-(IBAction)printDocument:(id)sender
{
	[[browserView activeTabView] printDocument:sender];
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
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
}

/* selectedArticle
 * Returns the current selected article in the article pane.
 */
-(Article *)selectedArticle
{
	return [mainArticleView selectedArticle];
}

/* currentFolderId
 * Return the ID of the currently selected folder whose articles are shown in
 * the article window.
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
	return [mainArticleView selectFolderAndArticle:folderId guid:nil];
}

/* updateCloseCommands
 * Update the keystrokes assigned to the Close Tab and Close Window
 * commands depending on whether any tabs are opened.
 */
-(void)updateCloseCommands
{
	if ([browserView countOfTabs] < 2 || ![mainWindow isKeyWindow])
	{
		[closeTabItem setKeyEquivalent:@""];
		[closeAllTabsItem setKeyEquivalent:@""];
		[closeWindowItem setKeyEquivalent:@"w"];
		[closeWindowItem setKeyEquivalentModifierMask:NSCommandKeyMask];
	}
	else
	{
		[closeTabItem setKeyEquivalent:@"w"];
		[closeTabItem setKeyEquivalentModifierMask:NSCommandKeyMask];
		[closeAllTabsItem setKeyEquivalent:@"w"];
		[closeAllTabsItem setKeyEquivalentModifierMask:NSCommandKeyMask|NSAlternateKeyMask];
		[closeWindowItem setKeyEquivalent:@"W"];
		[closeWindowItem setKeyEquivalentModifierMask:NSCommandKeyMask];
	}
}

/* handleRSSLink
 * Handle feed://<rss> links. If we're already subscribed to the link then make the folder
 * active. Otherwise offer to subscribe to the link.
 */
-(void)handleRSSLink:(NSString *)linkPath
{
	[self createNewSubscription:linkPath underFolder:[foldersTree groupParentSelection]];
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

/* handleFolderSelection
 * Called when the selection changes in the folder pane.
 */
-(void)handleFolderSelection:(NSNotification *)nc
{
	TreeNode * node = (TreeNode *)[nc object];
	int newFolderId = [node nodeId];
	
	// We only care if the selection really changed
	if ([mainArticleView currentFolderId] != newFolderId && newFolderId != 0)
	{
		// Make sure article viewer is active
		[browserView setActiveTabToPrimaryTab];
		
		// Blank out the search field
		[self setSearchString:@""];
		[mainArticleView selectFolderWithFilter:newFolderId];
		[self updateSearchPlaceholder];
	}
}

/* handleDidBecomeKeyWindow
 * Called when a window becomes the key window.
 */
-(void)handleDidBecomeKeyWindow:(NSNotification *)nc
{
	[self updateCloseCommands];
}

/* handleReloadPreferences
 * Called when MA_Notify_PreferencesUpdated is broadcast.
 * Update the menus.
 */
-(void)handleReloadPreferences:(NSNotification *)nc
{
	[self updateAlternateMenuTitle];
	[foldersTree updateAlternateMenuTitle];
	[mainArticleView updateAlternateMenuTitle];
}

/* handleCheckFrequencyChange
 * Called when the refresh frequency is changed.
 */
-(void)handleCheckFrequencyChange:(NSNotification *)nc
{
	int newFrequency = [[Preferences standardPreferences] refreshFrequency];
	
	[checkTimer invalidate];
	[checkTimer release];
	checkTimer = nil;
	if (newFrequency > 0)
	{
		checkTimer = [[NSTimer scheduledTimerWithTimeInterval:newFrequency
													   target:self
													 selector:@selector(refreshOnTimer:)
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
	[[NSWorkspace sharedWorkspace] openFile:[[Preferences standardPreferences] scriptsFolder]];
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

/* handleTabChange
 * Handle a change in the active tab field.
 */
-(void)handleTabChange:(NSNotification *)nc
{
	NSView<BaseView> * newView = [nc object];
	if (newView == mainArticleView)
		[mainWindow makeFirstResponder:[mainArticleView mainView]];
	else
	{
		BrowserPane * webPane = (BrowserPane *)newView;
		[mainWindow makeFirstResponder:[webPane mainView]];
	}
	[self updateCloseCommands];
	[self updateSearchPlaceholder];
}

/* handleFolderNameChange
 * Handle folder name change.
 */
-(void)handleFolderNameChange:(NSNotification *)nc
{
	int folderId = [(NSNumber *)[nc object] intValue];
	if (folderId == [mainArticleView currentFolderId])
		[self updateSearchPlaceholder];
}

/* handleRefreshStatusChange
 * Handle a change of the refresh status.
 */
-(void)handleRefreshStatusChange:(NSNotification *)nc
{
	if ([NSApp isRefreshing])
	{
		// Save the date/time of this refresh so we do the right thing when
		// we apply the filter.
		[[Preferences standardPreferences] setObject:[NSCalendarDate date] forKey:MAPref_LastRefreshDate];
		
		[self startProgressIndicator];
		[self setStatusMessage:[[RefreshManager sharedManager] statusMessageDuringRefresh] persist:YES];
	}
	else
	{
		[self setStatusMessage:NSLocalizedString(@"Refresh completed", nil) persist:YES];
		[self stopProgressIndicator];
		
		// Run the auto-expire now
		Preferences * prefs = [Preferences standardPreferences];
		[db purgeArticlesOlderThanDays:[prefs autoExpireDuration] sendNotification:YES];
		
		[self showUnreadCountOnApplicationIconAndWindowTitle];
		
		int newUnread = [[RefreshManager sharedManager] countOfNewArticles];
		if (growlAvailable && newUnread > 0)
		{
			[GrowlApplicationBridge
				notifyWithTitle:NSLocalizedString(@"Growl notification title", nil)
					description:[NSString stringWithFormat:NSLocalizedString(@"Growl description", nil), newUnread]
			   notificationName:NSLocalizedString(@"Growl notification name", nil)
					   iconData:nil
					   priority:0.0
					   isSticky:NO
				   clickContext:[NSNumber numberWithInt:newUnread]];
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
		[self openURLInDefaultBrowser:[NSURL URLWithString:stylesPage]];
}

/* moreScripts
 * Display the web page where the user can download additional scripts.
 */
-(IBAction)moreScripts:(id)sender
{
	NSString * scriptsPage = [standardURLs valueForKey:@"ViennaMoreScriptsPage"];
	if (scriptsPage != nil)
		[self openURLInDefaultBrowser:[NSURL URLWithString:scriptsPage]];
}

/* viewArticlePage
 * Display the article in the browser.
 */
-(IBAction)viewArticlePage:(id)sender
{
	Article * theArticle = [self selectedArticle];
	if (theArticle && ![[theArticle link] isBlank])
		[self openURLFromString:[theArticle link] inPreferredBrowser:YES];
}

/* viewArticlePageInAlternateBrowser
 * Display the article in the non-preferred browser.
 */
-(IBAction)viewArticlePageInAlternateBrowser:(id)sender
{
	Article * theArticle = [self selectedArticle];
	if (theArticle && ![[theArticle link] isBlank])
		[self openURLFromString:[theArticle link] inPreferredBrowser:NO];
}

/* goForward
 * In article view, forward track through the list of articles displayed. In 
 * web view, go to the next web page.
 */
-(IBAction)goForward:(id)sender
{
	[[browserView activeTabView] handleGoForward:sender];
}

/* goBack
 * In article view, back track through the list of articles displayed. In 
 * web view, go to the previous web page.
 */
-(IBAction)goBack:(id)sender
{
	[[browserView activeTabView] handleGoBack:sender];
}

/* localPerformFindPanelAction
 * The default handler for the Find actions is the first responder. Unfortunately the
 * WebView, although it claims to implement this, doesn't. So we redirect the Find
 * commands here and trap the case where the webview has first responder status and
 * handle it especially. For other first responders, we pass this command through.
 */
-(IBAction)localPerformFindPanelAction:(id)sender
{
	switch ([sender tag]) 
	{
		case NSFindPanelActionShowFindPanel:
			[mainWindow makeFirstResponder:searchField];
			break;
			
		default:
			[[browserView activeTabView] performFindPanelAction:[sender tag]];
			break;
	}
}

#pragma mark Key Listener

/* handleKeyDown [delegate]
 * Support special key codes. If we handle the key, return YES otherwise
 * return NO to allow the framework to pass it on for default processing.
 */
-(BOOL)handleKeyDown:(unichar)keyChar withFlags:(unsigned int)flags
{
	switch (keyChar)
	{
		case NSLeftArrowFunctionKey:
			if (flags & NSCommandKeyMask)
				[self goBack:self];
			else
			{
				if ([mainWindow firstResponder] == [mainArticleView mainView])
				{
					[mainWindow makeFirstResponder:[foldersTree mainView]];
					return YES;
				}
			}
				return NO;
			
		case NSRightArrowFunctionKey:
			if (flags & NSCommandKeyMask)
				[self goForward:self];
			else
			{
				if ([mainWindow firstResponder] == [foldersTree mainView])
				{
					[mainWindow makeFirstResponder:[mainArticleView mainView]];
					return YES;
				}
			}
				return NO;
			
		case NSDeleteFunctionKey:
			[self deleteMessage:self];
			return YES;

		case 'f':
		case 'F':
			[mainWindow makeFirstResponder:searchField];
			return YES;
			
		case '>':
			[self goForward:self];
			return YES;
			
		case '<':
			[self goBack:self];
			return YES;
			
		case 'k':
		case 'K':
			[self markAllRead:self];
			return YES;
			
		case 'm':
		case 'M':
			[self markFlagged:self];
			return YES;
			
		case 'u':
		case 'U':
		case 'r':
		case 'R':
			[self markRead:self];
			return YES;
			
		case 's':
		case 'S':
			[self skipFolder:self];
			return YES;
			
		case NSEnterCharacter:
		case NSCarriageReturnCharacter:
			if (flags & NSShiftKeyMask)
				[self viewArticlePageInAlternateBrowser:self];
			else
				[self viewArticlePage:self];
			return YES;

		case ' ': //SPACE
		{
			ArticleView * view = (ArticleView *)[mainArticleView articleView];
			NSView * theView = [[[view mainFrame] frameView] documentView];
			NSRect visibleRect;

			visibleRect = [theView visibleRect];
			if (flags & NSShiftKeyMask)
			{
				if (visibleRect.origin.y < 2)
					[self goBack:self];
				else
					[[[view mainFrame] webView] scrollPageUp:self];
			}
			else
			{
				if (visibleRect.origin.y + visibleRect.size.height >= [theView frame].size.height)
					[self viewNextUnread:self];
				else
					[[[view mainFrame] webView] scrollPageDown:self];
			}
			return YES;
		}
	}
	return NO;
}

/* isConnecting
 * Returns whether or not 
 */
-(BOOL)isConnecting
{
	return [[RefreshManager sharedManager] totalConnections] > 0;
}

/* refreshOnTimer
 * Each time the check timer fires, we see if a connect is not nswindow
 * running and then kick one off.
 */
-(void)refreshOnTimer:(NSTimer *)aTimer
{
	[self refreshAllSubscriptions:self];
}

/* markSelectedFoldersRead
 * Mark read all articles in the specified array of folders.
 */
-(void)markSelectedFoldersRead:(NSArray *)arrayOfFolders
{
	if (![db readOnly])
		[mainArticleView markAllReadByArray:arrayOfFolders withUndo:YES];
}

/* createNewSubscription
 * Create a new subscription for the specified URL under the given parent folder.
 */
-(void)createNewSubscription:(NSString *)urlString underFolder:(int)parentId
{
	// Replace feed:// with http:// if necessary
	if ([urlString hasPrefix:@"feed://"])
		urlString = [NSString stringWithFormat:@"http://%@", [urlString substringFromIndex:7]];
	
	// If the folder already exists, just select it.
	Folder * folder = [db folderFromFeedURL:urlString];
	if (folder != nil)
	{
		[browserView setActiveTabToPrimaryTab];
		[foldersTree selectFolder:[folder itemId]];
		return;
	}
	
	// Create then select the new folder.
	int folderId = [db addRSSFolder:[Database untitledFeedFolderName] underParent:parentId subscriptionURL:urlString];
	if (folderId != -1)
	{
		[mainArticleView selectFolderAndArticle:folderId guid:nil];
		if (isAccessible(urlString))
		{
			Folder * folder = [db folderFromID:folderId];
			[[RefreshManager sharedManager] refreshSubscriptions:[NSArray arrayWithObject:folder]];
		}
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

/* restoreMessage
 * Restore a message in the Trash folder back to where it came from.
 */
-(IBAction)restoreMessage:(id)sender
{
	Folder * folder = [db folderFromID:[mainArticleView currentFolderId]];
	if (IsTrashFolder(folder) && [self selectedArticle] != nil && ![db readOnly])
	{
		NSArray * articleArray = [mainArticleView markedArticleRange];
		[mainArticleView markDeletedByArray:articleArray deleteFlag:NO];
		[self clearUndoStack];
	}
}

/* deleteMessage
 * Delete the current article. If we're in the Trash folder, this represents a permanent
 * delete. Otherwise we just move the article to the trash folder.
 */
-(IBAction)deleteMessage:(id)sender
{
	if ([self selectedArticle] != nil && ![db readOnly])
	{
		Folder * folder = [db folderFromID:[mainArticleView currentFolderId]];
		if (!IsTrashFolder(folder))
		{
			NSArray * articleArray = [mainArticleView markedArticleRange];
			[mainArticleView markDeletedByArray:articleArray deleteFlag:YES];
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
		[mainArticleView deleteSelectedArticles];
}

/* showDownloadsWindow
 * Show the Downloads window, bringing it to the front if necessary.
 */
-(IBAction)showDownloadsWindow:(id)sender
{
	if (downloadWindow == nil)
		downloadWindow = [[DownloadWindow alloc] init];
	[[downloadWindow window] makeKeyAndOrderFront:sender];
}

/* conditionalShowDownloadsWindow
 * Make the Downloads window visible only if it hasn't been shown.
 */
-(IBAction)conditionalShowDownloadsWindow:(id)sender
{
	if (downloadWindow == nil)
		downloadWindow = [[DownloadWindow alloc] init];
	if (![[downloadWindow window] isVisible])
		[[downloadWindow window] makeKeyAndOrderFront:sender];
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
 * Moves the selection to the next unread article.
 */
-(IBAction)viewNextUnread:(id)sender
{
	[browserView setActiveTabToPrimaryTab];
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

/* skipFolder
 * Mark all articles in the current folder read then skip to the next folder with
 * unread articles.
 */
-(IBAction)skipFolder:(id)sender
{
	if (![db readOnly])
	{
		[mainArticleView markAllReadByArray:[foldersTree selectedFolders] withUndo:YES];
		[self viewNextUnread:self];
	}
}

#pragma mark Marking Articles 

/* markAllRead
 * Mark all articles read in the selected folders.
 */
-(IBAction)markAllRead:(id)sender
{
	if (![db readOnly])
		[mainArticleView markAllReadByArray:[foldersTree selectedFolders] withUndo:YES];
}

/* markAllSubscriptionsRead
 * Mark all subscriptions as read
 */
-(IBAction)markAllSubscriptionsRead:(id)sender
{
	if (![db readOnly])
	{
		[mainArticleView markAllReadByArray:[foldersTree folders:0] withUndo:NO];
		[self clearUndoStack];
	}
}

/* markRead
 * Toggle the read/unread state of the selected articles
 */
-(IBAction)markRead:(id)sender
{
	Article * theArticle = [self selectedArticle];
	if (theArticle != nil && ![db readOnly])
	{
		NSArray * articleArray = [mainArticleView markedArticleRange];
		[mainArticleView markReadByArray:articleArray readFlag:![theArticle isRead]];
	}
}

/* markFlagged
 * Toggle the flagged/unflagged state of the selected article
 */
-(IBAction)markFlagged:(id)sender
{
	Article * theArticle = [self selectedArticle];
	if (theArticle != nil && ![db readOnly])
	{
		NSArray * articleArray = [mainArticleView markedArticleRange];
		[mainArticleView markFlaggedByArray:articleArray flagged:![theArticle isFlagged]];
	}
}

/* renameFolder
 * Renames the current folder
 */
-(IBAction)renameFolder:(id)sender
{
	if (!renameFolder)
		renameFolder = [[RenameFolder alloc] init];
	[renameFolder renameFolder:mainWindow folderId:[foldersTree actualSelection]];
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
		
		// This little hack is so if we're deleting the folder currently being displayed
		// and there's more than one folder being deleted, we delete the folder currently
		// being displayed last so that the MA_Notify_FolderDeleted handlers that only
		// refresh the display if the current folder is being deleted only trips once.
		if ([folder itemId] == [mainArticleView currentFolderId] && index < count - 1)
		{
			[selectedFolders insertObject:folder atIndex:count];
			++count;
			continue;
		}
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
	[self showUnreadCountOnApplicationIconAndWindowTitle];
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
			[self openURLFromString:validatorURL inPreferredBrowser:YES];
		}
	}
}

/* viewSourceHomePage
 * Display the web site associated with this feed, if there is one.
 */
-(IBAction)viewSourceHomePage:(id)sender
{
	Article * thisArticle = [self selectedArticle];
	Folder * folder = (thisArticle) ? [db folderFromID:[thisArticle folderId]] : [db folderFromID:[foldersTree actualSelection]];
	if (thisArticle || IsRSSFolder(folder))
		[self openURLFromString:[folder homePage] inPreferredBrowser:YES];
}

/* viewSourceHomePageInAlternateBrowser
 * Display the web site associated with this feed, if there is one, in non-preferred browser.
 */
-(IBAction)viewSourceHomePageInAlternateBrowser:(id)sender
{
	Article * thisArticle = [self selectedArticle];
	Folder * folder = (thisArticle) ? [db folderFromID:[thisArticle folderId]] : [db folderFromID:[foldersTree actualSelection]];
	if (thisArticle || IsRSSFolder(folder))
		[self openURLFromString:[folder homePage] inPreferredBrowser:NO];
}

/* showViennaHomePage
 * Open the Vienna home page in the default browser.
 */
-(IBAction)showViennaHomePage:(id)sender
{
	NSString * homePage = [standardURLs valueForKey:@"ViennaHomePage"];
	if (homePage != nil)
		[self openURLInDefaultBrowser:[NSURL URLWithString:homePage]];
}

/* showAcknowledgements
 * Display the acknowledgements document in a new tab.
 */
-(IBAction)showAcknowledgements:(id)sender
{
	NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];
	NSString * pathToAckFile = [thisBundle pathForResource:@"Acknowledgements.rtf" ofType:@""];
	if (pathToAckFile != nil)
		[self createNewTab:[NSURL URLWithString:[NSString stringWithFormat:@"file://%@", pathToAckFile]] inBackground:NO];
}

#pragma mark Tabs

/* previousTab
 * Display the previous tab, if there is one.
 */
-(IBAction)previousTab:(id)sender
{
	[browserView showPreviousTab];
}

/* nextTab
 * Display the next tab, if there is one.
 */
-(IBAction)nextTab:(id)sender
{
	[browserView showNextTab];
}

/* closeAllTabs
 * Closes all tab windows.
 */
-(IBAction)closeAllTabs:(id)sender
{
	[browserView closeAllTabs];
}

/* closeTab
 * Close the active tab unless it's the primary view.
 */
-(IBAction)closeTab:(id)sender
{
	[browserView closeTab:[browserView activeTab]];
}

/* reloadPage
 * Reload the web page.
 */
-(IBAction)reloadPage:(id)sender
{
	NSView<BaseView> * theView = [browserView activeTabView];
	if ([theView isKindOfClass:[BrowserPane class]])
		[theView performSelector:@selector(handleReload:)];
}

/* stopReloadingPage
 * Cancel current reloading of a web page.
 */
-(IBAction)stopReloadingPage:(id)sender
{
	NSView<BaseView> * theView = [browserView activeTabView];
	if ([theView isKindOfClass:[BrowserPane class]])
		[theView performSelector:@selector(handleStopLoading:)];
}

/* updateAlternateMenuTitle
 * Set the appropriate title for the menu items that override browser preferences
 * For future implementation, perhaps we can save a lot of code by
 * creating an ivar for the title string and binding the menu's title to it.
 */
-(void)updateAlternateMenuTitle
{
	Preferences * prefs = [Preferences standardPreferences];
	NSString * alternateLocation;
	if ([prefs openLinksInVienna])
	{
		alternateLocation = getDefaultBrowser();
		if (alternateLocation == nil)
			alternateLocation = NSLocalizedString(@"External Browser", nil);
	}
	else
		alternateLocation = [self appName];
	NSMenuItem * item = menuWithAction(@selector(viewSourceHomePageInAlternateBrowser:));
	if (item != nil)
	{
		[item setTitle:[NSString stringWithFormat:NSLocalizedString(@"Open Subscription Home Page in %@", nil), alternateLocation]];
	}
	item = menuWithAction(@selector(viewArticlePageInAlternateBrowser:));
	if (item != nil)
	{
		[item setTitle:[NSString stringWithFormat:NSLocalizedString(@"Open Article Page in %@", nil), alternateLocation]];
	}
}

/* updateSearchPlaceholder
 * Update the search placeholder string in the search field depending on the view in
 * the active tab.
 */
-(void)updateSearchPlaceholder
{
	[[searchField cell] setSendsWholeSearchString:[browserView activeTabView] != mainArticleView];
	[[searchField cell] setPlaceholderString:[[browserView activeTabView] searchPlaceholderString]];
}

#pragma mark Searching

/* setSearchString
 * Sets the search field's search string.
 */
-(void)setSearchString:(NSString *)newSearchString
{
	[searchField setStringValue:newSearchString];
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
	[[browserView activeTabView] performFindPanelAction:NSFindPanelActionNext];
}

#pragma mark Refresh Subscriptions

/* refreshAllFolderIcons
 * Get new favicons from all subscriptions.
 */
-(IBAction)refreshAllFolderIcons:(id)sender
{
	if (![self isConnecting])
		[[RefreshManager sharedManager] refreshFolderIconCacheForSubscriptions:[db arrayOfRSSFolders]];
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
	[[RefreshManager sharedManager] refreshSubscriptions:[foldersTree selectedFolders]];
}

/* cancelAllRefreshes
 * Used to kill all active refresh connections and empty the queue of folders due to
 * be refreshed.
 */
-(IBAction)cancelAllRefreshes:(id)sender
{
	[[RefreshManager sharedManager] cancelAll];
}

/* mailLinkToArticlePage
 * Prompts the default email application to send a link to the currently selected article(s). 
 * Builds a string that contains a well-formed link according to the "mailto:"-scheme (RFC2368).
 */
-(IBAction)mailLinkToArticlePage:(id)sender
{
	NSMutableString * mailtoLink = [NSMutableString stringWithFormat:@"mailto:?subject=&body="];
	NSString * mailtoLineBreak = @"%0D%0A"; // necessary linebreak characters according to RFC
	
	Article * theArticle = [self selectedArticle];
	if (theArticle != nil) 
	{
		NSArray * articleArray = [mainArticleView markedArticleRange];
		NSEnumerator *e = [articleArray objectEnumerator];
		id currentArticle;
		
		while ( (currentArticle = [e nextObject]) ) {
			[mailtoLink appendFormat: @"%@%@", [currentArticle link], mailtoLineBreak];
		}
		[self openURLInDefaultBrowser:[NSURL URLWithString: mailtoLink]];
	}
}

/* changeFiltering
 * Refresh the filtering of articles.
 */
-(IBAction)changeFiltering:(id)sender
{
	NSMenuItem * menuItem = (NSMenuItem *)sender;
	[[Preferences standardPreferences] setFilterMode:[menuItem tag]];
}

#pragma mark Status Message

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

#pragma mark Progress Indicator 

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
	BOOL isArticleView = [browserView activeTabView] == mainArticleView;
	
	if (theAction == @selector(printDocument:))
	{
		return ([self selectedArticle] != nil && isMainWindowVisible);
	}
	else if (theAction == @selector(goBack:))
	{
		return [[browserView activeTabView] canGoBack] && isMainWindowVisible;
	}
	else if (theAction == @selector(goForward:))
	{
		return [[browserView activeTabView] canGoForward] && isMainWindowVisible;
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
	else if (theAction == @selector(skipFolder:))
	{
		return ![db readOnly] && isArticleView && isMainWindowVisible && [db countOfUnread] > 0;
	}
	else if (theAction == @selector(viewNextUnread:))
	{
		return [db countOfUnread] > 0;
	}
	else if ((theAction == @selector(refreshAllSubscriptions:)) || (theAction == @selector(refreshAllFolderIcons:)))
	{
		return ![self isConnecting] && ![db readOnly];
	}
	else if (theAction == @selector(doViewColumn:))
	{
		Field * field = [menuItem representedObject];
		[menuItem setState:[field visible] ? NSOnState : NSOffState];
		return isMainWindowVisible && isArticleView;
	}
	else if (theAction == @selector(doSelectStyle:))
	{
		NSString * styleName = [menuItem title];
		[menuItem setState:[styleName isEqualToString:[[Preferences standardPreferences] displayStyle]] ? NSOnState : NSOffState];
		return isMainWindowVisible && isArticleView;
	}
	else if (theAction == @selector(doSortColumn:))
	{
		Field * field = [menuItem representedObject];
		if ([[field name] isEqualToString:[mainArticleView sortColumnIdentifier]])
			[menuItem setState:NSOnState];
		else
			[menuItem setState:NSOffState];
		return isMainWindowVisible && isArticleView;
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
		return folder && !IsTrashFolder(folder) && ![db readOnly] && isArticleView && isMainWindowVisible && [db countOfUnread] > 0;
	}
	else if (theAction == @selector(markAllSubscriptionsRead:))
	{
		return ![db readOnly] && isMainWindowVisible && isArticleView && [db countOfUnread] > 0;
	}
	else if (theAction == @selector(importSubscriptions:))
	{
		return ![db readOnly] && isMainWindowVisible;
	}
	else if (theAction == @selector(cancelAllRefreshes:))
	{
		return [self isConnecting];
	}
	else if ((theAction == @selector(viewSourceHomePage:)) || (theAction == @selector(viewSourceHomePageInAlternateBrowser:)))
	{
		Article * thisArticle = [self selectedArticle];
		Folder * folder = (thisArticle) ? [db folderFromID:[thisArticle folderId]] : [db folderFromID:[foldersTree actualSelection]];
		return folder && (thisArticle || IsRSSFolder(folder)) && ([folder homePage] && ![[folder homePage] isBlank] && isMainWindowVisible);
	}
	else if ((theAction == @selector(viewArticlePage:)) || (theAction == @selector(viewArticlePageInAlternateBrowser:)))
	{
		Article * thisArticle = [self selectedArticle];
		if (thisArticle != nil)
			return ([thisArticle link] && ![[thisArticle link] isBlank] && isMainWindowVisible && isArticleView);
		return NO;
	}
	else if (theAction == @selector(exportSubscriptions:))
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
	else if (theAction == @selector(restoreMessage:))
	{
		Folder * folder = [db folderFromID:[foldersTree actualSelection]];
		return IsTrashFolder(folder) && [self selectedArticle] != nil && ![db readOnly] && isMainWindowVisible && isArticleView;
	}
	else if (theAction == @selector(deleteMessage:))
	{
		return [self selectedArticle] != nil && ![db readOnly] && isMainWindowVisible && isArticleView;
	}
	else if (theAction == @selector(emptyTrash:))
	{
		return ![db readOnly];
	}
	else if (theAction == @selector(readingPaneOnRight:))
	{
		[menuItem setState:([[Preferences standardPreferences] readingPaneOnRight] ? NSOnState : NSOffState)];
		return isMainWindowVisible && isArticleView;
	}
	else if (theAction == @selector(readingPaneOnBottom:))
	{
		[menuItem setState:([[Preferences standardPreferences] readingPaneOnRight] ? NSOffState : NSOnState)];
		return isMainWindowVisible && isArticleView;
	}
	else if (theAction == @selector(previousTab:))
	{
		return isMainWindowVisible && [browserView countOfTabs] > 1;
	}
	else if (theAction == @selector(nextTab:))
	{
		return isMainWindowVisible && [browserView countOfTabs] > 1;
	}
	else if (theAction == @selector(closeTab:))
	{
		return isMainWindowVisible && [browserView activeTabView] != mainArticleView;
	}
	else if (theAction == @selector(closeAllTabs:))
	{
		return isMainWindowVisible && [browserView countOfTabs] > 1;
	}
	else if (theAction == @selector(reloadPage:))
	{
		NSView<BaseView> * theView = [browserView activeTabView];
		return ([theView isKindOfClass:[BrowserPane class]]) && ![(BrowserPane *)theView isLoading];
	}
	else if (theAction == @selector(stopReloadingPage:))
	{
		NSView<BaseView> * theView = [browserView activeTabView];
		return ([theView isKindOfClass:[BrowserPane class]]) && [(BrowserPane *)theView isLoading];
	}
	else if (theAction == @selector(changeFiltering:))
	{
		[menuItem setState:([menuItem tag] == [[Preferences standardPreferences] filterMode]) ? NSOnState : NSOffState];
		return isMainWindowVisible;
	}
	else if (theAction == @selector(markFlagged:))
	{
		Article * thisArticle = [self selectedArticle];
		if (thisArticle != nil)
		{
			if ([thisArticle isFlagged])
				[menuItem setTitle:NSLocalizedString(@"Mark Unflagged", nil)];
			else
				[menuItem setTitle:NSLocalizedString(@"Mark Flagged", nil)];
		}
		return (thisArticle != nil && ![db readOnly] && isMainWindowVisible && isArticleView);
	}
	else if (theAction == @selector(markRead:))
	{
		Article * thisArticle = [self selectedArticle];
		if (thisArticle != nil)
		{
			if ([thisArticle isRead])
				[menuItem setTitle:NSLocalizedString(@"Mark Unread", nil)];
			else
				[menuItem setTitle:NSLocalizedString(@"Mark Read", nil)];
		}
		return (thisArticle != nil && ![db readOnly] && isMainWindowVisible && isArticleView);
	}
	else if (theAction == @selector(mailLinkToArticlePage:))
	{
		Article * thisArticle = [self selectedArticle];
		
		if ([[mainArticleView markedArticleRange] count] > 1)
			[menuItem setTitle:NSLocalizedString(@"Send Links", nil)];
		else
			[menuItem setTitle:NSLocalizedString(@"Send Link", nil)];
		
		return (thisArticle != nil && isMainWindowVisible && isArticleView);
	}
	
	return YES;
}

/* dealloc
 * Clean up and release resources.
 */
-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[scriptsMenuItem release];
	[standardURLs release];
	[downloadWindow release];
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
