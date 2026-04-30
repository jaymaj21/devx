cd CppAppWithUdpProbes
g++ -O3 -std=c++17 -DMPREWRITER_STANDALONE=0 latency_bench.cpp mprewriter.cpp -lws2_32 -o latency_bench.exe

./latency_bench.exe

g++ -O3 -std=c++17 -DMPREWRITER_STANDALONE=0 -DNDEBUG -march=native -flto mprewriter.cpp latency_bench.cpp -lws2_32 -o latency_bench2.exe
./latency_bench2.exe

cl /O2 /GL /DNDEBUG /std:c++17 mprewriter.cpp latency_bench.cpp ws2_32.lib /Fe:latency_bench_msvc.exe
./latency_bench_msvc.exe


