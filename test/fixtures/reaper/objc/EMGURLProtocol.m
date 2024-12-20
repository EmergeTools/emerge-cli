//
//  EMGURLProtocol.m
//  PerfTesting
//
//  Created by Noah Martin on 8/4/22.
//

#import "EMGURLProtocol.h"
#import "EMGLog.h"
#import "EMGTuple.h"

@interface EMGCacheEntry : NSObject <NSSecureCoding>

@property(strong, nonatomic) NSURLRequest *request;
@property(strong, nonatomic) NSURLResponse *response;
@property(strong, nonatomic, nullable) NSData *data;

@end

@implementation EMGCacheEntry

- (instancetype)initWithRequest:(NSURLRequest *)request
                       response:(NSURLResponse *)response
                           data:(NSData *)data {
  self = [super init];
  if (self) {
    _request = request;
    _response = response;
    _data = data;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _request = [coder decodeObjectOfClass:[NSURLRequest class]
                                   forKey:@"request"];
    _response = [coder decodeObjectOfClass:[NSURLResponse class]
                                    forKey:@"response"];
    _data = [coder decodeObjectOfClass:[NSData class] forKey:@"data"];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_request forKey:@"request"];
  [coder encodeObject:_response forKey:@"response"];
  [coder encodeObject:_data forKey:@"data"];
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

@end

@implementation EMGURLProtocol

static NSMutableArray<EMGTuple<NSURLRequest *, NSArray<NSError *> *> *>
    *sRequestNotFoundErrors;

+ (NSArray<NSDictionary *> *)requestMisses {
  __block NSArray<NSDictionary *> *result;
  // sRequestNotFoundErrors should only be accessed on requestQueue
  dispatch_sync(requestQueue(), ^{
    if (sRequestNotFoundErrors == nil) {
      result = @[];
    } else {
      NSMutableArray<NSDictionary *> *networkReplayMisses =
          [NSMutableArray array];
      for (EMGTuple<NSURLRequest *, NSArray<NSError *> *>
               *tuple in sRequestNotFoundErrors) {
        NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
        for (NSError *error in tuple.second) {
          [candidates addObject:error.userInfo];
        }
        NSDictionary *miss = @{
          @"requestUrl" : tuple.first.URL.description,
          @"candidates" : [candidates copy],
        };
        [networkReplayMisses addObject:miss];
      }
      result = [networkReplayMisses copy];
    }
  });
  return result;
}

+ (BOOL)canInitWithTask:(NSURLSessionTask *)task {
  return [self canInitWithRequest:task.originalRequest];
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
  if ([NSURLProtocol propertyForKey:@"EMGURLProtocolHandledKey"
                          inRequest:request]) {
    return NO;
  }
  if (([request.URL.scheme isEqualToString:@"https"] ||
       [request.URL.scheme isEqualToString:@"http"]) &&
      ![request.URL.host isEqual:@"localhost"]) {
    // Avoid localhost requests since those are to communicate with the UI test
    // runner
    return YES;
  } else {
    EMGLog(@"Not handling request URL = %@", request.URL.absoluteString);
  }
  return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
  return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
  return [super requestIsCacheEquivalent:a toRequest:b];
}

+ (NSString *)folderNameForURL:(NSURL *)url {
  if (url.path.length > 0) {
    return [url.host stringByAppendingPathComponent:url.path];
  }
  return url.host;
}

dispatch_queue_t requestQueue(void) {
  static dispatch_once_t queueCreationGuard;
  static dispatch_queue_t queue;
  dispatch_once(&queueCreationGuard, ^{
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(
        DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
    queue =
        dispatch_queue_create("com.emerge.networkreplay.requestQueue", attr);
  });
  return queue;
}

- (void)startLoading {
  dispatch_async(requestQueue(), ^{
    [self startLoading_Locked];
  });
}

- (NSURL *)directoryForURL:(NSURL *)url {
  NSURL *documentsURL =
      [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                             inDomains:NSUserDomainMask][0];
  NSString *className =
      [NSProcessInfo processInfo].environment[@"EMERGE_CLASS_NAME"];
  NSURL *emergeDirectoryURL =
      [[documentsURL URLByAppendingPathComponent:@"emerge-cache"]
          URLByAppendingPathComponent:className];
  return [emergeDirectoryURL
      URLByAppendingPathComponent:[EMGURLProtocol folderNameForURL:url]];
}

- (void)receivedResponse:(NSURLResponse *)response
               toRequest:(NSURLRequest *)request
                withData:(NSData *)data
                   error:(NSError *)error {
  NSURL *emergeDirectoryURL = [self directoryForURL:request.URL];
  NSString *uuid = [NSUUID UUID].UUIDString;
  if (error) {
    [self.client URLProtocol:self didFailWithError:error];
  } else {
    NSURL *url = [emergeDirectoryURL URLByAppendingPathComponent:uuid];
    EMGCacheEntry *entry = [[EMGCacheEntry alloc] initWithRequest:request
                                                         response:response
                                                             data:data];
    NSError *error = nil;
    NSData *entryData = [NSKeyedArchiver archivedDataWithRootObject:entry
                                              requiringSecureCoding:YES
                                                              error:&error];
    if (error) {
      EMGLog(@"Error archiving response %@", error);
      return;
    }
    if (![entryData writeToURL:url atomically:YES]) {
      EMGLog(@"Error writing response to file");
    }
    [self.client URLProtocol:self
          didReceiveResponse:response
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (data) {
      [self.client URLProtocol:self didLoadData:data];
    }
  }
  [self.client URLProtocolDidFinishLoading:self];
  EMGLog(@"Finished url request %@", request.URL);
}

+ (NSString *)comparisonStringForQueryParams:(NSURL *)url {
  NSURLComponents *components = [NSURLComponents componentsWithURL:url
                                           resolvingAgainstBaseURL:NO];

  // Sort these to make sure the path is always the same
  NSArray *items = [components.queryItems
      sortedArrayUsingComparator:^NSComparisonResult(NSURLQueryItem *obj1,
                                                     NSURLQueryItem *obj2) {
        return [obj2.name compare:obj1.name];
      }];
  NSString *string = @"";
  for (NSURLQueryItem *item in items) {
    // Workaround for until they don't have a random string or timestamp in this
    // param
    if (![item.name isEqual:@"variables"] &&
        ![item.name isEqual:@"extensions"] && ![item.name isEqual:@"ts"]) {
      string = [string
          stringByAppendingString:[NSString stringWithFormat:@"&%@=%@",
                                                             item.name,
                                                             item.value]];
    }
  }
  return string;
}

+ (NSDictionary *)diffDictionaryBetween:(NSDictionary *)dict1
                                    and:(NSDictionary *)dict2 {
  NSMutableDictionary *diff = [NSMutableDictionary dictionary];
  NSSet *allKeys = [NSSet
      setWithArray:[dict1.allKeys arrayByAddingObjectsFromArray:dict2.allKeys]];
  for (NSString *key in allKeys) {
    if ([key isEqual:@"Content-Length"]) {
      continue;
    }
    if (dict1[key] != dict2[key] && ![dict1[key] isEqual:dict2[key]]) {
      diff[key] = @[ dict1[key] ?: [NSNull null], dict2[key] ?: [NSNull null] ];
    }
  }
  return [diff copy];
}

+ (NSError *)responseNotFoundErrorWithType:(NSString *)type
                               cachedValue:(NSString *)cachedValue
                                givenValue:(NSString *)givenValue {
  return [NSError
      errorWithDomain:@"NetworkRequestNotFound"
                 code:1
             userInfo:@{
               @"type" : type,
               @"cachedValue" : cachedValue ? cachedValue : [NSNull null],
               @"givenValue" : givenValue ? givenValue : [NSNull null]
             }];
}

+ (BOOL)isCachedRequestEqual:(NSURLRequest *)req1
                          to:(NSURLRequest *)req2
                       error:(NSError **)error {
  if (req1.HTTPBody != req2.HTTPBody &&
      ![req1.HTTPBody isEqualToData:req2.HTTPBody]) {
    NSString *body1 = [[NSString alloc] initWithData:req1.HTTPBody
                                            encoding:NSUTF8StringEncoding];
    NSString *body2 = [[NSString alloc] initWithData:req2.HTTPBody
                                            encoding:NSUTF8StringEncoding];
    EMGLog(@"HTTP body mismatch: %@ vs. %@", body1, body2);
    *error = [self responseNotFoundErrorWithType:@"body"
                                     cachedValue:body1
                                      givenValue:body2];
    return false;
  }

  // Ignore headers for now, as they've caused many network replay misses for
  // trivial fields like device ID, and because the headers shouldn't cause
  // different data anyways
  /*NSDictionary *diff = [self diffDictionaryBetween:req1.allHTTPHeaderFields ?:
  @{} and:req2.allHTTPHeaderFields ?: @{}]; if (diff.count > 0) { EMGLog(@"HTTP
  header field mismatch, diff: %@", diff); return false;
  }*/

  if (![req1.HTTPMethod isEqual:req2.HTTPMethod]) {
    EMGLog(@"HTTP method mismatch: %@ vs. %@", req1.HTTPMethod,
           req2.HTTPMethod);
    *error = [self responseNotFoundErrorWithType:@"HTTP method"
                                     cachedValue:req1.HTTPMethod
                                      givenValue:req2.HTTPMethod];
    return false;
  }

  if (![req1.URL.host isEqual:req2.URL.host]) {
    EMGLog(@"Host mismatch: %@ vs. %@", req1.URL.host, req2.URL.host);
    *error = [self responseNotFoundErrorWithType:@"HTTP method"
                                     cachedValue:req1.URL.host
                                      givenValue:req2.URL.host];
    return false;
  }

  // Paths should be equal anyways, but this is here for the sake of
  // completeness
  if (![req1.URL.path isEqual:req2.URL.path]) {
    EMGLog(@"Path mismatch: %@ vs. %@", req1.URL.path, req2.URL.path);
    *error = [self responseNotFoundErrorWithType:@"Path"
                                     cachedValue:req1.URL.path
                                      givenValue:req2.URL.path];
    return false;
  }

  NSString *comparisonString1 = [self comparisonStringForQueryParams:req1.URL];
  NSString *comparisonString2 = [self comparisonStringForQueryParams:req2.URL];
  if (![comparisonString1 isEqual:comparisonString2]) {
    EMGLog(@"Query params mismatch: %@ vs. %@", comparisonString1,
           comparisonString2);
    *error = [self responseNotFoundErrorWithType:@"Query params"
                                     cachedValue:comparisonString1
                                      givenValue:comparisonString2];
    return false;
  }

  return true;
}

// Always called on requestQueue
- (void)startLoading_Locked {
  NSURL *url = self.request.URL;
  EMGLog(@"Starting loading for %@", url);

  NSURL *emergeDirectoryURL = [self directoryForURL:url];
  if (![[NSFileManager defaultManager] fileExistsAtPath:emergeDirectoryURL.path
                                            isDirectory:NULL]) {
    [[NSFileManager defaultManager] createDirectoryAtURL:emergeDirectoryURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
  }
  EMGCacheEntry *matchedEntry = nil;
  NSArray<NSURL *> *contents = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:emergeDirectoryURL
      includingPropertiesForKeys:nil
                         options:0
                           error:nil];
  if (contents.count == 0) {
    EMGLog(@"No matching path for %@", url);
  }
  // This might be too slow - it has to read and decode potentially every saved
  // request for this host/path However, most of the time apps won't have many
  // request with the same host/path
  NSMutableArray<NSError *> *errors = [NSMutableArray array];
  for (NSURL *url in contents) {
    BOOL isDirectory = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:url.path
                                         isDirectory:&isDirectory];
    if (isDirectory) {
      continue;
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSError *unarchiveError = nil;
    EMGLog(@"Trying %@", url);
    EMGCacheEntry *entry =
        [NSKeyedUnarchiver unarchivedObjectOfClass:[EMGCacheEntry class]
                                          fromData:data
                                             error:&unarchiveError];
    if (unarchiveError) {
      EMGLog(@"Error unarchiving network replay entry: %@", unarchiveError);
      [errors addObject:unarchiveError];
      continue;
    }

    NSError *notEqualError = nil;
    if ([EMGURLProtocol isCachedRequestEqual:entry.request
                                          to:self.request
                                       error:&notEqualError]) {
      matchedEntry = entry;
      break;
    } else {
      [errors addObject:notEqualError];
    }
  }

  // If there is a matchedRequest, always return the saved response
  if (matchedEntry) {
    EMGLog(@"Found matching request for %@, data size %@, response %@",
           self.request.URL, @(matchedEntry.data.length),
           matchedEntry.response);
    [self.client URLProtocol:self
          didReceiveResponse:matchedEntry.response
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (matchedEntry.data) {
      [self.client URLProtocol:self didLoadData:matchedEntry.data];
    }
    [self.client URLProtocolDidFinishLoading:self];
  } else if ([[NSProcessInfo processInfo].environment[@"EMG_RECORD_NETWORK"]
                 isEqual:@"1"]) {
    EMGLog(@"Going to record for %@", self.request.URL);
    // Only record, don't replay
    // TODO: Possibly implement an append only state when re-running with the
    // control/experiment app
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES
                        forKey:@"EMGURLProtocolHandledKey"
                     inRequest:newRequest];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:newRequest
          completionHandler:^(NSData *_Nullable data,
                              NSURLResponse *_Nullable response,
                              NSError *_Nullable error) {
            dispatch_async(requestQueue(), ^{
              [self receivedResponse:response
                           toRequest:self.request
                            withData:data
                               error:error];
            });
          }];
    [task resume];
  } else {
    if (!sRequestNotFoundErrors) {
      sRequestNotFoundErrors = [NSMutableArray array];
    }
    [sRequestNotFoundErrors addObject:[EMGTuple tupleWith:self.request
                                                      and:[errors copy]]];
    EMGLog(@"Did not find matching request for %@", self.request.URL);
    // Not recording but no recorded response, leave request hanging
  }
}

- (void)stopLoading {
}

@end