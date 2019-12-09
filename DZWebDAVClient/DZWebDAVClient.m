//
//  DZWebDAVClient.m
//  DZWebDAVClient
//

#import <AFNetworking/AFNetworking.h>
#import "DZWebDAVClient.h"
#import "DZDictionaryResponseSerializer.h"
#import "NSDate+RFC1123.h"
#import "NSDate+ISO8601.h"
#import "DZWebDAVLock.h"

NSString const *DZWebDAVETagKey				= @"getetag";
NSString const *DZWebDAVCTagKey				= @"getctag";
NSString const *DZWebDAVLastModifiedDateKey	= @"modificationdate";
NSString const *DZWebDAVContentTypeKey		= @"getcontenttype";
NSString const *DZWebDAVContentLengthKey	= @"getcontentlength";
NSString const *DZWebDAVCreationDateKey		= @"creationdate";

@interface DZWebDAVClient()
- (NSURLSessionTask *)mr_listPath:(NSString *)path
                            depth:(NSUInteger)depth
                          success:(void(^)(NSURLSessionDataTask *, id))success
                          failure:(void(^)(NSURLSessionDataTask *, NSError *))failure;

@property (nonatomic, strong) NSFileManager *fileManager;
@end

@implementation DZWebDAVClient

@synthesize fileManager = _fileManager;

- (id)initWithBaseURL:(NSURL *)url {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForRequest = 60;
    
    if ((self = [super initWithBaseURL:url sessionConfiguration:config])) {
		self.fileManager = [NSFileManager defaultManager];

        self.responseSerializer = [DZDictionaryResponseSerializer serializer];
        //NSArray *allowedHTTPMethods = @[@"GET", @"MKCOL", @"PUT", @"PROPFIND", @"LOCK", @"UNLOCK"];
        //return [allowedHTTPMethods containsObject:urlRequest.HTTPMethod] || [super canProcessRequest:urlRequest];

    }
    return self;
}

- (NSURLSessionDataTask *)mr_taskWithRequest:(NSURLRequest *)request success:(void(^)(void))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    __block NSURLSessionDataTask *dataTask = nil;
    dataTask = [self dataTaskWithRequest:request
                          uploadProgress:nil
                        downloadProgress:nil
                       completionHandler:^(NSURLResponse * __unused response, id responseObject, NSError *error) {
        if (error) {
            if (failure) {
                failure(dataTask, error);
            }
        } else {
            if (success) {
                success();
            }
        }
    }];

    return dataTask;
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters {
    if ([path rangeOfString:@"remote.php/webdav"].location == NSNotFound) {
        path = [NSString stringWithFormat:@"remote.php/webdav/%@", path];
    }

    NSString *URLString = [NSURL URLWithString:path relativeToURL:self.baseURL].absoluteString;
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:method URLString:URLString parameters:parameters error:nil];
    return request;
}

- (NSURLSessionTask *)copyPath:(NSString *)source toPath:(NSString *)destination success:(void(^)(void))success
                       failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    NSString *destinationPath = [[self.baseURL URLByAppendingPathComponent:destination] absoluteString];
    NSMutableURLRequest *request = [self requestWithMethod:@"COPY" path:source parameters:nil];
    [request setValue:destinationPath forHTTPHeaderField:@"Destination"];
	[request setValue:@"T" forHTTPHeaderField:@"Overwrite"];
    
	NSURLSessionDataTask *task = [self mr_taskWithRequest:request success:success failure:failure];
    [task resume];
    return task;
}

- (NSURLSessionTask *)movePath:(NSString *)source toPath:(NSString *)destination success:(void(^)(void))success
                       failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    NSString *destinationPath = [[self.baseURL URLByAppendingPathComponent:destination] absoluteString];
    NSMutableURLRequest *request = [self requestWithMethod:@"MOVE" path:source parameters:nil];
    [request setValue:destinationPath forHTTPHeaderField:@"Destination"];
	[request setValue:@"T" forHTTPHeaderField:@"Overwrite"];
    
    NSURLSessionDataTask *task = [self mr_taskWithRequest:request success:success failure:failure];
    [task resume];
    return task;
}

