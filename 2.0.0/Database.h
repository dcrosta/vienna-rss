//
//  Database.h
//  Vienna
//
//  Created by Steve on Tue Feb 03 2004.
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

#import <Foundation/Foundation.h>
#import "SQLDatabase.h"
#import "Folder.h"
#import "TreeNode.h"
#import "Field.h"
#import "Criteria.h"

@interface Database : NSObject {
	SQLDatabase * sqlDatabase;
	BOOL initializedFoldersArray;
	BOOL initializedSmartFoldersArray;
	BOOL readOnly;
	int databaseVersion;
	int countOfUnread;
	NSThread * mainThread;
	BOOL inTransaction;
	Folder * trashFolder;
	NSMutableArray * fieldsOrdered;
	NSMutableDictionary * fieldsByName;
	NSMutableDictionary * fieldsByTitle;
	NSMutableDictionary * foldersArray;
	NSMutableDictionary * smartFoldersArray;
}

// General database functions
+(Database *)sharedDatabase;
-(BOOL)initDatabase:(NSString *)databaseFileName;
-(void)syncLastUpdate;
-(int)databaseVersion;
-(void)beginTransaction;
-(void)commitTransaction;
-(void)compactDatabase;
-(int)countOfUnread;
-(BOOL)readOnly;
-(void)close;

// Fields functions
-(void)addField:(NSString *)name type:(int)type tag:(int)tag sqlField:(NSString *)sqlField visible:(BOOL)visible width:(int)width;
-(NSArray *)arrayOfFields;
-(Field *)fieldByName:(NSString *)name;

// Folder functions
-(void)initFolderArray;
-(int)trashFolderId;
-(NSArray *)arrayOfFolders:(int)parentID;
-(Folder *)folderFromID:(int)wantedId;
-(Folder *)folderFromFeedURL:(NSString *)wantedFeedURL;
-(Folder *)folderFromName:(NSString *)wantedName;
-(int)addFolder:(int)conferenceId folderName:(NSString *)name type:(int)type mustBeUnique:(BOOL)mustBeUnique;
-(BOOL)deleteFolder:(int)folderId;
-(BOOL)setFolderName:(int)folderId newName:(NSString *)newName;
-(BOOL)setFolderDescription:(int)folderId newDescription:(NSString *)newDescription;
-(BOOL)setFolderHomePage:(int)folderId newHomePage:(NSString *)newLink;
-(BOOL)setFolderFeedURL:(int)folderId newFeedURL:(NSString *)newFeedURL;
-(BOOL)setFolderUsername:(int)folderId newUsername:(NSString *)name;
-(void)flushFolder:(int)folderId;
-(void)releaseMessages:(int)folderId;
-(void)deleteDeletedMessages;
-(BOOL)markFolderRead:(int)folderId;
-(void)setFolderUnreadCount:(Folder *)folder adjustment:(int)adjustment;
-(void)setFolderLastUpdate:(int)folderId lastUpdate:(NSDate *)lastUpdate;
-(BOOL)setParent:(int)newParentID forFolder:(int)folderId;
-(BOOL)setBloglinesId:(int)folderId newBloglinesId:(long)bloglinesId;

// RSS folder functions
-(NSString *)untitledFeedFolderName;
-(NSArray *)arrayOfRSSFolders;
-(int)addRSSFolder:(NSString *)feedName underParent:(int)parentId subscriptionURL:(NSString *)url;

// smart folder functions
-(void)initSmartFoldersArray;
-(int)addSmartFolder:(NSString *)folderName underParent:(int)parentId withQuery:(CriteriaTree *)criteriaTree;
-(BOOL)updateSearchFolder:(int)folderId withFolder:(NSString *)folderName withQuery:(CriteriaTree *)criteriaTree;
-(CriteriaTree *)searchStringForSearchFolder:(int)folderId;
-(NSString *)criteriaToSQL:(CriteriaTree *)criteriaTree;

// Article functions
-(BOOL)createArticle:(int)folderID message:(Article *)message;
-(BOOL)deleteArticle:(int)folderId guid:(NSString *)guid;
-(NSArray *)arrayOfUnreadArticles:(int)folderId;
-(NSArray *)arrayOfArticles:(int)folderId filterString:(NSString *)filterString;
-(NSString *)articleText:(int)folderId guid:(NSString *)guid;
-(void)markArticleRead:(int)folderId guid:(NSString *)guid isRead:(BOOL)isRead;
-(void)markArticleFlagged:(int)folderId guid:(NSString *)guid isFlagged:(BOOL)isFlagged;
-(void)markArticleDeleted:(int)folderId guid:(NSString *)guid isDeleted:(BOOL)isDeleted;
@end
