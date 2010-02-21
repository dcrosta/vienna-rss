//
//  FolderPlugin.h
//  Vienna
//
//  Created by Daniel Crosta on 1/11/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "ViennaPlugin.h"
#import "Folder.h"

@protocol FolderPlugin <ViennaPlugin>

/* folderAdded:type:
 * A new folder was added. The folder is passed in, and
 * has already been saved.
 * 
 * folderType is one of the constants defined in Folder.h
 */
-(void)folderAdded:(Folder *)folder type:(int)folderType;

/* folderDeleted:type:
 * A folder was deleted. The folder is passed in, and
 * has not yet been deleted from the database.
 * 
 * folderType is one of the constants defined in Folder.h
 */
-(void)folderDeleted:(Folder *)folder type:(int)folderType;


/* folderNameChanged:oldName:type:
 * The name of a folder was changed. The folder is passed
 * in and has already been saved to the database. oldName
 * is the previous name of the folder.
 * 
 * folderType is one of the constants defined in Folder.h
 */
-(void)folderNameChanged:(Folder *)folder oldName:(NSString *)oldName type:(int)folderType;

/* folderURLChanged:oldURL:type:
 * The URL of a folder was changed. The folder is passed
 * in and has already been saved to the database. oldURL
 * is the previous URL of the folder (as a NSString).
 * 
 * folderType is one of the constants defined in Folder.h
 */
-(void)folderURLChanged:(Folder *)folder oldURL:(NSString *)oldURL type:(int)folderType;

/* folderSubscriptionChanged:oldSubscription:type:
 * The subscribed status of a folder was changed. The folder
 * is passed in and has already been saved to the database.
 * oldSubscribed is the previous subscribed state of the folder.
 * 
 * folderType is one of the constants defined in Folder.h
 */
-(void)folderSubscribedChanged:(Folder *)folder oldSubscribed:(BOOL)oldSubscribed type:(int)folderType;

/* folderAuthenticationChanged:oldUsername:oldPassword:type:
 * The username or password of a folder was changed. The folder
 * is passed in and has already been saved to the database.
 * oldUsername and oldPassword are the old username or password;
 * one of oldUsername or oldPassword may be nil (if it was not
 * changed by the user).
 * 
 * folderType is one of the constants defined in Folder.h
 */
-(void)folderAuthenticationChanged:(Folder *)folder oldUsername:(NSString *)oldUsername oldPassword:(NSString *)oldPassword type:(int)folderType;

@end
