//
//  SynkBundle.m
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

// from SynkPlugin
#import "SynkPlugin.h"
#import "SynkArticleExtensions.h"
#import "SynkPreferencesController.h"

#import "ASIHTTPRequest.h"
#import "JSON.h"

// from Vienna
#import "Preferences.h"
#import "RefreshManager.h"
#import "Database.h"
#import "Folder.h"
#import "PluginHelper.h"
#import "KeyChain.h"


@implementation SynkPlugin

@synthesize progress;
@synthesize lastSynkDate;
@synthesize syncArticleEvents;
@synthesize syncFolderEvents;
@synthesize username;
@synthesize password;
@synthesize hostname;

#pragma mark -
#pragma mark ViennaPlugin

/* startup
 * Called by Vienna at an appropriate time to initialize anything in the
 * plugin. Preferences has already been loaded, as have all NIBs.
 */
-(void)startup
{
	DebugLog(@"SynkPlugin got -(void)startup");
	
	Preferences * prefs = [Preferences standardPreferences];
	
	NSString * profilePath = [prefs profileFolder];
	synkDbPath = [[profilePath stringByAppendingPathComponent:@"Synk.db"] retain];
	DebugLog(@"synkLogPath is %@", synkDbPath);
	
	self.username = [prefs stringForKey:@"username" plugin:self];
	self.password = [KeyChain getGenericPasswordFromKeychain:username serviceName:@"ViennaSynk"];
	self.hostname = [prefs stringForKey:@"server" plugin:self];
	if (!hostname || [hostname isEqual:@""])
		self.hostname = [NSString stringWithString:@"https://rssynk.appspot.com"];
	
	enabled = !(!username || !password || !hostname || [username isEqual:@""] || [password isEqual:@""] || [hostname isEqual:@""]);
	
	// defaults to NO
	self.syncArticleEvents = [prefs boolForKey:@"SyncArticleEvents" plugin:self];
	self.syncFolderEvents = [prefs boolForKey:@"SyncFolderEvents" plugin:self];
	
	pendingArticleEvents = [[NSMutableDictionary alloc] init];
	pendingFolderEvents = [[NSMutableDictionary alloc] init];
	unappliedArticleEvents = [[NSMutableDictionary alloc] init];
	unappliedFolderEvents = [[NSMutableDictionary alloc] init];
	synkIdIndex = [[NSMutableDictionary alloc] init];
	[self setLastSynkDate:[NSDate dateWithTimeIntervalSince1970:0]];
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:synkDbPath])
	{
		DebugLog(@"Loading synk log from %@", synkDbPath);
		NSDictionary * root = [NSKeyedUnarchiver unarchiveObjectWithFile:synkDbPath];

		if ([root objectForKey:@"clean"])
		{
			[pendingArticleEvents addEntriesFromDictionary:[root objectForKey:@"pendingArticleEvents"]];
			[pendingFolderEvents addEntriesFromDictionary:[root objectForKey:@"pendingFolderEvents"]];
			[unappliedArticleEvents addEntriesFromDictionary:[root objectForKey:@"unappliedArticleEvents"]];
			[unappliedFolderEvents addEntriesFromDictionary:[root objectForKey:@"unappliedFolderEvents"]];
			[synkIdIndex addEntriesFromDictionary:[root objectForKey:@"synkIdIndex"]];
			[self setLastSynkDate:[root objectForKey:@"lastSynkDate"]];
		}
		else
		{
			[self recreateSynkDb];
		}
		
		// save as unclean
		NSMutableDictionary * newRoot = [NSMutableDictionary dictionary];
		[newRoot addEntriesFromDictionary:root];
		[newRoot setObject:[NSNumber numberWithBool:NO] forKey:@"clean"];
		[NSKeyedArchiver archiveRootObject:newRoot toFile:synkDbPath];
	}
	else
	{
		[self recreateSynkDb];
	}
	
	prefsController = nil;
}

