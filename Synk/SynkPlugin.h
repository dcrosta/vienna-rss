//
//  SynkBundle.h
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "ArticlePlugin.h"
#import "FolderPlugin.h"
#import "RefreshPlugin.h"

typedef enum {
	SynkURLTypeArticle = 1,
	SynkURLTypeFolder,
	SynkURLTypeTestAccount,
	SynkURLTypeSignup
} SynkURLType;

typedef enum {
	SynkStateIdle = 0,
	SynkStateRebuildingCache = 1,
	SynkStateCommunicatingWithServer
} SynkState;

#define SynkCacheStateChanged @"SynkPluginStateChanged"

@class SynkPreferencesController;

@interface SynkPlugin : NSObject <ArticlePlugin, FolderPlugin, RefreshPlugin> {
	NSString * synkDbPath;
	// "pending" being sent to Synk
	NSMutableDictionary * pendingArticleEvents;
	NSMutableDictionary * pendingFolderEvents;
	// "unapplied" to local DB
	NSMutableDictionary * unappliedArticleEvents;
	NSMutableDictionary * unappliedFolderEvents;
	// synkId => {folderId, articleGuid}
	NSMutableDictionary * synkIdIndex;
	NSDate * lastSynkDate;

	NSString * username;
	NSString * password;
	NSString * hostname;
	BOOL enabled;
	BOOL syncArticleEvents;
	BOOL syncFolderEvents;
	
	SynkState currentState;
	
	float progress;
	IBOutlet NSTextField * progressLabel;
	IBOutlet NSWindow * progressWindow;
	IBOutlet NSProgressIndicator * progressBar;
	
	SynkPreferencesController * prefsController;
}

@property (assign) float progress;
@property (nonatomic, retain) NSDate * lastSynkDate;
@property (assign) BOOL syncArticleEvents;
@property (assign) BOOL syncFolderEvents;
@property (nonatomic, copy) NSString * username;
@property (nonatomic, copy) NSString * password;
@property (nonatomic, copy) NSString * hostname;

// recreating the synk cache
-(void)recreateSynkDb;
-(void)doRecreateSynkDb:(id)ignored;
-(void)finishRecreateSynkDb:(id)ignored;

// synk cache info
-(int)countOfUnprocessedServerEvents;
-(int)countOfUnsentLocalEvents;

// helpers
-(void)getAllFolders:(id)mutableArrayToFill;
-(void)getAllArticles:(id)mutableDictionaryToFill;
-(void)getFolder:(id)mutableDictionaryToFill;
-(void)getArticle:(id)mutableDictionaryToFill;
-(void)markArticle:(Article *)article read:(BOOL)read flagged:(BOOL)flagged deleted:(BOOL)deleted folder:(Folder *)folder;
-(void)doMarkArticle:(NSDictionary *)commandsDict;

-(void)doPostRefreshSynk:(id)ignored;
-(void)applyArticleEvents:(NSArray *)events;
-(NSMutableDictionary *)getArticleEventsSince:(NSDate *)date;
-(void)sendArticleEvents;
-(void)sendFolderEvents;

-(NSURL *)synkURLforType:(SynkURLType)type since:(NSDate *)since;
-(NSURL *)synkURLforType:(SynkURLType)type;

@end
