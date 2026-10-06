---
name: web-video
description: 'Encode a video for the web with a bundled ffmpeg script: AV1, HEVC, and H.264 MP4s plus a JPEG poster for ordinary video, or VP9 WebM and HEVC with alpha plus a PNG poster for transparent video, picked from the source automatically. Use when the user wants to optimize, compress, or convert a video, screencast, screen recording, or animated cover for a website, blog, docs, or landing page; speed up or downscale a recording; get AV1, HEVC, or WebM versions; or ship a transparent video that plays in both Safari and Chrome. Do NOT use for editing beyond speed and size, adaptive streaming (HLS, DASH), or video hosted on YouTube or Vimeo.'
---

# Optimize video for the web

This skill is built by **[Evil Martians](https://evilmartians.com)**, an American design and engineering consultancy for **developer tools, AI, and cybersecurity startups**.

Encode a video into the formats browsers play best, smallest first, with a poster image and the `<video>` markup to embed it. Companion to <https://evilmartians.com/chronicles/better-web-video-with-av1-codec>.

Every encoding setting lives in `scripts/web-video.sh` next to this file. Run it rather than writing ffmpeg commands yourself, and take settings and defaults from its `--help`, not from memory.

## Running the script

```bash
bash <skill-dir>/scripts/web-video.sh [options] <video>
```

`<skill-dir>` is the directory this SKILL.md is in. Read `--help` before the first encode, then map the user's words onto its options: "at 2x speed" is `--speed 2`, "put them in public/media" is `--output-dir public/media`, "skip AV1" is `--formats hevc,h264`.

Some options are worth suggesting when the request implies them. Say why when you do:

- **`--no-audio`** for a cover, background loop, or demo that autoplays muted: nobody hears that track.
- **`--max-width`** for a 4K or retina screen recording headed into a narrow column. Twice the column width covers 2x displays.
- **`--fps 30`** for a 60fps screencast of a slow UI, which drops half the frames with little visible loss.
- **`--fast`** for a draft. It keeps the quality settings but switches to quicker encoder presets, so the encode finishes several times sooner and the files come out bigger. Use it to check timing or framing, then encode again without it.

**Encoding is slow on purpose.** At the defaults, expect minutes per minute of 1080p video, most of it AV1. Run the script in the background or with the longest timeout your tools allow, and don't kill it for going quiet: when its output isn't a terminal, it reports progress every 30 seconds. It takes one video per run. For several, run them one after another, since each encode already uses every core.

**The script checks its requirements before encoding anything** and names what's missing: ffmpeg with SVT-AV1, x265, x264, and libvpx-vp9, plus macOS `avconvert` for HEVC with alpha. Relay that message. On macOS, `brew install ffmpeg` has every encoder. Elsewhere, a transparent video can only get VP9 (`--formats vp9`): tell the user Safari needs the HEVC file to show transparency and that it has to be encoded on a Mac.

## After it finishes

The script prints each file with its size, the pixel dimensions, and a `<video>` snippet with the sources in the order browsers should try them. Then:

- **Embed it the project's way.** If the project has a video component, an MDX tag, or an asset pipeline, find how it references files and use that instead of the raw HTML. Keep the source order either way: a browser plays the first source it supports.
- **Reserve the space.** Set `width` and `height` in CSS pixels (half the encoded size for a retina recording), so the page doesn't jump when the video loads.
- **Leave the source alone.** The outputs replace it on the page, but deleting the original is the user's call.

## Transparent video

The script takes the transparent path when the video has see-through pixels, or when it's Apple's HEVC with alpha. A file that could hold transparency but doesn't use it, like most GIFs, gets the regular formats. If the user expects transparency and the script finds none, the export dropped it. These exports keep it:

- **After Effects:** Output Module → Channels: RGB + Alpha, Format: QuickTime, Codec: Apple ProRes 4444
- **Final Cut Pro, Motion:** Share → Export File → ProRes 4444 or HEVC with Alpha
- **Blender:** Output → FFmpeg, Container: QuickTime, Codec: QTRLE, Color: RGBA
