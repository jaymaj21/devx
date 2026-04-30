#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <cstdio>
#include <cstdlib>

#include "server.hpp"
#include "context_manager.hpp"

// Tcl embedding
extern "C" {
#include <tcl.h>
}

static void printHelp(){
    std::cout << "Commands (native):\n"
              << "  hits ?limit?\n"
              << "  coverage ?appId? ?instId?\n"
              << "  ctx current|list|attach NAME|withdraw NAME\n"
              << "  report APP_ID INSTANCE_ID FILENAME\n"
              << "  trace rotate FILENAME\n"
              << "  help\n"
              << "  exit\n\n"
              << "Java-style aliases (colon-prefixed):\n"
              << "  :hits\n"
              << "  :apply-context NAME\n"
              << "  :withdraw-context NAME\n"
              << "  :coverage-report APP_ID INSTANCE_ID FILENAME\n"
              << "  :help\n"
              << "  :exit\n";
}

// Global server pointer for command closures
static Server* g_server = nullptr;

// Tcl command helpers
static int Tcl_HitsCmd(ClientData, Tcl_Interp* interp, int objc, Tcl_Obj* const objv[]){
    int limit = 100;
    if (objc>=2) { Tcl_GetIntFromObj(interp, objv[1], &limit); }
    auto rows = g_server->ctx().snapshotHits();
    std::ostringstream oss;
    int n=0;
    for (auto& r : rows){
        if (n++>=limit) break;
        uint16_t app; uint32_t inst, thr, loc; uint64_t cnt;
        std::tie(app,inst,thr,loc,cnt) = r;
        oss << app << "," << inst << "," << thr << "," << loc << " -> " << cnt << "\n";
    }
    Tcl_SetObjResult(interp, Tcl_NewStringObj(oss.str().c_str(), -1));
    return TCL_OK;
}

static int Tcl_CoverageCmd(ClientData, Tcl_Interp* interp, int objc, Tcl_Obj* const objv[]){
    int appId=0; int instId=0;
    if (objc>=2) Tcl_GetIntFromObj(interp, objv[1], &appId);
    if (objc>=3) Tcl_GetIntFromObj(interp, objv[2], &instId);
    auto rows = g_server->ctx().snapshotCoverage((uint16_t)appId, (uint32_t)instId);
    std::ostringstream oss;
    for (auto& r : rows){
        oss << r.appId << ","<< r.instId << ","<< r.locId << " [ctx "<< r.ctxId << "] -> " << r.count << "\n";
    }
    Tcl_SetObjResult(interp, Tcl_NewStringObj(oss.str().c_str(), -1));
    return TCL_OK;
}

static int Tcl_CtxCmd(ClientData, Tcl_Interp* interp, int objc, Tcl_Obj* const objv[]){
    if (objc<2) { Tcl_WrongNumArgs(interp,1,objv,(char*)"subcommand ?args?"); return TCL_ERROR; }
    std::string sub = Tcl_GetString(objv[1]);
    if (sub=="current"){
        auto id = g_server->ctx().currentSetId();
        auto s  = g_server->ctx().currentSet();
        std::ostringstream oss;
        oss << "id=" << id << " {";
        bool first=true; for (auto& x : s){ if(!first) oss<<","; first=false; oss<<x; }
        oss << "}";
        Tcl_SetObjResult(interp, Tcl_NewStringObj(oss.str().c_str(), -1));
        return TCL_OK;
    } else if (sub=="list"){
        auto mp = g_server->ctx().snapshotIdToSet();
        std::ostringstream oss;
        for (auto& kv : mp){
            oss << kv.first << " {";
            bool first=true; for (auto& x : kv.second){ if(!first) oss<<","; first=false; oss<<x; }
            oss << "}\n";
        }
        Tcl_SetObjResult(interp, Tcl_NewStringObj(oss.str().c_str(), -1));
        return TCL_OK;
    } else if (sub=="attach"){
        if (objc<3){ Tcl_SetResult(interp,(char*)"usage: ctx attach NAME", TCL_STATIC); return TCL_ERROR; }
        g_server->ctx().attach(Tcl_GetString(objv[2]));
        Tcl_SetResult(interp,(char*)"OK", TCL_STATIC);
        return TCL_OK;
    } else if (sub=="withdraw"){
        if (objc<3){ Tcl_SetResult(interp,(char*)"usage: ctx withdraw NAME", TCL_STATIC); return TCL_ERROR; }
        g_server->ctx().withdraw(Tcl_GetString(objv[2]));
        Tcl_SetResult(interp,(char*)"OK", TCL_STATIC);
        return TCL_OK;
    } else {
        Tcl_SetResult(interp,(char*)"subcommands: current|list|attach|withdraw", TCL_STATIC);
        return TCL_ERROR;
    }
}

