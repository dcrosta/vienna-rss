//
//  SynkBundle.h
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "ArticlePlugin.h"
#import "FolderPlugin.h"

#import <Cocoa/Cocoa.h>

@interface SynkPlugin : NSObject <ArticlePlugin, FolderPlugin> {

}


@end
