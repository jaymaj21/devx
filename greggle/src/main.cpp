#include "greggle_domain.h"
#include "greggle_graph.h"
#include "greggle_query.h"
#include "greggle_parse.h"

#include <iostream>
#include <sstream>
#include <fstream>
#include <vector>
#include <memory>

#include <bdd.h>

// Simple test harness: build small labelled graphs, run a few path queries,
// and print the resulting bindings.

static void writeGraphDot(const greggle::Graph& g, const char* filename) {
    std::ofstream out(filename);
    if (!out) {
        return;
    }
    out << "digraph greggle_demo {\n";
    for (int i = 0; i < g.numNodes(); ++i) {
        out << "  " << i << ";\n";
        for (const auto& e : g.outgoing(i)) {
            std::string label;
            bool first = true;
            for (const auto& lab : e.labels) {
                if (!first) label += ",";
                label += lab;
                first = false;
            }
            out << "  " << e.src << " -> " << e.dst
                << " [label=\"" << label << "\"];\n";
        }
    }
    out << "}\n";
}

static void runExistsPathDemo() {
    std::cout << "=== greggle demo: exists-path ===\n";

    // Graph: 0 -> 1 -> 2, 0 -> 3
    // labels: 0->1: a, 1->2: b, 0->3: a
    greggle::Graph g(4);
    g.addEdge(0, 1, {"a"});
    g.addEdge(1, 2, {"b"});
    g.addEdge(0, 3, {"a"});

    greggle::Domain nodeDom("Node", g.numNodes());
    greggle::Variable x("x", &nodeDom);
    greggle::Variable y("y", &nodeDom);

    // Regex: a (b)+  (paths starting with 'a' followed by one or more 'b')
    std::vector<std::shared_ptr<greggle::Regex>> kids;
    kids.push_back(greggle::sym("a"));
    kids.push_back(greggle::plus(greggle::sym("b")));
    auto re = greggle::concat(kids);

    auto ep = greggle::Expr::existsPath(&x, &y, re);

    std::vector<const greggle::Variable*> allVars{&x, &y};
    greggle::Relation r = greggle::eval(*ep, g, allVars);

    r.traverse([&](const greggle::Tuple& t) {
        if (t.values.size() == 2) {
            std::cout << "x=" << t.values[0] << ", y=" << t.values[1] << "\n";
        }
    });
    std::cout << "=== end demo ===\n\n";
}

static void runAndDemo() {
    std::cout << "=== greggle demo: conjunction of path predicates ===\n";

    // Graph:
    // 0 -a-> 1 -b-> 2
    // 0 -a-> 3 -b-> 2
    greggle::Graph g(4);
    g.addEdge(0, 1, {"a"});
    g.addEdge(1, 2, {"b"});
    g.addEdge(0, 3, {"a"});
    g.addEdge(3, 2, {"b"});

    greggle::Domain nodeDom("Node", g.numNodes());
    greggle::Variable x("x", &nodeDom);
    greggle::Variable y("y", &nodeDom);

    // Regex1: a b
    std::vector<std::shared_ptr<greggle::Regex>> kids1;
    kids1.push_back(greggle::sym("a"));
    kids1.push_back(greggle::sym("b"));
    auto re1 = greggle::concat(kids1);
    auto ep1 = greggle::Expr::existsPath(&x, &y, re1);

    // Regex2: a (b)+
    std::vector<std::shared_ptr<greggle::Regex>> kids2;
    kids2.push_back(greggle::sym("a"));
    kids2.push_back(greggle::plus(greggle::sym("b")));
    auto re2 = greggle::concat(kids2);
    auto ep2 = greggle::Expr::existsPath(&x, &y, re2);

    std::vector<std::shared_ptr<greggle::Expr>> exprKids{ep1, ep2};
    auto conj = greggle::Expr::makeAnd(exprKids);

    std::vector<const greggle::Variable*> allVars{&x, &y};
    greggle::Relation r = greggle::eval(*conj, g, allVars);

    r.traverse([&](const greggle::Tuple& t) {
        if (t.values.size() == 2) {
            std::cout << "x=" << t.values[0] << ", y=" << t.values[1] << "\n";
        }
    });
    std::cout << "=== end demo ===\n\n";
}

