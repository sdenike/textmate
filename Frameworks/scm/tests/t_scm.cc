#include <scm/scm.h>
#include <io/exec.h>
#include <text/format.h>
#include <test/jail.h>
#include <chrono>

void test_disabling_scm ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "scmStatus = false\n");
	OAK_ASSERT_EQ(scm::info(jail.path()) ? true : false, false);
}

// Each shared_info_t owns its own dispatch queue (was a function-local
// static — one queue serialized every repo). This test confirms that
// two info_t instances for different paths produce independent status
// without one's lifetime affecting the other's.
void test_two_repos_have_independent_queues ()
{
	static std::string const git = scm::find_executable("git", "TM_GIT");
	if(git == NULL_STR)
		return;

	auto bootstrap = [&](test::jail_t const& jail) {
		std::string script = text::format(
			"{ cd '%1$s' && '%2$s' init -b master "
			"&& '%2$s' config user.email 'test@example.com' "
			"&& '%2$s' config user.name 'Test Test' "
			"&& '%2$s' config commit.gpgsign false "
			"&& touch .dummy && '%2$s' add .dummy "
			"&& '%2$s' commit .dummy -mGetHead ; } >/dev/null",
			jail.path().c_str(), git.c_str());
		io::exec("/bin/sh", "-c", script.c_str(), nullptr);
	};

	test::jail_t jail_a, jail_b;
	bootstrap(jail_a);
	bootstrap(jail_b);

	// Linearize creation. wait_for_status returns when *any* callback
	// fires for the info, including one fired synchronously by
	// push_callback the moment the info gets bound — even if its data
	// has not yet loaded. Creating both infos before either wait would
	// race that window for info_b.
	auto info_a = scm::info(jail_a.path());
	OAK_ASSERT(info_a);
	OAK_ASSERT(scm::wait_for_status(info_a));

	auto info_b = scm::info(jail_b.path());
	OAK_ASSERT(info_b);
	OAK_ASSERT(scm::wait_for_status(info_b));

	OAK_ASSERT_EQ(info_a->scm_variables()["TM_SCM_NAME"], "git");
	OAK_ASSERT_EQ(info_b->scm_variables()["TM_SCM_NAME"], "git");
	OAK_ASSERT_NE(info_a->root_path(), info_b->root_path());
}

// Regression guard for the unbounded-wait hang that cancelled PR #9 and
// PR #17 merge CI runs at the 15-minute GitHub Actions step limit.
// wait_for_status must return within its supplied timeout regardless
// of whether a callback ever fires. The exact value returned (true or
// false) depends on the race between the bootstrap commit's status
// callback and the timeout; what we assert here is the bound itself.
void test_wait_for_status_is_bounded ()
{
	static std::string const git = scm::find_executable("git", "TM_GIT");
	if(git == NULL_STR)
		return;

	test::jail_t jail;
	std::string const script = text::format(
		"{ cd '%1$s' && '%2$s' init -b master "
		"&& '%2$s' config user.email 'test@example.com' "
		"&& '%2$s' config user.name 'Test Test' "
		"&& '%2$s' config commit.gpgsign false "
		"&& touch .dummy && '%2$s' add .dummy "
		"&& '%2$s' commit .dummy -mGetHead ; } >/dev/null",
		jail.path().c_str(), git.c_str());
	io::exec("/bin/sh", "-c", script.c_str(), nullptr);

	auto info = scm::info(jail.path());
	OAK_ASSERT(info);

	// 250 ms cap. The previous implementation could spin forever; this
	// call must return promptly even if no callback arrives in window.
	auto const start = std::chrono::steady_clock::now();
	scm::wait_for_status(info, 0.25);
	auto const elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
		std::chrono::steady_clock::now() - start).count();

	// Generous upper bound: a single CFRunLoopRunInMode chunk plus
	// scheduling slop. Anything in the seconds range means the bound
	// is not being honoured.
	OAK_ASSERT_LT(elapsed_ms, 2000);
}