/* shutdown
 * Called by Vienna before quitting so that plugins can deinitialize
 * anything as necessary.
 */
-(void)shutdown
{
	DebugLog(@"SynkPlugin got -(void)shutdown");
	
	NSDictionary * root = [[NSDictionary alloc] initWithObjectsAndKeys:
						   pendingArticleEvents, @"pendingArticleEvents",
						   pendingFolderEvents, @"pendingFolderEvents",
						   unappliedArticleEvents, @"unappliedArticleEvents",
						   unappliedFolderEvents, @"unappliedFolderEvents",
						   synkIdIndex, @"synkIdIndex",
						   lastSynkDate, @"lastSynkDate",
						   [NSNumber numberWithBool:YES], @"clean",
						   nil];
	if (![NSKeyedArchiver archiveRootObject:root toFile:synkDbPath])
	{
		DebugLog(@"unable to archive articleSynklog and folderSynkLog");
	}
	[root release];
	
	// save settings
	Preferences * prefs = [Preferences standardPreferences];
	[prefs setString:username forKey:@"username" plugin:self];
	[KeyChain setGenericPasswordInKeychain:password username:username serviceName:@"ViennaSynk"];
	[prefs setBool:syncArticleEvents forKey:@"SyncArticleEvents" plugin:self];
	[prefs setBool:syncFolderEvents forKey:@"SyncFolderEvents" plugin:self];
	
	// "dealloc"
	self.username = nil;
	self.password = nil;
	self.hostname = nil;
	
	[synkDbPath release];
	synkDbPath = nil;
	[pendingArticleEvents release];
	pendingArticleEvents = nil;
	[pendingFolderEvents release];
	pendingFolderEvents = nil;
	[synkIdIndex release];
	synkIdIndex = nil;
	self.lastSynkDate = nil;
	
	[prefsController release];
	prefsController = nil;
}

/* preferencePaneView
 * Return a view to be used as the preference pane for this plugin.
 */
-(NSView *)preferencePaneView
{
	if (prefsController == nil)
	{
		prefsController = [[SynkPreferencesController alloc] init];
	}
	
	return [prefsController preferencesView];
}

/* name
 * Return a human-friendly string name, which should be localized
 * if possible.
 */
-(NSString *)name
{
	return @"Synk";
}

#pragma mark -
#pragma mark ArticlePlugin

// called by Vienna after an article's state has changed. only one of the
// four BOOL arguments will be set to YES in any valid message
-(void)articleStateChanged:(Article *)article
			 wasMarkedRead:(BOOL)wasMarkedRead
		   wasMarkedUnread:(BOOL)wasMarkedUnread
				wasFlagged:(BOOL)wasFlagged
			  wasUnFlagged:(BOOL)wasUnFlagged
				wasDeleted:(BOOL)wasDeleted
			  wasUnDeleted:(BOOL)wasUnDeleted
			wasHardDeleted:(BOOL)wasHardDeleted
{
	DebugLog(@"SynkPlugin received articleStateChanged:%@ wasMarkedRead:%@ wasMarkedUnread:%@ wasFlagged:%@ wasUnFlagged:%@ wasDeleted:%@ wasUnDeleted:%@ wasHardDeleted:%@", article, (wasMarkedRead ? @"YES" : @"NO"), (wasMarkedUnread ? @"YES" : @"NO"), (wasFlagged ? @"YES" : @"NO"), (wasUnFlagged ? @"YES" : @"NO"), (wasDeleted ? @"YES" : @"NO"), (wasUnDeleted ? @"YES" : @"NO"), (wasHardDeleted ? @"YES" : @"NO"));
	
	NSString * synkId = [article synkId];
	NSMutableDictionary * event = [pendingArticleEvents objectForKey:synkId];
	if (event == nil)
	{
		event = [NSMutableDictionary dictionary];
		[event setObject:synkId forKey:@"id"];
		[pendingArticleEvents setObject:event forKey:synkId];
	}
	
	[event setObject:[NSNumber numberWithInt:[[NSDate date] timeIntervalSince1970]] forKey:@"timestamp"];
	
	if (wasMarkedRead)
		[event setObject:[NSNumber numberWithBool:YES] forKey:@"read"];
	else if (wasMarkedUnread)
		[event setObject:[NSNumber numberWithBool:NO] forKey:@"read"];
	else if (wasFlagged)
		[event setObject:[NSNumber numberWithBool:YES] forKey:@"flagged"];
	else if (wasUnFlagged)
		[event setObject:[NSNumber numberWithBool:NO] forKey:@"flagged"];
	else if (wasDeleted || wasHardDeleted)
		[event setObject:[NSNumber numberWithBool:YES] forKey:@"deleted"];
	else if (wasUnDeleted)
		[event setObject:[NSNumber numberWithBool:NO] forKey:@"deleted"];
	
	NSDictionary * indexEntry = [NSDictionary dictionaryWithObjectsAndKeys:
								 [NSNumber numberWithInt:[[article containingFolder] itemId]], @"folderId",
								 [article guid], @"articleGuid", nil];
	[synkIdIndex setObject:indexEntry forKey:synkId];
	[[NSNotificationCenter defaultCenter] postNotificationName:SynkCacheStateChanged object:self];
}