static void runNotDemo() {
    std::cout << "=== greggle demo: NOT over path predicate ===\n";

    // Graph:
    // 0 -a-> 1 -b-> 2
    // 1 -a-> 3
    // Domain = {0,1,2,3}
    greggle::Graph g(4);
    g.addEdge(0, 1, {"a"});
    g.addEdge(1, 2, {"b"});
    g.addEdge(1, 3, {"a"});

    greggle::Domain nodeDom("Node", g.numNodes());
    greggle::Variable x("x", &nodeDom);
    greggle::Variable y("y", &nodeDom);

    // Build expression:
    // not (exists-path x y (concat a b))
    std::vector<std::shared_ptr<greggle::Regex>> kids;
    kids.push_back(greggle::sym("a"));
    kids.push_back(greggle::sym("b"));
    auto re = greggle::concat(kids);
    auto ep = greggle::Expr::existsPath(&x, &y, re);
    auto notExpr = std::make_shared<greggle::Expr>();
    notExpr->kind = greggle::Expr::Kind::Not;
    notExpr->subExpr = ep;

    std::vector<const greggle::Variable*> allVars{&x, &y};
    greggle::Relation r = greggle::eval(*notExpr, g, allVars);

    // Print all pairs (x,y) that do NOT have an a b path between them.
    r.traverse([&](const greggle::Tuple& t) {
        if (t.values.size() == 2) {
            std::cout << "x=" << t.values[0] << ", y=" << t.values[1] << "\n";
        }
    });
    std::cout << "=== end demo ===\n\n";
}

static void runNegatedEdgeDemo() {
    std::cout << "=== greggle demo: negated edge predicate (~a) ===\n";

    // Graph:
    // 0 -a-> 1
    // 0 -b-> 2
    // 1 -b-> 2
    greggle::Graph g(3);
    g.addEdge(0, 1, {"a"});
    g.addEdge(0, 2, {"b"});
    g.addEdge(1, 2, {"b"});

    greggle::Domain nodeDom("Node", g.numNodes());
    std::map<std::string, std::unique_ptr<greggle::Variable>> vars;

    // All edges whose label set does NOT contain 'a'.
    std::string queryText = "(exists-path x y ~a)";
    std::istringstream iss(queryText);
    greggle::SExpr sexpr;
    if (greggle::parseSExpr(iss, sexpr)) {
        auto expr = greggle::buildExpr(sexpr, nodeDom, vars);
        std::vector<const greggle::Variable*> allVars;
        for (auto& kv : vars) {
            allVars.push_back(kv.second.get());
        }
        greggle::Relation r = greggle::eval(*expr, g, allVars);
        r.traverse([&](const greggle::Tuple& t) {
            if (t.values.size() == 2) {
                std::cout << "x=" << t.values[0] << ", y=" << t.values[1] << "\n";
            }
        });
    }
    std::cout << "=== end demo ===\n\n";
}

static void runAllSomeOfDemo() {
    std::cout << "=== greggle demo: all-of / some-of edge predicates ===\n";

    // Graph with multi-labelled edges:
    // 0 -{a,b}-> 1
    // 0 -{a}-> 2
    // 1 -{b,c}-> 2
    greggle::Graph g(3);
    g.addEdge(0, 1, {"a", "b"});
    g.addEdge(0, 2, {"a"});
    g.addEdge(1, 2, {"b", "c"});

    greggle::Domain nodeDom("Node", g.numNodes());
    std::map<std::string, std::unique_ptr<greggle::Variable>> vars;

    // Edges that have both a and b: (all-of a b)
    std::string queryText =
        "(exists-path x y (all-of a b))";
    std::istringstream iss(queryText);
    greggle::SExpr sexpr;
    if (greggle::parseSExpr(iss, sexpr)) {
        auto expr = greggle::buildExpr(sexpr, nodeDom, vars);
        std::vector<const greggle::Variable*> allVars;
        for (auto& kv : vars) {
            allVars.push_back(kv.second.get());
        }
        greggle::Relation r = greggle::eval(*expr, g, allVars);
        std::cout << "Edges with both a and b:\n";
        r.traverse([&](const greggle::Tuple& t) {
            if (t.values.size() == 2) {
                std::cout << "x=" << t.values[0] << ", y=" << t.values[1] << "\n";
            }
        });
    }

    // Edges that have b or c (or both): (some-of b c)
    vars.clear();
    queryText = "(exists-path x y (some-of b c))";
    std::istringstream iss2(queryText);
    if (greggle::parseSExpr(iss2, sexpr)) {
        auto expr = greggle::buildExpr(sexpr, nodeDom, vars);
        std::vector<const greggle::Variable*> allVars;
        for (auto& kv : vars) {
            allVars.push_back(kv.second.get());
        }
        greggle::Relation r = greggle::eval(*expr, g, allVars);
        std::cout << "Edges with b or c:\n";
        r.traverse([&](const greggle::Tuple& t) {
            if (t.values.size() == 2) {
                std::cout << "x=" << t.values[0] << ", y=" << t.values[1] << "\n";
            }
        });
    }

    std::cout << "=== end demo ===\n\n";
}

