#import <SoftwareUpdate/SoftwareUpdate.h>

// GitHub answers non-2xx with a JSON body like
// { "message": "API rate limit exceeded for 1.2.3.4. ...", "documentation_url": ... }.
// Before issue #26 those bodies fell through tag_name extraction and were
// misreported as "Incomplete server response."
static NSHTTPURLResponse* response_with_status (NSInteger statusCode, NSDictionary* headers = @{ })
{
	return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://api.github.com/repos/x/y/releases/latest"] statusCode:statusCode HTTPVersion:@"HTTP/1.1" headerFields:headers];
}

void test_success_statuses_produce_no_error ()
{
	OAK_ASSERT(OakGitHubResponseError(response_with_status(200), @{ @"tag_name": @"v1" }) == nil);
	OAK_ASSERT(OakGitHubResponseError(response_with_status(204), nil) == nil);
}

void test_rate_limit_gets_dedicated_message ()
{
	// Headers as sent by api.github.com when the unauthenticated quota for the
	// IP is exhausted (captured live, issue #26). GitHub's own body message is
	// noisy dialog copy ("But here's the good news: …"), so the updater says
	// what happened and when it resets instead.
	NSDictionary* headers = @{ @"x-ratelimit-remaining": @"0", @"x-ratelimit-reset": @"1781193371" };
	NSDictionary* body    = @{ @"message": @"API rate limit exceeded for 1.2.3.4. (But here's the good news: ...)" };

	NSError* err = OakGitHubResponseError(response_with_status(403, headers), body);
	OAK_ASSERT(err != nil);
	OAK_ASSERT([err.localizedDescription containsString:@"GitHub API rate limit"]);
	OAK_ASSERT(![err.localizedDescription containsString:@"good news"]);

	NSDateFormatter* formatter = [NSDateFormatter new];
	formatter.dateStyle = NSDateFormatterNoStyle;
	formatter.timeStyle = NSDateFormatterShortStyle;
	NSString* resetTime = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:1781193371]];
	OAK_ASSERT([err.localizedDescription containsString:resetTime]);

	// Same headers on 429 (GitHub uses both statuses for limits).
	OAK_ASSERT([[OakGitHubResponseError(response_with_status(429, headers), nil) localizedDescription] containsString:@"GitHub API rate limit"]);

	// Missing reset header still names the problem.
	err = OakGitHubResponseError(response_with_status(403, @{ @"x-ratelimit-remaining": @"0" }), body);
	OAK_ASSERT([err.localizedDescription containsString:@"GitHub API rate limit"]);
}

void test_other_errors_surface_github_message ()
{
	NSDictionary* body = @{ @"message": @"Repository access blocked", @"documentation_url": @"https://docs.github.com" };
	NSError* err = OakGitHubResponseError(response_with_status(451), body);
	OAK_ASSERT(err != nil);
	OAK_ASSERT([err.localizedDescription containsString:@"Repository access blocked"]);
}

void test_non_2xx_without_message_reports_status ()
{
	NSError* err = OakGitHubResponseError(response_with_status(500), nil);
	OAK_ASSERT(err != nil);
	OAK_ASSERT([err.localizedDescription containsString:@"500"]);

	err = OakGitHubResponseError(response_with_status(404), @[ @"not", @"a", @"dict" ]);
	OAK_ASSERT(err != nil);
	OAK_ASSERT([err.localizedDescription containsString:@"404"]);
}

void test_non_http_response_produces_no_error ()
{
	NSURLResponse* plain = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.org"] MIMEType:@"application/json" expectedContentLength:0 textEncodingName:nil];
	OAK_ASSERT(OakGitHubResponseError(plain, nil) == nil);
}