#pragma mark -
#pragma mark RefreshPlugin

/* willRefreshArticles
 * Called by Vienna just before beginning refreshing articles.
 */
-(void)willRefreshArticles
{
	DebugLog(@"SynkPlugin received -(void)willRefreshArticles");
}

/* didRefreshArticles
 * Called by Vienna just after finishing refreshing articles.
 */
-(void)didRefreshArticles
{
	DebugLog(@"SynkPlugin received -(void)didRefreshArticles");
	
	currentState = SynkStateCommunicatingWithServer;
	[self performSelectorInBackground:@selector(doPostRefreshSynk:) withObject:nil];
}

/* shouldDelayStartOfArticleRefresh
 * Return YES if RefreshManager should not begin refreshing
 * articles, e.g. if the plugin needs to do something first.
 */
-(BOOL)shouldDelayStartOfArticleRefresh
{
	DebugLog(@"SynkPlugin received -(BOOL)shouldDelayStartOfArticleRefresh");
	if (currentState == SynkStateRebuildingCache)
	{
		[[RefreshManager sharedManager] setStatusMessage:@"Rebuilding Synk cache..." forPlugin:self];
	}
	return (currentState == SynkStateRebuildingCache);
}

/* shouldDelayEndOfArticleRefresh
 * Return YES if RefreshManager should not finish refreshing
 * articles, e.g. if the plugin needs to do something first.
 */
-(BOOL)shouldDelayEndOfArticleRefresh
{
	DebugLog(@"SynkPlugin received -(BOOL)shouldDelayEndOfArticleRefresh");
	return (currentState == SynkStateCommunicatingWithServer);
}

#pragma mark -
#pragma mark Private

/* recreateSynkDb
 * Display a modal dialog w/ progress bar, then begin
 * doRecreateSynkDb in a background thread.
 */
-(void)recreateSynkDb
{
	currentState = SynkStateRebuildingCache;
	
	[self setProgress:0.0];
	[NSBundle loadNibNamed:@"SynkRecreateDbWindow" owner:self];

	[progressBar setUsesThreadedAnimation:YES];
	[progressBar startAnimation:self];
	[progressWindow makeKeyAndOrderFront:self];
	
	[self performSelectorInBackground:@selector(doRecreateSynkDb:) withObject:nil];
}

/* doRecreateSynkDb:
 * Scan the Folders and Articles and update Synk's state.
 */
