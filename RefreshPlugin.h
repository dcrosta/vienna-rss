//
//  RefreshPlugin.h
//  Vienna
//
//  Created by Daniel Crosta on 2/10/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "ViennaPlugin.h"

/* RefreshPlugin
 * This protocol is implemented by plugins that wish to recieve
 * notifications about, and optionally modify, the refresh process.
 */
@protocol RefreshPlugin <ViennaPlugin>

/* willRefreshArticles
 * Called by Vienna just before beginning refreshing articles.
 */
-(void)willRefreshArticles;

/* didRefreshArticles
 * Called by Vienna just after finishing refreshing articles.
 */
-(void)didRefreshArticles;

/* shouldDelayStartOfArticleRefresh
 * Return YES if RefreshManager should not begin refreshing
 * articles, e.g. if the plugin needs to do something first.
 */
-(BOOL)shouldDelayStartOfArticleRefresh;

/* shouldDelayEndOfArticleRefresh
 * Return YES if RefreshManager should not finish refreshing
 * articles, e.g. if the plugin needs to do something first.
 */
-(BOOL)shouldDelayEndOfArticleRefresh;

@end