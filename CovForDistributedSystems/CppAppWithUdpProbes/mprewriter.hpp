#pragma once

#include <thread>
#include <string>

// Declarations for the C++ UDP probe runtime and RAII scope macro.

// Thread-local stack depth counter (defined in .cpp)
extern thread_local int g_mpr_stack_depth;

// Queue a hit record with explicit stack depth (implemented in .cpp)
void scope_record_hit(int locationId, int stackDepth);

// Start and stop the background sender thread
void mpr_start_sender();
void mpr_join_sender();

// Simple logging API
void log_message(const std::string& log);
void close_probe();

// RAII guard: increments on entry, records hit, decrements on exit
struct MprScopeGuard {
    explicit MprScopeGuard(int locationId) {
        ++g_mpr_stack_depth;
        scope_record_hit(locationId, g_mpr_stack_depth);
    }
    ~MprScopeGuard() {
        --g_mpr_stack_depth;
    }
};

// Token pasting helper for unique variable names
#ifndef MPR_CAT
#define MPR_CAT_(a,b) a##b
#define MPR_CAT(a,b) MPR_CAT_(a,b)
#endif

// Public macro to begin a probe scope in current block
#ifndef mprewriter_scope_START
#define mprewriter_scope_START(locationId) ::MprScopeGuard MPR_CAT(_mpr_guard_, __COUNTER__)(locationId)
#endif
