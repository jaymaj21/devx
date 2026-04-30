#include "greggle_domain.h"
#include "greggle_graph.h"
#include "greggle_query.h"
#include "greggle_parse.h"

#include <bdd.h>

#include <functional>
#include <algorithm>
#include <cctype>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <regex>
#include <set>
#include <sstream>
#include <queue>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

struct EdgeSpec {
    int src;
    int dst;
    std::set<std::string> labels;
};

static std::string trim(const std::string& s) {
    std::size_t b = 0;
    while (b < s.size() && std::isspace(static_cast<unsigned char>(s[b]))) {
        ++b;
    }
    std::size_t e = s.size();
    while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) {
        --e;
    }
    return s.substr(b, e - b);
}

static std::string unquote(const std::string& s) {
    if (s.size() >= 2 && s.front() == '"' && s.back() == '"') {
        return s.substr(1, s.size() - 2);
    }
    return s;
}

static bool extractQuotedAttrValue(const std::string& text,
                                   const std::string& attrName,
                                   std::string& value) {
    std::size_t pos = text.find(attrName + "=");
    if (pos == std::string::npos) {
        return false;
    }
    std::size_t q1 = text.find('"', pos);
    if (q1 == std::string::npos) {
        return false;
    }
    std::size_t q2 = text.find('"', q1 + 1);
    if (q2 == std::string::npos) {
        return false;
    }
    value = text.substr(q1 + 1, q2 - q1 - 1);
    return true;
}

static int smallestPos(std::size_t a, std::size_t b) {
    const std::size_t npos = std::string::npos;
    if (a == npos) return static_cast<int>(b);
    if (b == npos) return static_cast<int>(a);
    return static_cast<int>(std::min(a, b));
}

// Very small DOT parser for graphs like large_graph.dot:
//   digraph name { 
//     node;
//     src -> dst [label="a,b"];
//   }
// Node identifiers may be bare or quoted. Edge labels are a comma-separated
// list inside the label attribute.
static bool parseDotFile(
    const std::string& path,
    std::vector<std::string>& idToName,
    std::vector<std::string>& nodeLabels,
    std::vector<EdgeSpec>& edges)
{
    std::ifstream in(path);
    if (!in) {
        std::cerr << "Error: cannot open DOT file '" << path << "'\n";
        return false;
    }

    std::map<std::string, int> labelToId;

    auto getId = [&](const std::string& name) -> int {
        auto it = labelToId.find(name);
        if (it != labelToId.end()) {
            return it->second;
        }
        int id = static_cast<int>(idToName.size());
        labelToId[name] = id;
        idToName.push_back(name);
        nodeLabels.push_back(name);
        return id;
    };

    std::string line;
    while (std::getline(in, line)) {
        std::string t = trim(line);
        if (t.empty()) continue;
        if (t.rfind("digraph", 0) == 0) continue;
        if (t == "{" || t == "}") continue;

        // Edge line: src -> dst [label="..."];
        std::size_t arrow = t.find("->");
        if (arrow == std::string::npos) {
            // Might be a standalone node declaration: "name;" or "name [label="..."];"
            std::size_t semi = t.find(';');
            if (semi != std::string::npos) {
                std::string nodeDecl = trim(t.substr(0, semi));
                std::size_t bracket = nodeDecl.find('[');
                std::string nodeName = trim(nodeDecl.substr(0, bracket));
                nodeName = unquote(nodeName);
                if (!nodeName.empty()) {
                    int nodeId = getId(nodeName);
                    std::string nodeLabel;
                    if (bracket != std::string::npos &&
                        extractQuotedAttrValue(nodeDecl.substr(bracket), "label", nodeLabel)) {
                        nodeLabels[static_cast<std::size_t>(nodeId)] = nodeLabel;
                    }
                }
            }
            continue;
        }

        std::string left = trim(t.substr(0, arrow));
        left = unquote(left);

        std::string rest = t.substr(arrow + 2);
        int endDest = smallestPos(rest.find('['), rest.find(';'));
        if (endDest < 0) endDest = static_cast<int>(rest.size());
        std::string right = trim(rest.substr(0, static_cast<std::size_t>(endDest)));
        right = unquote(right);

        int srcId = getId(left);
        int dstId = getId(right);

        std::set<std::string> labels;
        std::size_t labPos = t.find("label=");
        if (labPos != std::string::npos) {
            std::size_t q1 = t.find('"', labPos);
            if (q1 != std::string::npos) {
                std::size_t q2 = t.find('"', q1 + 1);
                if (q2 != std::string::npos && q2 > q1 + 1) {
                    std::string labStr = t.substr(q1 + 1, q2 - q1 - 1);
                    std::stringstream ss(labStr);
                    std::string tok;
                    while (std::getline(ss, tok, ',')) {
                        tok = trim(tok);
                        if (!tok.empty()) {
                            labels.insert(tok);
                        }
                    }
                }
            }
        }

        EdgeSpec e;
        e.src = srcId;
        e.dst = dstId;
        e.labels = std::move(labels);
        edges.push_back(std::move(e));
    }

    return true;
}

