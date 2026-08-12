#import <SoftwareUpdate/SoftwareUpdate.h>

std::string to_s (NSComparisonResult result)
{
	switch(result)
	{
		case NSOrderedAscending:  return "NSOrderedAscending";
		case NSOrderedSame:       return "NSOrderedSame";
		case NSOrderedDescending: return "NSOrderedDescending";
	}
	return NULL_STR;
}

void test_trailing_zero ()
{
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2-beta",        @"2.0"),          NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0-beta",      @"2.0"),          NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0.0-beta",    @"2.0"),          NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2",             @"2.0"),          NSOrderedSame);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2",             @"2.0+git.hash"), NSOrderedSame);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2+git.hash",    @"2.0"),          NSOrderedSame);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0.1-beta",    @"2.0"),          NSOrderedDescending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.1-beta",      @"2.0"),          NSOrderedDescending);
}

// The fork's actual tag forms: stable releases are X.Y.Z-undead, betas are
// X.Y.Z-undead-beta.N (and one legacy 2.0.23-undead.0). Beta channel users
// must be offered the next beta AND the stable that supersedes their beta.
void test_undead_versions ()
{
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.1.2-undead-beta.1",  @"2.1.2-undead"),         NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.1.2-undead-beta.1",  @"2.1.2-undead-beta.2"),  NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.1.2-undead-beta.2",  @"2.1.2-undead-beta.10"), NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.1.1-undead",         @"2.1.2-undead-beta.1"),  NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0.23-undead.0",      @"2.1.0-undead"),         NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.1.2-undead",         @"2.1.2-undead"),         NSOrderedSame);
}

void test_null_string ()
{
	OAK_ASSERT_EQ(OakCompareVersionStrings(nil, @"2.0"), NSOrderedAscending);
	OAK_ASSERT_NE(OakCompareVersionStrings(nil, @"2.0"), NSOrderedSame);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0", nil), NSOrderedDescending);
}

void test_exhaustive ()
{
	NSMutableArray<NSString*>* versions = [NSMutableArray array];
	for(NSString* number in @[ @"1", @"1.01", @"1.1.1", @"1.1.2", @"1.2", @"1.2.1", @"1.10", @"2", @"2.1", @"2.1.1", @"2.2" ])
	{
		for(NSString* suffix in @[ @"-alpha", @"-alpha.1", @"-alpha.2", @"-alpha.3+debug", @"-beta", @"-beta.1", @"-beta.2", @"-rc.1", @"" ])
			[versions addObject:[number stringByAppendingString:suffix]];
	}

	for(NSUInteger i = 0; i < versions.count; ++i)
	{
		for(NSUInteger j = i; j < versions.count; ++j)
		{
			for(NSString* lhs in @[ versions[i], [versions[i] stringByAppendingString:@"+git.c0de"] ])
			{
				for(NSString* rhs in @[ versions[j], [versions[j] stringByAppendingString:@"+git.b337"] ])
				{
					NSString* msg = [NSString stringWithFormat:@"%@ %c %@", lhs, i < j ? '<' : (i == j ? '=' : '>'), rhs];
					if(i < j)  { OAK_MASSERT_EQ(msg.UTF8String, OakCompareVersionStrings(lhs, rhs), NSOrderedAscending);  }
					if(i == j) { OAK_MASSERT_EQ(msg.UTF8String, OakCompareVersionStrings(lhs, rhs), NSOrderedSame);       }
					if(i > j)  { OAK_MASSERT_EQ(msg.UTF8String, OakCompareVersionStrings(lhs, rhs), NSOrderedDescending); }
				}
			}
		}
	}
}
