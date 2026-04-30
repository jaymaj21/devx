#include <iostream>
#include <vector>
#include <limits>
#include <algorithm>
#include <random>
#include "mprewriter.hpp"

struct Node {
    std::vector<double> coords;
    Node* left;
    Node* right;

    Node(const std::vector<double>& c) : coords(c), left(nullptr), right(nullptr) {mprewriter_scope_START(10001);}
};

std::vector<double> addVec(const std::vector<double>& a, const std::vector<double>& b) {mprewriter_scope_START(10002);
    std::vector<double> res(a.size());
    for (std::size_t i = 0; i < a.size(); ++i) res[i] = a[i] + b[i];
    return res;
}

std::vector<double> subVec(const std::vector<double>& a, const std::vector<double>& b) {mprewriter_scope_START(10003);
    std::vector<double> res(a.size());
    for (std::size_t i = 0; i < a.size(); ++i) res[i] = a[i] - b[i];
    return res;
}

inline double sq(double x) {mprewriter_scope_START(10004); return x * x; }

double dist(const std::vector<double>& c1, const std::vector<double>& c2) {mprewriter_scope_START(10005);
    std::vector<double> diff = subVec(c1, c2);
    double sum = 0.0;
    for (double v : diff) sum += sq(v);
    return sum;
}

void swap_elem(std::vector<Node*>& arr, int i, int j) {mprewriter_scope_START(10006);
    //std::cout << "swapping " << i << " and " << j << "\n";
    std::swap(arr[i], arr[j]);
}

int partition(std::vector<Node*>& arr, int low, int high, int coordidx) {mprewriter_scope_START(10007);
    //std::cout << "partition called with low=" << low << " and high=" << high << "\n";
    double pivot = arr[high]->coords[coordidx];
    //std::cout << "pivot=" << pivot << "\n";
    int i = low;
    for (int j = low; j < high; ++j) {mprewriter_scope_START(10008);
        //std::cout << "comparing " << j << "-th value " << arr[j]->coords[coordidx]
            //      << " and pivot " << pivot << "\n";
        if (arr[j]->coords[coordidx] < pivot) {mprewriter_scope_START(10009);
            swap_elem(arr, i++, j);
        }
    }
    swap_elem(arr, i, high);
    //std::cout << "Partition returning " << i << "\n";
    return i;
}

int find_median(std::vector<Node*>& nodes_arr, int coordidx,
                int left, int right, int mid) {mprewriter_scope_START(10010);
    //std::cout << "find_median left=" << left << " right=" << right
           //   << " mid=" << mid << "\n";
    if (left == right) return left;
    int partition_idx = partition(nodes_arr, left, right, coordidx);
    if (partition_idx == mid) return mid;
    if (partition_idx < mid) {mprewriter_scope_START(10011);
        // Note: this follows your JS code exactly, including "mid - partition_idx"
        return find_median(nodes_arr, coordidx, partition_idx + 1, right,
                           mid - partition_idx);
    } else {mprewriter_scope_START(10012);
        return find_median(nodes_arr, coordidx, left, partition_idx - 1, mid);
    }
}

int median(std::vector<Node*>& nodes_arr, int coordidx) {mprewriter_scope_START(10013);
    int n = static_cast<int>(nodes_arr.size());
    return find_median(nodes_arr, coordidx, 0, n - 1, n / 2);
}

Node* make_tree(std::vector<Node*>& nodes_arr, int low, int high, int idx) {mprewriter_scope_START(10014);
    //std::cout << "make_tree low=" << low << " high=" << high << " idx=" << idx << "\n";
    if (low == high) return nodes_arr[low];
    if (low > high) return nullptr;

    int m = find_median(nodes_arr, idx, low, high, (high + low) / 2);
    //std::cout << "median index=" << m << "\n";

    Node* medianNode = nodes_arr[m];
    int dim = static_cast<int>(medianNode->coords.size());
    medianNode->left  = make_tree(nodes_arr, low, m - 1, (idx + 1) % dim);
    medianNode->right = make_tree(nodes_arr, m + 1, high, (idx + 1) % dim);

    return medianNode;
}

struct Result {
    double bestDist;
    Node* nearestNode;
    Result()
        : bestDist(std::numeric_limits<double>::infinity()),
          nearestNode(nullptr) {mprewriter_scope_START(10015);}
};

void nearest(Node* root, const std::vector<double>& point, int index, Result& result) {mprewriter_scope_START(10016);
    if (root == nullptr)
        return;

    double d = dist(root->coords, point);
    if (result.nearestNode == nullptr || d < result.bestDist) {mprewriter_scope_START(10017);
        result.bestDist = d;
        result.nearestNode = root;
    }
    if (result.bestDist == 0.0)
        return;

    double dx = root->coords[index] - point[index];
    index = (index + 1) % static_cast<int>(point.size());

    nearest(dx > 0 ? root->left : root->right, point, index, result);
    if (dx * dx >= result.bestDist)
        return;
    nearest(dx > 0 ? root->right : root->left, point, index, result);
}

