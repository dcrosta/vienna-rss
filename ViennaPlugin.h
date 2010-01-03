//
//  ViennaPlugin.h
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "Message.h"

#import <Cocoa/Cocoa.h>


@protocol ViennaPlugin


/* initialize
 * Called by Vienna at an appropriate time to initialize anything in the
 * plugin. Preferences has already been loaded, as have all NIBs.
 */
-(void)initialize;

/* deInitialize
 * Called by Vienna before quitting so that plugins can deinitialize
 * anything as necessary.
 */
-(void)deInitialize;

/* willRefreshArticles
 * Called by Vienna just before beginning refreshing articles.
 */
-(void)willRefreshArticles;

/* didRefreshArticles
 * Called by Vienna just after finishing refreshing articles.
 */
-(void)didRefreshArticles;

/* articleStateChanged
 * Called by Vienna after an article's state has changed. only one of the
 * four BOOL arguments will be set to YES in any valid message.
 */
-(void)articleStateChanged:(Article *)article
			 wasMarkedRead:(BOOL)wasMarkedRead
		   wasMarkedUnread:(BOOL)wasMarkedUnread
				wasFlagged:(BOOL)wasFlagged
			  wasUnFlagged:(BOOL)wasUnFlagged
				wasDeleted:(BOOL)wasDeleted
			  wasUnDeleted:(BOOL)wasUnDeleted
			wasHardDeleted:(BOOL)wasHardDeleted;

@end
