# mandible-apt

The apt repository for [mandible](https://github.com/AS-FOSS/mandible), served
from GitHub Pages at <https://as-foss.github.io/mandible-apt>.

Packages are built by mandible's own release workflow and attached to its
GitHub releases; this repository indexes and signs them. It holds no packages
of its own.

## Install mandible from this repository

Fetch the signing key:

```console
sudo curl -fsSL https://as-foss.github.io/mandible-apt/mandible-archive-keyring.gpg \
  -o /usr/share/keyrings/mandible-archive-keyring.gpg
```

Add the repository:

```console
sudo tee /etc/apt/sources.list.d/mandible.sources >/dev/null <<'EOF'
Types: deb
URIs: https://as-foss.github.io/mandible-apt
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: /usr/share/keyrings/mandible-archive-keyring.gpg
EOF
```

Then install:

```console
sudo apt-get update
sudo apt-get install mandible
```

`Signed-By` names the keyring for this repository alone, so the key can only
vouch for packages served from here — unlike `apt-key add`, which was deprecated
precisely because it made every added key trusted for every repository. The
armored form of the key is published beside it as
`mandible-archive-keyring.asc`.

The one-file `deb822` format above needs apt 2.4 or newer (Debian 12, Ubuntu
22.04 and later). On something older, the equivalent one-liner is:

```console
echo "deb [signed-by=/usr/share/keyrings/mandible-archive-keyring.gpg] https://as-foss.github.io/mandible-apt stable main" \
  | sudo tee /etc/apt/sources.list.d/mandible.list
```

## Layout

```
/pool/main/m/mandible/mandible_<version>-1_<arch>.deb
/dists/stable/main/binary-amd64/Packages{,.gz}
/dists/stable/main/binary-arm64/Packages{,.gz}
/dists/stable/Release          index of the indices; the file the signatures cover
/dists/stable/InRelease        clear-signed Release, what modern apt fetches
/dists/stable/Release.gpg      detached signature over Release, for older clients
/mandible-archive-keyring.gpg  public signing key, dearmored
/mandible-archive-keyring.asc  public signing key, armored
```

One suite (`stable`) carries both architectures, so the sources entry above is
the same on either and apt picks the right index.

## How it is published

`.github/workflows/publish.yml` runs on `workflow_dispatch` (naming a tag) or on
a `repository_dispatch` of type `release` sent by mandible's release workflow. It
downloads the `.deb` assets from the most recent releases of `AS-FOSS/mandible`,
builds and signs the indices with `build-repo.sh`, and deploys the result to
GitHub Pages.

The build is stateless: the whole repository is regenerated from the upstream
release assets on every run, and nothing is committed here between runs. The
releases are already the source of truth for what a version of mandible is, so a
second copy in git would be a second thing that can be wrong — and a rebuild
that owns no state is idempotent, which makes "run it again" the fix for any bad
publication.

`build-repo.sh` and `render-index.sh` are ordinary scripts and run outside CI:

```console
./build-repo.sh site <signing-key-id>       # site/pool/... must already hold the .deb files
./render-index.sh site <signing-key-id> > site/index.html
```

## Publishing a release by hand

Normally mandible's release workflow dispatches this one. To run it yourself:

```console
gh workflow run publish.yml -R AS-FOSS/mandible-apt -f tag=v0.4.5
```

The repository needs one secret, `APT_SIGNING_KEY`: the armored private half of
the archive signing key, without a passphrase. The workflow fails rather than
skips when it is absent — an unsigned apt repository either refuses to work for
everyone or teaches people to bypass verification, and publishing nothing is
better than either.