// --- NFA + path witness ----------------------------------------------------

struct NFAState {
    bool accepting = false;
    std::vector<int> eps;                          // epsilon edges
    std::vector<std::pair<std::shared_ptr<greggle::EdgePred>,int>> trans;
};

struct NFA {
    int start = 0;
    std::vector<NFAState> states;
};

static int newState(NFA& nfa) {
    int id = static_cast<int>(nfa.states.size());
    nfa.states.emplace_back();
    return id;
}

static std::shared_ptr<greggle::EdgePred> atomPred(const std::string& lab) {
    auto p = std::make_shared<greggle::EdgePred>();
    p->kind = greggle::EdgePred::Kind::Atom;
    p->label = lab;
    return p;
}

static std::pair<int,int> buildNFA(const std::shared_ptr<greggle::Regex>& re, NFA& nfa) {
    using Kind = greggle::Regex::Kind;
    if (!re) {
        int s = newState(nfa);
        int e = newState(nfa);
        nfa.states[s].eps.push_back(e);
        return {s,e};
    }
    switch (re->kind) {
    case Kind::Symbol: {
        int s = newState(nfa);
        int e = newState(nfa);
        std::shared_ptr<greggle::EdgePred> p = re->pred;
        if (!p) p = atomPred(re->symbol);
        nfa.states[s].trans.emplace_back(p, e);
        return {s,e};
    }
    case Kind::Concat: {
        std::pair<int,int> acc;
        bool first = true;
        for (const auto& child : re->children) {
            auto sub = buildNFA(child, nfa);
            if (first) {
                acc = sub;
                first = false;
            } else {
                nfa.states[acc.second].eps.push_back(sub.first);
                acc.second = sub.second;
            }
        }
        if (first) {
            int s = newState(nfa);
            int e = newState(nfa);
            nfa.states[s].eps.push_back(e);
            return {s,e};
        }
        return acc;
    }
    case Kind::Alt: {
        int s = newState(nfa);
        int e = newState(nfa);
        for (const auto& child : re->children) {
            auto sub = buildNFA(child, nfa);
            nfa.states[s].eps.push_back(sub.first);
            nfa.states[sub.second].eps.push_back(e);
        }
        return {s,e};
    }
    case Kind::Star: {
        auto sub = buildNFA(re->sub, nfa);
        int s = newState(nfa);
        int e = newState(nfa);
        nfa.states[s].eps.push_back(sub.first);
        nfa.states[s].eps.push_back(e);
        nfa.states[sub.second].eps.push_back(sub.first);
        nfa.states[sub.second].eps.push_back(e);
        return {s,e};
    }
    case Kind::Plus: {
        auto sub = buildNFA(re->sub, nfa);
        int s = newState(nfa);
        int e = newState(nfa);
        nfa.states[s].eps.push_back(sub.first);
        nfa.states[sub.second].eps.push_back(sub.first);
        nfa.states[sub.second].eps.push_back(e);
        return {s,e};
    }
    }
    int s = newState(nfa);
    int e = newState(nfa);
    nfa.states[s].eps.push_back(e);
    return {s,e};
}

static bool evalEdgePred(const greggle::EdgePred& p,
                         const std::set<std::string>& labels,
                         const std::string& srcNodeLabel,
                         const std::string& dstNodeLabel) {
    using K = greggle::EdgePred::Kind;
    switch (p.kind) {
    case K::Any: return true;
    case K::Atom: return labels.count(p.label) > 0;
    case K::SourceNodeMatch:
        try {
            return std::regex_match(srcNodeLabel, std::regex(p.nodePattern));
        } catch (const std::regex_error&) {
            return false;
        }
    case K::SinkNodeMatch:
        try {
            return std::regex_match(dstNodeLabel, std::regex(p.nodePattern));
        } catch (const std::regex_error&) {
            return false;
        }
    case K::Not: return p.sub ? !evalEdgePred(*p.sub, labels, srcNodeLabel, dstNodeLabel) : true;
    case K::AllOf:
        for (const auto& c : p.children) {
            if (c && !evalEdgePred(*c, labels, srcNodeLabel, dstNodeLabel)) return false;
        }
        return true;
    case K::SomeOf:
        for (const auto& c : p.children) {
            if (c && evalEdgePred(*c, labels, srcNodeLabel, dstNodeLabel)) return true;
        }
        return false;
    }
    return false;
}

