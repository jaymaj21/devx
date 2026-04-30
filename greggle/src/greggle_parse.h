// Minimal S-expression parser and query builder for greggle.

#pragma once

#include "greggle_query.h"

#include <istream>
#include <map>
#include <memory>
#include <string>

namespace greggle {

struct SExpr {
    bool isAtom = true;
    std::string atom;
    std::vector<SExpr> list;
};

// Parse a single S-expression from an input stream.
// Tokens: parentheses and atoms separated by whitespace.
bool parseSExpr(std::istream& in, SExpr& out);

// Build a Regex AST from an S-expression.
// Grammar:
//   atom        -> symbol name
//   (concat e+) -> concatenation
//   (alt e+)    -> alternation
//   (star e)    -> repetition *
//   (plus e)    -> repetition +
std::shared_ptr<Regex> buildRegex(const SExpr& sexpr);

// Build an Expr AST from an S-expression.
// Grammar:
//   (exists (v1 v2 ...) sub)
//   (and e1 e2 ...)
//   (or  e1 e2 ...)
//   (exists-path v1 v2 regex-expr)
//
// Variables are created on demand in 'vars' using the given domain.
std::shared_ptr<Expr> buildExpr(const SExpr& sexpr,
                                Domain& dom,
                                std::map<std::string, std::unique_ptr<Variable>>& vars);

} // namespace greggle
