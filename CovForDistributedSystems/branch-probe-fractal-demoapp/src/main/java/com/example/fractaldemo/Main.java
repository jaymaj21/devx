package com.example.fractaldemo;

import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) throws Exception {
        System.out.println("Fractal Demo (no probes in source): start");
        renderMandelbrot("fractal_bp.ppm", 800, 600, 256);
        System.out.println("Fractal Demo: wrote fractal_bp.ppm");
        System.out.println("Fractal Demo: end");
    }

    private static void renderMandelbrot(String path, int W, int H, int MAX_IT) throws IOException {
        byte[] rgb = new byte[W * H * 3];
        for (int y = 0; y < H; y++) {
            double cy = (y - H / 2.0) * 4.0 / H;
            for (int x = 0; x < W; x++) {
                double cx = (x - W / 2.0) * 4.0 / W;
                double zx = 0.0, zy = 0.0;
                int it = 0;
                while (zx * zx + zy * zy < 4.0 && it < MAX_IT) {
                    double xt = zx * zx - zy * zy + cx;
                    zy = 2.0 * zx * zy + cy;
                    zx = xt;
                    it++;
                }
                int idx = (y * W + x) * 3;
                byte c = (byte) (it & 0xFF);
                rgb[idx] = c;
                rgb[idx + 1] = (byte) ((c & 0xFF) * 5 & 0xFF);
                rgb[idx + 2] = (byte) ((c & 0xFF) * 13 & 0xFF);
            }
        }
        try (FileOutputStream out = new FileOutputStream(path)) {
            out.write(String.format("P6\n%d %d\n255\n", W, H).getBytes(StandardCharsets.US_ASCII));
            out.write(rgb);
        }
    }
}

