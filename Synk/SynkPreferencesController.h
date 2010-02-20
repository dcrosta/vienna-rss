//
//  SynkPreferencesController.h
//  Vienna
//
//  Created by Daniel Crosta on 2/19/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "ASIHTTPRequest.h"

@class SynkPlugin;

@interface SynkPreferencesController : NSObject {
	SynkPlugin * synkPlugin;
	
	NSView * preferencesView;
	
	IBOutlet NSTextField * usernameField;
	IBOutlet NSTextField * passwordField;
	IBOutlet NSTextField * synkCacheInfoLabel;
	IBOutlet NSProgressIndicator * testSpinner;
	IBOutlet NSImageView * testSuccessOrFailureImage;
	
	NSDateFormatter * dateFormatter;
}

-(NSView *)preferencesView;
-(void)handleSynkUpdateNotification:(NSNotification *)notification;
-(void)setCacheInfoLabel;

-(IBAction)testSynkLogin:(id)sender;
-(void)usernameChanged:(NSNotification *)notification;
-(void)passwordChanged:(NSNotification *)notification;

-(IBAction)clickedSignupButton:(id)sender;

// KVC compliance methods
-(NSString *)username;
-(void)setUsername:(NSString *)username;
-(NSString *)password;
-(void)setPassword:(NSString *)password;
-(BOOL)syncArticleEvents;
-(void)setSyncArticleEvents:(BOOL)syncArticleEvents;
-(BOOL)syncFolderEvents;
-(void)setSyncFolderEvents:(BOOL)syncFolderEvents;

// ASIHTTPRequest delegate
-(void)requestFinished:(ASIHTTPRequest *)request;
-(void)requestFailed:(ASIHTTPRequest *)request;
-(void)testDidSucceed:(BOOL)succeeded;

@end
