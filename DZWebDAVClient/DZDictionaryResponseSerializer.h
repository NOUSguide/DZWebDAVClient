//
//  DZDictionaryResponseSerializer.h
//  DZWebDAVClient
//
//  Created by Zachary Waldowski on 1/27/12.
//  Copyright (c) 2012 Dizzy Technology. All rights reserved.
//
//  Licensed under MIT. See LICENSE.
//

#import <AFNetworking/AFNetworking.h>

/**
 `DZDictionaryRequestOperation` is a subclass of `AFXMLRequestOperation` for downloading and working with XML response data as an NSDictionary.
 
 ## Acceptable Content Types
 
 By default, `DZDictionaryRequestOperation` accepts the following MIME types, which includes the official standard, `application/xml`, as well as other commonly-used types:
 
 - `application/xml`
 - `text/xml`
 
 ## Use With AFHTTPClient
 
 When `DZDictionaryResponseSerializer` is registered with `AFHTTPClient`, the response object in the success callback of `HTTPRequestOperationWithRequest:success:failure:` will be an instance of `NSDictionary`. While the `AFXMLRequestOperation` properties `responseXMLParser` and `responseXMLDocument` are available, their use is not recommended to avoid parsing twice.
 */
@interface DZDictionaryResponseSerializer : AFXMLParserResponseSerializer

@end
