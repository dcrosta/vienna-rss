//
//  ViennaPluginHelper.h
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "ViennaPlugin.h"

#import <Cocoa/Cocoa.h>

/* ViennaPluginHelper implements ViennaPlugin, but rather than
 * actually doing anything of its own when plugin methods are
 * called, it delegates to the actual loaded plugins. Order in
 * which plugins are called is consistent from one call to the
 * next, but not necessarily predictable (it is the order in
 * which plugins are loaded)
 */
@interface ViennaPluginHelper : NSObject <ViennaPlugin> {
	NSArray * plugins;
}

+(ViennaPluginHelper *)helper;

-(id)initWithPlugins:(NSArray *)thePlugins;
-(void)dealloc;

@end