-(void)doRecreateSynkDb:(id)ignored
{
	// this runs in a separate thread, so set up
	// a pool and release it at the end
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	[progressLabel setStringValue:@"Contacting Synk Server..."];
	NSMutableDictionary * synkEvents = [self getArticleEventsSince:nil];
	
	// remove any pending events -- since we were called, we assume
	// that we can't rely on them (likely an unclan Vienna shutdown)
	[pendingArticleEvents removeAllObjects];
	[pendingFolderEvents removeAllObjects];
	
	[progressLabel setStringValue:@"Rebuilding Synk Cache..."];
	
	NSMutableArray * allFolders = [NSMutableArray array];
	[self performSelectorOnMainThread:@selector(getAllFolders:) withObject:allFolders waitUntilDone:YES];
	
	// this is a bad guess at progress! some folders
	// will have many more articles than others
	float folderProgressStep = 1.0 / (float)[allFolders count];
	[progressBar setIndeterminate:NO];
	
	for (Folder * folder in allFolders)
	{
		if ([folder type] == MA_RSS_Folder)
		{
			NSMutableDictionary * helperDict = [NSMutableDictionary dictionary];
			[helperDict setObject:folder forKey:@"folder"];
			[self performSelectorOnMainThread:@selector(getAllArticles:) withObject:helperDict waitUntilDone:YES];
			NSArray * articles = [helperDict objectForKey:@"articles"];
			
			for (Article * article in articles)
			{
				NSString * synkId = [article synkId];
				
				NSDictionary * indexEntry = [NSDictionary dictionaryWithObjectsAndKeys:
											 [NSNumber numberWithInt:[[article containingFolder] itemId]], @"folderId",
											 [article guid], @"articleGuid", nil];
				[synkIdIndex setObject:indexEntry forKey:synkId];
				
				NSDictionary * eventFromSynk = [synkEvents objectForKey:synkId];
				
				if (eventFromSynk)
				{
					// if an event exists in the server for this article,
					// treat it as correct and update the local database
					[self markArticle:article
								 read:[[eventFromSynk objectForKey:@"read"] boolValue]
							  flagged:[[eventFromSynk objectForKey:@"flagged"] boolValue]
							  deleted:[[eventFromSynk objectForKey:@"deleted"] boolValue]
							   folder:folder];
				}
				else
				{
					// otherwise, record the current state to be sent to
					// Synk next time we refresh
					NSMutableDictionary * event = [NSMutableDictionary dictionary];
					[event setObject:synkId forKey:@"id"];
					[event setObject:[NSNumber numberWithBool:[article isRead]] forKey:@"read"];
					[event setObject:[NSNumber numberWithBool:[article isFlagged]] forKey:@"flagged"];
					[event setObject:[NSNumber numberWithBool:[article isDeleted]] forKey:@"deleted"];
					[event setObject:[NSNumber numberWithInt:[[article date] timeIntervalSince1970]] forKey:@"timestamp"];
					// DebugLog(@"event: %@", event);
					[pendingArticleEvents setObject:event forKey:synkId];	
				}
			}
		}
		
		if ([folder type] == MA_Smart_Folder || [folder type] == MA_RSS_Folder)
		{
			// figure out what data we need to store for synking
			// subscriptions and smart folders
			
		}
		
		[self setProgress:[self progress] + folderProgressStep];
	}
	
	[self setProgress:1.0];
	DebugLog(@"doRecreateSynkDb ... DONE");
	
	if ([pendingArticleEvents count] || [pendingFolderEvents count])
	{
		// then we should take this opportunity to try to update the server
		[progressBar setIndeterminate:YES];
		[progressBar startAnimation:self];
		[progressLabel setStringValue:@"Updating Synk Server..."];
	
		[self sendArticleEvents];
		[self sendFolderEvents];
	}
	
	[self performSelectorOnMainThread:@selector(finishRecreateSynkDb:) withObject:nil waitUntilDone:NO];
	
	[pool release];
}

/* finishRecreateSynkDb:
 * Called on the main thread once doRecreateSynkDb:
 * has finished.
 */
