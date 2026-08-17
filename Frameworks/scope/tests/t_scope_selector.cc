#include <scope/scope.h>

void test_child_selector ()
{
	OAK_ASSERT_EQ(scope::selector_t("foo fud").does_match("foo bar fud").has_value(),                     true);
	OAK_ASSERT_EQ(scope::selector_t("foo > fud").does_match("foo bar fud").has_value(),                   false);
	OAK_ASSERT_EQ(scope::selector_t("foo > foo > fud").does_match("foo foo fud").has_value(),             true);
	OAK_ASSERT_EQ(scope::selector_t("foo > foo > fud").does_match("foo foo fud fud").has_value(),         true);
	OAK_ASSERT_EQ(scope::selector_t("foo > foo > fud").does_match("foo foo fud baz").has_value(),         true);

	OAK_ASSERT_EQ(scope::selector_t("foo > foo fud > fud").does_match("foo foo bar fud fud").has_value(), true);
}

void test_mixed ()
{
	OAK_ASSERT_EQ(scope::selector_t("^ foo > bar").does_match("foo bar foo").has_value(),                       true);
	OAK_ASSERT_EQ(scope::selector_t("foo > bar $").does_match("foo bar foo").has_value(),                       false);
	OAK_ASSERT_EQ(scope::selector_t("bar > foo $").does_match("foo bar foo").has_value(),                       true);
	OAK_ASSERT_EQ(scope::selector_t("foo > bar > foo $").does_match("foo bar foo").has_value(),                 true);
	OAK_ASSERT_EQ(scope::selector_t("^ foo > bar > foo $").does_match("foo bar foo").has_value(),               true);
	OAK_ASSERT_EQ(scope::selector_t("bar > foo $").does_match("foo bar foo").has_value(),                       true);
	OAK_ASSERT_EQ(scope::selector_t("^ foo > bar > baz").does_match("foo bar baz foo bar baz").has_value(),     true);
	OAK_ASSERT_EQ(scope::selector_t("^ foo > bar > baz").does_match("foo foo bar baz foo bar baz").has_value(), false);
}

void test_dollar ()
{
	scope::scope_t dyn("foo bar");
	dyn.push_scope("dyn.selection");
	OAK_ASSERT_EQ(scope::selector_t("foo bar$").does_match(dyn).has_value(),     true);
	OAK_ASSERT_EQ(scope::selector_t("foo bar dyn$").does_match(dyn).has_value(), false);
	OAK_ASSERT_EQ(scope::selector_t("foo bar dyn").does_match(dyn).has_value(),  true);
}

void test_anchor ()
{
	OAK_ASSERT_EQ(scope::selector_t("^ foo").does_match("foo bar").has_value(),     true);
	OAK_ASSERT_EQ(scope::selector_t("^ bar").does_match("foo bar").has_value(),     false);
	OAK_ASSERT_EQ(scope::selector_t("^ foo").does_match("foo bar foo").has_value(), true);
	OAK_ASSERT_EQ(scope::selector_t("foo $").does_match("foo bar").has_value(),     false);
	OAK_ASSERT_EQ(scope::selector_t("bar $").does_match("foo bar").has_value(),     true);
}

void test_scope_selector ()
{
	static scope::scope_t const textScope = "text.html.markdown meta.paragraph.markdown markup.bold.markdown";
	static scope::selector_t const matchingSelectors[] =
	{
		"text.* markup.bold",
		"text markup.bold",
		"markup.bold",
		"text.html meta.*.markdown markup",
		"text.html meta.* markup",
		"text.html * markup",
		"text.html markup",
		"text markup",
		"markup",
		"text.html",
		"text"
	};

	double lastRank = 1;
	for(auto const& selector : matchingSelectors)
	{
		OAK_ASSERT(selector.does_match(textScope).has_value());
		OAK_ASSERT_LT(*selector.does_match(textScope), lastRank);
		lastRank = *selector.does_match(textScope);
	}
}

void test_rank ()
{
	scope::scope_t const leftScope  = "text.html.php meta.embedded.block.php source.php comment.block.php";
	scope::scope_t const rightScope = "text.html.php meta.embedded.block.php source.php";
	scope::context_t const scope(leftScope, rightScope);

	scope::selector_t const globalSelector = "comment.block | L:comment.block";
	scope::selector_t const phpSelector    = "L:source.php - string";

	OAK_ASSERT(globalSelector.does_match(scope).has_value());
	OAK_ASSERT(phpSelector.does_match(scope).has_value());
	OAK_ASSERT_LT(*phpSelector.does_match(scope), *globalSelector.does_match(scope));
}

