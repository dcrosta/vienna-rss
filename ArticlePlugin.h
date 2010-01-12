//
//  ArticlePlugin.h
//  Vienna
//
//  Created by Daniel Crosta on 1/11/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "ViennaPlugin.h"

#import <Cocoa/Cocoa.h>


@protocol ArticlePlugin <ViennaPlugin>

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
