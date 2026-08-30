#include <buffer/buffer.h>
#include <test/bundle_index.h>
#include <chrono>

namespace
{
	// A small but genuinely nested grammar -- namespace containing class
	// containing function containing if/for/while blocks, plus comment/
	// string/number/call token rules reachable at every depth via a
	// shared '#body' repository entry -- modeled on how C.tmbundle's C++
	// grammar nests namespace/class bodies (Syntaxes/C++.plist's
	// 'special_block' repository entry), though far smaller. The
	// identifier each namespace/class/function's begin pattern captures is
	// spliced into that rule's own pushed scope name via $-capture
	// expansion (parse.cc's expand(), compiled from format_string::expand),
	// exactly the technique C++.plist uses for
	// 'meta.namespace-block${2:+.$2}.c++' -- so distinct entities get
	// distinct scope stacks, not just distinct surface text.
	//
	// This replaced a six-sibling, non-nesting grammar that measured only
	// 7 distinct scope contexts across a full 1 MB parse: bundles::
	// value_for_setting's settings cache -- which symbols_t::did_parse
	// queries once per distinct scope_t it sees, for every did_parse batch
	// -- was therefore 0% of profiled samples on both threads, so that
	// benchmark could not exercise the cache fix CLAUDE.md records
	// (Frameworks/bundles/src/wrappers.cc, raised from 1000 to 50000
	// entries) at all. Self-contained (no include/repository lookups into
	// real bundles at parse time; only test::bundle_index_t's fixture
	// registry is ever consulted).
	//
	// One string literal per source line, NOT a multi-line raw string:
	// bin/gen_test splices a `#line N "path"` directive before every line
	// of this file's body, textually, with no awareness of C++ literal
	// boundaries. A raw string spanning several source lines would capture
	// those injected directives as literal plist text -- confirmed by
	// hand: plist::parse_ascii silently failed on exactly that, taking the
	// generated `#line ...` lines as garbage inside the value.
	static std::string const kGrammarPlist =
		"{	scopeName = 'source.c_bench';\n"
		"	uuid      = 'B7B6F6C2-9C1E-4E7B-9C0E-6E9B9C1E4E7B';\n"
		"	patterns  = ( { include = '#body'; } );\n"
		"	repository = {\n"
		"		body = { patterns = (\n"
		"			{ include = '#namespace'; },\n"
		"			{ include = '#class'; },\n"
		"			{ include = '#function'; },\n"
		"			{ include = '#control-block'; },\n"
		"			{ include = '#bare-block'; },\n"
		"			{ include = '#common'; },\n"
		"		); };\n"
		"		namespace = {\n"
		"			begin = '\\b(namespace)\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\{';\n"
		"			beginCaptures = { 1 = { name = 'storage.type.bench'; }; 2 = { name = 'entity.name.namespace.bench'; }; };\n"
		"			end  = '\\}';\n"
		"			name = 'meta.namespace.bench.$2';\n"
		"			patterns = ( { include = '#body'; } );\n"
		"		};\n"
		"		class = {\n"
		"			begin = '\\b(class|struct)\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\{';\n"
		"			beginCaptures = { 1 = { name = 'storage.type.bench'; }; 2 = { name = 'entity.name.class.bench'; }; };\n"
		"			end  = '\\}';\n"
		"			name = 'meta.class.bench.$2';\n"
		"			patterns = ( { include = '#body'; } );\n"
		"		};\n"
		"		function = {\n"
		"			begin = '\\b(int|void|bool|double)\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\([^)]*\\)\\s*\\{';\n"
		"			beginCaptures = { 1 = { name = 'storage.type.bench'; }; 2 = { name = 'entity.name.function.bench'; }; };\n"
		"			end  = '\\}';\n"
		"			name = 'meta.function.bench.$2';\n"
		"			patterns = ( { include = '#body'; } );\n"
		"		};\n"
		"		control-block = {\n"
		"			begin = '\\b(if|for|while)\\b[^{]*\\{';\n"
		"			beginCaptures = { 1 = { name = 'keyword.control.bench'; }; };\n"
		"			end  = '\\}';\n"
		"			name = 'meta.block.control.bench.$1';\n"
		"			patterns = ( { include = '#body'; } );\n"
		"		};\n"
		"		bare-block = {\n"
		"			begin = '\\{';\n"
		"			end   = '\\}';\n"
		"			name  = 'meta.block.bench';\n"
		"			patterns = ( { include = '#body'; } );\n"
		"		};\n"
		"		common = { patterns = (\n"
		"			{ name = 'comment.line.double-slash.bench'; match = '//.*$'; },\n"
		"			{ name = 'comment.block.bench'; begin = '/\\*'; end = '\\*/'; },\n"
		"			{ name = 'string.quoted.double.bench'; begin = '\"'; end = '\"';\n"
		"			  patterns = ( { name = 'constant.character.escape.bench'; match = '\\\\.'; } ); },\n"
		"			{ name = 'keyword.control.bench'; match = '\\b(return|public|auto)\\b'; },\n"
		"			{ name = 'constant.numeric.bench'; match = '\\b[0-9]+\\b'; },\n"
		"			{ name = 'entity.name.function.call.bench'; match = '\\b[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()'; },\n"
		"		); };\n"
		"	};\n"
		"}\n";

