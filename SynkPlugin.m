//
//  SynkBundle.m
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "SynkPlugin.h"


@implementation SynkPlugin

// called by Vienna at an appropriate time to initialize anything in the
// plugin. Preferences has already been loaded, as have all NIBs
-(void)initialize
{
	dummyString = @"OK, it was loaded now";
}

/* deInitialize
 * Called by Vienna before quitting so that plugins can deinitialize
 * anything as necessary.
 */
-(void)deInitialize
{
	[dummyString release];
}

// called by Vienna just before beginning refreshing articles
-(void)willRefreshArticles
{
	
}

// called by Vienna just after finishing refreshing articles
-(void)didRefreshArticles
{
	
}

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
	NSString * action;
	if (wasMarkedRead)
		action = @"marked read";
	else if (wasMarkedUnread)
		action = @"marked unread";
	else if (wasFlagged)
		action = @"marked flagged";
	else if (wasUnFlagged)
		action = @"marked unflagged";
	else if (wasDeleted)
		action = @"deleted";
	else if (wasUnDeleted)
		action = @"undeleted";
	else if (wasHardDeleted)
		action = @"hard deleted";
	
	NSLog(@"article %@ was %@", article, action);
}

@end
