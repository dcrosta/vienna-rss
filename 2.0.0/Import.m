//
//  Import.m
//  Vienna
//
//  Created by Steve on 5/27/05.
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

#import "Import.h"
#import "XMLParser.h"

@implementation AppController (Import)

/* importSubscriptions
 * Import an OPML file which lists RSS feeds.
 */
-(IBAction)importSubscriptions:(id)sender
{
	NSOpenPanel * panel = [NSOpenPanel openPanel];
	NSArray * fileTypes = [NSArray arrayWithObjects:@"txt", @"text", @"opml", NSFileTypeForHFSTypeCode('TEXT'), nil];
	
	[panel beginSheetForDirectory:nil
							 file:nil
							types:fileTypes
				   modalForWindow:mainWindow
					modalDelegate:self
				   didEndSelector:@selector(importOpenPanelDidEnd:returnCode:contextInfo:)
					  contextInfo:nil];
}

/* importOpenPanelDidEnd
 * Called when the user completes the Import open panel
 */
-(void)importOpenPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSOKButton)
	{
		[panel orderOut:self];
		[self importFromFile:[panel filename]];
	}
}

/* importSubscriptionGroup
 * Import one group of an OPML subscription tree.
 */
-(int)importSubscriptionGroup:(XMLParser *)tree underParent:(int)parentId
{
	int countImported = 0;
	int count = [tree countOfChildren];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		XMLParser * outlineItem = [tree treeByIndex:index];
		NSDictionary * entry = [outlineItem attributesForTree];
		NSString * feedTitle = [entry objectForKey:@"title"];
		NSString * feedDescription = [entry objectForKey:@"description"];
		NSString * feedURL = [entry objectForKey:@"xmlUrl"];
		NSString * feedHomePage = [entry objectForKey:@"htmlUrl"];
		if (feedURL == nil)
		{
			// This is a new group so try to create it. If there's an error then default to adding
			// the sub-group items under the parent.
			int folderId = [db addFolder:parentId folderName:feedTitle type:MA_Group_Folder mustBeUnique:YES];
			if (folderId == -1)
				folderId = MA_Root_Folder;
			countImported += [self importSubscriptionGroup:outlineItem underParent:folderId];
		}
		else
		{
			if ([db folderFromFeedURL:feedURL] == nil)
			{
				int folderId = [db addRSSFolder:feedTitle underParent:parentId subscriptionURL:feedURL];
				if (feedDescription != nil)
					[db setFolderDescription:folderId newDescription:feedDescription];
				if (feedHomePage != nil)
					[db setFolderHomePage:folderId newHomePage:feedHomePage];
				++countImported;
			}
		}
	}
	return countImported;
}

/* importFromFile
 * Import a list of RSS subscriptions.
 */
-(void)importFromFile:(NSString *)importFileName
{
	NSData * data = [NSData dataWithContentsOfFile:[importFileName stringByExpandingTildeInPath]];
	int countImported = 0;

	if (data != nil)
	{
		XMLParser * tree = [[XMLParser alloc] init];
		if ([tree setData:data])
		{
			XMLParser * bodyTree = [tree treeByPath:@"opml/body"];
			
			// Some OPML feeds organise exported subscriptions by groups. We can't yet handle those
			// so flatten the groups as we import.
			countImported = [self importSubscriptionGroup:bodyTree underParent:MA_Root_Folder];
		}
		[tree release];
	}

	// Announce how many we successfully imported
	NSString * successString = [NSString stringWithFormat:NSLocalizedString(@"%d subscriptions successfully imported", nil), countImported];
	NSRunAlertPanel(NSLocalizedString(@"RSS Subscription Import Title", nil), successString, NSLocalizedString(@"OK", nil), nil, nil);
}
@end
