#!/usr/bin/env bash
# Build the signed apt repository from a populated pool.
#
#   ./build-repo.sh <site-dir> <signing-key-id>
#
# `<site-dir>` must already contain the .deb files under
# `pool/main/m/mandible/`; this script writes everything else. The result is
# the directory that gets published to GitHub Pages, laid out the way apt
# expects to find it:
#
#   <site>/pool/main/m/mandible/mandible_<ver>-1_<arch>.deb
#       The packages themselves. `main` is the component, `m` is the first
#       letter of the source package name — Debian's pool convention, kept
#       so the layout is the one a reader already knows rather than one
#       invented here.
#
#   <site>/dists/stable/main/binary-amd64/Packages{,.gz}
#   <site>/dists/stable/main/binary-arm64/Packages{,.gz}
#       Per-architecture package indices. One suite ("stable") carries both
#       architectures, so a single sources entry works on either and
#       `Architectures:` selects. Both plain and gzipped: apt prefers .gz,
#       but a plain Packages costs a few kilobytes and keeps the repository
#       readable with curl.
#
#   <site>/dists/stable/Release
#       Index of the indices — sizes and checksums for every file above.
#       This is the file the signatures cover, and therefore the root of
#       trust for everything apt downloads from here.
#
#   <site>/dists/stable/InRelease      clear-signed Release (what apt prefers)
#   <site>/dists/stable/Release.gpg    detached signature over Release
#       Both, deliberately. Modern apt fetches InRelease and never looks at
#       the other; Release + Release.gpg is the older split that some
#       tooling and older releases still ask for. Publishing both costs one
#       extra signature and removes a class of "works on my machine".
#
#   <site>/mandible-archive-keyring.gpg   public key, dearmored (binary)
#   <site>/mandible-archive-keyring.asc   public key, armored
#       The signing key's public half, at a stable path across releases so
#       a setup line written once keeps working. The binary form is what
#       `Signed-By:` wants on disk; the armored form is there to be read.
#
# Everything under dists/ is regenerated from scratch on every run, so the
# published metadata always describes exactly the pool that was built with
# it — a stale index that references a .deb no longer in the pool is the
# one failure that makes apt look broken to a user who did nothing wrong.
set -euo pipefail

site="${1:?usage: build-repo.sh <site-dir> <signing-key-id>}"
key="${2:?usage: build-repo.sh <site-dir> <signing-key-id>}"

ORIGIN="mandible"
LABEL="mandible"
SUITE="stable"
CODENAME="stable"
COMPONENT="main"
ARCHES=(amd64 arm64)

cd "$site"

[[ -d pool ]] || { echo "no pool/ under ${site} — nothing to index" >&2; exit 1; }

# Refuse to publish an empty repository. apt-ftparchive is perfectly happy
# to emit a valid, signed, empty index, and the result installs nothing
# while looking entirely healthy from the outside.
deb_count="$(find pool -name '*.deb' -type f | wc -l)"
if [[ "$deb_count" -eq 0 ]]; then
  echo "pool/ contains no .deb files — refusing to publish an empty repository" >&2
  exit 1
fi
echo "indexing ${deb_count} package file(s)"

rm -rf dists
for arch in "${ARCHES[@]}"; do
  mkdir -p "dists/${SUITE}/${COMPONENT}/binary-${arch}"
  index="dists/${SUITE}/${COMPONENT}/binary-${arch}/Packages"

  # --multiversion, and it is not optional here. By default
  # dpkg-scanpackages emits only the newest version of each package, so a
  # pool holding every released .deb produced an index listing exactly
  # one — measured: 26 files in the pool, 1 entry per architecture, and
  # every older version silently uninstallable. Anything that downloads
  # more than the latest release must index more than the latest release,
  # or it is downloading for nothing.
  #
  # No override file argument. Passing /dev/null as one is the usual
  # incantation, but it makes dpkg-scanpackages warn "Packages in archive
  # but missing from override file" for every package on every run;
  # omitting it entirely is silent and produces byte-identical output.
  dpkg-scanpackages --multiversion --arch "$arch" pool > "$index"

  if [[ ! -s "$index" ]]; then
    echo "no ${arch} package in the pool — refusing to publish a suite that claims an architecture it cannot serve" >&2
    exit 1
  fi

  # Every .deb of this architecture in the pool must appear in the index.
  # The default-versus-multiversion trap above is silent by construction —
  # a short index is a valid index — so it is checked rather than trusted.
  in_pool="$(find pool -name "*_${arch}.deb" -type f | wc -l)"
  indexed="$(grep -c '^Package:' "$index")"
  if [[ "$indexed" -ne "$in_pool" ]]; then
    echo "binary-${arch}: ${in_pool} package file(s) in the pool but ${indexed} in the index — the index does not describe the pool" >&2
    exit 1
  fi

  gzip -9nkf "$index"
  echo "  binary-${arch}: ${indexed} package(s)"
done

# `apt-ftparchive release` hashes every file it finds under the directory
# it is given, so the output must not be written into that directory while
# it runs. Redirecting straight to dists/stable/Release does not work: the
# shell creates the file before apt-ftparchive starts, so apt-ftparchive
# finds it and lists `Release` inside Release, with a length and checksum
# for a file that was still being written. Measured — the first build here
# emitted a self-referencing `222 Release` line. Build it outside the tree
# and move it in.
release_tmp="$(mktemp)"
trap 'rm -f "$release_tmp"' EXIT

apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=${ORIGIN}" \
  -o "APT::FTPArchive::Release::Label=${LABEL}" \
  -o "APT::FTPArchive::Release::Suite=${SUITE}" \
  -o "APT::FTPArchive::Release::Codename=${CODENAME}" \
  -o "APT::FTPArchive::Release::Components=${COMPONENT}" \
  -o "APT::FTPArchive::Release::Architectures=${ARCHES[*]}" \
  -o "APT::FTPArchive::Release::Description=mandible — universal interactive TUI reference for CLI tools" \
  release "dists/${SUITE}" > "$release_tmp"
mv "$release_tmp" "dists/${SUITE}/Release"

# The index must describe the indices and nothing else. If `Release` ever
# names itself again, the hashes in it are for a file that did not exist
# in its final form when they were taken.
if grep -qE '^ [0-9a-f]+ +[0-9]+ Release$' "dists/${SUITE}/Release"; then
  echo "Release lists itself — the index was written into the directory being indexed" >&2
  exit 1
fi

gpg --batch --yes --local-user "$key" \
  --clearsign --output "dists/${SUITE}/InRelease" "dists/${SUITE}/Release"
gpg --batch --yes --local-user "$key" \
  --armor --detach-sign --output "dists/${SUITE}/Release.gpg" "dists/${SUITE}/Release"

gpg --batch --yes --export --output mandible-archive-keyring.gpg "$key"
gpg --batch --yes --armor --export --output mandible-archive-keyring.asc "$key"

# Verify what was just written rather than assume gpg succeeded quietly.
# A signature that does not verify is indistinguishable from a good one
# until a user's `apt-get update` reports it, by which point it is
# published.
gpg --batch --verify "dists/${SUITE}/InRelease" >/dev/null 2>&1 \
  || { echo "InRelease does not verify against the imported key" >&2; exit 1; }
gpg --batch --verify "dists/${SUITE}/Release.gpg" "dists/${SUITE}/Release" >/dev/null 2>&1 \
  || { echo "Release.gpg does not verify against Release" >&2; exit 1; }

echo "signed with $(gpg --batch --with-colons --fingerprint "$key" | awk -F: '/^fpr:/{print $10; exit}')"
echo "repository built under ${site}"
