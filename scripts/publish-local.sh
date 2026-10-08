#!/bin/bash
# Publish a fork release from this machine with gh: build, pack, checksum, GitHub release.
# No Actions minutes. See workbench/README.md "Fork releases" for the version and asset contract.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${OPENRIG_RELEASE_REPO:-kairos-tech-oh/openrig}"
DRY_RUN=false
ASSUME_YES=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes) ASSUME_YES=true ;;
    -h|--help)
      echo "Usage: scripts/publish-local.sh [--dry-run] [--yes]"
      echo "  --dry-run  build, pack and checksum only; create no release"
      echo "  --yes      skip the confirmation prompt"
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

die() { echo "publish-local: $*" >&2; exit 1; }
# Remote-state checks only warn in a dry run, so it works before the branch is pushed.
check() { if $DRY_RUN; then echo "publish-local: warning: $*" >&2; else die "$@"; fi; }

for tool in git gh node npm sha256sum; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done

cd "$REPO_ROOT"

# Untracked files outside the build inputs (editor scratch, .mcp.json) do not reach the tarball.
if [ -n "$(git status --porcelain --untracked-files=no)" ] \
  || [ -n "$(git status --porcelain -- packages scripts docs)" ]; then
  git status --short
  die "working tree is dirty; commit or stash first"
fi

VERSION="$(node -p "require('./packages/cli/package.json').version")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-kairos\.[0-9]+$ ]] \
  || die "packages/cli version '$VERSION' is not a fork version (X.Y.Z-kairos.N)"
for pkg in package.json packages/daemon/package.json packages/ui/package.json; do
  v="$(node -p "require('./$pkg').version")"
  [ "$v" = "$VERSION" ] || die "$pkg is at $v, expected $VERSION"
done

TAG="v$VERSION"
COMMIT="$(git rev-parse HEAD)"

# gh creates the tag on GitHub at this commit, so the commit must already be pushed.
gh api "repos/$REPO/commits/$COMMIT" --silent 2>/dev/null \
  || check "commit ${COMMIT:0:8} is not on $REPO; push the branch first"
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 \
  || [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
  check "$TAG already exists on $REPO; bump the -kairos.N number"
fi

LATEST="$(gh release view -R "$REPO" --json tagName -q .tagName 2>/dev/null || true)"
if [ -n "$LATEST" ]; then
  node -e '
    const parse = (v) => v.replace(/^v/, "").split(/[.-]/).map((p) => (/^\d+$/.test(p) ? Number(p) : p));
    const [a, b] = [parse(process.argv[1]), parse(process.argv[2])];
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
      if (a[i] === b[i]) continue;
      process.exit(a[i] > b[i] ? 0 : 1);
    }
    process.exit(1);
  ' "$VERSION" "$LATEST" || check "$VERSION is not newer than the latest release $LATEST"
fi

echo "=== Fork release $TAG from ${COMMIT:0:8} to $REPO ==="
bash "$REPO_ROOT/scripts/build-package.sh"

grep -q 'dirty: false' packages/cli/dist/build-info.js \
  || die "build stamped dirty=true; the artifact would not match $COMMIT"

OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openrig-release-$VERSION.XXXXXX")"
TARBALL="openrig-cli-$VERSION.tgz"
(cd packages/cli && npm pack --pack-destination "$OUT_DIR" >/dev/null)
[ -f "$OUT_DIR/$TARBALL" ] || die "npm pack did not produce $TARBALL in $OUT_DIR"

(cd "$OUT_DIR" && sha256sum "$TARBALL" > "$TARBALL.sha256")

echo ""
echo "Assets in $OUT_DIR:"
ls -l "$OUT_DIR"

if $DRY_RUN; then
  echo "Dry run: no release created."
  exit 0
fi

if ! $ASSUME_YES; then
  read -r -p "Create and publish $TAG on $REPO as the latest release? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || die "aborted; nothing published"
fi

gh release create "$TAG" -R "$REPO" \
  --target "$COMMIT" \
  --title "OpenRig fork $VERSION" \
  --notes "Fork build of OpenRig from ${COMMIT:0:8}. Install with \`npm install -g $TARBALL\` after checking $TARBALL.sha256." \
  --latest \
  "$OUT_DIR/$TARBALL" "$OUT_DIR/$TARBALL.sha256"

echo "Published: https://github.com/$REPO/releases/tag/$TAG"
