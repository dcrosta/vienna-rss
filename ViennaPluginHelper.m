//
//  ViennaPluginHelper.m
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "ViennaPluginHelper.h"


// The default preferences object.
static ViennaPluginHelper * _sharedHelper = nil;


@implementation ViennaPluginHelper

-(id)initWithPlugins:(NSArray *)thePlugins
{
	if ((self = [super init]) != nil)
	{
		plugins = [thePlugins retain];
	}
	_sharedHelper = self;
	return self;
}

-(void)dealloc
{
	[plugins release];
	[super dealloc];
}

/* helper
 * return the singleton ViennaPluginHelper instance
 */
+(ViennaPluginHelper *)helper
{
	return _sharedHelper;
}

/* initialize
 * Called by Vienna at an appropriate time to initialize anything in the
 * plugin. Preferences has already been loaded, as have all NIBs.
 */
-(void)initialize
{
	for (id<ViennaPlugin> plugin in plugins)
	{
		[plugin initialize];
	}
}

/* deInitialize
 * Called by Vienna before quitting so that plugins can deinitialize
 * anything as necessary.
 */
-(void)deInitialize
{
	for (id<ViennaPlugin> plugin in plugins)
	{
		[plugin deInitialize];
	}
}


/* willRefreshArticles
 * Called by Vienna just before beginning refreshing articles.
 */
-(void)willRefreshArticles
{
	for (id<ViennaPlugin> plugin in plugins)
	{
		[plugin willRefreshArticles];
	}
}

/* didRefreshArticles
 * Called by Vienna just after finishing refreshing articles.
 */
-(void)didRefreshArticles
{
	for (id<ViennaPlugin> plugin in plugins)
	{
		[plugin didRefreshArticles];
	}
}

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
			wasHardDeleted:(BOOL)wasHardDeleted
{
	for (id<ViennaPlugin> plugin in plugins)
	{
		[plugin articleStateChanged:article
					  wasMarkedRead:wasMarkedRead
					wasMarkedUnread:wasMarkedUnread
						 wasFlagged:wasFlagged
					   wasUnFlagged:wasUnFlagged
						 wasDeleted:wasDeleted
					   wasUnDeleted:wasUnDeleted
					 wasHardDeleted:wasHardDeleted];
	}
}


@end
