//
//  BrowserPane.m
//  Vienna
//
//  Created by Steve on 9/7/05.
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

#import "BrowserPane.h"
#import "ArticleView.h"
#import "AppController.h"
#import "Preferences.h"
#import "HelperFunctions.h"
#import "WebKit/WebPolicyDelegate.h"
#import "WebKit/WebUIDelegate.h"
#import "WebKit/WebFrame.h"

// Private functions
@interface BrowserPane (Private)
	-(void)loadMinimumFontSize;
@end

@implementation BrowserPane

/* initWithFrame
 * Initialise our view.
 */
-(id)initWithFrame:(NSRect)frame
{
    if (([super initWithFrame:frame]) != nil)
	{
		// Create our webview
		webPane = [[ArticleView alloc] initWithFrame:frame];
		[webPane setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
		[webPane setUIDelegate:self];
		[webPane setFrameLoadDelegate:self];
		[webPane setPolicyDelegate:self];

		// Set our box attributes
		[self setTitlePosition:NSNoTitle];
		[self setBoxType:NSBoxOldStyle];
		[self setBorderType:NSLineBorder];
		[self setContentViewMargins:NSMakeSize(1, 1)];
		[self setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable|NSViewMinXMargin|NSViewMinYMargin];
		[self addSubview:webPane];

		// Register to be notified when things happen
		NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
		[nc addObserver:self selector:@selector(handleMinimumFontSizeChange:) name:@"MA_Notify_MinimumFontSizeChange" object:nil];

		// Other initialisation
		controller = nil;
		isLoadingFrame = NO;

		// Handle minimum font size
		defaultWebPrefs = [[webPane preferences] retain];
		[self loadMinimumFontSize];
    }
    return self;
}

/* performFindPanelAction
 * WebView doesn't actually implement this. So pass it up to the delegate.
 */
-(void)performFindPanelAction:(id)sender
{
	[[NSApp delegate] performFindPanelAction:sender];
}

/* setController
 * Sets the controller used by this view.
 */
-(void)setController:(AppController *)theController
{
	controller = theController;
}

/* setTab
 * Set the tab associated with this browser view.
 */
-(void)setTab:(BrowserTab *)newTab
{
	[newTab retain];
	[tab release];
	tab = newTab;
}

/* loadURL
 * Load the specified URL into the web frame.
 */
-(void)loadURL:(NSURL *)url
{
	[[webPane mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
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

/* didStartProvisionalLoadForFrame
 * Invoked when a new client request is made by sender to load a provisional data source for frame.
 */
-(void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
	{
		[[controller browserView] setTabTitle:tab title:NSLocalizedString(@"Loading...", nil)];
		isLoadingFrame = YES;
	}
}

/* didFinishLoadForFrame
 * Invoked when a location request for frame has successfully; that is, when all the resources are done loading.
 */
-(void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
		isLoadingFrame = NO;
}

/* didReceiveTitle
 * Invoked when the page title arrives. We use this to set the tab title.
 */
-(void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
		[[controller browserView] setTabTitle:tab title:title];
}

/* decidePolicyForNewWindowAction
 * Called by the web view to get our policy on handling actions that would open a new window.
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

/* createWebViewWithRequest
 * Called when the browser wants to create a new window. The request is opened in a new tab.
 */
-(WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
	[controller openURLInBrowserWithURL:[request URL]];
	return nil;
}

/* contextMenuItemsForElement
 * Creates a new context menu for our web pane.
 */
-(NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems
{
	NSURL * urlLink = [element valueForKey:WebElementLinkURLKey];
	if (urlLink != nil) 
		return [controller contextMenuItemsLink:urlLink defaultMenuItems:defaultMenuItems];
	
	WebFrame * frameKey = [element valueForKey:WebElementFrameKey];
	if (frameKey != nil)
	{
		NSMutableArray * newDefaultMenu = [[NSMutableArray alloc] initWithArray:defaultMenuItems];
		[newDefaultMenu addObject:[NSMenuItem separatorItem]];

		// Add command to open the current page in the external browser
		NSString * defaultBrowser = getDefaultBrowser();
		NSMenuItem * newMenuItem = [[NSMenuItem alloc] init];
		if (defaultBrowser != nil && newMenuItem != nil)
		{
			[newMenuItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Open Page in %@", nil), defaultBrowser]];
			[newMenuItem setTarget:controller];
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
			[newMenuItem setTarget:controller];
			[newMenuItem setAction:@selector(copyPageURLToClipboard:)];
			[newMenuItem setTag:WebMenuItemTagOther];
			[newDefaultMenu addObject:newMenuItem];
			[newMenuItem release];
		}
		
		return newDefaultMenu;
	}
	
	return defaultMenuItems;
}

/* handleMinimumFontSizeChange
 * Called when the minimum font size for articles is enabled or disabled, or changed.
 */
-(void)handleMinimumFontSizeChange:(NSNotification *)nc
{
	[self loadMinimumFontSize];
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

/* printDocument
 * Print the web page.
 */
-(void)printDocument:(id)sender
{
	[webPane printDocument:sender];
}

/* mainView
 * Return the view that typically receives focus
 */
-(NSView *)mainView
{
	return webPane;
}

/* searchPlaceholderString
 * Return the search field placeholder.
 */
-(NSString *)searchPlaceholderString
{
	return NSLocalizedString(@"Search web page", nil);
}

/* search
 * Implement the search action. Search the web page for the specified
 * text.
 */
-(void)search
{
	[webPane searchFor:[controller searchString] direction:YES caseSensitive:NO wrap:YES];
}

/* url
 * Return the URL of the page being displayed.
 */
-(NSURL *)url
{
	WebDataSource * dataSource = [[webPane mainFrame] dataSource];
	return dataSource ? [[dataSource request] URL] : nil;
}

/* canGoForward
 * Return TRUE if we can go forward to a web page.
 */
-(BOOL)canGoForward
{
	return [webPane canGoForward];
}

/* canGoBack
 * Return TRUE if we can go to a previous web page.
 */
-(BOOL)canGoBack
{
	return [webPane canGoBack];
}

/* handleGoForward
 * Go to the next web page.
 */
-(void)handleGoForward
{
	[webPane goForward];
}

/* handleGoBack
 * Go to the previous web page.
 */
-(void)handleGoBack
{
	[webPane goBack];
}

/* handleReload
 * Reload the current web page.
 */
-(void)handleReload:(id)sender
{
	[webPane reload:self];
}

/* handleStopLoading
 * Stop loading the current web page.
 */
-(void)handleStopLoading:(id)sender
{
	[webPane stopLoading:self];
}

/* isLoading
 * Returns whether the current web page is in the process of being loaded.
 */
-(BOOL)isLoading
{
	return isLoadingFrame;
}

/* handleKeyDown [delegate]
 * Support special key codes. If we handle the key, return YES otherwise
 * return NO to allow the framework to pass it on for default processing.
 */
-(BOOL)handleKeyDown:(unichar)keyChar withFlags:(unsigned int)flags
{
	return NO;
}

/* dealloc
 * Clean up when the view is being deleted.
 */
-(void)dealloc
{
	[webPane stopLoading:self];
	[webPane release];
	[defaultWebPrefs release];
	[super dealloc];
}
@end
