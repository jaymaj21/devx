// Simple labelled directed graph for greggle.

#pragma once

#include <vector>
#include <string>
#include <set>

namespace greggle {

struct Edge {
    int src;
    int dst;
    std::set<std::string> labels; // atomic propositions true on this edge
};

class Graph {
public:
    explicit Graph(int numNodes);

    int numNodes() const { return _numNodes; }

    void addEdge(int src, int dst, const std::set<std::string>& labels);

    const std::vector<Edge>& outgoing(int node) const { return _adj[node]; }

    const std::string& nodeLabel(int node) const { return _labels[node]; }
    void setNodeLabel(int node, const std::string& label) { _labels[node] = label; }

private:
    int _numNodes;
    std::vector<std::vector<Edge>> _adj;
    std::vector<std::string> _labels;
};

} // namespace greggle
