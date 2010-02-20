//
//  PluginPreferences.h
//  Vienna
//
//  Created by Daniel Crosta on 2/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "ViennaPlugin.h"

@interface PluginPreferences : NSWindowController {
	NSArray * plugins;
	
	IBOutlet NSTableView * pluginList;
	IBOutlet NSView * subpane;
}

-(void)showContentViewForPlugin:(id<ViennaPlugin>)plugin;

@end