	// ===========================================================================
	// = Realistic bundles::kItemTypeSettings population (STREAM.md 2026-08-29) =
	// ===========================================================================
	//
	// symbols_t::did_parse (buffer/src/symbols.cc) calls bundles::value_for_setting
	// ("showInSymbolList", scope) -- and, when that is true, ("symbolTransformation",
	// scope) too -- once per distinct scope it sees in every did_parse batch. That
	// query lands in bundles::cache_search (query.cc), which equal-range-scans
	// whichever items registered "showInSymbolList" under kFieldSettingName and
	// calls item_t::does_match -> scope::selector_t::does_match on each: this is
	// the exact path the historical profile put at 72% of samples, and Phase 7's
	// does_match fast-reject (match.cc's root_prefix) exists to speed up. Until
	// this fixture had zero Settings items registered, so that bucket was always
	// empty and cache_search/does_match never ran at all.
	//
	// Measured against the 54 bundles actually installed under ~/Library/
	// Application Support/TextMate/Managed/Bundles/, not guessed: 272 Settings
	// items total (every *.plist/*.tmDelta/*.tmPreferences under a bundle's
	// Preferences/, per load.cc's own glob), 265 with a non-empty scope selector,
	// 7 with none (match unconditionally). Only 53 of the 272 declare
	// 'showInSymbolList' -- the only setting name this benchmark's own code path
	// ever queries, so the only one cache_search's equal-range bucket here is ever
	// non-empty for -- matching HANDOFF.md's "all 53 installed settings items"
	// from the original profile, and 53 * ~61,000 distinct scopes (CLAUDE.md's
	// real-1MB-file figure) lands on the ~3.25M selector evaluations it also
	// records. Their shape breakdown: 31 descendant paths (space-separated
	// ancestor chains), 12 bare literals, 7 comma-separated, 2 using the '-'
	// composite operator, 1 parenthesised sub-selector -- kept verbatim below so
	// shape AND count are both real: a fixture of only bare literals would
	// exercise path_t::does_match's root_prefix fast-reject's REJECT branch and
	// nothing else match.cc can do.
	static char const* const kRealShowInSymbolListScopes[] = {
		"entity.name.function.active4d",
		"meta.toc-list.directory.apache-config",
		"meta.toc-list.location.apache-config",
		"meta.vhost.apache-config meta.toc-list.directory.apache-config",
		"meta.vhost.apache-config meta.toc-list.location.apache-config",
		"meta.toc-list.virtual-host.apache-config",
		"source.plist.textmate.grammar support.constant.repository",
		"source.plist.textmate.grammar meta.value-pair.repository-item constant.other.scope - meta.dictionary.captures",
		"source.plist.textmate.grammar meta.dictionary.repository entity.name.section.repository",
		"source.plist.textmate.grammar constant.other.scope - (meta.dictionary.repository|meta.value-pair.scopename)",
		"entity.name.type.inherited.c++",
		"source.css comment.block.css -text source.css",
		"* source.css meta.selector, * source.css meta.at-rule.media",
		"source.css meta.selector, source.css meta.at-rule.media",
		"source.coffee meta.function.coffee",
		"source.coffee entity.name.type.instance",
		"source.erlang entity.name.function.definition",
		"source.erlang entity.name.function.macro.definition",
		"source.erlang entity.name.type.class.module.definition.erlang",
		"source.erlang entity.name.type.class.record.definition",
		"source.erlang entity.name.function, source.erlang entity.name.type.class",
		"entity.name.section.subsection.git-config - punctuation.definition.section.subsection",
		"entity.name.section.git-config",
		"source.go meta.function.declaration.go",
		"source.go meta.function.receiver.declaration.go",
		"source.groovy meta.definition.class meta.definition.variable.name",
		"source.groovy entity.name.type.class",
		"source.groovy meta.definition.class meta.definition.method.signature",
		"source.groovy meta.definition.method.signature",
		"source.groovy meta.definition.variable.name",
		"meta.attribute.id.html > string",
		"source.java meta.class meta.class.identifier",
		"source.java meta.class.body meta.class.body meta.method.identifier",
		"source.java meta.class.body meta.class.identifier",
		"source.java meta.class.body meta.class.body meta.class.body meta.method.identifier",
		"source.java meta.class.body meta.class.body meta.class.identifier",
		"source.java meta.class.body meta.method.identifier",
		"source.js entity.name.function.js, source.js meta.function.js meta.function.variable.js",
		"text.html.markdown markup.heading",
		"meta.function.objc",
		"support.function.magic.php",
		"entity.name.goto-label.php",
		"constant.other.name.xml.plist",
		"source.python meta.function.python, source.python meta.class.python",
		"source.python meta.function.decorator.python entity.name.function.decorator.python",
		"source.ruby meta.function",
		"meta.class.ruby",
		"source.ruby meta.function-call entity.name.function",
		"source.sql meta.create.sql, source.sql meta.drop.sql, source.sql meta.alter.sql",
		"entity.name.function, entity.name.type, meta.toc-list",
		"meta.group.toml",
		"text.xml.xsl meta.tag.xml.template",
		"source.yaml entity.name.tag.yaml",
	};

