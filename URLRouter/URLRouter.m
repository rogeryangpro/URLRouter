//
//  VURLRouter.m
//  Vacation
//
//  Created by cheng.yang on 4/7/16.
//

#import "URLRouter.h"



static const NSRegularExpression *posRegex;


@interface URLRouter()

@property (nonatomic, strong) NSMutableDictionary *config;

@end

@implementation URLRouter
+ (id)shareInstance {
    static URLRouter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        posRegex = [NSRegularExpression regularExpressionWithPattern:@"\\$[A-Za-z0-9]+" options:NSRegularExpressionCaseInsensitive error:nil];
        instance = [[self alloc] init];
        [instance loadConfig];
        
    });
    return instance;
}

- (void) loadConfig {
    // load config from dynamic config
    NSString *configContent = nil;
    
    // parse to json
    _config = nil;
}

- (NSString *) nativeURIForURL:(NSURL *) url {
    NSString *host = [url host];
    NSArray *rules = [_config objectForKey:host];
    
    NSString *uri = nil;
    
    for (NSDictionary *rule in rules) {
        NSString *scheme = [rule objectForKey:@"url"];
        NSString *nativeScheme = [rule objectForKey:@"uri"];
        
        NSString *pathScheme = [self pathSchemeOfScheme:scheme];
        
        if ([self matchPath:url.path scheme:pathScheme]) {
            
            if (nativeScheme != nil && [nativeScheme length] > 0) {
                NSDictionary *params = [self paramsOfURL:url inScheme:scheme];
                uri = [self nativeURIWithURL:url andParams:params andNativeURIScheme:nativeScheme];
            } else {
                url = nil; // custome webview scheme
            }
            break;
        }
    }
    
    if (uri == nil || [uri length] <=0 ) {
        url = nil; // custome webview scheme
    }
    
    return uri;
}



- (BOOL) matchPath:(NSString *) path scheme:(NSString *) scheme {
    if (![scheme containsString:@"$"]) {
        return [path isEqualToString:scheme];
    } else {
        NSRegularExpression *matchRegex = [NSRegularExpression regularExpressionWithPattern:[self regexForPathScheme:scheme] options:0 error:nil];
        return [matchRegex numberOfMatchesInString:path options:0 range:NSMakeRange(0, path.length)] > 0;
    }
}

- (NSString *) regexForPathScheme:(NSString *) pathScheme {
    NSArray *segments = [pathScheme componentsSeparatedByString:@"/"];
    
    NSMutableString *pathRegex = [[NSMutableString alloc] init];
    
    
    for (NSInteger i = 0; i < [segments count]; i++) {
        NSString *segment = segments[i];
        
        if (segment.length > 0) {
            NSString *temp = [posRegex stringByReplacingMatchesInString:segment options:0 range:NSMakeRange(0, segment.length) withTemplate:@"$"];
            NSArray *subSegs = [temp componentsSeparatedByString:@"$"];
            
            for (NSInteger j = 0; j < [subSegs count]; j++) {
                NSString *subSeg = subSegs[j];
                [pathRegex appendString:subSeg];
                
                if (j < [subSegs count] - 1) {
                    NSMutableString *subRegex = [[NSMutableString alloc] init];
                    
                    
                    // 正则表达式的字符不是$前的字符
                    if (subSeg.length > 0) {
                        [subRegex appendString:[subSeg substringFromIndex:subSeg.length - 1]];
                    }
                    
                    NSString *nextSeg = subSegs[j + 1];
                    if (nextSeg.length > 0) {
                        NSString *head = [nextSeg substringToIndex:1];
                        
                        // 正则表达式的字符不是$后的字符
                        if (![subRegex containsString:head]) {
                            [subRegex appendString:head];
                        }
                    }
                    
                    if (subRegex != nil && [subRegex length] > 0) {
                        [pathRegex appendString:[NSString stringWithFormat:@"([^%@]+)", subRegex]];
                    } else {
                        [pathRegex appendString:@"(\\w+)"];
                    }
                }
            }
        }
        
        if (i < [segments count] - 1) {
            [pathRegex appendString:@"/"];
        }
    }
    return pathRegex;
    
}

- (NSDictionary *) paramsOfURL:(NSURL *) url inScheme:(NSString *) scheme {
    NSString *pathScheme = [self pathSchemeOfScheme:scheme];
    NSRegularExpression *keyRegex = [NSRegularExpression regularExpressionWithPattern:[posRegex stringByReplacingMatchesInString:scheme options:0 range:NSMakeRange(0, scheme.length) withTemplate:@"(\\\\$[A-Za-z0-9]+)"] options:0 error:nil];
    NSRegularExpression *valueRegex = [NSRegularExpression regularExpressionWithPattern:[self regexForPathScheme:pathScheme] options:0 error:nil];
    
    
    NSString *path = url.path;
    
    NSTextCheckingResult *keyResult = [keyRegex firstMatchInString:scheme options:0 range:NSMakeRange(0, scheme.length)];
    NSTextCheckingResult *valueResult = [valueRegex firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    
    
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    
    for (NSInteger i = 1; i < keyResult.numberOfRanges; i++) {
        [params setObject:[path substringWithRange:[valueResult rangeAtIndex:i]] forKey:[scheme substringWithRange:[keyResult rangeAtIndex:i]]];
    }
    
    
    NSString *queryScheme = [self querySchemeOfScheme:scheme];
    
    
    if (queryScheme) {
        NSString *query = url.query;
        NSDictionary *actualParams = nil; // [query dictionaryFromQueryComponents]
        NSDictionary *schemeParams = nil; // [queryScheme dictionaryFromQueryComponents]
        
        
        for (NSString *key in schemeParams) {
            NSString *value = [actualParams objectForKey:key];
            [params setObject:value forKey:[schemeParams objectForKey:key]];
        }
    }
    
    return params;
    
}


- (NSString *) pathSchemeOfScheme:(NSString *) scheme {
    return [scheme containsString:@"?"] ? [scheme substringToIndex:[scheme rangeOfString:@"?"].location] : scheme;
}

- (NSString *) querySchemeOfScheme:(NSString *) scheme {
    return [scheme containsString:@"?"] ? [scheme substringFromIndex:[scheme rangeOfString:@"?"].location + 1] : nil;
}



- (NSString *) nativeURIWithURL:(NSURL *) url andParams:(NSDictionary *) params andNativeURIScheme:(NSString *) scheme {
    
    NSString *uri = nil; // append custom head
    
    for (NSString *key in params) {
        
        // replace parameter
        // uri = [uri stringByReplacingOccurrencesOfString:key withString:[[params objectForKey:key] URLEncodedString]];
        
    }
    return uri;
}

@end
