#!/usr/bin/env bash
# Builds the bundled Linux runtime for XRK Harness mobile (Ubuntu Base + Node.js +
# @xrkseek/harness-cli, run through Termux proot) for each Android ABI, on an x86_64
# Linux host without executing foreign-architecture code.
#
#   runtime/build-runtime.sh                 # both ABIs (x86_64 first)
#   runtime/build-runtime.sh arm64-v8a       # one ABI
#   COMPRESS=gz runtime/build-runtime.sh     # .tar.gz instead of .tar.xz
#   RUNTIME_OUT=/path runtime/build-runtime.sh
#   ENGINE_TGZ=/path/to/xrkseek-harness-cli-<ver>.tgz ENGINE_VERSION=<ver> …
#
# Outputs (consumed by app/android/app/build.gradle.kts flavors):
#   runtime/out/<abi>/assets/runtime/rootfs-<abi>.tar.xz
#   runtime/out/<abi>/assets/runtime/manifest.json
#   runtime/out/<abi>/assets/runtime/licenses/...
#   runtime/out/<abi>/jniLibs/<abi>/lib{proot,proot-loader,talloc,android-shmem}.so
#   runtime/out/<abi>/build-report.json
#   runtime/out/manifest.json
#
# Idempotent: downloads cache in runtime/.cache; engine/pnpm trees pin under
# runtime/locks/engine-<version>/ and runtime/locks/pnpm-<version>/.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="$HERE/.cache"
WORK="$HERE/.work"
OUT="${RUNTIME_OUT:-$HERE/out}"   # the app build reads runtime/out; RUNTIME_OUT stages a build elsewhere
LOCKS="$HERE/locks"
PY=(python3 -I "$HERE/lib/rtbuild.py")

# ---- pinned inputs (override via environment; pinned hashes then must be updated too) ----
RUNTIME_REVISION="${RUNTIME_REVISION:-r17}"  # r17: +libatomic1 for Node; r16 swapped engine to harness-cli
ENGINE_PKG="${ENGINE_PKG:-@xrkseek/harness-cli}"
ENGINE_VERSION="${ENGINE_VERSION:-0.7.15}"
# Optional absolute path to a local `npm pack` / `pnpm release:stage` tarball.
# When set, install_engine uses that file instead of registry.npmjs.org — for
# APK hand-tests of uncommitted / unpublished harness-cli (no git push required).
ENGINE_TGZ="${ENGINE_TGZ:-}"
# Keep XRK_VERSION as an alias for scripts/docs that still read it during the cutover.
ENGINE_VERSION="${ENGINE_VERSION}"
NODE_VERSION="${NODE_VERSION:-26.12.1}"
# pnpm remains available inside the guest for plugin installs.
PNPM_VERSION="${PNPM_VERSION:-11.28.5}"
# dist.integrity of pnpm-$PNPM_VERSION.tgz, identical on registry.npmjs.org and npmmirror
PNPM_INTEGRITY="${PNPM_INTEGRITY:-sha512-SEVj0wtMKtJ8tIqpT/KzAtvOvI/2vyiBbCWJiG4UbOf3bzVPO8GkOOb16XaMMCqgpvet2CMpA81M+BQmy8FNng==}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.5}"
PROOT_VERSION="5.1.107.102"
TALLOC_VERSION="2.5.0"
SHMEM_VERSION="0.7"
# libatomic1: Node official linux binaries need libatomic.so.1 (not in ubuntu-base).
UBUNTU_EXTRA="${UBUNTU_EXTRA:-tzdata ca-certificates git libatomic1}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12.15}"
PBS_RELEASE="${PBS_RELEASE:-20261021}"    # astral-sh/python-build-standalone release tag
COMPRESS="${COMPRESS:-xz}"          # xz | gz
XZ_PRESET="${XZ_PRESET:-6}"         # 8 MiB dictionary: modest memory for xz-java on phones
XZ_THREADS="${XZ_THREADS:-4}"       # each xz -6 worker needs ~100 MiB; output does not depend on this
PRUNE_DEV_METADATA="${PRUNE_DEV_METADATA:-1}"   # drop *.map / *.d.ts from node_modules
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1767225600}"  # 2026-01-01T00:00:00Z, fixed tar mtimes

UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release"
NODE_MIRROR="https://npmmirror.com/mirrors/node"
# Engine package lives on npmjs; npmmirror may lag — prefer npmjs for the engine install.
NPM_REGISTRY="https://registry.npmmirror.com"
ENGINE_REGISTRY="${ENGINE_REGISTRY:-https://registry.npmjs.org}"
TERMUX_REPO="https://packages.termux.dev/apt/termux-main"
UBUNTU_ARCHIVE_AMD64="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"        # InRelease verified with gpgv
UBUNTU_ARCHIVE_ARM64="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
PBS_OFFICIAL="https://github.com/astral-sh/python-build-standalone/releases/download"
PBS_MIRROR="https://registry.npmmirror.com/-/binary/python-build-standalone"

