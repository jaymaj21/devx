package com.example.fractal;

import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) throws Exception {
        try (var g0 = mprewriter.scopeStart(2000)) { // outer render
            log("Java fractal demo: starting Mandelbrot render");
            final int W = 800;
            final int H = 600;
            final int MAX_IT = 256;
            byte[] rgb = new byte[W * H * 3];

            for (int y = 0; y < H; y++) {
                try (var g1 = mprewriter.scopeStart(2001)) { // per-row
                    double cy = (y - H / 2.0) * 4.0 / H;
                    for (int x = 0; x < W; x++) {
                        try (var g2 = mprewriter.scopeStart(2002)) { // per-pixel
                            double cx = (x - W / 2.0) * 4.0 / W;
                            double zx = 0.0, zy = 0.0;
                            int it = 0;
                            try (var g3 = mprewriter.scopeStart(2003)) { // iteration scope
                                while (zx * zx + zy * zy < 4.0 && it < MAX_IT) {
                                    double xt = zx * zx - zy * zy + cx;
                                    zy = 2.0 * zx * zy + cy;
                                    zx = xt;
                                    it++;
                                }
                            }
                            int idx = (y * W + x) * 3;
                            byte c = (byte) (it & 0xFF);
                            rgb[idx] = c;
                            rgb[idx + 1] = (byte) ((c & 0xFF) * 5 & 0xFF);
                            rgb[idx + 2] = (byte) ((c & 0xFF) * 13 & 0xFF);
                        }
                    }
                }
                if (y % 50 == 0) log("fractal_demo: row " + y);
            }

            writePPM("fractal_java.ppm", W, H, rgb);
            log("Java fractal demo: wrote fractal_java.ppm");
        } finally {
            mprewriter.shutdown();
        }
    }

    private static void writePPM(String path, int w, int h, byte[] rgb) throws IOException {
        try (FileOutputStream out = new FileOutputStream(path)) {
            out.write(String.format("P6\n%d %d\n255\n", w, h).getBytes(StandardCharsets.US_ASCII));
            out.write(rgb);
        }
    }

    private static void log(String s) { mprewriter.log(s); }
}