	// Registers the 53 real selectors above under kFieldSettingName
	// "showInSymbolList", plus one deliberately-matching item: 'meta.function.bench'
	// is the scope generate_function's rule pushes (kGrammarPlist above), the same
	// shape as a language bundle's OWN symbol-list setting for whatever file is
	// actually open -- which none of the 53 real ones (all for other languages) is.
	// Without it, every does_match call this benchmark makes would take the
	// fast-reject's REJECT branch, and the ACCEPT branch -- the recursive walk in
	// path_t::does_match actually running to completion -- would go unexercised.
	void register_real_symbol_list_settings (test::bundle_index_t& bundleIndex)
	{
		for(char const* scope : kRealShowInSymbolListScopes)
			bundleIndex.add(bundles::kItemTypeSettings, std::string("{ settings = { showInSymbolList = 1; }; scope = '") + scope + "'; }");

		bundleIndex.add(bundles::kItemTypeSettings, "{ settings = { showInSymbolList = 1; }; scope = 'meta.function.bench entity.name.function.bench'; }");
	}

	// The other 219 of the real install's 272 Settings items: 212 with a scope
	// (shape distribution is the overall 265 minus the 53 above) plus the measured
	// 7 with none. None of these declare showInSymbolList or symbolTransformation,
	// so cache_search never scans them for this benchmark's own queries -- they
	// exist only so AllItems, and bundles::cache_t::fetch's one-time build of the
	// "settings" bucket map, are the real install's order of magnitude rather than
	// just the 53 that matter to did_parse. Selectors are generated, not copied
	// verbatim, cycling real root/leaf scope vocabulary through the measured
	// per-shape proportions.
	void register_settings_chaff (test::bundle_index_t& bundleIndex)
	{
		static char const* const kOtherKeys[] = {
			"shellVariables", "foldingStopMarker", "foldingStartMarker", "decreaseIndentPattern",
			"increaseIndentPattern", "smartTypingPairs", "disableIndentCorrections", "highlightPairs",
			"completions", "spellChecking", "indentedSoftWrap", "foldingIndentedBlockStart",
			"indentOnPaste", "softWrap", "indentNextLinePattern", "unIndentedLinePattern",
			"foreground", "background",
		};
		static char const* const kRoots[] = {
			"source.ruby", "source.python", "source.php", "text.html.basic", "source.js", "source.css",
			"source.java", "source.go", "source.perl", "source.lua", "text.xml", "source.shell",
		};
		static char const* const kLeaves[] = {
			"meta.function", "string.quoted.double", "comment.block", "entity.name.tag",
			"keyword.control", "meta.class", "constant.numeric", "variable.parameter",
		};
		struct shape_count_t { std::string shape; int count; };
		// 157/20/21/8/2/3/1 = the overall 265 (bare 169, descendant 51, comma 28,
		// operator 10, parenthesized 3, filter 3, wildcard 1) minus the 53 real
		// showInSymbolList items' own shapes (bare 12, descendant 31, comma 7,
		// operator 2, parenthesized 1, filter 0, wildcard 0) -- so the two sets
		// together reproduce the real, measured, overall distribution exactly.
		static shape_count_t const kShapeCounts[] = {
			{ "bare", 157 }, { "descendant", 20 }, { "comma", 21 }, { "operator", 8 },
			{ "parenthesized", 2 }, { "filter", 3 }, { "wildcard", 1 },
		};

		size_t i = 0;
		for(auto const& shapeCount : kShapeCounts)
		{
			for(int n = 0; n < shapeCount.count; ++n, ++i)
			{
				std::string const root  = kRoots[i % (sizeof(kRoots)/sizeof(*kRoots))];
				std::string const root2 = kRoots[(i + 5) % (sizeof(kRoots)/sizeof(*kRoots))];
				std::string const leaf  = kLeaves[i % (sizeof(kLeaves)/sizeof(*kLeaves))];
				std::string const key   = kOtherKeys[i % (sizeof(kOtherKeys)/sizeof(*kOtherKeys))];

				std::string scope;
				if(shapeCount.shape == "bare")               scope = root;
				else if(shapeCount.shape == "descendant")    scope = root + " " + leaf;
				else if(shapeCount.shape == "comma")         scope = root + " " + leaf + ", " + root2 + " " + leaf;
				else if(shapeCount.shape == "operator")      scope = root + " " + leaf + " - " + root + " punctuation.definition";
				else if(shapeCount.shape == "parenthesized") scope = "(" + root + " | " + root2 + ") - " + leaf;
				else if(shapeCount.shape == "filter")        scope = "L:" + root + " " + leaf;
				else                                         scope = root + ".*"; // wildcard

				bundleIndex.add(bundles::kItemTypeSettings, "{ settings = { " + key + " = 1; }; scope = '" + scope + "'; }");
			}
		}

		for(int n = 0; n < 7; ++n, ++i)
		{
			std::string const key = kOtherKeys[i % (sizeof(kOtherKeys)/sizeof(*kOtherKeys))];
			bundleIndex.add(bundles::kItemTypeSettings, "{ settings = { " + key + " = 1; }; }");
		}
	}

