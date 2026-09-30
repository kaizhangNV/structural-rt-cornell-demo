#!/usr/bin/env python3
"""Render the README showcase using the structural API and HEADLESS Vulkan only.

Requires Python 3.10+, Pillow, FFmpeg with the libvpx encoder, and DejaVu Sans
fonts. No desktop window is opened. Build the normal Cornell RHI executable first.
From the repository root:

    python3 tools/render-readme-video.py --ffmpeg /path/to/ffmpeg

Use --reuse-rendered to re-encode this script's existing PPM captures without GPU
work. The output is an edited offline showcase, NOT a real-time/FPS recording.
All displayed scene pixels come from the renderer; Pillow adds titles/progress.
The capture manifest, renderer logs, and a contact sheet stay under build/.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
WIDTH, HEIGHT, FPS = 896, 640, 12
BACKGROUND = "#121820"
TEXT, MUTED, ACCENT = "#eef4f5", "#a5b4bf", "#63dfbd"
# name, samples, view, seconds, section, title, description
SHOTS = [
    ("beauty-4096", 4096, "beauty", 2, "SLANG / STRUCTURAL RT", "Analytic glass sphere",
     ["Custom intersection stage", "Center (0, 0.75, 0); r = 0.40", "Reflection + refraction", "Rendered caustics + shadow"]),
    ("beauty-1", 1, "beauty", 1.5, "01 / CONVERGENCE", "1 sample / pixel",
     ["Fixed camera and seed", "Stochastic path sampling", "Eight maximum bounces"]),
    ("beauty-16", 16, "beauty", 1.5, "01 / CONVERGENCE", "16 samples / pixel",
     ["Fixed camera and seed", "Stochastic path sampling", "Eight maximum bounces"]),
    ("beauty-256", 256, "beauty", 1.5, "01 / CONVERGENCE", "256 samples / pixel",
     ["Fixed camera and seed", "Stochastic path sampling", "Eight maximum bounces"]),
    ("beauty-4096", 4096, "beauty", 4.5, "02 / PATH-TRACED BEAUTY", "Glass + indirect light",
     ["Fresnel reflection", "Refraction + absorption", "Diffuse color bleeding", "Soft area-light shadows"]),
    ("direct-1024", 1024, "direct", 3, "03 / DIRECT-ONLY CONTROL", "Without diffuse GI",
     ["Same scene and camera", "Glass interactions retained", "Indirect diffuse light off", "Compare walls and floor"]),
    ("ao-256", 256, "ao", 4, "04 / AMBIENT OCCLUSION", "Visibility diagnostic",
     ["Eight AO rays / sample", "Radius: 0.75 scene units", "Dark = nearby occluders", "Separate from beauty"]),
    ("beauty-4096", 4096, "beauty", 2, "SLANG / STRUCTURAL RT", "Cornell path tracer",
     ["One shader implementation", "Diffuse and glass transport", "Dedicated visibility rays", "Host-defined shader table"]),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fonts(font_dir):
    return {
        "title": ImageFont.truetype(str(font_dir / "DejaVuSans-Bold.ttf"), 27),
        "heading": ImageFont.truetype(str(font_dir / "DejaVuSans-Bold.ttf"), 20),
        "body": ImageFont.truetype(str(font_dir / "DejaVuSans.ttf"), 16),
        "small": ImageFont.truetype(str(font_dir / "DejaVuSans.ttf"), 13),
        "label": ImageFont.truetype(str(font_dir / "DejaVuSans-Bold.ttf"), 12),
    }


def compose(capture, shot, elapsed, duration, font):
    _, samples, view, _, section, title, lines = shot
    frame = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(frame)
    draw.text((28, 22), "Cornell / Path tracing", font=font["title"], fill=TEXT)
    draw.text((29, 59), "Slang structural ray-tracing API", font=font["body"], fill=MUTED)
    draw.rounded_rectangle((686, 27, 868, 54), 6, fill="#20332f")
    draw.text((699, 34), "OFFLINE SHOWCASE", font=font["label"], fill=ACCENT)
    frame.paste(capture, (28, 92))
    draw.line((562, 106, 562, 581), fill="#2d3945", width=1)
    draw.text((585, 119), section, font=font["label"], fill=ACCENT)
    draw.text((585, 151), title, font=font["heading"], fill=TEXT)
    draw.text((585, 188), f"{samples:,} spp  /  {view}", font=font["body"], fill=MUTED)
    for index, line in enumerate(lines):
        y = 254 + index * 36
        draw.ellipse((585, y + 6, 590, y + 11), fill=ACCENT)
        draw.text((602, y), line, font=font["body"], fill=TEXT)
    draw.text((585, 495), "512 x 512  |  Vulkan", font=font["small"], fill=MUTED)
    draw.text((585, 518), "Seed 1  |  Exposure 1", font=font["small"], fill=MUTED)
    draw.text((585, 553), "Edited timing; not an FPS test.", font=font["small"], fill=MUTED)
    draw.text((28, 616), "Actual renderer output  /  fixed camera  /  headless capture", font=font["small"], fill=MUTED)
    draw.rectangle((0, HEIGHT - 3, WIDTH, HEIGHT), fill="#293843")
    draw.rectangle((0, HEIGHT - 3, int(WIDTH * elapsed / duration), HEIGHT), fill=ACCENT)
    return frame


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--renderer", type=Path, default=ROOT / "build/structural-rt-cornell-rhi")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--font-dir", type=Path, default=Path("/usr/share/fonts/truetype/dejavu"))
    parser.add_argument("--work-dir", type=Path, default=ROOT / "build/readme-video")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "media")
    parser.add_argument("--reuse-rendered", action="store_true")
    args = parser.parse_args()
    if not args.ffmpeg:
        parser.error("FFmpeg not found; provide --ffmpeg /path/to/ffmpeg")
    font = fonts(args.font_dir)
    args.work_dir.mkdir(parents=True, exist_ok=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = args.work_dir / "manifest.json"
    previous = json.loads(manifest_path.read_text()) if args.reuse_rendered and manifest_path.exists() else {}
    manifest = {"capture": "headless Vulkan structural API", "playback": "edited offline showcase",
                "resolution": [512, 512], "frames_per_second": FPS, "shots": {},
                "renderer_sha256": digest(args.renderer),
                "source_sha256": {str(path.relative_to(ROOT)): digest(path)
                                  for path in [ROOT / "scene.h", *sorted((ROOT / "shaders").glob("*.slang*"))]}}
    if args.reuse_rendered and any(previous.get(key) != manifest[key]
                                   for key in ("renderer_sha256", "source_sha256")):
        parser.error("Cannot reuse captures after renderer/source changes; run without --reuse-rendered")
    captures = {}
    for shot in SHOTS:
        name, samples, view = shot[:3]
        if name in captures:
            continue
        path = args.work_dir / f"{name}.ppm"
        command = [str(args.renderer.resolve()), str(ROOT / "shaders"), "--backend", "vulkan",
                   "--api", "structural", "--headless", "--width", "512", "--height", "512",
                   "--samples", str(samples), "--bounces", "8", "--seed", "1", "--exposure", "1",
                   "--sphere", "glass", "--view", view, "--ao-samples", "8", "--ao-radius", "0.75",
                   "--output", str(path.resolve())]
        if args.reuse_rendered:
            old = previous.get("shots", {}).get(name, {})
            if old.get("command") != command or not path.exists() or old.get("sha256") != digest(path):
                parser.error(f"Cannot reuse {name}: missing/changed capture or settings; run without --reuse-rendered")
        else:
            print("Rendering", name, flush=True)
            with (args.work_dir / f"{name}.log").open("w") as log:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=300, check=True)
        with Image.open(path) as source:
            if source.size != (512, 512):
                raise ValueError(f"Unexpected capture dimensions: {path}: {source.size}")
            captures[name] = source.convert("RGB")
        manifest["shots"][name] = {"command": command, "sha256": digest(path)}
    duration = sum(shot[3] for shot in SHOTS)
    manifest["duration_seconds"] = duration
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    captures["beauty-4096"].save(args.output_dir / "cornell-pathtracer-beauty.png")
    captures["ao-256"].save(args.output_dir / "cornell-pathtracer-ao.png")
    output = args.output_dir / "cornell-box-demo.webm"
    # MJPEG input also works with the small FFmpeg binary bundled with Playwright.
    encode = [args.ffmpeg, "-y", "-f", "image2pipe", "-vcodec", "mjpeg",
              "-framerate", str(FPS), "-i", "pipe:0", "-an", "-c:v", "libvpx", "-b:v", "1200k", "-crf", "8",
              "-pix_fmt", "yuv420p", "-threads", "2", str(output)]
    preview_frames, cards = [], []
    elapsed = 0
    with (args.work_dir / "encode.log").open("w") as log:
        with subprocess.Popen(encode, stdin=subprocess.PIPE, stdout=log, stderr=log) as process:
            try:
                for shot in SHOTS:
                    count = round(shot[3] * FPS)
                    for index in range(count):
                        frame = compose(captures[shot[0]], shot, elapsed + index / FPS, duration, font)
                        frame.save(process.stdin, format="JPEG", quality=95, subsampling=0)
                        if index == 0:
                            cards.append(frame)
                        # 4 fps GIF: smaller preview; WebM preserves full resolution.
                        if index % 3 == 0:
                            preview_frames.append(frame.resize((672, 480), Image.Resampling.LANCZOS))
                    elapsed += shot[3]
            except BrokenPipeError as error:
                raise RuntimeError(f"FFmpeg rejected input; see {args.work_dir / 'encode.log'}") from error
            finally:
                process.stdin.close()
            if process.wait() != 0:
                raise RuntimeError(f"FFmpeg failed; see {args.work_dir / 'encode.log'}")
    # One palette across shots avoids colors changing during held frames.
    palette_source = Image.new("RGB", (672, 480 * len(cards)))
    for i, card in enumerate(cards):
        palette_source.paste(card.resize((672, 480), Image.Resampling.LANCZOS), (0, i * 480))
    palette = palette_source.quantize(colors=256)
    preview_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in preview_frames]
    preview_frames[0].save(args.output_dir / "cornell-box-demo.gif", save_all=True,
                           append_images=preview_frames[1:], duration=250, loop=0, optimize=True)
    contact = Image.new("RGB", (448 * 2, 320 * 4), BACKGROUND)
    for i, card in enumerate(cards):
        contact.paste(card.resize((448, 320), Image.Resampling.LANCZOS), ((i % 2) * 448, (i // 2) * 320))
    contact.save(args.work_dir / "contact-sheet.png")
    cards[0].save(args.work_dir / "beauty-card.png")
    print(f"Wrote {duration:g}s WebM ({WIDTH}x{HEIGHT}, {FPS} fps) and GIF (672x480, 4 fps)")
    print(f"Captures, manifest and contact sheet: {args.work_dir}")


if __name__ == "__main__":
    main()
