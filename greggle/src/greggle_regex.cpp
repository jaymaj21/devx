#include "greggle_regex.h"

namespace greggle {

Regex::Regex(const std::string& sym) : kind(Kind::Symbol), symbol(sym) {}

Regex::Regex(Kind k, const std::vector<std::shared_ptr<Regex>>& kids)
    : kind(k), children(kids) {}

Regex::Regex(Kind k, const std::shared_ptr<Regex>& child)
    : kind(k), sub(child) {}

std::shared_ptr<Regex> sym(const std::string& s) {
    return std::make_shared<Regex>(s);
}

std::shared_ptr<Regex> concat(const std::vector<std::shared_ptr<Regex>>& kids) {
    return std::make_shared<Regex>(Regex::Kind::Concat, kids);
}

std::shared_ptr<Regex> alt(const std::vector<std::shared_ptr<Regex>>& kids) {
    return std::make_shared<Regex>(Regex::Kind::Alt, kids);
}

std::shared_ptr<Regex> star(const std::shared_ptr<Regex>& sub) {
    return std::make_shared<Regex>(Regex::Kind::Star, sub);
}

std::shared_ptr<Regex> plus(const std::shared_ptr<Regex>& sub) {
    return std::make_shared<Regex>(Regex::Kind::Plus, sub);
}

} // namespace greggle