	// Emits one leaf statement inside a function or block body -- a
	// comment, a string literal, a numeric constant, a call-like
	// reference, or a return -- so the token-level scopes (comment/
	// string/number/call) recur at every nesting depth, not just the
	// structural namespace/class/function/block scopes. 'id' is drawn
	// fresh from the caller's counter, so distinct leaves carry distinct
	// text (a distinct string literal, a distinct number, and so on).
	std::string generate_leaf (size_t id, std::string const& indent)
	{
		switch(id % 5)
		{
			case 0:  return indent + "// note " + std::to_string(id) + "\n";
			case 1:  return indent + "auto text_" + std::to_string(id) + " = \"payload " + std::to_string(id) + "\";\n";
			case 2:  return indent + "auto count_" + std::to_string(id) + " = " + std::to_string(id % 9973) + ";\n";
			case 3:  return indent + "helper_call(" + std::to_string(id) + ");\n";
			default: return indent + "return x + y;\n";
		}
	}

	// Emits an if/for/while control-block nested 'depth' levels deep, with
	// a leaf at every level and, at the innermost level, an occasional
	// bare compound block for extra shape variety. The construct kind and
	// leaf content both vary with the counter, so two calls at the same
	// depth still differ -- runs of source text differ in *shape*, not
	// only in the names sprinkled through one repeating template. Depth
	// is capped by the caller (generate_function).
	std::string generate_block (size_t& idCounter, int depth, std::string const& indent)
	{
		size_t const id = idCounter++;
		std::string res = generate_leaf(id, indent);

		if(depth > 0)
		{
			static char const* const kinds[] = { "if", "for", "while" };
			std::string const kind = kinds[id % 3];
			std::string const cond = kind == "for"
				? "(size_t i = 0; i < " + std::to_string(id % 13 + 1) + "; ++i)"
				: "(" + std::to_string(id % 7) + " > " + std::to_string(id % 3) + ")";

			res += indent + kind + " " + cond + " {\n";
			res += generate_block(idCounter, depth - 1, indent + "\t");
			res += indent + "}\n";
		}
		else if(id % 6 == 0) // an occasional bare compound block, for shape variety
		{
			res += indent + "{\n";
			res += generate_leaf(idCounter++, indent + "\t");
			res += indent + "}\n";
		}

		return res;
	}