- (NSURLSessionTask *)deletePath:(NSString *)path success:(void(^)(void))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    NSMutableURLRequest *request = [self requestWithMethod:@"DELETE" path:path parameters:nil];
    
    NSURLSessionDataTask *task = [self mr_taskWithRequest:request success:success failure:failure];
    [task resume];
    return task;
}

- (NSURLSessionTask *)getPath:(NSString *)remoteSource success:(void(^)(NSURLSessionDataTask *, id))success
                      failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    return [self GET:remoteSource parameters:nil progress:nil success:success failure:failure];
}

- (void)getPaths:(NSArray *)remoteSources progressBlock:(void(^)(NSUInteger, NSUInteger))progressBlock completionBlock:(void(^)(NSArray *))completionBlock {
	NSMutableArray *requests = [NSMutableArray arrayWithCapacity:remoteSources.count];
    NSMutableArray *tasks = [NSMutableArray arrayWithCapacity:remoteSources.count];
    
    dispatch_group_t group = dispatch_group_create();
    
	[remoteSources enumerateObjectsUsingBlock:^(NSString *remotePath, NSUInteger idx, BOOL *stop) {
        dispatch_group_enter(group);
        
        [self GET:remotePath parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            if (progressBlock) {
                progressBlock(tasks.count, remoteSources.count);
            }
            [tasks addObject:task];
            dispatch_group_leave(group);
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            if (progressBlock) {
                progressBlock(tasks.count, remoteSources.count);
            }
            dispatch_group_leave(group);
        }];
        
		NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:remotePath parameters:nil];
		[requests addObject:request];
	}];
    
    dispatch_group_notify(group, self.completionQueue ?: dispatch_get_main_queue(), ^{
        if (completionBlock) {
            completionBlock(tasks);
        }
    });
}

