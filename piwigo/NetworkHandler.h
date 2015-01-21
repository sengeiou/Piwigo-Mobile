//
//  NetworkHandler.h
//  WordSearch
//
//  Created by Spencer Baker on 9/10/14.
//  Copyright (c) 2014 CS 3450. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^SuccessBlock)(id responseObject);

FOUNDATION_EXPORT NSString * const kPiwigoSessionLogin;
FOUNDATION_EXPORT NSString * const kPiwigoSessionGetStatus;



@interface NetworkHandler : NSObject

+(AFHTTPRequestOperation*)getPost:(NSString*)path success:(SuccessBlock)success;

+(AFHTTPRequestOperation*)post:(NSString*)path
				 URLParameters:(NSDictionary*)urlParams
					parameters:(NSDictionary*)parameters
					   success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
					   failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))fail;

@end
