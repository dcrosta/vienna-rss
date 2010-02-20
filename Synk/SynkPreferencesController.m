//
//  SynkPreferencesController.m
//  Vienna
//
//  Created by Daniel Crosta on 2/19/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "SynkPreferencesController.h"
#import "SynkPlugin.h"

#import "PluginHelper.h"


@implementation SynkPreferencesController

-(id)init
{
	if ((self = [super init]))
	{
		synkPlugin = (SynkPlugin*)[[PluginHelper helper] pluginWithName:@"Synk"];
		
		dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setDateStyle:NSDateFormatterMediumStyle];
		[dateFormatter setTimeStyle:NSDateFormatterShortStyle];
		
		NSNib * prefsNib = [[NSNib alloc] initWithNibNamed:@"SynkPreferences" bundle:[NSBundle bundleForClass:[self class]]];
		NSArray * topLevelObjects;
		// awakeFromNib gets called now
		[prefsNib instantiateNibWithOwner:self topLevelObjects:&topLevelObjects];
		for (id object in topLevelObjects)
		{
			if ([object isKindOfClass:[NSView class]])
			{
				preferencesView = object;
				break;
			}
		}
	}
	return self;
}

-(void)awakeFromNib
{	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(usernameChanged:) name:NSControlTextDidChangeNotification object:usernameField];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(passwordChanged:) name:NSControlTextDidChangeNotification object:passwordField];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSynkUpdateNotification:) name:SynkCacheStateChanged object:synkPlugin];
		
	[self setCacheInfoLabel];
}

-(void)handleSynkUpdateNotification:(NSNotification *)notification
{
	[self setCacheInfoLabel];
}

-(void)setCacheInfoLabel
{
	int server = [synkPlugin countOfUnprocessedServerEvents];
	int local = [synkPlugin countOfUnsentLocalEvents];

	NSString * formattedDate;
	if (![synkPlugin lastSynkDate] || [[synkPlugin lastSynkDate] timeIntervalSince1970] == 0)
		formattedDate = @"never";
	else
		formattedDate = [dateFormatter stringFromDate:[synkPlugin lastSynkDate]];
	
	NSString * infoString = [NSString stringWithFormat:@"%d unprocessed server event%@", server, (server == 1 ? @"" : @"s")];
	infoString = [infoString stringByAppendingFormat:@"\n%d unsent local event%@", local, (local == 1 ? @"" : @"s")];
	infoString = [infoString stringByAppendingFormat:@"\nLast synchronized %@", formattedDate];
	
	[synkCacheInfoLabel setStringValue:infoString];
}

-(void)dealloc
{
	[dateFormatter release];
	[preferencesView release];
	[super dealloc];
}

-(NSView *)preferencesView
{
	return preferencesView;
}

#pragma mark -
#pragma mark Preference Pane

/* testSynkLogin:
 * Attempt to test that the currently-set username and password
 * identify a valid account on the Synk server.
 */
-(IBAction)testSynkLogin:(id)sender
{
	[testSpinner setHidden:NO];
	[testSpinner startAnimation:self];
	[usernameField setEnabled:NO];
	[passwordField setEnabled:NO];
	
	NSURL * synkTestUrl = [synkPlugin synkURLforType:SynkURLTypeTestAccount since:nil];
	ASIHTTPRequest * request = [ASIHTTPRequest requestWithURL:synkTestUrl];
	[request setUseKeychainPersistance:NO];
	[request setUseSessionPersistance:NO];
	[request setUsername:[self username]];
	[request setPassword:[self password]];
	[request setDelegate:self];
	[request startAsynchronous];
}

/* usernameChanged:
 * Called each time the username is changed in the preference pane.
 */
-(void)usernameChanged:(NSNotification *)notificaton
{
	[testSuccessOrFailureImage setHidden:YES];
	[self setUsername:[usernameField stringValue]];
}

/* passwordChanged:
 * Called each time the password is changed in the preference pane.
 */
-(void)passwordChanged:(NSNotification *)notificaton
{
	[testSuccessOrFailureImage setHidden:YES];
	[self setPassword:[passwordField stringValue]];
}

/* clickedSignupLink:
 * Open the URL to the Synk signup page in the user's browser.
 */
-(IBAction)clickedSignupButton:(id)sender
{
	NSLog(@"clickedSignupLink:%@", sender);
	NSURL * signupURL = [synkPlugin synkURLforType:SynkURLTypeSignup];
	[[NSWorkspace sharedWorkspace] openURL:signupURL];
}

#pragma mark -
#pragma mark KVC Compliance

-(NSString *)username
{
	return [synkPlugin username];
}

-(void)setUsername:(NSString *)username
{
	[synkPlugin setUsername:username];
}

-(NSString *)password
{
	return [(SynkPlugin *)[[PluginHelper helper] pluginWithName:@"Synk"] password];
}

-(void)setPassword:(NSString *)password
{
	[synkPlugin setPassword:password];
}

-(BOOL)syncArticleEvents
{
	return [(SynkPlugin *)[[PluginHelper helper] pluginWithName:@"Synk"] syncArticleEvents];
}

-(void)setSyncArticleEvents:(BOOL)syncArticleEvents
{
	[synkPlugin setSyncArticleEvents:syncArticleEvents];
}

-(BOOL)syncFolderEvents
{
	return [(SynkPlugin *)[[PluginHelper helper] pluginWithName:@"Synk"] syncFolderEvents];
}

-(void)setSyncFolderEvents:(BOOL)syncFolderEvents
{
	[synkPlugin setSyncFolderEvents:syncFolderEvents];
}

#pragma mark -
#pragma mark ASIHTTPRequest delegate

-(void)requestFinished:(ASIHTTPRequest *)request
{
	[self testDidSucceed:([request responseStatusCode] == 200)];
}

-(void)requestFailed:(ASIHTTPRequest *)request
{
	[self testDidSucceed:NO];
}

-(void)testDidSucceed:(BOOL)succeeded
{
	[testSpinner stopAnimation:self];
	[testSpinner setHidden:YES];
	
	NSString * fileName = (succeeded ? @"green-checkmark" : @"red-x");
	NSImage * img = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:fileName ofType:@"png"]];
	[testSuccessOrFailureImage setHidden:NO];
	[testSuccessOrFailureImage setImage:img];
	[img release];
	
	[usernameField setEnabled:YES];
	[passwordField setEnabled:YES];	
	
}

@end
