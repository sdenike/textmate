#include <buffer/buffer.h>
#include <test/bundle_index.h>
#include <chrono>

namespace
{
	// A small but structurally real grammar -- line/block comments, a quoted
	// string with an escape rule, a keyword alternation, numbers and a
	// function-name heuristic -- so parsing this text produces the kind of
	// varied, nested scope stack a real language grammar would, rather than
	// the near-inert two-pattern fixture in t_buffer.mm. Self-contained (no
	// include/repository), so it needs no bundle registry lookups at parse
	// time.
	//
	// One string literal per source line, NOT a multi-line raw string:
	// bin/gen_test splices a `#line N "path"` directive before every line of
	// this file's body, textually, with no awareness of C++ literal
	// boundaries. A raw string spanning several source lines would capture
	// those injected directives as literal plist text -- confirmed by
	// hand: plist::parse_ascii silently failed on exactly that, taking the
	// generated `#line ...` lines as garbage inside the value.
	static std::string const kGrammarPlist =
		"{	scopeName = 'source.c_bench';\n"
		"	uuid      = 'B7B6F6C2-9C1E-4E7B-9C0E-6E9B9C1E4E7B';\n"
		"	patterns  = (\n"
		"		{ name = 'comment.line.double-slash.bench'; match = '//.*$'; },\n"
		"		{ name = 'comment.block.bench'; begin = '/\\*'; end = '\\*/'; },\n"
		"		{ name = 'string.quoted.double.bench'; begin = '\"'; end = '\"';\n"
		"		  patterns = ( { name = 'constant.character.escape.bench'; match = '\\\\.'; } ); },\n"
		"		{ name = 'keyword.control.bench'; match = '\\b(if|else|for|while|return|switch|case|break|continue|namespace|class|struct|public|private|protected|template|typename|using|const|static|virtual|void|int|size_t|auto|include|define)\\b'; },\n"
		"		{ name = 'constant.numeric.bench'; match = '\\b[0-9]+\\b'; },\n"
		"		{ name = 'entity.name.function.bench'; match = '\\b[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()'; },\n"
		"	);\n"
		"}\n";

	// Generates deterministic, C++-like source text -- comments, a string
	// literal, keywords, a function definition -- repeated until it is at
	// least targetBytes long. Generated rather than a committed fixture, and
	// hermetic (no filesystem access): the benchmark needs nothing beyond this
	// source file. Roughly matches the shape, though not the exact byte
	// count, of the ~1 MB / ~25,800-line real-source sample used to design it.
	std::string generate_source (size_t targetBytes)
	{
		static char const* const block[] = {
			"#include <vector>\n",
			"#include <string>\n",
			"\n",
			"// widget_t computes a simple transform over an integer value.\n",
			"namespace ng\n",
			"{\n",
			"	/* Block comment describing widget_t,\n",
			"	 * spanning two lines to exercise begin/end rules.\n",
			"	 */\n",
			"	struct widget_t\n",
			"	{\n",
			"		widget_t (int value) : _value(value) { }\n",
			"\n",
			"		int compute (int x) const\n",
			"		{\n",
			"			if(x > 0)\n",
			"			{\n",
			"				return x + _value;\n",
			"			}\n",
			"			else if(x < 0)\n",
			"			{\n",
			"				return _value - x;\n",
			"			}\n",
			"			return _value;\n",
			"		}\n",
			"\n",
			"		static char const* name () { return \"widget\"; }\n",
			"\n",
			"	private:\n",
			"		int _value = 42;\n",
			"	};\n",
			"}\n",
			"\n",
		};

		std::string res;
		res.reserve(targetBytes + 1024);
		while(res.size() < targetBytes)
		{
			for(auto line : block)
				res += line;
		}
		return res;
	}