static void epsilonClosure(const NFA& nfa, const std::set<int>& in, std::set<int>& out) {
    std::vector<int> stack(in.begin(), in.end());
    out = in;
    while (!stack.empty()) {
        int s = stack.back();
        stack.pop_back();
        for (int t : nfa.states[s].eps) {
            if (!out.count(t)) {
                out.insert(t);
                stack.push_back(t);
            }
        }
    }
}

// Return one witness path as list of (src,dst) node IDs, or empty if none.
static std::vector<std::pair<int,int>> findWitnessPath(const greggle::Graph& g,
                                                       const std::shared_ptr<greggle::Regex>& re) {
    NFA nfa;
    auto sp = buildNFA(re, nfa);
    nfa.start = sp.first;
    nfa.states[sp.second].accepting = true;

    struct Key { int node; int state; };
    auto pack = [](Key k){ return ((long long)k.node<<32) ^ (long long)(unsigned int)k.state; };
    std::unordered_map<long long, std::pair<long long, std::pair<int,int>>> pred;

    for (int startNode = 0; startNode < g.numNodes(); ++startNode) {
        std::queue<Key> q;
        std::set<int> startSet{nfa.start};
        std::set<int> closure;
        epsilonClosure(nfa, startSet, closure);
        std::set<long long> visited;
        for (int sState : closure) {
            Key k{startNode, sState};
            q.push(k);
            visited.insert(pack(k));
        }
        while (!q.empty()) {
            Key cur = q.front(); q.pop();
            if (nfa.states[cur.state].accepting) {
                // reconstruct
                std::vector<std::pair<int,int>> path;
                long long key = pack(cur);
                while (pred.count(key)) {
                    auto info = pred[key];
                    auto edge = info.second;
                    path.push_back(edge);
                    key = info.first;
                }
                std::reverse(path.begin(), path.end());
                return path;
            }
            for (const auto& edge : g.outgoing(cur.node)) {
                for (const auto& tr : nfa.states[cur.state].trans) {
                    if (!tr.first || evalEdgePred(*tr.first,
                                                  edge.labels,
                                                  g.nodeLabel(edge.src),
                                                  g.nodeLabel(edge.dst))) {
                        std::set<int> ns{tr.second};
                        std::set<int> nsc;
                        epsilonClosure(nfa, ns, nsc);
                        for (int nxt : nsc) {
                            Key nk{edge.dst, nxt};
                            long long pk = pack(nk);
                            if (!visited.count(pk)) {
                                visited.insert(pk);
                                pred[pk] = {pack(cur), {edge.src, edge.dst}};
                                q.push(nk);
                            }
                        }
                    }
                }
            }
        }
    }
    return {};
}

static void writeDot(const std::vector<std::string>& idToName,
                     const std::vector<std::string>& nodeLabels,
                     const std::vector<EdgeSpec>& edges) {
    std::cout << "digraph G {\n";
    for (std::size_t i = 0; i < idToName.size(); ++i) {
        std::cout << "    \"" << idToName[i] << "\"";
        if (i < nodeLabels.size() && nodeLabels[i] != idToName[i]) {
            std::cout << " [label=\"" << nodeLabels[i] << "\"]";
        }
        std::cout << ";\n";
    }
    for (const auto& e : edges) {
        std::cout << "    \"" << idToName[static_cast<std::size_t>(e.src)] << "\" -> "
                  << "\"" << idToName[static_cast<std::size_t>(e.dst)] << "\"";
        if (!e.labels.empty()) {
            std::cout << " [label=\"";
            bool first = true;
            for (const auto& lab : e.labels) {
                if (!first) std::cout << ",";
                std::cout << lab;
                first = false;
            }
            std::cout << "\"]";
        }
        std::cout << ";\n";
    }
    std::cout << "}\n";
}

} // namespace