-(void)finishRecreateSynkDb:(id)ignored
{
	DebugLog(@"pendingArticleEvents count: %d", [pendingArticleEvents count]);
	DebugLog(@"pendingFolderEvents count: %d", [pendingFolderEvents count]);
	[self setLastSynkDate:[NSDate date]];
	[progressWindow orderOut:self];
	currentState = SynkStateIdle;
	[[NSNotificationCenter defaultCenter] postNotificationName:SynkCacheStateChanged object:self];
}

/* getAllFolders:
 * Helper to doRecreateSynkDb: which is called on the main
 * thread to ensure thread safety in the database.
 */
-(void)getAllFolders:(id)mutableArrayToFill
{
	Database * database = [Database sharedDatabase];
	NSArray * allFolders = [database arrayOfAllFolders];
	[mutableArrayToFill addObjectsFromArray:allFolders];
}

/* getAllArticles:fromFolder:
 * Helper to doRecreateSynkDb: which is called on the main
 * thread to ensure thread safety in the database.
 */
-(void)getAllArticles:(id)mutableDictionaryToFill
{
	Folder * folder = [mutableDictionaryToFill objectForKey:@"folder"];
	NSArray * articles = [folder articles];
	[mutableDictionaryToFill setObject:articles forKey:@"articles"];
}

/* getFolder:
 * Helper to processArticleEvents which is called on the main
 * thread to ensure thread safety in the database.
 */
-(void)getFolder:(id)mutableDictionaryToFill
{
	int folderId = [[mutableDictionaryToFill objectForKey:@"folderId"] intValue];
	[mutableDictionaryToFill setObject:[[Database sharedDatabase] folderFromID:folderId] forKey:@"folder"];
}

/* getArticle:
 * Helper to processArticleEvents which is called on the main
 * thread to ensure thread safety in the database.
 */
-(void)getArticle:(id)mutableDictionaryToFill
{
	Folder * folder = [mutableDictionaryToFill objectForKey:@"folder"];
	[mutableDictionaryToFill setObject:[folder articleFromGuid:[mutableDictionaryToFill objectForKey:@"articleGuid"]] forKey:@"article"];
}


/* markArticle:read:flagged:deleted:folder:
 * Helper to update the status of an article, will be
 * called on the main thread to ensure thread safety in the
 * database.
 */
-(void)markArticle:(Article *)article read:(BOOL)read flagged:(BOOL)flagged deleted:(BOOL)deleted folder:(Folder *)folder
{
	NSDictionary * commandsDict = [NSDictionary dictionaryWithObjectsAndKeys:
								   article, @"article",
								   folder, @"folder",
								   [NSNumber numberWithBool:read], @"read",
								   [NSNumber numberWithBool:flagged], @"flagged",
								   [NSNumber numberWithBool:deleted], @"deleted",
								   nil];
	[self performSelectorOnMainThread:@selector(doMarkArticle:) withObject:commandsDict waitUntilDone:YES];
}

/* doMarkArticle:
 * Called with performSelectorOnMainThread by
 * markArticle:read:flagged:deleted:folder:
 */