void test_match ()
{
	auto match = [](scope::selector_t const& sel, scope::scope_t const& scope){ return sel.does_match(scope); };

	OAK_ASSERT( match("foo",                  "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT( match("foo bar",              "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT( match("foo bar baz",          "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT( match("foo baz",              "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT( match("foo.*",                "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT( match("foo.qux",              "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT( match("foo.qux baz.*.garply", "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT( match("bar",                  "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT(!match("foo qux",              "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT(!match("foo.bar",              "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT(!match("foo.qux baz.garply",   "foo.qux bar.quux.grault baz.corge.garply"));
	OAK_ASSERT(!match("bar.*.baz",            "foo.qux bar.quux.grault baz.corge.garply"));

	OAK_ASSERT( match("foo > bar",             "foo bar baz bar baz"));
	OAK_ASSERT( match("bar > baz",             "foo bar baz bar baz"));
	OAK_ASSERT( match("foo > bar baz",         "foo bar baz bar baz"));
	OAK_ASSERT( match("foo bar > baz",         "foo bar baz bar baz"));
	OAK_ASSERT( match("foo > bar > baz",       "foo bar baz bar baz"));
	OAK_ASSERT( match("foo > bar bar > baz",   "foo bar baz bar baz"));
	OAK_ASSERT(!match("foo > bar > bar > baz", "foo bar baz bar baz"));

	OAK_ASSERT( match("baz $",                 "foo bar baz bar baz"));
	OAK_ASSERT( match("bar > baz $",           "foo bar baz bar baz"));
	OAK_ASSERT( match("bar > baz $",           "foo bar baz bar baz"));
	OAK_ASSERT( match("foo bar > baz $",       "foo bar baz bar baz"));
	OAK_ASSERT( match("foo > bar > baz",       "foo bar baz bar baz"));
	OAK_ASSERT(!match("foo > bar > baz $",     "foo bar baz bar baz"));
	OAK_ASSERT(!match("bar $",                 "foo bar baz bar baz"));

	OAK_ASSERT( match("baz $",                 "foo bar baz bar baz dyn.qux"));
	OAK_ASSERT( match("bar > baz $",           "foo bar baz bar baz dyn.qux"));
	OAK_ASSERT( match("bar > baz $",           "foo bar baz bar baz dyn.qux"));
	OAK_ASSERT( match("foo bar > baz $",       "foo bar baz bar baz dyn.qux"));
	OAK_ASSERT(!match("foo > bar > baz $",     "foo bar baz bar baz dyn.qux"));
	OAK_ASSERT(!match("bar $",                 "foo bar baz bar baz dyn.qux"));

	OAK_ASSERT( match("^ foo",                 "foo bar foo bar baz"));
	OAK_ASSERT( match("^ foo > bar",           "foo bar foo bar baz"));
	OAK_ASSERT( match("^ foo bar > baz",       "foo bar foo bar baz"));
	OAK_ASSERT( match("^ foo > bar baz",       "foo bar foo bar baz"));
	OAK_ASSERT(!match("^ foo > bar > baz",     "foo bar foo bar baz"));
	OAK_ASSERT(!match("^ bar",                 "foo bar foo bar baz"));

	OAK_ASSERT( match("foo > bar > baz",       "foo bar baz foo bar baz"));
	OAK_ASSERT( match("^ foo > bar > baz",     "foo bar baz foo bar baz"));
	OAK_ASSERT( match("foo > bar > baz $",     "foo bar baz foo bar baz"));
	OAK_ASSERT(!match("^ foo > bar > baz $",   "foo bar baz foo bar baz"));
}

// Coverage for the root-atom fast-reject in path_t::does_match (match.cc).
void test_root_fast_reject ()
{
	auto match = [](scope::selector_t const& sel, scope::scope_t const& scope){ return sel.does_match(scope); };

	// Should match, and must not be wrongly rejected by the fast-reject.
	OAK_ASSERT( match("source.c++ meta.function", "source.c++ meta.function.free.definition"));

	// Embedded language: "source.php" is not the query’s root (“text.html.php” is,
	// same shape as test_rank’s scope) — it matches a node in the middle of the
	// chain instead. The fast-reject must not assume the first scope has to equal
	// the root, only that it must appear somewhere in the chain.
	OAK_ASSERT( match("source.php", "text.html.php meta.embedded.block.php source.php comment.block.php"));

	// Should not match — "source.go" appears nowhere in the chain — and is rejected.
	OAK_ASSERT(!match("source.go meta.function", "source.c++ meta.function.free"));

	// Negated selector: the fast-reject only answers for the un-negated path_t;
	// the caller (composite_t) still applies the negation on top of that.
	OAK_ASSERT( match("-source.go",  "source.c++"));
	OAK_ASSERT(!match("-source.c++", "source.c++"));

	// Comma alternative: the first composite is rejected, the second matches.
	OAK_ASSERT( match("source.go, source.c++", "source.c++ meta.function"));

	// Leading wildcard: the first scope is unanalysable ('*' matches any atom), so
	// root_prefix is left unset and does_match always falls back to the full match.
	OAK_ASSERT( match("* source.css", "text.html source.css.embedded"));
}
