//
//  RefreshManager.h
//  Vienna
//
//  Created by Steve on 7/19/05.
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

#import <Cocoa/Cocoa.h>
#import "Database.h"
#import "AsyncConnection.h"
#import "FeedCredentials.h"
#import "RefreshPlugin.h"

@interface RefreshManager : NSObject {
	int maximumConnections;
	int countOfNewArticles;
	NSMutableArray * connectionsArray;
	NSMutableArray * refreshArray;
	NSMutableArray * authQueue;
	NSTimer * pumpTimer;
	FeedCredentials * credentialsController;
	BOOL hasStarted;
	BOOL didFinish;
	NSString * statusMessageDuringRefresh;
	NSMutableDictionary * statusMessagePerPlugin;
}

+(RefreshManager *)sharedManager;
-(void)refreshFolderIconCacheForSubscriptions:(NSArray *)foldersArray;
-(void)refreshSubscriptions:(NSArray *)foldersArray ignoringSubscriptionStatus:(BOOL)ignoreSubStatus;
-(void)cancelAll;
-(int)countOfNewArticles;
-(int)totalConnections;
-(NSString *)statusMessageDuringRefresh;
-(BOOL)isRefreshing;
-(void)setStatusMessage:(NSString *)statusMessage forPlugin:(id<RefreshPlugin>)plugin;
@end