- (NSURLSessionTask *)mr_listPath:(NSString *)path depth:(NSUInteger)depth success:(void(^)(NSURLSessionDataTask *, id))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
	NSParameterAssert(success);
    
	NSMutableURLRequest *request = [self requestWithMethod:@"PROPFIND" path:path parameters:nil];
	
    NSString *depthHeader = nil;
	if (depth <= 0)
		depthHeader = @"0";
	else if (depth == 1)
		depthHeader = @"1";
	else
		depthHeader = @"infinity";
    
    [request setValue: depthHeader forHTTPHeaderField: @"Depth"];
    [request setHTTPBody:[@"<?xml version=\"1.0\" encoding=\"utf-8\" ?><a:propfind xmlns:a=\"DAV:\"><a:allprop/></a:propfind>" dataUsingEncoding:NSUTF8StringEncoding]];
    [request setValue:@"application/xml" forHTTPHeaderField:@"Content-Type"];
    
    __block NSURLSessionDataTask *task;
    task = [self dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil
            completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) {
                failure(task, error);
            }
            return;
        }
		if (responseObject == nil || ![responseObject isKindOfClass:[NSDictionary class]]) {
            if (failure) {
                NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
                NSError *error;
                if (statusCode == 403) {
                    error = [NSError errorWithDomain:AFURLResponseSerializationErrorDomain code:statusCode userInfo: @{
                        NSLocalizedDescriptionKey: _(@"Access denied")
                    }];
                } else {
                    error = [NSError errorWithDomain:AFURLResponseSerializationErrorDomain code:NSURLErrorCannotParseResponse userInfo:nil];
                }
                failure(task, error);
            }
            return;
        }
        
		id checkItems = [responseObject valueForKeyPath:@"multistatus.response.propstat.prop"];
        id checkHrefs = [responseObject valueForKeyPath:@"multistatus.response.href"];
		
		NSArray *objects = [checkItems isKindOfClass:[NSArray class]] ? checkItems : @[ checkItems ],
		*keys = [checkHrefs isKindOfClass:[NSArray class]] || checkHrefs == nil ? checkHrefs : @[ checkHrefs ];
		
		NSDictionary *unformattedDict = [NSDictionary dictionaryWithObjects: objects forKeys: keys];
		NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity: unformattedDict.count];
		
		[unformattedDict enumerateKeysAndObjectsUsingBlock:^(NSString *absoluteKey, id possibleArrayOrDict, BOOL *stop) {
			// filter out Finder thumbnail files (._filename), they get us screwed up.
			if ([absoluteKey.lastPathComponent hasPrefix: @"._"])
				return;

            NSDictionary *unformatted = [possibleArrayOrDict isKindOfClass:[NSDictionary class]] ? (NSDictionary *)possibleArrayOrDict : (NSDictionary *)[possibleArrayOrDict objectAtIndex:0];
			
			// Replace an absolute path with a relative one
			NSString *key = [absoluteKey stringByReplacingOccurrencesOfString:@"/remote.php/webdav" withString:@""];
			if ([[key substringToIndex:1] isEqualToString:@"/"])
				key = [key substringFromIndex:1];
			
			// reformat the response dictionaries into usable values
			NSMutableDictionary *object = [NSMutableDictionary dictionary];
			
            NSString *origCreationDate = [unformatted objectForKey: DZWebDAVCreationDateKey];
            NSDate *creationDate = [NSDate dateFromRFC1123String: origCreationDate] ?: [NSDate dateFromISO8601String: origCreationDate] ?: nil;
			
			NSString *origModificationDate = [unformatted objectForKey: DZWebDAVLastModifiedDateKey] ?: [unformatted objectForKey: @"getlastmodified"];
			NSDate *modificationDate = [NSDate dateFromRFC1123String: origModificationDate] ?: [NSDate dateFromISO8601String: origModificationDate] ?: nil;
			
			if ([unformatted objectForKey:DZWebDAVETagKey] != nil) {
                [object setObject:[unformatted objectForKey:DZWebDAVETagKey] forKey:DZWebDAVETagKey];
			}
            if ([unformatted objectForKey:DZWebDAVLastModifiedDateKey] != nil) {
                [object setObject:[unformatted objectForKey:DZWebDAVLastModifiedDateKey] forKey:DZWebDAVLastModifiedDateKey];
            }
			if ([unformatted objectForKey:DZWebDAVContentTypeKey] != nil) {
                [object setObject:[unformatted objectForKey:DZWebDAVContentTypeKey] forKey:DZWebDAVContentTypeKey];
            }
            if ([unformatted objectForKey:DZWebDAVContentLengthKey] != nil) {
                [object setObject:[unformatted objectForKey:DZWebDAVContentLengthKey] forKey:DZWebDAVContentLengthKey];
            }
            if (creationDate != nil) {
                [object setObject:creationDate forKey:DZWebDAVCreationDateKey];
            }
            if (modificationDate != nil) {
                [object setObject:modificationDate forKey:DZWebDAVLastModifiedDateKey];
            }
			
			[dict setObject: object forKey: key];
		}];
		
        if (success) {
			success(task, dict);
        }
	}];
    
    [task resume];
    return task;
}

- (NSURLSessionTask *)propertiesOfPath:(NSString *)path success:(void(^)(NSURLSessionDataTask *, id ))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
	return [self mr_listPath:path depth:0 success:success failure:failure];
}

- (NSURLSessionTask *)listPath:(NSString *)path success:(void(^)(NSURLSessionDataTask *, id))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
	return [self mr_listPath:path depth:1 success:success failure:failure];
}

- (NSURLSessionTask *)listPath:(NSString *)path recursive:(BOOL)recursive success:(void(^)(NSURLSessionDataTask *, id))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    return [self mr_listPath:path depth:recursive ? 2 : 1 success:success failure:failure];
}