# sha256 pins, cross-checked against cdimage.ubuntu.com / nodejs.org / the Termux Packages
# index. The mirror's SHA256SUMS / SHASUMS256.txt are verified as well.
declare -A PIN=(
  [ubuntu-base-24.04.5-base-arm64.tar.gz]=a91d5a93010193712d346d761372b7c9db6dfcf093893161c64ca107f05914f2
  [ubuntu-base-24.04.5-base-amd64.tar.gz]=e77b6f10c2590cef872b33ee9f635a0e3fd1f57fb074c0e52b5c7f56147a0c86
  [node-v26.12.1-linux-arm64.tar.xz]=42aa04922591ee5d4dbc7740d452621acf28508239daa512f5ee8c47ee224fdb
  [node-v26.12.1-linux-x64.tar.xz]=6170b2d474e1c626f43cff3adc118df9fe3b573258a4fc3d850c8dbc6b079bbd
  [proot_5.1.107.102_aarch64.deb]=10a394b585c2fc2b2c8502544f4e5f1be581dc8bfff79e8ba62f16207423e030
  [proot_5.1.107.102_x86_64.deb]=2497064226c15971be8131c7facead94a06c225347796326a383c832dca57758
  [libtalloc_2.5.0_aarch64.deb]=556591f43bb773ad8777e1a29522640866a55f95dab71914418b94a8c58ad5a7
  [libtalloc_2.5.0_x86_64.deb]=b8c6d95f20075dc1f9ec6573575b2444e8d526e48e0d8d6d5cf4e071e6e06530
  [libandroid-shmem_0.7_aarch64.deb]=0da3a24d558b93c92bcf8d611e0826a99ff96e396b148e6cdf33b47c47c57ff6
  [libandroid-shmem_0.7_x86_64.deb]=ffa9e4c87467b158b148d0ff92dda796aa038276c2075af3269cdcdb06f25797
  [cpython-3.12.15+20261021-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz]=b4567aa5a11f51b540c4dfd9e082ebf23e554f8ac17b85caa6cea23e83693394
  [cpython-3.12.15+20261021-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz]=6d7521138fd33afddc1ccd08abb007d9a2829e38117c2576f9efdc0ec73ce772
  # GPL-2.0 source of the proot binary (same archive Termux's build recipe pins); used for COPYING.
  [proot-v5.1.107.102.zip]=30d12a6e2cc4147123756ff58edea262d3083bbc238c12d0ab9b39e3d1c40852
)

