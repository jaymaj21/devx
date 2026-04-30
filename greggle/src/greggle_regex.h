// Minimal regular-expression AST for path expressions in greggle.
// This supports symbols, concatenation, alternation, Kleene star and plus.

#pragma once

#include <memory>
#include <string>
#include <vector>

namespace greggle {

// Edge-level boolean predicates over labels that guard NFA transitions.
struct EdgePred {
    enum class Kind { Atom, Not, AllOf, SomeOf, Any, SourceNodeMatch, SinkNodeMatch };

    Kind kind = Kind::Atom;
    std::string label; // for Atom
    std::string nodePattern; // for SourceNodeMatch / SinkNodeMatch
    std::vector<std::shared_ptr<EdgePred>> children; // for AllOf / SomeOf
    std::shared_ptr<EdgePred> sub; // for Not
};

struct Regex {
    enum class Kind { Symbol, Concat, Alt, Star, Plus };

    Kind kind;
    std::string symbol;                    // optional name for Symbol
    std::shared_ptr<EdgePred> pred;        // edge predicate for Symbol
    std::vector<std::shared_ptr<Regex>> children; // for Concat / Alt
    std::shared_ptr<Regex> sub;           // for Star / Plus

    explicit Regex(const std::string& sym);
    Regex(Kind k, const std::vector<std::shared_ptr<Regex>>& kids);
    Regex(Kind k, const std::shared_ptr<Regex>& child);
};

// Helper builders
std::shared_ptr<Regex> sym(const std::string& s);
std::shared_ptr<Regex> concat(const std::vector<std::shared_ptr<Regex>>& kids);
std::shared_ptr<Regex> alt(const std::vector<std::shared_ptr<Regex>>& kids);
std::shared_ptr<Regex> star(const std::shared_ptr<Regex>& sub);
std::shared_ptr<Regex> plus(const std::shared_ptr<Regex>& sub);

} // namespace greggle