void printNode(const Node* n, int depth = 0) {mprewriter_scope_START(10018);
    if (!n) return;
    for (int i = 0; i < depth; ++i) std::cout << "  ";
    std::cout << "Node(";
    for (std::size_t i = 0; i < n->coords.size(); ++i) {mprewriter_scope_START(10019);
        std::cout << n->coords[i];
        if (i + 1 < n->coords.size()) std::cout << ",";
    }
    std::cout << ")\n";
    printNode(n->left, depth + 1);
    printNode(n->right, depth + 1);
}

void test1() {mprewriter_scope_START(10020);
    Node* node1 = new Node({1, 2});
    Node* node2 = new Node({3, 4});
    Node* node3 = new Node({7, 1});
    Node* node4 = new Node({5, 2});
    Node* node5 = new Node({12, 0});

    std::vector<Node*> nodes = {node1, node2, node3, node4, node5};

    partition(nodes, 0, static_cast<int>(nodes.size()) - 1, 0);

    // For testing the intermediate steps
    for (int i = 0; i < 2; ++i) {mprewriter_scope_START(10021);
        std::cout << "Computing median by index " << i << "\n";
        int m = median(nodes, i);
        std::cout << "all_nodes=\n";
        for (std::size_t k = 0; k < nodes.size(); ++k) {mprewriter_scope_START(10022);
            std::cout << "  [" << k << "] (" << nodes[k]->coords[0]
                      << "," << nodes[k]->coords[1] << ")\n";
        }
        std::cout << "median=\n";
        std::cout << "  index " << m << " -> ("
                  << nodes[m]->coords[0] << "," << nodes[m]->coords[1] << ")\n";
    }

    // Make tree
    Node* tree = make_tree(nodes, 0, static_cast<int>(nodes.size()) - 1, 0);
    std::cout << "Tree:\n";
    printNode(tree);

    // Try out a couple of queries
    Result res;
    std::cout << "checking nearest point to 12.1,0.5\n";
    nearest(tree, {12.1, 0.5}, 0, res);
    if (res.nearestNode) {mprewriter_scope_START(10023);
        std::cout << "Nearest: (" << res.nearestNode->coords[0] << ","
                  << res.nearestNode->coords[1] << "), dist^2="
                  << res.bestDist << "\n";
    }

    res = Result();
     std::cout << "checking nearest point to 6,2\n";
    nearest(tree, {6, 2}, 0, res);
    if (res.nearestNode) {mprewriter_scope_START(10024);
         std::cout << "Nearest: (" << res.nearestNode->coords[0] << ","
                   << res.nearestNode->coords[1] << "), dist^2="
                   << res.bestDist << "\n";
    }

    // NOTE: raw new/delete for brevity; in real code use smart pointers or free them.
}
void test_random_5000() {mprewriter_scope_START(10025);
    const int N = 5000;
    std::vector<Node*> nodes;
    nodes.reserve(N);

    // Random generator for 2D points in [0, 1000) x [0, 1000)
    std::mt19937 rng(std::random_device{}());
    std::uniform_real_distribution<double> dist(0.0, 1000.0);

    for (int i = 0; i < N; ++i) {mprewriter_scope_START(10026);
        double x = dist(rng);
        double y = dist(rng);
        nodes.push_back(new Node({x, y}));
    }

    std::cout << "Building kd-tree with " << N << " random points...\n";
    Node* tree = make_tree(nodes, 0, static_cast<int>(nodes.size()) - 1, 0);
    std::cout << "Tree built.\n";

    // Try a few random query points
    for (int q = 0; q < 5; ++q) {mprewriter_scope_START(10027);
        double qx = dist(rng);
        double qy = dist(rng);
        Result res;
        std::cout << "Query " << q + 1 << ": nearest to (" << qx << ", " << qy << ")\n";
        nearest(tree, {qx, qy}, 0, res);
        if (res.nearestNode) {mprewriter_scope_START(10028);
            std::cout << "  Nearest: (" << res.nearestNode->coords[0]
                      << ", " << res.nearestNode->coords[1]
                      << "), dist^2 = " << res.bestDist << "\n";
        }
    }

    // In a real program you should delete all Node* here.
    // (Skipping for brevity, as with test1.)
}


int main() {
    mpr_start_sender();

    test1();
    test_random_5000();
    
    close_probe();
    mpr_join_sender();
    return 0;
}