log() { printf '\033[1;34m[runtime %s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf '\033[1;31m[runtime] error:\033[0m %s\n' "$*" >&2; exit 1; }
sha256() { sha256sum "$1" | cut -d' ' -f1; }

for tool in curl sha256sum python3 tar xz; do
  command -v "$tool" >/dev/null || die "missing host tool: $tool"
done

# fetch URL DEST [expected-sha256]: cached download with checksum verification.
fetch() {
  local url="$1" dest="$2" want="${3:-}"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" && -n "$want" && "$(sha256 "$dest")" == "$want" ]]; then return 0; fi
  if [[ -f "$dest" && -z "$want" ]]; then return 0; fi
  log "download $url"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -sS -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
  if [[ -n "$want" ]]; then
    local got; got="$(sha256 "$dest")"
    [[ "$got" == "$want" ]] || { rm -f "$dest"; die "sha256 mismatch for $dest: got $got want $want"; }
  fi
}

pin_of() {
  local name="$1"
  if [[ -n "${PIN[$name]:-}" ]]; then printf '%s' "${PIN[$name]}"; fi
}

# ---------------------------------------------------------------------------
# inputs
# ---------------------------------------------------------------------------
ubuntu_base() {  # $1 = ubuntu arch; echoes path
  local arch="$1" name="ubuntu-base-${UBUNTU_VERSION}-base-$1.tar.gz"
  local dir="$CACHE/ubuntu/$UBUNTU_VERSION"
  fetch "$UBUNTU_MIRROR/SHA256SUMS" "$dir/SHA256SUMS"
  local listed; listed="$(awk -v f="$name" '{n=$2; sub(/^\*/,"",n); if (n==f) print $1}' "$dir/SHA256SUMS")"
  [[ -n "$listed" ]] || { rm -f "$dir/SHA256SUMS"; die "$name not listed in SHA256SUMS (stale cache removed, rerun)"; }
  local pin; pin="$(pin_of "$name")"
  [[ -z "$pin" || "$pin" == "$listed" ]] || die "SHA256SUMS disagrees with pinned hash for $name"
  fetch "$UBUNTU_MIRROR/$name" "$dir/$name" "$listed"
  printf '%s' "$dir/$name"
}

node_dist() {  # $1 = node arch (arm64|x64); echoes path
  local name="node-v${NODE_VERSION}-linux-$1.tar.xz" dir="$CACHE/node/v$NODE_VERSION"
  fetch "$NODE_MIRROR/v$NODE_VERSION/SHASUMS256.txt" "$dir/SHASUMS256.txt"
  local listed; listed="$(awk -v f="$name" '$2==f {print $1}' "$dir/SHASUMS256.txt")"
  [[ -n "$listed" ]] || die "$name not listed in SHASUMS256.txt"
  local pin; pin="$(pin_of "$name")"
  [[ -z "$pin" || "$pin" == "$listed" ]] || die "SHASUMS256.txt disagrees with pinned hash for $name"
  fetch "$NODE_MIRROR/v$NODE_VERSION/$name" "$dir/$name" "$listed"
  printf '%s' "$dir/$name"
}

termux_deb() {  # $1 = package, $2 = version, $3 = termux arch; echoes path
  local pkg="$1" ver="$2" arch="$3" name="$1_$2_$3.deb"
  local dest="$CACHE/termux/$name" pin; pin="$(pin_of "$name")"
  if [[ -f "$dest" && -n "$pin" && "$(sha256 "$dest")" == "$pin" ]]; then printf '%s' "$dest"; return; fi
  # Resolve pool path + hash from the current Packages index (verifies index -> deb).
  local idx="$CACHE/termux/Packages-$arch"
  fetch "$TERMUX_REPO/dists/stable/main/binary-$arch/Packages" "$idx.new" && mv "$idx.new" "$idx"
  local rec; rec="$(awk -v RS= -v p="$pkg" -v v="$ver" \
    '$0 ~ "(^|\n)Package: " p "\n" && $0 ~ "\nVersion: " v "\n"' "$idx")"
  [[ -n "$rec" ]] || die "Termux index no longer has $pkg $ver for $arch (bump the pin in build-runtime.sh)"
  local file sum; file="$(sed -n 's/^Filename: //p' <<<"$rec")"; sum="$(sed -n 's/^SHA256: //p' <<<"$rec")"
  [[ -z "$pin" || "$pin" == "$sum" ]] || die "Termux index hash for $name differs from pin"
  fetch "$TERMUX_REPO/$file" "$dest" "$sum"
  printf '%s' "$dest"
}

# Extra Ubuntu noble packages (tzdata, ca-certificates, git and their dependency closure).
# Chain of trust: InRelease of noble / noble-updates / noble-security verified with gpgv against
# ubuntu-archive-keyring.gpg from the checksum-verified Ubuntu Base tarball -> Packages.xz hash
# -> each .deb hash. The resolved set is pinned in runtime/locks/ubuntu-noble-<arch>.json
# (re-resolve with UPDATE_DEB_LOCK=1).
ubuntu_extra_debs() {  # $1 = ubuntu arch, $2 = verified base tarball; echoes deb paths, one per line
  local arch="$1" base="$2" lock="$LOCKS/ubuntu-noble-$1.json" mirror
  [[ "$arch" == amd64 ]] && mirror="$UBUNTU_ARCHIVE_AMD64" || mirror="$UBUNTU_ARCHIVE_ARM64"
  if [[ ! -f "$lock" || "${UPDATE_DEB_LOCK:-0}" == 1 ]] || \
     ! python3 -I -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["want"] != sys.argv[2].split())' "$lock" "$UBUNTU_EXTRA"; then
    command -v gpgv >/dev/null || die "gpgv is required to resolve Ubuntu packages"
    local dir="$CACHE/ubuntu/dists-$arch"; rm -rf "$dir"; mkdir -p "$dir"
    python3 -I - "$base" "$dir/archive-keyring.gpg" <<'PYEOF'
import sys, tarfile
with tarfile.open(sys.argv[1], "r:gz") as t:
    for m in t:
        if m.name.lstrip("./") == "usr/share/keyrings/ubuntu-archive-keyring.gpg":
            open(sys.argv[2], "wb").write(t.extractfile(m).read()); break
    else:
        sys.exit("keyring not found in base tarball")
PYEOF
    local -a idx=() ; local suite want
    for suite in noble noble-updates noble-security; do
      fetch "$mirror/dists/$suite/InRelease" "$dir/$suite.InRelease"
      gpgv --keyring "$dir/archive-keyring.gpg" "$dir/$suite.InRelease" 2>/dev/null \
        || die "InRelease signature check failed for $suite"
      want="$(awk -v f="main/binary-$arch/Packages.xz" '/^SHA256:/{s=1;next} /^[A-Za-z]/{s=0} s && $3==f {print $1}' "$dir/$suite.InRelease")"
      [[ -n "$want" ]] || die "no Packages.xz hash for $suite/$arch"
      fetch "$mirror/dists/$suite/main/binary-$arch/Packages.xz" "$dir/$suite.Packages.xz" "$want"
      idx+=(--packages "$dir/$suite.Packages.xz")
    done
    mkdir -p "$LOCKS"
    # shellcheck disable=SC2086
    "${PY[@]}" resolve-debs --base "$base" --arch "$arch" "${idx[@]}" --want $UBUNTU_EXTRA --out "$lock" >&2
  fi
  local name file sum
  while read -r file sum; do
    name="$(basename "$file")"
    fetch "$mirror/$file" "$CACHE/ubuntu/debs/$name" "$sum"
    printf '%s\n' "$CACHE/ubuntu/debs/$name"
  done < <(python3 -I -c 'import json,sys; [print(p["filename"], p["sha256"]) for p in json.load(open(sys.argv[1]))["packages"]]' "$lock")
}

# Relocatable CPython (python-build-standalone, install_only_stripped).
# Pins in this script are authoritative when present — skip GitHub SHA256SUMS
# (AGT often gets SSL/504 on github.com). Tarball: npmmirror first.
python_dist() {  # $1 = aarch64|x86_64; echoes path
  local name="cpython-${PYTHON_VERSION}+${PBS_RELEASE}-$1-unknown-linux-gnu-install_only_stripped.tar.gz"
  local dir="$CACHE/python/$PBS_RELEASE" pin; pin="$(pin_of "$name")"
  if [[ -f "$dir/$name" && -n "$pin" && "$(sha256 "$dir/$name")" == "$pin" ]]; then printf '%s' "$dir/$name"; return; fi
  local listed="$pin"
  if [[ -z "$listed" ]]; then
    fetch "$PBS_OFFICIAL/$PBS_RELEASE/SHA256SUMS" "$dir/SHA256SUMS"
    listed="$(awk -v f="$name" '$2==f {print $1}' "$dir/SHA256SUMS")"
    [[ -n "$listed" ]] || die "$name not in SHA256SUMS of $PBS_RELEASE"
  else
    log "using pinned hash for $name (skip SHA256SUMS)"
  fi
  # Mirror first; if curl fails, fetch() aborts under set -e — prefer mirror-only when pinned.
  fetch "$PBS_MIRROR/$PBS_RELEASE/$name" "$dir/$name" "$listed"
  printf '%s' "$dir/$name"
}

# Node used to run npm on the build host (the official x64 build; never the foreign one).
host_npm() {
  if [[ "$(uname -m)" == "x86_64" ]]; then
    local tarball; tarball="$(node_dist x64)"
    local dir="$CACHE/host-node/node-v${NODE_VERSION}-linux-x64"
    if [[ ! -x "$dir/bin/node" ]]; then
      mkdir -p "$CACHE/host-node"; tar -xJf "$tarball" -C "$CACHE/host-node"
    fi
    printf '%s' "$dir/bin"
  else
    command -v npm >/dev/null || die "non-x86_64 host without npm on PATH"
    dirname "$(command -v npm)"
  fi
}

# ---------------------------------------------------------------------------
# Engine npm tree (@xrkseek/harness-cli)
# ---------------------------------------------------------------------------
# npm flags for a host-side install into a prefix (no user/global config, no scripts).
npm_prefix_flags() {  # $1 = npm cpu, $2 = prefix dir; sets the caller's npm_flags array
  local registry="${3:-$NPM_REGISTRY}"
  : > "$WORK/empty-user-npmrc"; : > "$WORK/empty-global-npmrc"
  npm_flags=(
    --prefix "$2" --cpu="$1" --os=linux --libc=glibc
    --registry="$registry" --cache "$CACHE/npm"
    --userconfig "$WORK/empty-user-npmrc" --globalconfig "$WORK/empty-global-npmrc"
    --ignore-scripts --no-audit --no-fund --update-notifier=false --loglevel=warn
  )
}

install_engine() {  # $1 = npm cpu, $2 = prefix dir
  local cpu="$1" prefix="$2" bin; bin="$(host_npm)"
  local lockdir="$LOCKS/engine-$ENGINE_VERSION"
  rm -rf "$prefix"; mkdir -p "$prefix"
  local -a npm_flags=(); npm_prefix_flags "$cpu" "$prefix" "$ENGINE_REGISTRY"
  # Published @xrkseek/* packages still embed "workspace:*" in nested package.json
  # dependency fields. npm ci cannot rehydrate that graph — always npm install.
  rm -rf "$lockdir"
  local engine_spec
  if [[ -n "$ENGINE_TGZ" ]]; then
    [[ -f "$ENGINE_TGZ" ]] || die "ENGINE_TGZ not a file: $ENGINE_TGZ"
    engine_spec="$(realpath "$ENGINE_TGZ")"
    log "npm install local ENGINE_TGZ=$engine_spec (cpu=$cpu; expect version $ENGINE_VERSION)"
  else
    engine_spec="$ENGINE_PKG@$ENGINE_VERSION"
    log "npm install $engine_spec (cpu=$cpu)"
  fi
  PATH="$bin:$PATH" npm install "${npm_flags[@]}" --save-exact "$engine_spec"
  local -a hoist=(); mapfile -t hoist < <("${PY[@]}" hoist-candidates "$prefix/package-lock.json")
  if [[ ${#hoist[@]} -gt 0 ]]; then
    log "hoisting duplicated exact dependencies: ${hoist[*]}"
    PATH="$bin:$PATH" npm install "${npm_flags[@]}" --save-exact "$engine_spec" "${hoist[@]}"
  fi
  # Rewrite leftover workspace: ranges to concrete versions so later tooling/npm
  # does not trip on the published metadata.
  python3 -I - "$prefix" <<'PYEOF' || die "failed to rewrite workspace: protocol in engine tree"
import json, os, sys
root = sys.argv[1]
changed = 0
for dirpath, _, files in os.walk(os.path.join(root, "node_modules")):
    if "package.json" not in files:
        continue
    path = os.path.join(dirpath, "package.json")
    try:
        with open(path, encoding="utf-8") as f:
            meta = json.load(f)
    except (OSError, ValueError, UnicodeDecodeError):
        continue
    dirty = False
    for field in ("dependencies", "optionalDependencies", "peerDependencies", "devDependencies"):
        deps = meta.get(field)
        if not isinstance(deps, dict):
            continue
        for name, spec in list(deps.items()):
            if not isinstance(spec, str) or not spec.startswith("workspace:"):
                continue
            # Prefer the installed package's version when present.
            cand = os.path.join(dirpath, "node_modules", *name.split("/"), "package.json")
            if not os.path.isfile(cand):
                cand = os.path.join(root, "node_modules", *name.split("/"), "package.json")
            ver = None
            if os.path.isfile(cand):
                try:
                    ver = json.load(open(cand, encoding="utf-8")).get("version")
                except (OSError, ValueError, UnicodeDecodeError):
                    ver = None
            deps[name] = ver or "*"
            dirty = True
            changed += 1
    if dirty:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2, ensure_ascii=False)
            f.write("\n")
print("rewrote %d workspace: dependency specs" % changed, file=sys.stderr)
PYEOF
  mkdir -p "$lockdir"
  cp "$prefix/package.json" "$prefix/package-lock.json" "$lockdir/"
  local got; got="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
    "$prefix/node_modules/@xrkseek/harness-cli/package.json")"
  [[ "$got" == "$ENGINE_VERSION" ]] || die "installed harness-cli $got != $ENGINE_VERSION"
  merge_mobile_skill_seeds "$prefix"
}

# Fold harness-cli seeds/mobile/skills/* into seeds/skills/ so guest establish
# (unchanged fingerprint path) picks up phone-only playbooks. Desktop/npm
# consumers never run this — they only establish seeds/skills/ as published.
merge_mobile_skill_seeds() {  # $1 = npm prefix holding node_modules/@xrkseek/harness-cli
  local cli="$1/node_modules/@xrkseek/harness-cli"
  local src="$cli/seeds/mobile/skills"
  local dst="$cli/seeds/skills"
  # Mobile runtime MUST ship phone playbooks. Silent skip left guests without
  # xrk-phone (skill tool → "unknown") while phone_* tools still worked.
  if [[ ! -d "$src" ]]; then
    die "harness-cli missing seeds/mobile/skills (ENGINE_TGZ / package incomplete — pack apps/cli/seeds/mobile)"
  fi
  if [[ ! -f "$src/xrk-phone/SKILL.md" ]]; then
    die "harness-cli missing seeds/mobile/skills/xrk-phone/SKILL.md"
  fi
  mkdir -p "$dst"
  local entry base merged=0
  for entry in "$src"/*; do
    [[ -d "$entry" ]] || continue
    base="$(basename "$entry")"
    rm -rf "$dst/$base"
    cp -a "$entry" "$dst/$base"
    log "merged mobile skill seed → seeds/skills/$base"
    merged=$((merged + 1))
  done
  [[ "$merged" -gt 0 ]] || die "seeds/mobile/skills had no skill directories to merge"
}

# pnpm for the guest (zero dependencies, plain JS). Same lock-then-`npm ci` scheme as XRK; the
# lock's integrity must equal PNPM_INTEGRITY, so a regenerated lock cannot swap the tarball.
install_pnpm() {  # $1 = npm cpu, $2 = prefix dir
  local cpu="$1" prefix="$2" bin; bin="$(host_npm)"
  local lockdir="$LOCKS/pnpm-$PNPM_VERSION"
  rm -rf "$prefix"; mkdir -p "$prefix"
  local -a npm_flags=(); npm_prefix_flags "$cpu" "$prefix"
  if [[ -f "$lockdir/package-lock.json" ]]; then
    log "npm ci pnpm@$PNPM_VERSION (pinned lock)"
    cp "$lockdir/package.json" "$lockdir/package-lock.json" "$prefix/"
    PATH="$bin:$PATH" npm ci "${npm_flags[@]}"
  else
    log "npm install pnpm@$PNPM_VERSION — first run, will pin the lock"
    PATH="$bin:$PATH" npm install "${npm_flags[@]}" --save-exact "pnpm@$PNPM_VERSION"
    mkdir -p "$lockdir"
    cp "$prefix/package.json" "$prefix/package-lock.json" "$lockdir/"
  fi
  python3 -I - "$prefix" "$PNPM_VERSION" "$PNPM_INTEGRITY" <<'PYEOF' || die "pnpm lock/install does not match the pins"
import json, os, sys
prefix, version, integrity = sys.argv[1:4]
lock = json.load(open(os.path.join(prefix, "package-lock.json")))
pkgs = lock["packages"]
entry = pkgs.get("node_modules/pnpm", {})
others = sorted(k for k in pkgs if k not in ("", "node_modules/pnpm"))
got = json.load(open(os.path.join(prefix, "node_modules/pnpm/package.json")))["version"]
ok = entry.get("version") == version and entry.get("integrity") == integrity and got == version and not others
print("pnpm lock: version=%s integrity=%s... installed=%s extra=%s -> %s" % (
    entry.get("version"), (entry.get("integrity") or "")[:20], got, others, "ok" if ok else "MISMATCH"), file=sys.stderr)
sys.exit(0 if ok else 1)
PYEOF
}

# ---------------------------------------------------------------------------
# per-ABI build
# ---------------------------------------------------------------------------
build_abi() {
  local abi="$1" ubuntu_arch node_arch npm_cpu termux_arch elf_name
  case "$abi" in
    arm64-v8a) ubuntu_arch=arm64; node_arch=arm64; npm_cpu=arm64; termux_arch=aarch64; elf_name="ARM aarch64" ;;
    x86_64)    ubuntu_arch=amd64; node_arch=x64;   npm_cpu=x64;   termux_arch=x86_64;  elf_name="x86-64" ;;
    *) die "unknown ABI $abi (use arm64-v8a or x86_64)" ;;
  esac
  log "=== $abi ==="
  local work="$WORK/$abi" out="$OUT/$abi"
  local assets="$out/assets/runtime" jni="$out/jniLibs/$abi"
  mkdir -p "$work"
  rm -rf "$out"; mkdir -p "$assets/licenses" "$jni"

  local base node proot_deb talloc_deb shmem_deb proot_src
  base="$(ubuntu_base "$ubuntu_arch")"
  node="$(node_dist "$node_arch")"
  ubuntu_extra_debs "$ubuntu_arch" "$base" > "$work/extra-debs.txt"   # set -e aborts on any failure inside
  local -a extra_debs=(); mapfile -t extra_debs < "$work/extra-debs.txt"
  [[ ${#extra_debs[@]} -gt 0 ]] || die "Ubuntu package resolution produced nothing"
  local python; python="$(python_dist "$termux_arch")"
  proot_deb="$(termux_deb proot "$PROOT_VERSION" "$termux_arch")"
  talloc_deb="$(termux_deb libtalloc "$TALLOC_VERSION" "$termux_arch")"
  shmem_deb="$(termux_deb libandroid-shmem "$SHMEM_VERSION" "$termux_arch")"
  proot_src="$CACHE/termux/proot-v$PROOT_VERSION.zip"
  fetch "https://github.com/termux/proot/archive/v$PROOT_VERSION.zip" "$proot_src" "$(pin_of "proot-v$PROOT_VERSION.zip")"

  # -- jniLibs: Termux binaries, renamed lib*.so so the package manager extracts them --
  local debx="$work/debs"; rm -rf "$debx"
  local d
  for d in "$proot_deb" "$talloc_deb" "$shmem_deb"; do "${PY[@]}" deb-extract "$d" "$debx"; done
  local tprefix="$debx/data/data/com.termux/files/usr"
  cp "$tprefix/bin/proot"                  "$jni/libproot.so"
  cp "$tprefix/libexec/proot/loader"       "$jni/libproot-loader.so"
  cp "$tprefix/lib/libtalloc.so.$TALLOC_VERSION" "$jni/libtalloc.so"
  cp "$tprefix/lib/libandroid-shmem.so"    "$jni/libandroid-shmem.so"
  local orig_proot orig_talloc
  orig_proot="$(sha256 "$jni/libproot.so")"; orig_talloc="$(sha256 "$jni/libtalloc.so")"
  # APKs can only carry lib*.so, so the DT_NEEDED/SONAME "libtalloc.so.2" becomes "libtalloc.so".
  "${PY[@]}" patch-dynstr "$jni/libproot.so" libtalloc.so.2 libtalloc.so >&2
  "${PY[@]}" patch-dynstr "$jni/libtalloc.so" libtalloc.so.2 libtalloc.so >&2
  chmod 0755 "$jni"/*.so
  "${PY[@]}" elf-info "$jni"/*.so > "$work/jni-elf.json"

  python3 -I - "$jni" "$work/jni-elf.json" "$work/jnilibs.json" <<PYEOF
import hashlib, json, os, sys
jni, elf, out = sys.argv[1:4]
info = json.load(open(elf))
src = {
  "libproot.so": ("proot", "$PROOT_VERSION", "$(basename "$proot_deb")", "usr/bin/proot",
                  "DT_NEEDED libtalloc.so.2 -> libtalloc.so", "$orig_proot"),
  "libproot-loader.so": ("proot", "$PROOT_VERSION", "$(basename "$proot_deb")", "usr/libexec/proot/loader", None, None),
  "libtalloc.so": ("libtalloc", "$TALLOC_VERSION", "$(basename "$talloc_deb")", "usr/lib/libtalloc.so.$TALLOC_VERSION",
                   "DT_SONAME libtalloc.so.2 -> libtalloc.so", "$orig_talloc"),
  "libandroid-shmem.so": ("libandroid-shmem", "$SHMEM_VERSION", "$(basename "$shmem_deb")", "usr/lib/libandroid-shmem.so", None, None),
}
res = {}
for name, (pkg, ver, deb, inner, patch, orig) in src.items():
    path = os.path.join(jni, name)
    e = info[path]
    res[name] = {
        "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(),
        "bytes": os.path.getsize(path),
        "source": "termux-main %s %s (%s:/data/data/com.termux/files/%s)" % (pkg, ver, deb, inner),
        "patch": patch, "originalSha256": orig,
        "machine": e["machine"], "type": e["type"], "needed": e.get("needed"),
        "soname": e.get("soname"), "minLoadAlign": e["minLoadAlign"],
    }
json.dump(res, open(out, "w"), indent=2)
PYEOF
  # licenses for the native bits
  python3 -I - "$proot_src" "$assets/licenses/proot-COPYING.txt" <<'PYEOF'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
name = next(n for n in z.namelist() if n.endswith("/COPYING") and n.count("/") == 1)
open(sys.argv[2], "wb").write(z.read(name))
PYEOF
  cp "$debx/data/data/com.termux/files/usr/share/doc/libandroid-shmem/copyright" "$assets/licenses/libandroid-shmem-copyright.txt"
  sed -n '1,/\*\//p' "$tprefix/include/talloc.h" > "$assets/licenses/libtalloc-notice.txt"

  # -- Engine (@xrkseek/harness-cli); no XRK patches / xrk-bridge --
  local prefix="$work/engine-prefix"
  install_engine "$npm_cpu" "$prefix"
  printf '[]\n' > "$work/engine-patches.json"
  local pnpm_prefix="$work/pnpm-prefix"
  install_pnpm "$npm_cpu" "$pnpm_prefix"

  # -- runtimeVersion: hash of every input + the recipe itself --
  local lockfile="$LOCKS/engine-$ENGINE_VERSION/package-lock.json"
  local pnpm_lockfile="$LOCKS/pnpm-$PNPM_VERSION/package-lock.json"
  local inputs_sha
  inputs_sha="$( {
      echo "$RUNTIME_REVISION $abi $ENGINE_VERSION $NODE_VERSION $PNPM_VERSION $UBUNTU_VERSION $COMPRESS $XZ_PRESET $PRUNE_DEV_METADATA $SOURCE_DATE_EPOCH"
      sha256 "$base"; sha256 "$node"; sha256 "$python"; sha256sum "${extra_debs[@]}" | cut -d' ' -f1
      sha256 "$proot_deb"; sha256 "$talloc_deb"; sha256 "$shmem_deb"
      sha256 "$lockfile"; sha256 "$pnpm_lockfile"; sha256 "$HERE/build-runtime.sh"; sha256 "$HERE/lib/rtbuild.py"
      (cd "$HERE" && find boot direct -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum)
    } | sha256sum | cut -c1-12 )"
  local runtime_version="${RUNTIME_REVISION}-xrk${ENGINE_VERSION}-node${NODE_VERSION}-ubuntu${UBUNTU_VERSION}-${inputs_sha}"
  local runtime_info
  runtime_info="$(printf '{"runtimeVersion":"%s","abi":"%s","engineVersion":"%s","nodeVersion":"%s","pnpmVersion":"%s","ubuntuVersion":"%s","prootVersion":"%s","enginePatches":[],"xrkBridge":null}' \
    "$runtime_version" "$abi" "$ENGINE_VERSION" "$NODE_VERSION" "$PNPM_VERSION" "$UBUNTU_VERSION" "$PROOT_VERSION")"

  # -- rootfs archive --
  local archive="$assets/rootfs-$abi.tar.$COMPRESS"
  local -a prune=(); [[ "$PRUNE_DEV_METADATA" == 1 ]] && prune=(--prune-dev-metadata)
  log "assembling rootfs ($COMPRESS)"
  "${PY[@]}" assemble --abi "$abi" --base "$base" --node "$node" --engine-prefix "$prefix" --pnpm-prefix "$pnpm_prefix" \
    --out "$archive" --report "$out/build-report.json" --runtime-info "$runtime_info" \
    --compress "$COMPRESS" --xz-preset "$XZ_PRESET" --threads "$XZ_THREADS" --epoch "$SOURCE_DATE_EPOCH" "${prune[@]}" \
    "${extra_debs[@]/#/--deb=}" --python "$python"

  local versions
  versions="$(printf '{"runtimeVersion":"%s","engineVersion":"%s","nodeVersion":"%s","pnpmVersion":"%s","ubuntuVersion":"%s","prootVersion":"%s","tallocVersion":"%s","androidShmemVersion":"%s","enginePatches":[],"xrkBridge":null,"build":{"inputsSha256_12":"%s","ubuntuBaseSha256":"%s","nodeSha256":"%s","engineLockSha256":"%s","pnpmIntegrity":"%s","sourceDateEpoch":%s}}' \
    "$runtime_version" "$ENGINE_VERSION" "$NODE_VERSION" "$PNPM_VERSION" "$UBUNTU_VERSION" "$PROOT_VERSION" "$TALLOC_VERSION" "$SHMEM_VERSION" \
    "$inputs_sha" "$(sha256 "$base")" "$(sha256 "$node")" "$(sha256 "$lockfile")" "$PNPM_INTEGRITY" "$SOURCE_DATE_EPOCH")"
  "${PY[@]}" manifest --abi "$abi" --report "$out/build-report.json" --jnilibs "$work/jnilibs.json" \
    --versions "$versions" --out "$assets/manifest.json" >&2

  # -- verification: every jniLib and every ELF in the rootfs must match the ABI --
  local f bad=0
  for f in "$jni"/*.so; do
    file -b "$f" | grep -q "$elf_name" || { log "ABI mismatch: $f: $(file -b "$f")"; bad=1; }
  done
  python3 -I - "$out/build-report.json" "$abi" <<'PYEOF' || bad=1
import json, sys
r = json.load(open(sys.argv[1])); want = {"arm64-v8a": "aarch64", "x86_64": "x86-64"}[sys.argv[2]]
wrong = [e["path"] for e in r["elf"] if e["machine"] != want]
print("rootfs ELF objects: %d, wrong-arch: %d, warnings: %d" % (len(r["elf"]), len(wrong), len(r["warnings"])), file=sys.stderr)
sys.exit(1 if wrong else 0)
PYEOF
  [[ "$bad" == 0 ]] || die "ABI verification failed for $abi"
  log "$abi done: $(du -h "$archive" | cut -f1) archive, version $runtime_version"
}

write_index() {
  python3 -I - "$OUT" <<'PYEOF'
import json, os, sys
out = sys.argv[1]
index = {"schema": 1, "abis": {}}
for abi in ("x86_64", "arm64-v8a"):
    p = os.path.join(out, abi, "assets", "runtime", "manifest.json")
    if not os.path.isfile(p):
        continue
    m = json.load(open(p))
    index["abis"][abi] = {k: m.get(k) for k in (  # .get: another ABI may still hold an older build
        "runtimeVersion", "rootfs", "rootfsSha256", "rootfsBytes", "uncompressedBytes", "entries",
        "engineVersion", "nodeVersion", "pnpmVersion", "ubuntuVersion", "prootVersion")}
    index["abis"][abi]["jniLibs"] = {n: {"sha256": v["sha256"], "bytes": v["bytes"]} for n, v in m["jniLibs"].items()}
json.dump(index, open(os.path.join(out, "manifest.json"), "w"), indent=2)
print("wrote " + os.path.join(out, "manifest.json"))
PYEOF
}

main() {
  local -a abis=("$@")
  [[ ${#abis[@]} -gt 0 ]] || abis=(x86_64 arm64-v8a)
  mkdir -p "$CACHE" "$WORK" "$OUT"
  local abi
  for abi in "${abis[@]}"; do build_abi "$abi"; done
  write_index
}

main "$@"