static int Tcl_ReportCmd(ClientData, Tcl_Interp* interp, int objc, Tcl_Obj* const objv[]){
    if (objc!=4){ Tcl_SetResult(interp,(char*)"usage: report APP_ID INSTANCE_ID FILENAME", TCL_STATIC); return TCL_ERROR; }
    int appId, instId;
    if (Tcl_GetIntFromObj(interp, objv[1], &appId)!=TCL_OK) return TCL_ERROR;
    if (Tcl_GetIntFromObj(interp, objv[2], &instId)!=TCL_OK) return TCL_ERROR;
    std::string fn = Tcl_GetString(objv[3]);
    auto msg = g_server->ctx().writeCoverageReport((uint16_t)appId, (uint32_t)instId, fn);
    Tcl_SetObjResult(interp, Tcl_NewStringObj(msg.c_str(), -1));
    return TCL_OK;
}

static int Tcl_HelpCmd(ClientData, Tcl_Interp* interp, int, Tcl_Obj* const[]){
    std::ostringstream oss; 
    printHelp();
    Tcl_SetObjResult(interp, Tcl_NewStringObj("", -1));
    return TCL_OK;
}

static int Tcl_TraceRotateCmd(ClientData, Tcl_Interp* interp, int objc, Tcl_Obj* const objv[]){
    if (objc!=3){ Tcl_SetResult(interp,(char*)"usage: trace rotate FILENAME", TCL_STATIC); return TCL_ERROR; }
    std::string sub = Tcl_GetString(objv[1]);
    if (sub!="rotate"){ Tcl_SetResult(interp,(char*)"only 'rotate' supported", TCL_STATIC); return TCL_ERROR; }
    // quick reopen
    // (We didn't expose Server::trace but you can re-run with --trace for simplicity.)
    Tcl_SetObjResult(interp, Tcl_NewStringObj("Not implemented in this demo (start server with --trace)", -1));
    return TCL_OK;
}

// Implement writeCoverageReport (out-of-line)
std::string ContextManager::writeCoverageReport(uint16_t appId, uint32_t instId, const std::string& filename) const {
    auto id2set = snapshotIdToSet();
    auto rows = snapshotCoverage(appId, instId);
    size_t hitCount = rows.size();
    FILE* f = std::fopen(filename.c_str(), "wb");
    if (!f) return "ERROR opening file";
    // Match Java server format
    std::fprintf(f, "CONTEXTS %zu\n", id2set.size());
    for (auto& kv : id2set){
        const auto& set = kv.second;
        if (kv.first == 1u) {
            std::fprintf(f, "%u default\n", kv.first);
        } else {
            std::ostringstream label;
            bool first=true; for (auto& x : set){ if(!first) label<<","; first=false; label<<x; }
            std::string s = label.str();
            std::fprintf(f, "%u %s\n", kv.first, s.c_str());
        }
    }
    std::fprintf(f, "HITS %zu\n", hitCount);
    for (auto& r : rows){
        // rows already filtered by app/inst; emit ctxId locId count
        std::fprintf(f, "%u %u %llu\n", r.ctxId, r.locId, (unsigned long long)r.count);
    }
    std::fclose(f);
    return "Coverage report written to " + filename;
}

