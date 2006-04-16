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
#import "Constants.h"
#import "AppController.h"
#import "Preferences.h"
#import "HelperFunctions.h"
#import "StringExtensions.h"
#import "AddressBarCell.h"
#import "WebKit/WebUIDelegate.h"
#import "WebKit/WebFrame.h"
#import "WebKit/WebKitErrors.h"
#import "WebKit/WebDocument.h"

// This is defined somewhere but I can't find where.
#define WebKitErrorPlugInWillHandleLoad	204

@interface BrowserPane (Private)
	-(void)endFrameLoad;
	-(void)setError:(NSError *)newError;
@end

@implementation BrowserPane

/* initWithFrame
 * Initialise our view.
 */
-(id)initWithFrame:(NSRect)frame
{
    if (([super initWithFrame:frame]) != nil)
	{
		controller = nil;
		isLoadingFrame = NO;
		isLocalFile = NO;
		hasPageTitle = NO;
		openURLInBackground = NO;
		pageFilename = nil;
		lastError = nil;
    }
    return self;
}

/* awakeFromNib
 * Do things that only make sense once the NIB is loaded.
 */
-(void)awakeFromNib
{
	// Create our webview
	[webPane setUIDelegate:self];
	[webPane setFrameLoadDelegate:self];
	[webPane setCustomUserAgent:MA_DefaultUserAgentString];
	
	// Set our box attributes
	[boxFrame setContentViewMargins:NSMakeSize(1, 1)];

	// Use an AddressBarCell for the address field which allows space for the
	// web page image and an optional lock icon for secure pages.
	AddressBarCell * cell = [[[AddressBarCell alloc] init] autorelease];
	[cell setEditable:YES];
	[cell setDrawsBackground:YES];
	[cell setBordered:YES];
	[cell setBezeled:YES];
	[cell setScrollable:YES];
	[cell setTarget:self];
	[cell setAction:@selector(handleAddress:)];
	[cell setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]]];
	[addressField setCell:cell];

	// Initialise address field
	[addressField setStringValue:@""];
	
	// Set tooltips
	[addressField setToolTip:NSLocalizedString(@"Enter the URL here", nil)];
	[refreshButton setToolTip:NSLocalizedString(@"Refresh the current page", nil)];
	[backButton setToolTip:NSLocalizedString(@"Return to the previous page", nil)];
	[forwardButton setToolTip:NSLocalizedString(@"Go forward to the next page", nil)];
}

/* setController
 * Sets the controller used by this view.
 */
-(void)setController:(AppController *)theController
{
	controller = theController;
	[webPane setController:controller];
}

/* viewLink
 * Return the URL being displayed as a string.
 */
-(NSString *)viewLink
{
	return [[self url] absoluteString];
}

/* setTab
 * Set the tab associated with this browser view. This is a shallow
 * reference.
 */
-(void)setTab:(BrowserTab *)newTab
{
	tab = newTab;
}

/* setError
 * Save the most recent error instance.
 */
-(void)setError:(NSError *)newError
{
	[newError retain];
	[lastError release];
	lastError = newError;
}

/* handleAddress
 * Called when the user hits Enter on the address bar.
 */
-(IBAction)handleAddress:(id)sender
{
	NSString * theURL = [addressField stringValue];
	
	// If no '.' appears in the string, wrap it with 'www' and 'com'
	if (![theURL hasCharacter:'.']) 
		theURL = [NSString stringWithFormat:@"www.%@.com", theURL];

	// If no schema, prefix http://
	if ([theURL rangeOfString:@"://"].location == NSNotFound)
		theURL = [NSString stringWithFormat:@"http://%@", theURL];

	[self loadURL:[NSURL URLWithString:theURL] inBackground:NO];
}

/* activateAddressBar
 * Put the focus on the address bar.
 */
-(void)activateAddressBar
{
	[[NSApp mainWindow] makeFirstResponder:addressField];
}

/* loadURL
 * Load the specified URL into the web frame.
 */
-(void)loadURL:(NSURL *)url inBackground:(BOOL)openInBackgroundFlag
{
	hasPageTitle = NO;
	openURLInBackground = openInBackgroundFlag;
	isLocalFile = [url isFileURL];

	[pageFilename release];
	pageFilename = [[[[url path] lastPathComponent] stringByDeletingPathExtension] retain];
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
        [addressField setStringValue:[[[[frame provisionalDataSource] request] URL] absoluteString]];
		[self setError:nil];
		hasPageTitle = NO;
		isLoadingFrame = YES;
	}
}

/* didCommitLoadForFrame
 * Invoked when data source of frame has started to receive data.
 */
-(void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
	{
		if (!openURLInBackground)
			[[sender window] makeFirstResponder:sender];

		// Show or hide the lock icon depending on whether this is a secure
		// web page. Also shade the address bar a nice light yellow colour as
		// Camino does.
		NSURLRequest * request = [[frame dataSource] request];
		if ([[[request URL] scheme] isEqualToString:@"https"])
		{
			[[addressField cell] setHasSecureImage:YES];
			[addressField setBackgroundColor:[NSColor colorWithDeviceRed:1.0 green:1.0 blue:0.777 alpha:1.0]];
			[lockIconImage setHidden:NO];
		}
		else
		{
			[[addressField cell] setHasSecureImage:NO];
			[addressField setBackgroundColor:[NSColor whiteColor]];
			[lockIconImage setHidden:YES];
		}
	}
}

