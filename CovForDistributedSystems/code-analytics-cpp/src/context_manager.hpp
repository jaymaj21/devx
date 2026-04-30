#pragma once
#include <unordered_map>
#include <unordered_set>
#include <map>
#include <set>
#include <vector>
#include <string>
#include <mutex>
#include <shared_mutex>
#include <atomic>
#include <tuple>

// Helpers for hash combining
struct HashCombine {
    static inline std::size_t mix(std::size_t h, std::size_t k) noexcept {
        h ^= k + 0x9e3779b97f4a7c15ull + (h << 6) + (h >> 2);
        return h;
    }
};

// Hash for (uint16_t,uint32_t,uint32_t,uint32_t)
struct HitKeyHash {
    std::size_t operator()(const std::tuple<uint16_t,uint32_t,uint32_t,uint32_t>& t) const noexcept {
        auto [a,b,c,d] = t;
        std::size_t h = 0;
        h = HashCombine::mix(h, std::hash<uint16_t>{}(a));
        h = HashCombine::mix(h, std::hash<uint32_t>{}(b));
        h = HashCombine::mix(h, std::hash<uint32_t>{}(c));
        h = HashCombine::mix(h, std::hash<uint32_t>{}(d));
        return h;
    }
};

// Hash for (uint16_t,uint32_t,uint32_t)
struct CovKeyHash {
    std::size_t operator()(const std::tuple<uint16_t,uint32_t,uint32_t>& t) const noexcept {
        auto [a,b,c] = t;
        std::size_t h = 0;
        h = HashCombine::mix(h, std::hash<uint16_t>{}(a));
        h = HashCombine::mix(h, std::hash<uint32_t>{}(b));
        h = HashCombine::mix(h, std::hash<uint32_t>{}(c));
        return h;
    }
};

class ContextManager {
public:
    using CtxSet     = std::set<std::string>;
    using HitKey     = std::tuple<uint16_t,uint32_t,uint32_t,uint32_t>; // app, inst, thread, loc
    using CovKey     = std::tuple<uint16_t,uint32_t,uint32_t>; // app, inst, dummy

    struct CovSubKey {
        uint32_t locationId;
        uint32_t ctxId;
        bool operator==(const CovSubKey& o) const noexcept {
            return locationId==o.locationId && ctxId==o.ctxId;
        }
    };
    struct CovSubKeyHash {
        std::size_t operator()(const CovSubKey& k) const noexcept {
            return (std::hash<uint32_t>{}(k.locationId) * 1315423911u) ^ std::hash<uint32_t>{}(k.ctxId);
        }
    };

private:
    mutable std::shared_mutex mtx_;
    CtxSet current_;
    std::map<CtxSet, uint32_t> setToId_; // deterministic ids
    std::map<uint32_t, CtxSet> idToSet_;
    std::atomic<uint32_t> nextId_{2};

    std::unordered_map<HitKey, uint64_t, HitKeyHash> hits_;
    std::unordered_map<CovKey, std::unordered_map<CovSubKey,uint64_t,CovSubKeyHash>, CovKeyHash> coverage_;

public:
    ContextManager(){
        setToId_[CtxSet{}] = 1;
        idToSet_[1] = CtxSet{};
    }

    void attach(const std::string& name){
        std::unique_lock lock(mtx_);
        current_.insert(name);
        ensureIdNoLock(current_);
    }
    void withdraw(const std::string& name){
        std::unique_lock lock(mtx_);
        current_.erase(name);
        ensureIdNoLock(current_);
    }
    uint32_t currentSetId() const {
        std::shared_lock lock(mtx_);
        auto it=setToId_.find(current_);
        return (it==setToId_.end()) ? 1u : it->second;
    }
    CtxSet currentSet() const {
        std::shared_lock lock(mtx_);
        return current_;
    }

    std::map<uint32_t,CtxSet> snapshotIdToSet() const {
        std::shared_lock lock(mtx_);
        return idToSet_;
    }

    void recordHit(uint16_t appId, uint32_t instanceId, uint32_t threadId, uint32_t locationId){
        uint32_t ctxId;
        {
            std::shared_lock lock(mtx_);
            auto it=setToId_.find(current_);
            ctxId = (it==setToId_.end()) ? 1u : it->second;
        }
        {
            std::unique_lock lock(mtx_);
            HitKey hk{appId,instanceId,threadId,locationId};
            hits_[hk] += 1;
            CovKey ck{appId,instanceId,0};
            auto& bySub = coverage_[ck];
            CovSubKey sk{locationId, ctxId};
            bySub[sk] += 1;
        }
    }

    std::vector<std::tuple<uint16_t,uint32_t,uint32_t,uint32_t,uint64_t>> snapshotHits() const {
        std::shared_lock lock(mtx_);
        std::vector<std::tuple<uint16_t,uint32_t,uint32_t,uint32_t,uint64_t>> out;
        out.reserve(hits_.size());
        for (auto& kv : hits_) {
            auto [app,inst,thr,loc] = kv.first;
            out.emplace_back(app,inst,thr,loc, kv.second);
        }
        return out;
    }

    struct CovRow {
        uint16_t appId; uint32_t instId; uint32_t locId; uint32_t ctxId; uint64_t count;
    };
    std::vector<CovRow> snapshotCoverage(uint16_t filterApp=0, uint32_t filterInst=0) const {
        std::shared_lock lock(mtx_);
        std::vector<CovRow> out;
        for (auto& kv : coverage_) {
            auto [app,inst,_] = kv.first;
            if (filterApp && app!=filterApp) continue;
            if (filterInst && inst!=filterInst) continue;
            for (auto& sk : kv.second) {
                out.push_back(CovRow{app,inst, sk.first.locationId, sk.first.ctxId, sk.second});
            }
        }
        return out;
    }

    std::string writeCoverageReport(uint16_t appId, uint32_t instId, const std::string& filename) const;

private:
    void ensureIdNoLock(const CtxSet& s){
        auto it = setToId_.find(s);
        if (it == setToId_.end()){
            uint32_t nid = nextId_.fetch_add(1);
            setToId_[s] = nid;
            idToSet_[nid] = s;
        }
    }
};

