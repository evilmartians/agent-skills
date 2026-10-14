#!/usr/bin/env bash
#
# Encodes a video for the web; run with --help for usage. Every encoding
# setting lives in this file. Part of the web-video agent skill by
# Evil Martians (https://evilmartians.com): copy the whole skill folder to reuse it.
#
# Runs on macOS's stock bash 3.2: no associative arrays, and a possibly empty
# array expands as ${arr[@]+"${arr[@]}"} under set -u.

set -euo pipefail

AV1_QP=45
HEVC_CRF=28
H264_CRF=26
VP9_CRF=30

# SVT-AV1 logs on its own, past -loglevel: keep only its errors.
export SVT_LOG=1

# Every scale and pixel format conversion: Lanczos keeps downscaled text and UI
# edges sharp where the default bicubic blurs them; chroma from every pixel;
# exact rounding.
sws=(-sws_flags lanczos+accurate_rnd+full_chroma_int+full_chroma_inp)

# In a terminal, progress redraws in place twice a second. Piped to an agent or
# a log, every redraw is another line, so report every 30 seconds instead.
if [[ -t 2 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m'
  stats=(-stats)
else
  RED='' GREEN='' NC=''
  stats=(-stats -stats_period 30)
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <video>

Encodes <video> for the web as <name>.<format>.<ext> files next to it.
  Opaque video:      AV1 (10-bit), HEVC, and H.264 MP4s and a JPEG poster
  Transparent video: VP9 WebM, HEVC MP4 with alpha (macOS only), and a PNG poster
Video with see-through pixels gets the transparent formats; --opaque overrides it.

Options:
  -o, --output-dir DIR  write the files to DIR instead of next to the source
  -f, --formats LIST    encode only these, comma-separated:
                        av1,hevc,h264 (opaque) or vp9,hevc (transparent)
      --opaque-formats LIST
                        what opaque video gets when --formats isn't given
                        (default: av1,hevc,h264)
      --opaque          flatten any transparency and encode as regular video
      --speed N         play N times faster (2, 1.5); 60fps, drops audio
      --max-width PX    downscale anything wider than PX, keeping the aspect ratio
      --fps N           re-time to N frames per second
      --no-audio        drop the audio track
      --poster-at SEC   take the poster SEC seconds in (default: the first frame)
      --no-poster       skip the poster image
      --fast            draft: same quality settings, quicker presets, bigger files
      --av1-qp N        AV1 quality, lower is better and bigger (default: $AV1_QP)
      --hevc-crf N      HEVC quality, lower is better and bigger (default: $HEVC_CRF)
      --h264-crf N      H.264 quality, lower is better and bigger (default: $H264_CRF)
      --vp9-crf N       VP9 quality, lower is better and bigger (default: $VP9_CRF)
  -h, --help            show this help

HEVC with alpha is encoded by avconvert's Apple presets, so --fast and the
quality options don't apply to it.

A project can set default options, like --opaque-formats av1,h264, in a
.web-video file at the root of its git repository (or the current directory
outside one). # starts a comment, and the command line overrides the file.
EOF
}

die() {
  echo -e "${RED}$*${NC}" >&2
  exit 1
}

has() {
  [[ ",$formats," == *",$1,"* ]]
}

# Apple's HEVC with alpha keeps it in a second layer that ffmpeg can't decode.
is_mv_hevc_alpha() {
  local codec
  codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$1")
  # No grep -q: it exits early, and pipefail turns ffprobe's SIGPIPE into a miss.
  [[ "$codec" == "hevc" ]] && ffprobe -v debug "$1" 2>&1 | grep "nuh_layer_id: 1" > /dev/null
}

# pix_fmt_has <flag> <file>: alpha, rgb, palette. ffprobe prints "bgra,1,1,8"
# up to 7.1 and "bgra,1" from 8.0 on.
pix_fmt_has() {
  local pix_fmt
  pix_fmt=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 "$2")
  grep -qE "^$pix_fmt,1(,|$)" <<< "$(ffprobe -v error -show_pixel_formats -show_entries pixel_format=name:flags=$1 -of csv=p=0)"
}

# A format with alpha doesn't mean the video uses it: every GIF has one. Scans
# each frame's lowest alpha value; awk reads to the end, so no SIGPIPE.
has_transparent_pixels() {
  ffmpeg -v error -i "$1" -vf "alphaextract,format=gray,signalstats,metadata=print:key=lavfi.signalstats.YMIN:file=/dev/stdout" -f null - |
    awk -F= '/YMIN=/ && $2 < 255 { found = 1 } END { exit !found }'
}