	// Emits one complete function -- signature, then a control-block nest
	// whose depth varies with the counter -- named uniquely across the
	// whole generated buffer. That per-function uniqueness is the main
	// source of distinct scope contexts: every position inside a uniquely
	// named function's body carries that function's own atom, so it
	// differs from the same relative position in any other function
	// regardless of which token or control-block happens to be active
	// there (see the file comment above kGrammarPlist).
	std::string generate_function (size_t& idCounter, std::string const& indent)
	{
		static char const* const returnTypes[] = { "int", "void", "bool", "double" };
		size_t const id = idCounter++;

		std::string res = indent + returnTypes[id % 4] + " fn_" + std::to_string(id) + " (int x, int y) {\n";
		res += generate_block(idCounter, int(id % 3), indent + "\t"); // depth 0..2
		res += indent + "}\n\n";
		return res;
	}

	// Emits one class (occasionally a struct, for a little extra token
	// variety) containing 'methodCount' uniquely-named methods.
	std::string generate_class (size_t& idCounter, size_t methodCount, std::string const& indent)
	{
		size_t const id = idCounter++;
		std::string res = indent + (id % 2 == 0 ? "class " : "struct ") + "widget_" + std::to_string(id) + " {\n";
		res += indent + "public:\n";
		for(size_t i = 0; i < methodCount; ++i)
			res += generate_function(idCounter, indent + "\t");
		res += indent + "};\n\n";
		return res;
	}

	// Emits one namespace containing 'classCount' uniquely-named classes.
	std::string generate_namespace (size_t& idCounter, size_t classCount, size_t methodsPerClass)
	{
		size_t const id = idCounter++;
		std::string res = "namespace ns_" + std::to_string(id) + " {\n";
		res += "\t// namespace ns_" + std::to_string(id) + " groups related widgets\n";
		for(size_t i = 0; i < classCount; ++i)
			res += generate_class(idCounter, methodsPerClass, "\t");
		res += "}\n\n";
		return res;
	}

	// Generates deterministic, C++-like source text with GENUINE nesting --
	// namespaces containing classes containing methods containing
	// if/for/while blocks, every entity named uniquely -- repeated until it
	// is at least targetBytes long. Generated rather than a committed
	// fixture, and hermetic (no filesystem access): the benchmark needs
	// nothing beyond this source file.
	std::string generate_source (size_t targetBytes)
	{
		std::string res;
		res.reserve(targetBytes + 4096);

		size_t idCounter = 0;
		while(res.size() < targetBytes)
			res += generate_namespace(idCounter, 3, 4);

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
	register_real_symbol_list_settings(bundleIndex);
	register_settings_chaff(bundleIndex);
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

	// Fidelity check, not a timing measurement: a grammar that doesn't
	// actually compound scopes on nested input would silently turn this
	// benchmark back into the flat one it replaced. 10000 is a floor with
	// headroom below what this fixture measures (see STREAM.md) -- high
	// enough that a regression back to a handful of shapes (the old flat
	// grammar produced 7) cannot pass, without being brittle to small
	// generator tweaks. CLAUDE.md's ~61,000 distinct scope contexts for a
	// real 1 MB C++ file is the target order of magnitude; this synthetic
	// fixture is not expected to match it exactly.
	std::set<scope::scope_t> distinctScopes;
	for(auto const& pair : buf.scopes(0, buf.size()))
		distinctScopes.insert(pair.second);
	OAK_ASSERT(distinctScopes.size() > 10000);

	fprintf(stdout, "benchmark_parse_cpp_like_1mb: %zu bytes, %zu lines, %zu initiate_repair dispatches, %zu distinct scope contexts\n", buf.size(), buf.lines(), ng::parse_dispatch_count(), distinctScopes.size());
}