	// Watches did_parse for the notification that covers end-of-buffer. This
	// stays valid however initiate_repair batches its dispatches: did_parse's
	// firing cadence is observable behaviour this benchmark must not rely on
	// beyond "it eventually reports up to end of buffer".
	struct wait_for_eof_t : ng::callback_t
	{
		size_t target = 0;
		bool done      = false;
		void did_parse (size_t from, size_t to) { if(to >= target) done = true; }
	};

	// Pumps the run loop until watcher reports the whole buffer parsed, or
	// fails the test/benchmark after 30s rather than hanging forever.
	void run_until_parsed (wait_for_eof_t& watcher, char const* who)
	{
		auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(30);
		while(!watcher.done)
		{
			if(std::chrono::steady_clock::now() > deadline)
				OAK_FAIL(std::string(who) + ": timed out waiting for background parse to complete");
			CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
		}
	}
}

// No existing test enables async parsing at all (every t_buffer.mm test
// relies solely on wait_for_repair, which -- see the comment below -- never
// touches initiate_repair), so nothing previously exercised this dispatch
// path's bookkeeping, batched or not. This checks the batched rewrite
// produces byte-for-byte the same scopes as the known-correct synchronous
// path, on a small buffer (kept small so the test suite stays fast; the
// benchmark below exercises the same code at real size).
void test_batched_parse_matches_synchronous ()
{
	test::bundle_index_t bundleIndex;
	bundles::item_ptr grammar = bundleIndex.add(bundles::kItemTypeGrammar, kGrammarPlist);
	bundleIndex.commit();

	std::string text = generate_source(4000);

	ng::buffer_t sync;
	sync.insert(0, text);
	sync.set_grammar(grammar);
	sync.bump_revision();
	sync.wait_for_repair();

	ng::buffer_t async;
	async.insert(0, text);
	async.set_grammar(grammar);

	wait_for_eof_t watcher;
	watcher.target = async.size();
	async.add_callback(&watcher);

	async.set_async_parsing(true);
	async.bump_revision();
	run_until_parsed(watcher, "test_batched_parse_matches_synchronous");

	async.remove_callback(&watcher);
	async.wait_for_repair();

	OAK_ASSERT_EQ(to_s(async), to_s(sync));
}

// Loads a large buffer, sets a real (if synthetic) grammar, enables async
// parsing exactly as OakDocument.mm does for a real file, and pumps the run
// loop -- headlessly, no window or app needed -- until the background parser
// has covered the whole buffer. wait_for_repair() is deliberately NOT used
// here: it cancels any in-flight async dispatch and redoes the remaining
// parse synchronously and inline (see parsing.cc), so it never exercises
// initiate_repair's dispatch_async/CFRunLoopPerformBlock/CFRunLoopWakeUp path
// at all -- using it here would time something other than the mechanism this
// benchmark exists to measure.
void benchmark_parse_cpp_like_1mb ()
{
	test::bundle_index_t bundleIndex;
	bundles::item_ptr grammar = bundleIndex.add(bundles::kItemTypeGrammar, kGrammarPlist);
	bundleIndex.commit();

	std::string text = generate_source(1000000);

	ng::buffer_t buf;
	buf.insert(0, text);

	bool ok = buf.set_grammar(grammar);
	OAK_ASSERT(ok);

	wait_for_eof_t watcher;
	watcher.target = buf.size();
	buf.add_callback(&watcher);

	ng::reset_parse_dispatch_count();

	// Mirrors OakDocument.mm's real load order (insert, set grammar, THEN
	// enable async parsing and bump the revision): set_async_parsing must
	// come before bump_revision, or nothing dispatches at all --
	// initiate_repair's first check is `!_async_parsing`.
	buf.set_async_parsing(true);
	buf.bump_revision();

	run_until_parsed(watcher, "benchmark_parse_cpp_like_1mb");

	buf.remove_callback(&watcher);
	buf.wait_for_repair();

	fprintf(stdout, "benchmark_parse_cpp_like_1mb: %zu bytes, %zu lines, %zu initiate_repair dispatches\n", buf.size(), buf.lines(), ng::parse_dispatch_count());
}
