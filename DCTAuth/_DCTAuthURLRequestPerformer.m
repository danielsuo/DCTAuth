//
//  _DCTAuthURLRequestPerformer.m
//  DCTAuth
//
//  Created by Daniel Tull on 20.01.2013.
//  Copyright (c) 2013 Daniel Tull. All rights reserved.
//

#import "_DCTAuthURLRequestPerformer.h"

@implementation _DCTAuthURLRequestPerformer

+ (_DCTAuthURLRequestPerformer *)sharedURLRequestPerformer {
	static _DCTAuthURLRequestPerformer *URLRequestPerformer;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		URLRequestPerformer = [self new];
	});
	return URLRequestPerformer;
}

- (void)performRequest:(NSURLRequest *)URLRequest withHandler:(DCTAuthRequestHandler)handler {

	if (self.URLRequestPerformer != NULL) {
		self.URLRequestPerformer(URLRequest, handler);
		return;
	}

	[NSURLConnection sendAsynchronousRequest:URLRequest queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {

		NSHTTPURLResponse *HTTPURLResponse = nil;
        if ([response isKindOfClass:[NSHTTPURLResponse class]])
            HTTPURLResponse = (NSHTTPURLResponse *)response;

		handler(data, HTTPURLResponse, error);
	}];
}

@end