int main(int argc, char** argv)
{
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0]
                  << " <graph.dot> \"<query in lisp syntax>\"\n";
        return 1;
    }

    const std::string dotPath = argv[1];
    const std::string queryText = argv[2];

    // Initialize Buddy before using any BDD-backed greggle structures.
    bdd_init(1000000, 1000000);

    std::vector<std::string> idToName;
    std::vector<std::string> nodeLabels;
    std::vector<EdgeSpec> edgeSpecs;
    if (!parseDotFile(dotPath, idToName, nodeLabels, edgeSpecs)) {
        bdd_done();
        return 1;
    }

    if (idToName.empty()) {
        std::cerr << "Error: DOT graph contains no nodes.\n";
        bdd_done();
        return 1;
    }

    greggle::Graph g(static_cast<int>(idToName.size()));
    // Install node labels so regex_match/regex_search can see them.
    for (std::size_t i = 0; i < nodeLabels.size(); ++i) {
        g.setNodeLabel(static_cast<int>(i), nodeLabels[i]);
    }
    for (const auto& e : edgeSpecs) {
        g.addEdge(e.src, e.dst, e.labels);
    }

    greggle::Domain nodeDom("Node", g.numNodes());
    std::map<std::string, std::unique_ptr<greggle::Variable>> vars;

    std::istringstream iss(queryText);
    greggle::SExpr sexpr;
    if (!greggle::parseSExpr(iss, sexpr)) {
        std::cerr << "Error: failed to parse query.\n";
        bdd_done();
        return 1;
    }

    // Special handling for (find-path <regex> <label>)
    if (!sexpr.isAtom && !sexpr.list.empty() && sexpr.list[0].isAtom &&
        sexpr.list[0].atom == "find-path") {
        if (sexpr.list.size() != 3) {
            std::cerr << "find-path expects (find-path <regex> <label>)\n";
            bdd_done();
            return 1;
        }
        std::shared_ptr<greggle::Regex> re;
        try {
            re = greggle::buildRegex(sexpr.list[1]);
        } catch (const std::exception& ex) {
            std::cerr << "Error while building regex: " << ex.what() << "\n";
            bdd_done();
            return 1;
        }
        if (!sexpr.list[2].isAtom) {
            std::cerr << "find-path: label must be atom\n";
            bdd_done();
            return 1;
        }
        std::string addLabel = sexpr.list[2].atom;
        auto path = findWitnessPath(g, re);
        if (path.empty()) {
            std::cerr << "No path found matching regex.\n";
            writeDot(idToName, nodeLabels, edgeSpecs);
            bdd_done();
            return 0;
        }
        for (const auto& pe : path) {
            for (auto& e : edgeSpecs) {
                if (e.src == pe.first && e.dst == pe.second) {
                    e.labels.insert(addLabel);
                    break;
                }
            }
        }
        writeDot(idToName, nodeLabels, edgeSpecs);
        bdd_done();
        return 0;
    }

    std::shared_ptr<greggle::Expr> expr;
    try {
        expr = greggle::buildExpr(sexpr, nodeDom, vars);
    } catch (const std::exception& ex) {
        std::cerr << "Error while building expression: " << ex.what() << "\n";
        bdd_done();
        return 1;
    }

    std::vector<const greggle::Variable*> allVars;
    allVars.reserve(vars.size());
    for (auto& kv : vars) {
        allVars.push_back(kv.second.get());
    }

    greggle::Relation r = greggle::eval(*expr, g, allVars);

    if (allVars.empty()) {
        if (!r.isEmpty()) {
            std::cout << "Query is satisfied (no free variables).\n";
        } else {
            std::cout << "No satisfying assignments.\n";
        }
        bdd_done();
        return 0;
    }

    std::cout << "Satisfying bindings:\n";
    r.traverse([&](const greggle::Tuple& t) {
        if (t.values.size() != allVars.size()) return;
        for (std::size_t i = 0; i < allVars.size(); ++i) {
            const greggle::Variable* v = allVars[i];
            int val = t.values[i];
            std::string nodeLabel = (val >= 0 &&
                                     val < static_cast<int>(nodeLabels.size()))
                                      ? nodeLabels[static_cast<std::size_t>(val)]
                                      : ("<out-of-range:" + std::to_string(val) + ">");
            std::cout << v->getName() << "=" << nodeLabel;
            if (i + 1 < allVars.size()) {
                std::cout << " ";
            }
        }
        std::cout << "\n";
    });

    bdd_done();
    return 0;
}