int main() {
    // Initialize the Buddy BDD package once before using any BDD-backed
    // Domain / Variable / Relation objects.
    bdd_init(1000000, 1000000);

    runExistsPathDemo();
    runAndDemo();
    runNotDemo();
    runNegatedEdgeDemo();
    runAllSomeOfDemo();
    // Optional: demonstrate parsing a simple S-expression query.
    std::cout << "=== greggle demo: parsed query ===\n";
    greggle::Graph g(4);
    g.addEdge(0, 1, {"a"});
    g.addEdge(1, 2, {"b"});
    g.addEdge(0, 3, {"a"});
    g.addEdge(3, 2, {"b"});

    greggle::Domain nodeDom("Node", g.numNodes());
    std::map<std::string, std::unique_ptr<greggle::Variable>> vars;

    // (and (exists-path x y (concat a b))
    //      (exists-path x y (concat a (plus b))))
    std::string queryText =
        "(and (exists-path x y (concat a b)) "
        "     (exists-path x y (concat a (plus b))))";
    std::istringstream iss(queryText);
    greggle::SExpr sexpr;
    if (greggle::parseSExpr(iss, sexpr)) {
        auto expr = greggle::buildExpr(sexpr, nodeDom, vars);
        std::vector<const greggle::Variable*> allVars;
        for (auto& kv : vars) {
            allVars.push_back(kv.second.get());
        }
        greggle::Relation r = greggle::eval(*expr, g, allVars);
        r.traverse([&](const greggle::Tuple& t) {
            if (t.values.size() == 2) {
                std::cout << "x=" << t.values[0] << ", y=" << t.values[1] << "\n";
            }
        });
    }
    std::cout << "=== end demo ===\n";

    // Larger graph and parsed query demo.
    std::cout << "\n=== greggle demo: large parsed query ===\n";
    greggle::Graph g2(10);
    // Paths for a (c+)
    g2.addEdge(0, 1, {"a"});
    g2.addEdge(1, 2, {"c"});
    g2.addEdge(2, 5, {"c"});
    // Paths for c (b+)
    g2.addEdge(0, 3, {"c"});
    g2.addEdge(3, 4, {"b"});
    g2.addEdge(4, 5, {"b"});

    // JM Adding one more with a c+
    //g2.addEdge(1, 4, {"c"});

    // Extra edges with labels a,b,c scattered around
    g2.addEdge(5, 6, {"a"});
    g2.addEdge(6, 7, {"b"});
    g2.addEdge(7, 8, {"c"});
    g2.addEdge(8, 9, {"a"});
    g2.addEdge(1, 7, {"b"});
    g2.addEdge(2, 8, {"a"});
    g2.addEdge(3, 9, {"c"});
    g2.addEdge(4, 6, {"c"});

    // Write the graph in DOT format so it can be visualized.
    writeGraphDot(g2, "large_graph.dot");

    greggle::Domain nodeDom2("Node", g2.numNodes());
    std::map<std::string, std::unique_ptr<greggle::Variable>> vars2;

    // (and (exists-path x y (concat a (plus c)))
    //      (exists-path x y (concat c (plus b))))
    std::string queryText2 =
        "(and "
        "  (exists-path x y (concat a (plus c))) "
        "  (exists-path x y (concat c (plus b)))"
        ")";
    std::istringstream iss2(queryText2);
    greggle::SExpr sexpr2;
    if (greggle::parseSExpr(iss2, sexpr2)) {
        auto expr2 = greggle::buildExpr(sexpr2, nodeDom2, vars2);
        std::vector<const greggle::Variable*> allVars2;
        for (auto& kv : vars2) {
            allVars2.push_back(kv.second.get());
        }
        greggle::Relation r2 = greggle::eval(*expr2, g2, allVars2);
        r2.traverse([&](const greggle::Tuple& t) {
            if (t.values.size() == 2) {
                std::cout << "x=" << t.values[0] << ", y=" << t.values[1] << "\n";
            }
        });
    }
    std::cout << "=== end demo ===\n";

    // Clean up Buddy global state after all BDD objects have been destroyed.
    bdd_done();
    return 0;
}
