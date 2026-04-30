use crate::mprewriter;
use mprewriter_macros::mprewriter_scope_START;

pub fn run_demo() {
    // Context label for grouping
    mprewriter::set_context("fractal_demo::run_demo");
    mprewriter_scope_START!(2000); // outer render scope
    mprewriter::log_message("Fractal demo: starting Mandelbrot render");

    const W: usize = 800;
    const H: usize = 600;
    const MAX_IT: u32 = 256;

    let mut rgb = vec![0u8; W * H * 3];

    for y in 0..H {
        mprewriter_scope_START!(2001); // per-row scope
        let cy = (y as f64 - (H as f64) / 2.0) * 4.0 / (H as f64);
        for x in 0..W {
            mprewriter_scope_START!(2002); // per-pixel scope
            let cx = (x as f64 - (W as f64) / 2.0) * 4.0 / (W as f64);
            let mut zx = 0.0f64;
            let mut zy = 0.0f64;
            let mut it: u32 = 0;
            {
                mprewriter_scope_START!(2003); // iteration scope
                while zx * zx + zy * zy < 4.0 && it < MAX_IT {
                    let xt = zx * zx - zy * zy + cx;
                    zy = 2.0 * zx * zy + cy;
                    zx = xt;
                    it += 1;
                }
            }
            let idx = (y * W + x) * 3;
            let c = (it % 256) as u8;
            rgb[idx] = c;
            rgb[idx + 1] = c.wrapping_mul(5);
            rgb[idx + 2] = c.wrapping_mul(13);
        }
        if y % 50 == 0 {
            mprewriter::log_message(&format!("fractal_demo: row {}", y));
        }
    }

    // Write PPM
    if let Err(e) = write_ppm("fractal_rust.ppm", W as u32, H as u32, &rgb) {
        mprewriter::log_message(&format!("fractal_demo: failed to write PPM: {}", e));
    } else {
        mprewriter::log_message("fractal_demo: wrote fractal_rust.ppm");
    }
}

fn write_ppm(path: &str, w: u32, h: u32, rgb: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let mut f = std::fs::File::create(path)?;
    write!(f, "P6\n{} {}\n255\n", w, h)?;
    f.write_all(rgb)?;
    Ok(())
}
