//
//  ViennaPluginHelper.h
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "ViennaPlugin.h"
#import "ArticlePlugin.h"
#import "FolderPlugin.h"
#import "RefreshPlugin.h"

#import <Cocoa/Cocoa.h>

/* PluginHelper implements the *Plugin protocols, but rather
 * than actually doing anything of its own when plugin methods
 * are called, it delegates to the loaded plugins. Order
 * in which plugins are called is consistent from one call
 * to the next, but not necessarily predictable (it is the
 * order in which plugins are loaded)
 */
@interface PluginHelper : NSObject </*ViennaPlugin, */ArticlePlugin, FolderPlugin, RefreshPlugin> {
	NSArray * plugins;
}

@property (readonly) NSArray * plugins;

+(PluginHelper *)helper;

-(id)initWithPlugins:(NSArray *)thePlugins;
-(void)dealloc;
-(id<ViennaPlugin>)pluginWithName:(NSString *)name;

// helper that can be called by a plugin when it changes
// the state of an article but does not wish to inform
// itself or specific other plugins
-(void)articleStateChanged:(Article *)article
			 wasMarkedRead:(BOOL)wasMarkedRead
		   wasMarkedUnread:(BOOL)wasMarkedUnread
				wasFlagged:(BOOL)wasFlagged
			  wasUnFlagged:(BOOL)wasUnFlagged
				wasDeleted:(BOOL)wasDeleted
			  wasUnDeleted:(BOOL)wasUnDeleted
			wasHardDeleted:(BOOL)wasHardDeleted
		  excludingPlugins:(NSArray *)excludedPlugins;

@end