need_encoder() {
  grep -q " $1 " <<< "$encoders" ||
    die "This ffmpeg build lacks $1, needed for $2. Install one that has it (brew install ffmpeg on macOS) or leave $2 out with --formats."
}

need_avconvert() {
  [[ "$(uname)" == "Darwin" ]] && command -v avconvert > /dev/null ||
    die "$1 needs macOS and avconvert (Xcode Command Line Tools). Run this on a Mac, or $2."
}

encode() {
  local label=$1 target=$2
  shift 2
  echo -e "\nEncoding $label..."
  ffmpeg -i "$src" -map_metadata -1 "${sws[@]}" "$@" -loglevel error "${stats[@]}" -y "$target"
  videos+=("$target")
}

# codecs <file> <format>: the codecs parameter for the type attribute, read from
# the file. A level below the stream's, or an audio codec the file doesn't
# carry, and the browser may skip the source or pick a worse one.
codecs() {
  local file=$1 video audio
  case "$2" in
    av1)
      # ffprobe's level is the AV1 seq_level_idx: 8 is 4.0, enough for 1080p.
      video=$(ffprobe -v error -select_streams v:0 -show_entries stream=level -of csv=p=0 "$file")
      video=$(printf 'av01.0.%02dM.%s' "$video" "$([[ "$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 "$file")" == *10le ]] && echo 10 || echo 08)")
      ;;
    h264)
      # The avcC box: a version byte, then profile, constraint flags, level.
      video=avc1.$(ffprobe -v error -select_streams v:0 -show_entries stream=extradata -show_data -of default=nw=1:nk=1 "$file" |
        awk '/^00000000:/ { print toupper(substr($2, 3, 2) substr($3, 1, 4)); exit }')
      ;;
    hevc) video=hvc1 ;;
    vp9) video=vp9 ;;
  esac
  audio=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$file")
  case "$audio" in
    aac) audio=", mp4a.40.2" ;;
    opus) audio=", opus" ;;
    *) audio="" ;;
  esac
  echo "$video$audio"
}

output_dir=""
formats=""
opaque_formats=""
opaque=false
speed=""
max_width=""
fps=""
audio=true
poster=true
poster_at=""
fast=false
input=""

# Project defaults go first, so the command line overrides them.
config="$(git rev-parse --show-toplevel 2> /dev/null || pwd)/.web-video"
if [[ -f "$config" ]]; then
  defaults=$(sed 's/#.*//' "$config" | tr -s '[:space:]' ' ')
  echo "Defaults from $config:$defaults"
  set -- $defaults "$@"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o | --output-dir) output_dir=${2:?$1 needs a value}; shift 2 ;;
    -f | --formats) formats=${2:?$1 needs a value}; shift 2 ;;
    --opaque-formats) opaque_formats=${2:?$1 needs a value}; shift 2 ;;
    --opaque) opaque=true; shift ;;
    --speed) speed=${2:?$1 needs a value}; shift 2 ;;
    --max-width) max_width=${2:?$1 needs a value}; shift 2 ;;
    --fps) fps=${2:?$1 needs a value}; shift 2 ;;
    --no-audio) audio=false; shift ;;
    --poster-at) poster_at=${2:?$1 needs a value}; shift 2 ;;
    --no-poster) poster=false; shift ;;
    --fast) fast=true; shift ;;
    --av1-qp) AV1_QP=${2:?$1 needs a value}; shift 2 ;;
    --hevc-crf) HEVC_CRF=${2:?$1 needs a value}; shift 2 ;;
    --h264-crf) H264_CRF=${2:?$1 needs a value}; shift 2 ;;
    --vp9-crf) VP9_CRF=${2:?$1 needs a value}; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) die "Unknown option: $1 (see --help)" ;;
    *)
      [[ -z "$input" ]] || die "One video at a time: got $input and $1"
      input=$1
      shift
      ;;
  esac
done

if [[ -z "$input" ]]; then
  usage >&2
  exit 1
fi
[[ -f "$input" ]] || die "No such file: $input"
command -v ffmpeg > /dev/null && command -v ffprobe > /dev/null ||
  die "ffmpeg is not installed: brew install ffmpeg on macOS, or see https://ffmpeg.org/download.html"

src=$input
name=$(basename "$input")
name=${name%.*}
output_dir=${output_dir:-$(dirname "$input")}
target="$output_dir/$name"

