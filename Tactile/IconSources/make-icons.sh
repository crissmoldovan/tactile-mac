#!/usr/bin/env bash
# Makes Tactile's app icon and menu-bar glyphs from one of the designer's six options.
#
#   Tactile/IconSources/make-icons.sh <option 1-6>
#
# Writes, in Tactile/Assets.xcassets:
#   AppIcon.appiconset   PNGs at every size macOS needs (16 to 512 pt, 1x and 2x), from
#                        options/option-N-app.svg: rendered once at 1024 px by headless Chrome,
#                        then scaled down with sips.
#   MenuBarGlyph.imageset, MenuBarGlyphOff.imageset, MenuBarGlyphAttention.imageset
#                        options/option-N-menubar{,-off,-attention}.svg, copied as they are: single-scale
#                        vectors, rendered as template images.
# Nothing else is changed. It needs Google Chrome (set CHROME to use another copy) and opens no window.
set -euo pipefail

usage() {
    echo "usage: $(basename "$0") <option 1-6>" >&2
    echo "Renders options/option-<N>-*.svg into Tactile/Assets.xcassets (the app icon and the menu-bar glyphs)." >&2
}

if [[ $# -ne 1 || ! "$1" =~ ^[1-6]$ ]]; then
    usage
    exit 2
fi
option="$1"

here="$(cd "$(dirname "$0")" && pwd)"
sources="$here/options"
catalog="$(cd "$here/../Assets.xcassets" && pwd)"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

app_svg="$sources/option-$option-app.svg"
for f in "$app_svg" "$sources/option-$option-menubar.svg" "$sources/option-$option-menubar-off.svg" \
         "$sources/option-$option-menubar-attention.svg"; do
    [[ -f "$f" ]] || { echo "missing: $f" >&2; exit 1; }
done
[[ -x "$chrome" ]] || { echo "Google Chrome not found at: $chrome (set CHROME to its binary)" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/tactile-icons.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# --- The app icon: one render at 1024 px, on a transparent background, in a throw-away Chrome profile.
{
    printf '<!doctype html><html><head><meta charset="utf-8"><style>'
    printf 'html,body{margin:0;padding:0;background:transparent;overflow:hidden}'
    printf 'svg{display:block;width:1024px;height:1024px}</style></head><body>'
    cat "$app_svg"
    printf '</body></html>'
} > "$work/page.html"

"$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --user-data-dir="$work/profile" --force-device-scale-factor=1 --window-size=1024,1024 \
    --default-background-color=00000000 --screenshot="$work/1024.png" "file://$work/page.html" \
    > "$work/chrome.log" 2>&1 || { cat "$work/chrome.log" >&2; echo "Chrome failed to render $app_svg" >&2; exit 1; }

size="$(sips -g pixelWidth -g pixelHeight "$work/1024.png" | awk '/pixel(Width|Height)/ {printf "%s ", $2}')"
[[ "$size" == "1024 1024 " ]] || { echo "the render is ${size}px, not 1024 x 1024" >&2; exit 1; }

iconset="$catalog/AppIcon.appiconset"
rm -rf "$iconset"
mkdir -p "$iconset"
entries=()
# point size, scale, pixels
for slot in "16 1 16" "16 2 32" "32 1 32" "32 2 64" "128 1 128" "128 2 256" "256 1 256" "256 2 512" "512 1 512" "512 2 1024"; do
    read -r pt scale px <<< "$slot"
    name="icon_${pt}x${pt}"
    if [[ "$scale" == 2 ]]; then name="${name}@2x"; fi
    if [[ "$px" == 1024 ]]; then
        cp "$work/1024.png" "$iconset/$name.png"
    else
        sips -z "$px" "$px" "$work/1024.png" --out "$iconset/$name.png" > /dev/null
    fi
    entries+=("    { \"filename\" : \"$name.png\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${pt}x${pt}\" }")
done
{
    echo '{'
    echo '  "images" : ['
    last=$(( ${#entries[@]} - 1 ))
    for i in "${!entries[@]}"; do
        if [[ "$i" -lt "$last" ]]; then echo "${entries[$i]},"; else echo "${entries[$i]}"; fi
    done
    echo '  ],'
    echo '  "info" : { "author" : "xcode", "version" : 1 }'
    echo '}'
} > "$iconset/Contents.json"

# --- The menu-bar glyphs: the SVGs as they are, as template images that keep their vector form.
for pair in "MenuBarGlyph:menubar" "MenuBarGlyphOff:menubar-off" "MenuBarGlyphAttention:menubar-attention"; do
    asset="${pair%%:*}"
    src="$sources/option-$option-${pair#*:}.svg"
    set_dir="$catalog/$asset.imageset"
    rm -rf "$set_dir"
    mkdir -p "$set_dir"
    cp "$src" "$set_dir/$asset.svg"
    cat > "$set_dir/Contents.json" <<EOF
{
  "images" : [
    { "filename" : "$asset.svg", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
EOF
done

echo "Option $option written to $catalog (AppIcon, MenuBarGlyph, MenuBarGlyphOff, MenuBarGlyphAttention)."
echo "Next: say which option it is in Tactile/IconSources/README.md, build, and look at the result."