/* didFailProvisionalLoadWithError
 * Invoked when a location request for frame has failed to load.
 */
-(void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
	{
		// Was this a feed redirect? If so, this isn't an error:
		if (![webPane isFeedRedirect] && ![webPane isDownload])
			[self setError:error];
		[self endFrameLoad];
	}
}

/* endFrameLoad
 * Handle the end of a load whether or not it completed and whether or not an error
 * occurred. The error variable is nil for no error or it contains the most recent
 * NSError incident.
 */
-(void)endFrameLoad
{
	if (!hasPageTitle)
	{
		if (lastError == nil)
			[[controller browserView] setTabTitle:tab title:pageFilename];
		else
		{
			// TODO: show an HTML error page in the webview instead or in addition to
			// the Error title on the tab.
			[[controller browserView] setTabTitle:tab title:NSLocalizedString(@"Error", nil)];
		}
	}
	isLoadingFrame = NO;
	openURLInBackground = NO;
}

/* didFailLoadWithError
 * Invoked when a location request for frame has failed to load.
 */
-(void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
	{
		// Not really an error. A plugin is grabbing the URL and will handle it
		// by itself.
		if (!([[error domain] isEqualToString:WebKitErrorDomain] && [error code] == WebKitErrorPlugInWillHandleLoad))
			[self setError:error];
		[self endFrameLoad];
	}
}

/* didFinishLoadForFrame
 * Invoked when a location request for frame has successfully; that is, when all the resources are done loading.
 */
-(void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
		[self endFrameLoad];
}

/* didReceiveTitle
 * Invoked when the page title arrives. We use this to set the tab title.
 */
-(void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
	{
		[[controller browserView] setTabTitle:tab title:title];
		hasPageTitle = YES;
	}
}

/* didReceiveIcon
 * Invoked when we get the page icon.
 */
-(void)webView:(WebView *)sender didReceiveIcon:(NSImage *)image forFrame:(WebFrame *)frame
{
	if (frame == [webPane mainFrame])
	{
		[image setScalesWhenResized:YES];
		[image setSize:NSMakeSize(14, 14)];
		[iconImage setImage:image];
	}
}

/* createWebViewWithRequest
 * Called when the browser wants to create a new webview.
 */
-(WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
	if ([request URL] != nil)
		[[webPane mainFrame] loadRequest:request];
	return webPane;
}

/* setFrame
 * Trap this to stop scripts from resizing the main Vienna window.
 */
-(void)webView:(WebView *)sender setFrame:(NSRect)frame
{
}

/* webViewClose
 * Handle scripting closing a window by just closing the tab.
 */
-(void)webViewClose:(WebView *)sender
{
	[[controller browserView] closeTab:tab];
}

/* contextMenuItemsForElement
 * Creates a new context menu for our web pane.
 */
-(NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems
{
	NSURL * urlLink = [element valueForKey:WebElementLinkURLKey];
	if (urlLink != nil) 
		return [controller contextMenuItemsForElement:element defaultMenuItems:defaultMenuItems];
	
	WebFrame * frameKey = [element valueForKey:WebElementFrameKey];
	if (frameKey != nil && !isLocalFile)
		return [controller contextMenuItemsForElement:element defaultMenuItems:defaultMenuItems];
	
	return defaultMenuItems;
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

/* performFindPanelAction
 * Implement the search action. Search the web page for the specified
 * text.
 */
-(void)performFindPanelAction:(int)actionTag
{
	switch (actionTag)
	{
		case NSFindPanelActionSetFindString:
		{
			NSView * docView = [[[webPane mainFrame] frameView] documentView];
			
			if ([docView conformsToProtocol:@protocol(WebDocumentText)])
				[controller setSearchString:[(id<WebDocumentText>)docView selectedString]];
			[webPane searchFor:[controller searchString] direction:YES caseSensitive:NO wrap:YES];
			break;
		}
			
		case NSFindPanelActionNext:
			[webPane searchFor:[controller searchString] direction:YES caseSensitive:NO wrap:YES];
			break;
			
		case NSFindPanelActionPrevious:
			[webPane searchFor:[controller searchString] direction:NO caseSensitive:NO wrap:YES];
			break;
	}
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
-(IBAction)handleGoForward:(id)sender
{
	[webPane goForward];
}

/* handleGoBack
 * Go to the previous web page.
 */
-(IBAction)handleGoBack:(id)sender
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

/* handleStopLoading webview
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
	[webPane setFrameLoadDelegate:nil];
	[webPane setUIDelegate:nil];
	[webPane stopLoading:self];
	[webPane removeFromSuperviewWithoutNeedingDisplay];
	[lastError release];
	[pageFilename release];
	[super dealloc];
}

@end
