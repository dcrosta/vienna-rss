//
//  ViennaPluginHelper.m
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "PluginHelper.h"


// The default preferences object.
static PluginHelper * _sharedHelper = nil;

@interface PluginHelper (PrivateMethods)
-(NSArray *)arrayOfPluginsConformingToProtocol:(Protocol *)protocol excludingPlugins:(NSArray *)excludedPlugins;
@end

@implementation PluginHelper

@synthesize plugins;

-(id)initWithPlugins:(NSArray *)thePlugins
{
	if ((self = [super init]))
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
+(PluginHelper *)helper
{
	return _sharedHelper;
}

/* pluginWithName:
 * Return the plugin whose name isEqual to the given name,
 * or nil if no loaded plugin matches.
 */
-(id<ViennaPlugin>)pluginWithName:(NSString *)name
{
	for (id<ViennaPlugin> plugin in plugins)
	{
		if ([[plugin name] isEqual:name])
			return plugin;
	}
	return nil;
}

#pragma mark -
#pragma mark ViennaPlugin

/* startup
 * Called by Vienna at an appropriate time to initialize anything in the
 * plugin. Preferences has already been loaded, as have all NIBs.
 */
-(void)startup
{
	for (id<ViennaPlugin> plugin in [self arrayOfPluginsConformingToProtocol:@protocol(ViennaPlugin) excludingPlugins:nil])
	{
		[plugin startup];
	}
}

/* shutdown
 * Called by Vienna before quitting so that plugins can deinitialize
 * anything as necessary.
 */
-(void)shutdown
{
	for (id<ViennaPlugin> plugin in [self arrayOfPluginsConformingToProtocol:@protocol(ViennaPlugin) excludingPlugins:nil])
	{
		[plugin shutdown];
	}
}


/* preferencePaneView
 * Return a view to be used as the preference pane for this plugin.
 *
 * PluginHelper always returns nil for this method.
 */
-(NSView *)preferencePaneView
{
	return nil;
}

/* name
 * Return a human-friendly string name, which should be localized
 * if possible.
 *
 * PluginHelper returns a comma-separated list of names of all the
 * loaded plugins, to conform to the protocol; thus this method is
 * likely not very useful for regular usage. The returned string is
 * autoreleased.
 */
-(NSString *)name
{
	NSMutableArray * names = [NSMutableArray array];
	for (id<ViennaPlugin> plugin in [self arrayOfPluginsConformingToProtocol:@protocol(ViennaPlugin) excludingPlugins:nil])
	{
		[names addObject:[plugin name]];
	}
	return [names componentsJoinedByString:@", "];
}

#pragma mark -
#pragma mark RefreshPlugin

/* willRefreshArticles
 * Called by Vienna just before beginning refreshing articles.
 */
-(void)willRefreshArticles
{
	for (id<RefreshPlugin> plugin in [self arrayOfPluginsConformingToProtocol:@protocol(RefreshPlugin) excludingPlugins:nil])
	{
		[plugin willRefreshArticles];
	}
}

/* didRefreshArticles
 * Called by Vienna just after finishing refreshing articles.
 */
-(void)didRefreshArticles
{
	for (id<RefreshPlugin> plugin in [self arrayOfPluginsConformingToProtocol:@protocol(RefreshPlugin) excludingPlugins:nil])
	{
		[plugin didRefreshArticles];
	}
}

/* shouldDelayStartOfArticleRefresh
 * Return YES if RefreshManager should not begin refreshing
 * articles, e.g. if the plugin needs to do something first.
 *
 * PluginHelper returns YES if any plugin returns YES, and NO
 * otherwise.
 */
-(BOOL)shouldDelayStartOfArticleRefresh
{
	BOOL shouldDelay = NO;
	for (id<RefreshPlugin> plugin in [self arrayOfPluginsConformingToProtocol:@protocol(RefreshPlugin) excludingPlugins:nil])
	{
		shouldDelay |= [plugin shouldDelayStartOfArticleRefresh];
	}
	return shouldDelay;
}

/* shouldDelayEndOfArticleRefresh
 * Return YES if RefreshManager should not finish refreshing
 * articles, e.g. if the plugin needs to do something first.
 *
 * PluginHelper returns YES if any plugin returns YES, and NO
 * otherwise.
 */
-(BOOL)shouldDelayEndOfArticleRefresh
{
	BOOL shouldDelay = NO;
	for (id<RefreshPlugin> plugin in [self arrayOfPluginsConformingToProtocol:@protocol(RefreshPlugin) excludingPlugins:nil])
	{
		shouldDelay |= [plugin shouldDelayEndOfArticleRefresh];
	}
	return shouldDelay;
}

#pragma mark -
#pragma mark ArticlePlugin

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
	[self articleStateChanged:article
				wasMarkedRead:wasMarkedRead
			  wasMarkedUnread:wasMarkedUnread
				   wasFlagged:wasFlagged
				 wasUnFlagged:wasUnFlagged
				   wasDeleted:wasDeleted
				 wasUnDeleted:wasUnDeleted
			   wasHardDeleted:wasHardDeleted
			 excludingPlugins:nil];
}


/* articleStateChanged
 * Called by Vienna after an article's state has changed. only one of the
 * four BOOL arguments will be set to YES in any valid message. Will not
 * send articleStateChanged to any plugin listed in excludedPlugins
 */
-(void)articleStateChanged:(Article *)article
			 wasMarkedRead:(BOOL)wasMarkedRead
		   wasMarkedUnread:(BOOL)wasMarkedUnread
				wasFlagged:(BOOL)wasFlagged
			  wasUnFlagged:(BOOL)wasUnFlagged
				wasDeleted:(BOOL)wasDeleted
			  wasUnDeleted:(BOOL)wasUnDeleted
			wasHardDeleted:(BOOL)wasHardDeleted
		  excludingPlugins:(NSArray *)excludedPlugins
{
	for (id<ArticlePlugin> plugin in [self arrayOfPluginsConformingToProtocol:@protocol(ArticlePlugin) excludingPlugins:excludedPlugins])
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



#pragma mark -
#pragma mark PrivateMethods

/* arrayOfPluginsConformingToProtocol:
 * Return an auto-released array containing only those plugins
 * in [self plugins] which conform to the given protocol.
 */
-(NSArray *)arrayOfPluginsConformingToProtocol:(Protocol *)protocol excludingPlugins:(NSArray *)excludedPlugins
{
	NSMutableArray * protocolPlugins = [NSMutableArray array];
	for (id plugin in plugins)
	{
		if ([plugin conformsToProtocol:protocol] && ![excludedPlugins containsObject:plugin])
		{
			[protocolPlugins addObject:plugin];
		}
	}
	return [NSArray arrayWithArray:protocolPlugins];
}

@end