int main(int argc, char** argv){
    uint16_t udpPort=8083, tcpPort=8084; std::string trace;
    std::string runScript;
    for (int i=1;i<argc;i++){
        std::string a=argv[i];
        if (a=="--udp" && i+1<argc) udpPort=uint16_t(std::stoi(argv[++i]));
        else if (a=="--tcp" && i+1<argc) tcpPort=uint16_t(std::stoi(argv[++i]));
        else if (a=="--trace" && i+1<argc) trace=argv[++i];
        else if (a=="--run" && i+1<argc) runScript=argv[++i];
        else if (a=="-h"||a=="--help"){ std::cout<<"Usage: cov_server [--udp P] [--tcp P] [--trace FILE] [--run script.tcl]\n"; return 0;}
    }

    ServerConfig cfg; cfg.udpPort=udpPort; cfg.tcpPort=tcpPort; cfg.tracePath=trace;
    Server server(cfg);
    if (!server.start()){ std::cerr<<"Failed to start server\n"; return 2; }
    g_server = &server;

    // Init Tcl and register commands
    Tcl_Interp* interp = Tcl_CreateInterp();
    if (Tcl_Init(interp) != TCL_OK){
        std::cerr<<"Tcl_Init failed: "<<Tcl_GetStringResult(interp)<<"\n"; return 2;
    }
    Tcl_CreateObjCommand(interp, "hits", Tcl_HitsCmd, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, "coverage", Tcl_CoverageCmd, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, "ctx", Tcl_CtxCmd, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, "report", Tcl_ReportCmd, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, "help", Tcl_HelpCmd, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, "trace", Tcl_TraceRotateCmd, nullptr, nullptr);

    // Java ClojureShell-compatible aliases (colon-prefixed)
    auto ColonApplyContext = [](ClientData, Tcl_Interp* i, int objc, Tcl_Obj* const objv[])->int{
        if (objc!=2){ Tcl_SetResult(i,(char*)"Usage: :apply-context NAME", TCL_STATIC); return TCL_ERROR; }
        g_server->ctx().attach(Tcl_GetString(objv[1]));
        Tcl_SetResult(i,(char*)"OK", TCL_STATIC); return TCL_OK;
    };
    auto ColonWithdrawContext = [](ClientData, Tcl_Interp* i, int objc, Tcl_Obj* const objv[])->int{
        if (objc!=2){ Tcl_SetResult(i,(char*)"Usage: :withdraw-context NAME", TCL_STATIC); return TCL_ERROR; }
        g_server->ctx().withdraw(Tcl_GetString(objv[1]));
        Tcl_SetResult(i,(char*)"OK", TCL_STATIC); return TCL_OK;
    };
    auto ColonCoverageReport = [](ClientData, Tcl_Interp* i, int objc, Tcl_Obj* const objv[])->int{
        if (objc!=4){ Tcl_SetResult(i,(char*)"Usage: :coverage-report APP_ID INSTANCE_ID FILENAME", TCL_STATIC); return TCL_ERROR; }
        int appId, instId; if (Tcl_GetIntFromObj(i,objv[1],&appId)!=TCL_OK) return TCL_ERROR; if (Tcl_GetIntFromObj(i,objv[2],&instId)!=TCL_OK) return TCL_ERROR;
        std::string fn = Tcl_GetString(objv[3]);
        auto msg = g_server->ctx().writeCoverageReport((uint16_t)appId,(uint32_t)instId,fn);
        Tcl_SetObjResult(i, Tcl_NewStringObj(msg.c_str(), -1)); return TCL_OK;
    };
    auto ColonHits = [](ClientData cd, Tcl_Interp* i, int objc, Tcl_Obj* const objv[])->int{ return Tcl_HitsCmd(cd,i,objc,objv); };
    auto ColonHelp = [](ClientData, Tcl_Interp* i, int, Tcl_Obj* const[])->int{ printHelp(); Tcl_SetObjResult(i,Tcl_NewStringObj("",-1)); return TCL_OK; };
    auto ColonExit = [](ClientData, Tcl_Interp*, int, Tcl_Obj* const[])->int{ std::exit(0); };
    auto ColonFlushTrace = [](ClientData, Tcl_Interp* i, int, Tcl_Obj* const[])->int{
        g_server->flushTrace();
        Tcl_SetResult(i,(char*)"Trace flushed", TCL_STATIC);
        return TCL_OK;
    };
    auto ColonTracePersist = [](ClientData, Tcl_Interp* i, int, Tcl_Obj* const[])->int{
        g_server->persistTrace();
        Tcl_SetResult(i,(char*)"Trace persisted", TCL_STATIC);
        return TCL_OK;
    };
    Tcl_CreateObjCommand(interp, ":apply-context", ColonApplyContext, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, ":withdraw-context", ColonWithdrawContext, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, ":coverage-report", ColonCoverageReport, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, ":hits", ColonHits, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, ":help", ColonHelp, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, ":exit", ColonExit, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, ":flush-trace", ColonFlushTrace, nullptr, nullptr);
    Tcl_CreateObjCommand(interp, ":trace-persist", ColonTracePersist, nullptr, nullptr);

    if (!runScript.empty()){
        if (Tcl_EvalFile(interp, runScript.c_str()) != TCL_OK){
            std::cerr << "Script error: " << Tcl_GetStringResult(interp) << "\n";
        }
        // Exit after script
        Tcl_DeleteInterp(interp);
        server.stop();
        return 0;
    }

    std::cout << "cov_server running (UDP "<<udpPort<<", TCP "<<tcpPort<<")\n";
    printHelp();
    // Simple REPL
    std::string line;
    while (true){
        std::cout << "% " << std::flush;
        if (!std::getline(std::cin, line)) break;
        if (line=="exit") break;
        if (Tcl_Eval(interp, line.c_str()) != TCL_OK){
            std::cerr << "ERR: " << Tcl_GetStringResult(interp) << "\n";
        } else {
            const char* res = Tcl_GetStringResult(interp);
            if (res && *res) std::cout << res << "\n";
        }
    }
    Tcl_DeleteInterp(interp);
    server.stop();
    return 0;
}
