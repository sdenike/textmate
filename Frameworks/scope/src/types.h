#ifndef PARSER_TYPES_H_C8O3OEFQ
#define PARSER_TYPES_H_C8O3OEFQ

#include <oak/debug.h>

namespace scope
{
	struct scope_t;

	namespace types
	{
		struct any_t
		{
			virtual ~any_t () { }
			virtual bool does_match (scope::scope_t const& lhs, scope::scope_t const& rhs, double* rank) const = 0;
			virtual std::string to_s () const = 0;
		};

		typedef std::shared_ptr<any_t> any_ptr;

		struct scope_t
		{
			scope_t () : anchor_to_previous(false) { }
			std::string atoms;
			bool anchor_to_previous;
		};

		struct path_t : any_t
		{
			path_t () : anchor_to_bol(false), anchor_to_eol(false) { }
			std::vector<scope_t> scopes;
			bool anchor_to_bol;
			bool anchor_to_eol;

			// Fast-reject: when set, some node in the candidate scope’s chain (root
			// to leaf, either side of a possible embedded language) must have this
			// as a dotted-prefix, or the path cannot match. Unset ("unknown") for
			// anything not proven safe — e.g. the first scope contains a '*' — in
			// which case does_match always falls through to the full algorithm.
			std::optional<std::string> root_prefix;

			bool does_match (scope::scope_t const& lhs, scope::scope_t const& rhs, double* rank) const;
			std::string to_s () const;
		};

		struct expression_t
		{
			expression_t (char op) : op((op_t)op), negate(false) { }
			enum op_t { op_none, op_or = '|', op_and = '&', op_minus = '-' } op;
			bool negate;
			any_ptr selector;

			bool does_match (scope::scope_t const& lhs, scope::scope_t const& rhs, double* rank) const;
		};

		struct composite_t
		{
			std::vector<expression_t> expressions;

			bool does_match (scope::scope_t const& lhs, scope::scope_t const& rhs, double* rank) const;
		};

		struct selector_t
		{
			std::vector<composite_t> composites;

			bool does_match (scope::scope_t const& lhs, scope::scope_t const& rhs, double* rank) const;
		};

		struct group_t : any_t
		{
			selector_t selector;

			bool does_match (scope::scope_t const& lhs, scope::scope_t const& rhs, double* rank) const;
			std::string to_s () const;
		};

		struct filter_t : any_t
		{
			filter_t () : filter(unset) { }
			enum side_t { unset, left = 'L', right = 'R', both = 'B' } filter;
			any_ptr selector;

			bool does_match (scope::scope_t const& lhs, scope::scope_t const& rhs, double* rank) const;
			std::string to_s () const;
		};

		std::string to_s (selector_t const& selector);

	} /* types */

} /* scope */

#endif /* end of include guard: PARSER_TYPES_H_2G9KD2WM */