-(void)doMarkArticle:(NSDictionary *)commandsDict
{
	Article * article = [commandsDict objectForKey:@"article"];
	Folder * folder = [commandsDict objectForKey:@"folder"];
	BOOL read = [[commandsDict objectForKey:@"read"] boolValue];
	BOOL flagged = [[commandsDict objectForKey:@"flagged"] boolValue];
	BOOL deleted = [[commandsDict objectForKey:@"deleted"] boolValue];
	
	PluginHelper * helper = [PluginHelper helper];
	NSArray * arrayOfSelf = [[NSArray alloc] initWithObjects:self, nil];
	
	Database * database = [Database sharedDatabase];
	if ([article isRead] != read)
	{
		[database markArticleRead:[folder itemId] guid:[article guid] isRead:read];
		[helper articleStateChanged:article wasMarkedRead:read wasMarkedUnread:(!read) wasFlagged:NO wasUnFlagged:NO wasDeleted:NO wasUnDeleted:NO wasHardDeleted:NO excludingPlugins:arrayOfSelf];
	}
	if ([article isFlagged] != flagged)
	{
		[database markArticleFlagged:[folder itemId] guid:[article guid] isFlagged:flagged];
		[helper articleStateChanged:article wasMarkedRead:NO wasMarkedUnread:NO wasFlagged:flagged wasUnFlagged:(!flagged) wasDeleted:NO wasUnDeleted:NO wasHardDeleted:NO excludingPlugins:arrayOfSelf];
	}
	if ([article isDeleted] != deleted)
	{
		[database markArticleDeleted:[folder itemId] guid:[article guid] isDeleted:deleted];
		[helper articleStateChanged:article wasMarkedRead:NO wasMarkedUnread:NO wasFlagged:NO wasUnFlagged:NO wasDeleted:deleted wasUnDeleted:(!deleted) wasHardDeleted:NO excludingPlugins:arrayOfSelf];
	}
	
	[arrayOfSelf release];
}


/* doPostRefreshSynk:
 * Do the series of steps required after a refresh finishes
 * (after we get didRefreshArticles).
 */
-(void)doPostRefreshSynk:(id)ignored
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	if (enabled)
	{
		[[RefreshManager sharedManager] setStatusMessage:@"Synchronizing with Synk..." forPlugin:self];
		
		if (syncArticleEvents)
		{
			NSMutableDictionary * events = [self getArticleEventsSince:[self lastSynkDate]];
			NSSortDescriptor * sortByTimestampAscending = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:YES];
			NSArray * sortedEvents = [[events allKeys] sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortByTimestampAscending]];
			[sortByTimestampAscending release];
			
			[self applyArticleEvents:sortedEvents];
			
			
			[self sendArticleEvents];
		}
		
		// [self sendFolderEvents];

		if (syncArticleEvents || syncFolderEvents)
			[self setLastSynkDate:[NSDate date]];
	}
	
	currentState = SynkStateIdle;
	[[NSNotificationCenter defaultCenter] postNotificationName:SynkCacheStateChanged object:self];
	
	[pool release];
}

/* applyArticleEvents:
 * Go through the given array of article events, and update
 * articles as necessary. Uses getArticle: and getFolder:
 * main-thread helpers to do its job.
 */
-(void)applyArticleEvents:(NSArray *)events
{
	for (NSDictionary * event in events)
	{
		NSString * synkId = [event objectForKey:@"id"];
		if (synkId == nil)
			continue;
		NSDictionary * indexEntry = [synkIdIndex objectForKey:synkId];
		NSNumber * folderId = [indexEntry objectForKey:@"folderId"];
		if (folderId == 0)
			continue;
		
		NSMutableDictionary * helperDict = [NSMutableDictionary dictionary];
		[helperDict setObject:folderId forKey:@"folderId"];
		[self performSelectorOnMainThread:@selector(getFolder:) withObject:helperDict waitUntilDone:YES];
		Folder * folder = [helperDict objectForKey:@"folder"];
		if (folder == nil)
		{
			if ([unappliedArticleEvents objectForKey:synkId] == nil)
				[unappliedArticleEvents setObject:[NSMutableDictionary dictionary] forKey:synkId];
			[[unappliedArticleEvents objectForKey:synkId] addEntriesFromDictionary:event];
			continue;
		}
		[self performSelectorOnMainThread:@selector(getArticle:) withObject:helperDict waitUntilDone:YES];
		Article * article = [helperDict objectForKey:@"article"];
		if (article == nil)
		{
			if ([unappliedArticleEvents objectForKey:synkId] == nil)
				[unappliedArticleEvents setObject:[NSMutableDictionary dictionary] forKey:synkId];
			[[unappliedArticleEvents objectForKey:synkId] addEntriesFromDictionary:event];
			continue;
		}
		
		// if an event exists in the server for this article,
		// treat it as correct and update the local database
		[self markArticle:article
					 read:[[event objectForKey:@"read"] boolValue]
				  flagged:[[event objectForKey:@"flagged"] boolValue]
				  deleted:[[event objectForKey:@"deleted"] boolValue]
				   folder:folder];
		
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SynkCacheStateChanged object:self];
}

