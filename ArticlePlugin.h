//
//  ArticlePlugin.h
//  Vienna
//
//  Created by Daniel Crosta on 1/11/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "ViennaPlugin.h"
#import "Message.h"

#import <Cocoa/Cocoa.h>


@protocol ArticlePlugin <ViennaPlugin>

/* articleStateChanged
 * Called by Vienna after an article's state has changed. Only one
 * of the BOOL arguments will be set to YES in any valid message.
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