- (NSURLSessionTask *)recursiveListPath:(NSString *)path success:(void(^)(NSURLSessionDataTask *, id))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
	return [self mr_listPath:path depth:2 success:success failure:failure];
}

- (NSURLSessionTask *)downloadPath:(NSString *)remoteSource
                             toURL:(NSURL *)localDestination
                          progress:(void(^)(long long totalBytesRead, long long totalBytesExpectedToRead))progressBlock
                           success:(void(^)(void))success
                           failure:(void(^)(NSURLSessionDownloadTask *, NSError *))failure {
	if ([self.fileManager respondsToSelector:@selector(createDirectoryAtURL:withIntermediateDirectories:attributes:error:) ]) {
		[self.fileManager createDirectoryAtURL: [localDestination URLByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: nil error: NULL];
	} else {
		[self.fileManager createDirectoryAtPath: [localDestination.path stringByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: nil error: NULL];
	}
	NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:remoteSource parameters:nil];

    __block NSURLSessionDownloadTask *task;
    task = [self downloadTaskWithRequest:request progress:^(NSProgress * _Nonnull downloadProgress) {
        if (progressBlock) {
            progressBlock(downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
        }
    } destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return localDestination;
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        if (error) {
            if (failure) {
                failure(task, error);
            }
        } else {
            if (success) {
                success();
            }
        }
    }];

    [task resume];
    return task;
}

- (NSArray *)downloadPaths:(NSArray *)remoteSources toURL:(NSURL *)localFolder progressBlock:(void(^)(NSUInteger, NSUInteger))progressBlock completionBlock:(void(^)(NSArray *))completionBlock {
	BOOL hasURL = YES;
	if ([self.fileManager respondsToSelector:@selector(createDirectoryAtURL:withIntermediateDirectories:attributes:error:)]) {
		[self.fileManager createDirectoryAtURL: localFolder withIntermediateDirectories: YES attributes: nil error: NULL];
	} else {
		[self.fileManager createDirectoryAtPath: localFolder.path withIntermediateDirectories: YES attributes: nil error: NULL];
		hasURL = NO;
	}

    NSMutableArray *tasks = [NSMutableArray arrayWithCapacity:remoteSources.count];
    
    dispatch_group_t group = dispatch_group_create();

    [remoteSources enumerateObjectsUsingBlock:^(NSString *remotePath, NSUInteger idx, BOOL *stop) {
        dispatch_group_enter(group);
        
        NSURL *localDestination = hasURL ? [localFolder URLByAppendingPathComponent: remotePath isDirectory: [remotePath hasSuffix:@"/"]]
        : [NSURL URLWithString: remotePath relativeToURL: localFolder];

        NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:remotePath parameters:nil];
        
        __block NSURLSessionDownloadTask *task;
        task = [self downloadTaskWithRequest:request progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
            return localDestination;
        } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
            if (progressBlock) {
                progressBlock(tasks.count, remoteSources.count);
            }
            [tasks addObject:task];
            dispatch_group_leave(group);
        }];
        [task resume];
	}];
    
    dispatch_group_notify(group, self.completionQueue ?: dispatch_get_main_queue(), ^{
        if (completionBlock) {
            completionBlock(tasks);
        }
    });

    return tasks;
}

- (NSURLSessionTask *)makeCollection:(NSString *)path success:(void(^)(void))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
	NSURLRequest *request = [self requestWithMethod:@"MKCOL" path:path parameters:nil];	
	NSURLSessionDataTask *task = [self mr_taskWithRequest:request success:success failure:failure];

    [task resume];
    return task;
}