alpha=false
mv_hevc=false
if ! $opaque; then
  if is_mv_hevc_alpha "$src"; then
    alpha=true
    mv_hevc=true
  elif pix_fmt_has alpha "$src"; then
    echo "Checking the alpha channel for see-through pixels..."
    if has_transparent_pixels "$src"; then
      alpha=true
    else
      echo "Nothing is see-through, so encoding it as regular video."
    fi
  fi
fi

if $alpha; then
  kind=transparent
  all=vp9,hevc
  default=$all
  hint=", or flatten the alpha with --opaque"
else
  kind=opaque
  all=av1,hevc,h264
  default=${opaque_formats:-$all}
  hint=""
fi
formats=${formats:-$default}
for format in ${formats//,/ }; do
  [[ ",$all," == *",$format,"* ]] || die "$format isn't a format for $kind video: pick from $all$hint"
done

needs_prep=false
if [[ -n "$speed$max_width$fps" ]]; then
  needs_prep=true
fi

# Check every requirement before the first encode, not after an hour of AV1.
encoders=$(ffmpeg -hide_banner -encoders 2> /dev/null)
if $mv_hevc; then
  need_avconvert "Decoding Apple's HEVC with alpha" "re-export the source as ProRes 4444"
fi
if $alpha && has hevc; then
  need_avconvert "HEVC with alpha" "leave it out with --formats vp9"
fi
if $alpha && has vp9; then
  need_encoder libvpx-vp9 vp9
fi
if ! $alpha && has av1; then
  need_encoder libsvtav1 av1
fi
if ! $alpha && has hevc; then
  need_encoder libx265 hevc
fi
if ! $alpha && { has h264 || $needs_prep; }; then
  need_encoder libx264 h264
fi

mkdir -p "$output_dir"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Source: $input"
echo "Output: $output_dir/"
echo "Pipeline: $kind ($formats)"

if $mv_hevc; then
  echo -e "\nConverting Apple HEVC with alpha to a ProRes 4444 intermediate..."
  avconvert -s "$src" -o "$tmp/prores.mov" -p PresetAppleProRes4444LPCM --progress --replace
  src="$tmp/prores.mov"
fi

even="scale=trunc(iw/2)*2:trunc(ih/2)*2"

# RGB has no color matrix, so swscale would convert with BT.601 and leave the
# stream untagged, which browsers show as BT.709. Convert with BT.709 instead,
# once, and tag it. YUV sources keep their own matrix and tags.
convert=""
if pix_fmt_has rgb "$src" || pix_fmt_has palette "$src"; then
  convert=":out_color_matrix=bt709:out_range=tv,setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709"
fi
# swscale reads a palette straight into YUV with BT.601 whatever matrix it's
# given, so expand it to RGB first.
expand=""
if pix_fmt_has palette "$src"; then
  expand="format=rgba,"
fi

# Speed, size, and frame rate go into one lossless intermediate, so avconvert's
# HEVC with alpha gets them too.
if $needs_prep; then
  filters=()
  if [[ -n "$speed" ]]; then
    filters+=("setpts=PTS/$speed")
  fi
  if [[ -n "$max_width" ]]; then
    filters+=("scale='min(iw,$max_width)':-2")
  fi
  filters+=("$even$convert")
  # A sped-up variable-rate video stutters in QuickTime; constant 60fps doesn't.
  if [[ -n "$speed$fps" ]]; then
    filters+=("fps=${fps:-60}")
  fi
  vf="$expand$(IFS=,; echo "${filters[*]}")"

  prep_audio=(-c:a pcm_s16le)
  if [[ -n "$speed" ]] || ! $audio; then
    prep_audio=(-an)
  fi
  # 10-bit: an 8-bit source stays bit-exact, and an RGB one is converted once,
  # at full precision, instead of being quantized to 8-bit YUV on the way.
  prep_video=(-c:v libx264 -qp 0 -preset ultrafast -pix_fmt yuv420p10le)
  if $alpha; then
    prep_video=(-c:v prores_ks -profile:v 4444 -pix_fmt yuva444p10le)
  fi

  echo -e "\nApplying speed, size, and frame rate..."
  ffmpeg -i "$src" "${sws[@]}" -vf "$vf" "${prep_video[@]}" "${prep_audio[@]}" -loglevel error "${stats[@]}" -y "$tmp/prepared.mov"
  src="$tmp/prepared.mov"
  convert=""
  expand=""
fi

if $fast; then
  av1_preset=8 x26x_preset=medium vp9_deadline=good vp9_cpu_used=4
else
  av1_preset=1 x26x_preset=veryslow vp9_deadline=best vp9_cpu_used=2
fi
aac=(-c:a aac)
opus=(-c:a libopus)
if ! $audio; then
  aac=(-an)
  opus=(-an)
fi

videos=()

if $alpha && has vp9; then
  encode "VP9 with alpha (Chrome, Firefox, Edge)" "$target.vp9.webm" \
    -an \
    -c:v libvpx-vp9 \
    -pix_fmt yuva420p \
    -b:v 0 \
    -crf "$VP9_CRF" \
    -deadline "$vp9_deadline" \
    -cpu-used "$vp9_cpu_used" \
    -auto-alt-ref 0 \
    -vf "$expand$even$convert,format=yuva420p"
fi

if $alpha && has hevc; then
  height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$src")
  preset=PresetHEVC1920x1080WithAlpha
  if [[ "$height" -gt 1080 ]]; then
    preset=PresetHEVC3840x2160WithAlpha
  fi
  echo -e "\nEncoding HEVC with alpha (Safari) with $preset..."
  avconvert -s "$src" -o "$target.hevc.mp4" -p "$preset" --progress --replace
  videos+=("$target.hevc.mp4")
fi

# Fastest first, so a broken setup fails before the long AV1 encode.
if ! $alpha && has h264; then
  encode "H.264 (fallback)" "$target.h264.mp4" \
    "${aac[@]}" \
    -c:v libx264 \
    -crf "$H264_CRF" \
    -preset "$x26x_preset" \
    -profile:v main \
    -pix_fmt yuv420p \
    -movflags +faststart \
    -vf "$expand$even$convert"
fi

if ! $alpha && has hevc; then
  encode "HEVC (Safari)" "$target.hevc.mp4" \
    "${aac[@]}" \
    -c:v libx265 \
    -crf "$HEVC_CRF" \
    -preset "$x26x_preset" \
    -pix_fmt yuv420p \
    -movflags +faststart \
    -tag:v hvc1 \
    -vf "$expand$even$convert" \
    -x265-params log-level=error
fi

# -qp is -crf with SVT-AV1's adaptive quantization off, which on screen content
# scores higher at equal size on every metric tried (SSIMULACRA2 by 4 points).
# ac-bias spends a little more on high-frequency detail (SVT-AV1 4.0+; older
# builds ignore it).
if ! $alpha && has av1; then
  encode "AV1 (smallest, and slow: no worries)" "$target.av1.mp4" \
    "${opus[@]}" \
    -c:v libsvtav1 \
    -qp "$AV1_QP" \
    -preset "$av1_preset" \
    -b:v 0 \
    -svtav1-params tile-columns=2:tile-rows=2:lp=0:ac-bias=1 \
    -pix_fmt yuv420p10le \
    -movflags +faststart \
    -vf "$expand$even$convert"
fi

poster_file=""
if $poster; then
  seek=()
  if [[ -n "$poster_at" ]]; then
    seek=(-ss "$poster_at")
  fi
  echo -e "\nExtracting the poster..."
  if $alpha; then
    poster_file="$target.png"
    ffmpeg ${seek[@]+"${seek[@]}"} -i "$src" "${sws[@]}" -frames:v 1 -vf "$even" -pix_fmt rgba -compression_level 9 -pred mixed -update 1 -loglevel error -y "$poster_file"
  else
    poster_file="$target.jpg"
    ffmpeg ${seek[@]+"${seek[@]}"} -i "$src" "${sws[@]}" -frames:v 1 -vf "$even" -q:v 5 -update 1 -loglevel error -y "$poster_file"
  fi
fi

echo -e "\n${GREEN}Done.${NC}\n"
ls -lh "${videos[@]}" ${poster_file:+"$poster_file"}
echo -e "\nSize: $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "${videos[0]}") px"

# Browsers play the first source they support, so the smallest goes first,
# except that Safari needs HEVC ahead of a VP9 it would play without alpha.
if $alpha; then
  order="hevc vp9"
else
  order="av1 hevc h264"
fi
echo -e "\nHTML:\n"
echo "<video${poster_file:+ poster=\"$(basename "$poster_file")\"} autoplay muted loop playsinline>"
for format in $order; do
  has "$format" || continue
  ext=$([[ "$format" == vp9 ]] && echo webm || echo mp4)
  echo "  <source src=\"$name.$format.$ext\" type='video/$ext; codecs=\"$(codecs "$target.$format.$ext" "$format")\"' />"
done
echo "</video>"

if [[ -t 1 ]]; then
  printf '\a'
fi
