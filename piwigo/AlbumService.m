//
//  AlbumService.m
//  piwigo
//
//  Created by Spencer Baker on 1/24/15.
//  Copyright (c) 2015 bakercrew. All rights reserved.
//

#import "AlbumService.h"
#import "PiwigoAlbumData.h"
#import "Model.h"
#import "CategoriesData.h"

@implementation AlbumService

+(AFHTTPRequestOperation*)getAlbumListOnCompletion:(void (^)(AFHTTPRequestOperation *operation, NSArray *albums))completion
									   onFailure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))fail
{
	return [self post:kPiwigoCategoriesGetList
		URLParameters:nil
		   parameters:nil
			  success:^(AFHTTPRequestOperation *operation, id responseObject) {
				  
				  if([[responseObject objectForKey:@"stat"] isEqualToString:@"ok"])
				  {
					  NSArray *albums = [AlbumService parseAlbumJSON:[[responseObject objectForKey:@"result"] objectForKey:@"categories"]];
					  [[CategoriesData sharedInstance] addAllCategories:albums];
					  if(completion)
					  {
						  completion(operation, albums);
					  }
				  }
				  else
				  {
					  if(completion)
					  {
						  completion(operation, nil);
					  }
				  }
			  } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
				  
				  if(fail) {
					  fail(operation, error);
				  }
			  }];
}

+(NSArray*)parseAlbumJSON:(NSArray*)json
{
	NSMutableArray *albums = [NSMutableArray new];
	for(NSDictionary *category in json)
	{
		PiwigoAlbumData *albumData = [PiwigoAlbumData new];
		albumData.albumId = [[category objectForKey:@"id"] integerValue];
		
		if([category objectForKey:@"id_uppercat"] == [NSNull null])
		{
			albumData.parentAlbumId = 0;
		}
		else
		{
			albumData.parentAlbumId = [[category objectForKey:@"id_uppercat"] integerValue];
		}
		
		
		albumData.name = [category objectForKey:@"name"];
		albumData.comment = [category objectForKey:@"comment"];
		albumData.globalRank = [[category objectForKey:@"global_rank"] floatValue];
		albumData.numberOfImages = [[category objectForKey:@"nb_images"] integerValue];
		albumData.numberOfSubAlbumImages = [[category objectForKey:@"total_nb_images"] integerValue];
		albumData.numberOfSubCategories = [[category objectForKey:@"nb_categories"] integerValue];
		
		id thumbId = [category objectForKey:@"representative_picture_id"];
		if(thumbId != [NSNull null]) {
			albumData.albumThumbnailId = [[category objectForKey:@"representative_picture_id"] integerValue];
			albumData.albumThumbnailUrl = [category objectForKey:@"tn_url"];
		}
		
		if([category objectForKey:@"max_date_last"] != [NSNull null])
		{
			NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
			[dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:[Model sharedInstance].language]];
			albumData.dateLast = [dateFormatter dateFromString:[category objectForKey:@"max_date_last"]];
		}
		
		[albums addObject:albumData];
	}
	
	return albums;
}

+(AFHTTPRequestOperation*)createCategoryWithName:(NSString*)categoryName
									OnCompletion:(void (^)(AFHTTPRequestOperation *operation, BOOL createdSuccessfully))completion
									   onFailure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))fail
{
	return [self post:kPiwigoCategoriesAdd
		URLParameters:@{@"name" : [categoryName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]}
		   parameters:nil
			  success:^(AFHTTPRequestOperation *operation, id responseObject) {
				  
				  if(completion)
				  {
					  completion(operation, [[responseObject objectForKey:@"stat"] isEqualToString:@"ok"]);
				  }
			  } failure:fail];
}

@end