- (NSURLSessionTask *)put:(NSData *)data path:(NSString *)remoteDestination success:(void(^)(void))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    NSMutableURLRequest *request = [self requestWithMethod:@"PUT" path:remoteDestination parameters:nil];
	[request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"%ld", (long)data.length] forHTTPHeaderField:@"Content-Length"];
    request.HTTPBodyStream = [NSInputStream inputStreamWithData:data];
    
    __block NSURLSessionUploadTask *task;
    task = [self uploadTaskWithStreamedRequest:request progress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) failure(task, error);
        } else {
            if (success) success();
        }
    }];

    [task resume];
    return task;
}

- (NSURLSessionTask *)putURL:(NSURL *)localSource path:(NSString *)remoteDestination success:(void(^)(void))success failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    NSMutableURLRequest *request = [self requestWithMethod:@"PUT" path:remoteDestination parameters:nil];
	[request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBodyStream = [NSInputStream inputStreamWithURL:localSource];

    __block NSURLSessionUploadTask *task;
    task = [self uploadTaskWithStreamedRequest:request progress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) failure(task, error);
        } else {
            if (success) success();
        }
    }];

    [task resume];
    return task;
}

- (NSURLSessionTask *)lockPath:(NSString *)path exclusive:(BOOL)exclusive recursive:(BOOL)recursive timeout:(NSTimeInterval)timeout success:(void(^)(NSURLSessionDataTask *task, DZWebDAVLock *lock))success failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure {
    NSParameterAssert(success);
    NSMutableURLRequest *request = [self requestWithMethod: @"LOCK" path: path parameters: nil];
    [request setValue: @"application/xml" forHTTPHeaderField: @"Content-Type"];
    [request setValue: timeout ? [NSString stringWithFormat: @"Second-%f", timeout] : @"Infinite, Second-4100000000" forHTTPHeaderField: @"Timeout"];
	[request setValue: recursive ? @"Infinity" : @"0" forHTTPHeaderField: @"Depth"];
    
    NSString *bodyData = [NSString stringWithFormat: @"<?xml version=\"1.0\" encoding=\"utf-8\"?><D:lockinfo xmlns:D=\"DAV:\"><D:lockscope><D:%@/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockinfo>", exclusive ? @"exclusive" : @"shared"];
    [request setHTTPBody: [bodyData dataUsingEncoding:NSUTF8StringEncoding]];
    
    __block NSURLSessionDataTask *task;
    task = [self dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) failure(task, error);
        } else {
            success(task, [[DZWebDAVLock alloc] initWithURL:task.originalRequest.URL responseObject:responseObject]);
        }
    }];

    [task resume];
    return task;
}

- (NSURLSessionTask *)refreshLock:(DZWebDAVLock *)lock success:(void(^)(NSURLSessionDataTask *task, DZWebDAVLock *lock))success failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure {
    NSMutableURLRequest *request = [self requestWithMethod: @"LOCK" path: lock.URL.path parameters: nil];
    [request setValue: [NSString stringWithFormat:@"(<%@>)", lock.token] forHTTPHeaderField: @"If"];
    [request setValue: lock.timeout ? [NSString stringWithFormat: @"Second-%f", lock.timeout] : @"Infinite, Second-4100000000" forHTTPHeaderField: @"Timeout"];
	[request setValue: lock.recursive ? @"Infinity" : @"0" forHTTPHeaderField: @"Depth"];
    
    __block NSURLSessionDataTask *task;
    task = [self dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) failure(task, error);
        } else {
            [lock updateFromResponseObject: responseObject];
            if (success) success(task, lock);
        }
    }];
    
    [task resume];
    return task;
}

- (NSURLSessionTask *)unlock:(DZWebDAVLock *)lock success:(void(^)(void))success failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure {
    NSMutableURLRequest *request = [self requestWithMethod: @"UNLOCK" path: lock.URL.path parameters: nil];
	[request setValue:@"application/xml" forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"<%@>", lock.token] forHTTPHeaderField:@"Lock-Token"];
    
    NSURLSessionDataTask *task = [self mr_taskWithRequest:request success:success failure:failure];
    [task resume];
    return task;
}

@end
