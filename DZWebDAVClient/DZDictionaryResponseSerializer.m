//
//  DZDictionaryResponseSerializer.m
//  DZWebDAVClient
//

#import "DZDictionaryResponseSerializer.h"
#import "DZXMLReader.h"

@implementation DZDictionaryResponseSerializer

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error {
    if ([super validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        NSXMLParser *parser = [super responseObjectForResponse:response data:data error:error];
        if (error == nil || *error == nil) {
            NSDictionary *responseDictionary = [DZXMLReader dictionaryForXMLParser:parser error:error];
            return responseDictionary;
        }
    } else if (error) *error = nil;
    return nil;
}

//+ (BOOL)canProcessRequest:(NSURLRequest *)urlRequest {
//    NSArray *allowedHTTPMethods = @[@"GET", @"MKCOL", @"PUT", @"PROPFIND", @"LOCK", @"UNLOCK"];
//    return [allowedHTTPMethods containsObject:urlRequest.HTTPMethod] || [super canProcessRequest:urlRequest];
//}

@end