#pragma mark -
#pragma mark Communications
										
/* getArticleEventsSince:
 * Contact the Synk server and get all article events since
 * the given date. date may be nil to get all article events
 * ever. The returned NSMutableDictionary is autoreleased.
 */
-(NSMutableDictionary *)getArticleEventsSince:(NSDate *)date
{
	if (!enabled)
		return [NSMutableDictionary dictionary];
	
	ASIHTTPRequest * synkRequest = [[ASIHTTPRequest alloc] initWithURL:[self synkURLforType:SynkURLTypeArticle since:date]];
	[synkRequest setUseKeychainPersistance:NO];
	[synkRequest setUseSessionPersistance:NO];
	[synkRequest setUsername:username];
	[synkRequest setPassword:password];
	[synkRequest startSynchronous];
	NSError * err = [synkRequest error];
	
	NSMutableDictionary * events = [NSMutableDictionary dictionary];
	
	if (err)
	{
		NSLog(@"error fetching from synk: %@ %@", err, [err userInfo]);
	}
	else
	{
		DebugLog(@"responseCode: %d %@", [synkRequest responseStatusCode], [synkRequest responseStatusMessage]);
		NSSortDescriptor * sortByTimestampAscending = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:YES];
		NSArray * parsedResponse = [[[synkRequest responseString] JSONValue] sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortByTimestampAscending]];
		[sortByTimestampAscending release];
		
		// Synk events are in order, newest to oldest; so
		// iterate in reverse order, and allow overwrites
		NSDictionary * synkEvent;
		NSEnumerator * eventsEnumerator = [parsedResponse reverseObjectEnumerator];
		while ((synkEvent = [eventsEnumerator nextObject]) != nil)
		{
			NSString * synkId = [synkEvent objectForKey:@"id"];
			if (![events objectForKey:synkId])
			{
				NSMutableDictionary * event = [NSMutableDictionary dictionary];
				[event setObject:synkId forKey:@"id"];
				[events setObject:event forKey:synkId];
			}
			
			NSMutableDictionary * event = [events objectForKey:synkId];
			[event addEntriesFromDictionary:synkEvent];
		}
	}
	
	[synkRequest release];
	
	return events;
}

/* sendArticleEvents
 * Send events in pendingArticleEvents to the Synk
 * server, and then remove updates from the array.
 */
-(void)sendArticleEvents
{
	if ([pendingArticleEvents count] == 0 || !enabled)
		return;
	
	NSArray * events = [pendingArticleEvents allValues];
	DebugLog(@"sending %d events to Synk...", [events count]);
	
	NSSortDescriptor * sortByTimestampDescending = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:NO];
	events = [events sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortByTimestampDescending]];
	[sortByTimestampDescending release];
	
	NSMutableData * postBody = [NSMutableData dataWithData:[[events JSONRepresentation] dataUsingEncoding:NSUTF8StringEncoding]];
	
	ASIHTTPRequest * synkRequest = [[ASIHTTPRequest alloc] initWithURL:[self synkURLforType:SynkURLTypeArticle since:nil]];
	[synkRequest setUseKeychainPersistance:NO];
	[synkRequest setUseSessionPersistance:NO];
	[synkRequest setRequestMethod:@"POST"];
	[synkRequest setPostBody:postBody];
	[synkRequest setUsername:username];
	[synkRequest setPassword:password];
	[synkRequest startSynchronous];
	
	NSError * err = [synkRequest error];
	if (err)
	{
		NSLog(@"failed to POST to %@", [synkRequest url]);
	}
	else
	{
		for (NSDictionary * event in events)
		{
			DebugLog(@"removing event for synkId: %@ from pendingArticleEvents (event is %@)", [event objectForKey:@"id"], event);
			[pendingArticleEvents removeObjectForKey:[event objectForKey:@"id"]];
		}
	}
	
	[synkRequest release];
	DebugLog(@"sent %d events to Synk", [events count]);
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SynkCacheStateChanged object:self];
}

