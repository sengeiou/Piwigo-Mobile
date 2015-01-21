//
//  NetworkHandler.m
//  WordSearch
//
//  Created by Spencer Baker on 9/10/14.
//  Copyright (c) 2014 CS 3450. All rights reserved.
//

#import "NetworkHandler.h"
#import "Model.h"

NSString * const kPiwigoSessionLogin = @"format=json&method=pwg.session.login";
NSString * const kPiwigoSessionGetStatus = @"format=json&method=pwg.session.getStatus";

@interface NetworkHandler()

@property (nonatomic, retain) NSMutableData *responseData;
@property (nonatomic, retain) NSURLConnection *connection;
@property (nonatomic, retain) NSDictionary *dictionary;
@property (nonatomic, assign) SEL action;
@property (nonatomic, copy) SuccessBlock block;

@end

@implementation NetworkHandler

+(AFHTTPRequestOperation*)getPost:(NSString*)path success:(SuccessBlock)success
{
	AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
	
	AFJSONResponseSerializer *jsonResponseSerializer = [AFJSONResponseSerializer serializer];
	NSMutableSet *jsonAcceptableContentTypes = [NSMutableSet setWithSet:jsonResponseSerializer.acceptableContentTypes];
	[jsonAcceptableContentTypes addObject:@"text/plain"];
	jsonResponseSerializer.acceptableContentTypes = jsonAcceptableContentTypes;
	
	manager.responseSerializer = jsonResponseSerializer;
	
	return [manager POST:[NSString stringWithFormat:@"%@format=json&method=pwg.categories.getImages&cat_id=5&per_page=100&page=10", @"http://pwg.bakercrew.com/piwigo/ws.php?"]
			  parameters:nil
				 success:^(AFHTTPRequestOperation *operation, id responseObject) {
					 success(responseObject);
				 } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
					 
					 NSLog(@"getPost error: %@", error);
				 }];
}

// path: format={param1}
// URLParams: {@"param1" : @"hello" }
+(AFHTTPRequestOperation*)post:(NSString*)path
				 URLParameters:(NSDictionary*)urlParams
					parameters:(NSDictionary*)parameters
					   success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
					   failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))fail
{
	AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
		
	AFJSONResponseSerializer *jsonResponseSerializer = [AFJSONResponseSerializer serializer];
	NSMutableSet *jsonAcceptableContentTypes = [NSMutableSet setWithSet:jsonResponseSerializer.acceptableContentTypes];
	[jsonAcceptableContentTypes addObject:@"text/plain"];
	jsonResponseSerializer.acceptableContentTypes = jsonAcceptableContentTypes;
	manager.responseSerializer = jsonResponseSerializer;
	
	return [manager POST:[NetworkHandler getURLWithPath:path andURLParams:urlParams]
			  parameters:parameters
				 success:success
				 failure:fail];
}

+(NSString*)getURLWithPath:(NSString*)path andURLParams:(NSDictionary*)params
{
	NSString *url = [NSString stringWithFormat:@"http://%@/ws.php?%@", [Model sharedInstance].serverName, path];

	for(NSString *parameter in params)
	{
		url = [url stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"{%@}", parameter] withString:[params objectForKey:parameter]];
	}
	
	return url;
}

@end
