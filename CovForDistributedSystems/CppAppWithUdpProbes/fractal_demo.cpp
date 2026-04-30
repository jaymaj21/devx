#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>
#include <string>
#include <fstream>
#include <chrono>
#include <thread>

#include "mprewriter.hpp"

static void write_ppm(const std::string& path, int w, int h, const std::vector<uint8_t>& rgb) {
    std::ofstream out(path, std::ios::binary);
    out << "P6\n" << w << " " << h << "\n255\n";
    out.write(reinterpret_cast<const char*>(rgb.data()), static_cast<std::streamsize>(rgb.size()));
}

int main() {
    mpr_start_sender();
    log_message("fractal_demo: starting Mandelbrot render");

    const int W = 800;
    const int H = 600;
    const int MAX_IT = 256;
    std::vector<uint8_t> rgb(W * H * 3);

    // Outer scope probe for the whole render
    mprewriter_scope_START(2000);

    for (int y = 0; y < H; ++y) {
        // Per-row probe
        mprewriter_scope_START(2001);
        double cy = (y - H / 2.0) * 4.0 / H; // map to [-2,2]
        for (int x = 0; x < W; ++x) {
            // Per-pixel probe
            mprewriter_scope_START(2002);
            double cx = (x - W / 2.0) * 4.0 / W;
            double zx = 0.0, zy = 0.0;
            int it = 0;
            // Iteration probe
            {
                mprewriter_scope_START(2003);
                while (zx*zx + zy*zy < 4.0 && it < MAX_IT) {
                    double xt = zx*zx - zy*zy + cx;
                    zy = 2.0*zx*zy + cy;
                    zx = xt;
                    ++it;
                }
            }
            // Simple palette
            int idx = (y * W + x) * 3;
            uint8_t c = static_cast<uint8_t>(it % 256);
            rgb[idx + 0] = c;
            rgb[idx + 1] = (c * 5) % 256;
            rgb[idx + 2] = (c * 13) % 256;
        }
        if (y % 50 == 0) log_message("fractal_demo: row " + std::to_string(y));
    }

    write_ppm("fractal.ppm", W, H, rgb);
    log_message("fractal_demo: wrote fractal.ppm");

    // Flush and shutdown
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    close_probe();
    mpr_join_sender();
    return 0;
}