/* sendFolderEvents
 * Send events in pendingFolderEvents to the Synk
 * server, and then remove updates from the array.
 */
-(void)sendFolderEvents
{
	if ([pendingFolderEvents count] == 0 || !enabled)
		return;
	
	NSArray * events = [[pendingFolderEvents allValues] copy];
	
	NSSortDescriptor * sortByTimestampDescending = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:NO];
	events = [events sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortByTimestampDescending]];
	[sortByTimestampDescending release];
	
	NSMutableData * postBody = [NSMutableData dataWithData:[[events JSONRepresentation] dataUsingEncoding:NSUTF8StringEncoding]];
	
	ASIHTTPRequest * synkRequest = [[ASIHTTPRequest alloc] initWithURL:[self synkURLforType:SynkURLTypeFolder since:nil]];
	[synkRequest setUseKeychainPersistance:NO];
	[synkRequest setUseSessionPersistance:NO];
	[synkRequest setRequestMethod:@"POST"];
	[synkRequest setPostBody:postBody];
	[synkRequest setUsername:username];
	[synkRequest setPassword:password];
	[synkRequest startSynchronous];
	
	NSError * err = [synkRequest error];
	if (err)
	{
		NSLog(@"failed to POST to %@", [synkRequest url]);
	}
	else
	{
		for (NSDictionary * event in events)
		{
			[pendingFolderEvents removeObjectForKey:[event objectForKey:@"id"]];
		}
	}
	
	[synkRequest release];
	[events release];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SynkCacheStateChanged object:self];
}

/* synkURLforType:since:
 * Return an NSURL for the given Synk request and optionally
 * filter-since date.
 */
-(NSURL *)synkURLforType:(SynkURLType)type since:(NSDate *)since
{
	NSString * synkServer = hostname;
	NSString * urlFragment;
	switch (type)
	{
		case SynkURLTypeArticle:
			urlFragment = @"events/rss/article";
			break;
		case SynkURLTypeFolder:
			urlFragment = @"events/rss/folder";
			break;
		case SynkURLTypeTestAccount:
			urlFragment = @"account/test";
			break;
		case SynkURLTypeSignup:
			urlFragment = @"register";
			break;
		default:
			return nil;
	}
	NSString * urlString = [NSString stringWithFormat:@"%@/%@", synkServer, urlFragment];
	if (since)
	{
		urlString = [urlString stringByAppendingFormat:@"/since/%d", (int)[since timeIntervalSince1970]];
	}
	
	return [NSURL URLWithString:urlString];
}

/* synkURLforType:
 * Return an NSURL for the given Synk request and optionally
 * filter-since date. Calls synkURLforType:since: with nil as
 * the second argument.
 */
-(NSURL *)synkURLforType:(SynkURLType)type
{
	return [self synkURLforType:type since:nil];
}

#pragma mark -
#pragma mark Infor for other parts of Synk

/* countOfUnprocessedServerEvents
 * Returns the number of stored but yet-unprocessed events from the server.
 */
-(int)countOfUnprocessedServerEvents
{
	return [unappliedArticleEvents count] + [unappliedFolderEvents count];
}

/* countOfUnsentLocalEvents
 * Returns the number of events not yet sent to the server.
 */
-(int)countOfUnsentLocalEvents
{
	return [pendingArticleEvents count] + [pendingFolderEvents count];
}

@end
