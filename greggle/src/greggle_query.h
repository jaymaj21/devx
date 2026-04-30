// Core query structures and evaluator for greggle.
// - variables over a finite node domain
// - exist-path path predicates with regex over edge labels
// - logical AND / OR
// - existential quantification

#pragma once

#include "greggle_domain.h"
#include "greggle_graph.h"
#include "greggle_regex.h"

#include <memory>
#include <string>
#include <vector>

namespace greggle {

struct Expr {
    enum class Kind { Exists, And, Or, Not, ExistsPath, NoEdge, NoConnection, Same, Different,
                      Match };

    Kind kind;

    // For Exists / Not
    std::vector<const Variable*> quantVars;
    std::shared_ptr<Expr> subExpr;

    // For And/Or
    std::vector<std::shared_ptr<Expr>> children;

    // For ExistsPath and relational predicates over variables
    const Variable* v1 = nullptr;
    const Variable* v2 = nullptr;
    std::shared_ptr<Regex> regex;

    // For string-regex-based node predicates
    std::string strPattern;

    static std::shared_ptr<Expr> exists(const std::vector<const Variable*>& vars,
                                        const std::shared_ptr<Expr>& sub);
    static std::shared_ptr<Expr> makeAnd(const std::vector<std::shared_ptr<Expr>>& kids);
    static std::shared_ptr<Expr> makeOr(const std::vector<std::shared_ptr<Expr>>& kids);
    static std::shared_ptr<Expr> existsPath(const Variable* v1,
                                            const Variable* v2,
                                            const std::shared_ptr<Regex>& re);
    static std::shared_ptr<Expr> noEdge(const Variable* v1,
                                        const Variable* v2);
    static std::shared_ptr<Expr> noConnection(const Variable* v1,
                                              const Variable* v2);
    static std::shared_ptr<Expr> same(const Variable* v1,
                                      const Variable* v2);
    static std::shared_ptr<Expr> different(const Variable* v1,
                                           const Variable* v2);
    static std::shared_ptr<Expr> match(const Variable* v,
                                       const std::string& pattern);
};

// Evaluate an expression to a Relation over the free variables.
Relation eval(const Expr& e, const Graph& g,
              const std::vector<const Variable*>& allVars);

} // namespace greggle
