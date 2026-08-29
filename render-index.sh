#!/usr/bin/env bash
# Render the repository's landing page to stdout.
#
#   ./render-index.sh <site-dir> <signing-key-id> > <site-dir>/index.html
#
# Anyone who opens the Pages URL in a browser lands here, so it carries the
# same setup lines as README.md plus the two things only a build knows: the
# fingerprint of the key that actually signed this publication, and which
# versions are actually in the pool. A fingerprint printed from the key in
# use cannot drift out of date the way one pasted into prose can.
set -euo pipefail

site="${1:?usage: render-index.sh <site-dir> <signing-key-id>}"
key="${2:?usage: render-index.sh <site-dir> <signing-key-id>}"

base_url="https://as-foss.github.io/mandible-apt"
fpr="$(gpg --batch --with-colons --fingerprint "$key" | awk -F: '/^fpr:/{print $10; exit}')"

versions="$(awk '/^Package: /{p=$2} /^Version: /{if (p=="mandible") print $2}' \
              "${site}/dists/stable/main/binary-amd64/Packages" \
              "${site}/dists/stable/main/binary-arm64/Packages" \
            | sort -Vru)"

cat <<HTML
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>mandible apt repository</title>
<style>
  :root { color-scheme: light dark; }
  body { max-width: 44rem; margin: 3rem auto; padding: 0 1.25rem;
         font: 16px/1.6 system-ui, -apple-system, "Segoe UI", sans-serif; }
  h1 { font-size: 1.5rem; margin-bottom: .25rem; }
  p.sub { margin-top: 0; opacity: .7; }
  pre { padding: .9rem 1rem; overflow-x: auto; border-radius: 6px;
        background: rgba(127,127,127,.14); }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; }
  footer { margin-top: 3rem; font-size: .875rem; opacity: .7; }
</style>

<h1>mandible apt repository</h1>
<p class="sub">Debian and Ubuntu packages for
  <a href="https://github.com/AS-FOSS/mandible">mandible</a>, on amd64 and arm64.</p>

<h2>Install</h2>
<p>Fetch the signing key:</p>
<pre><code>sudo curl -fsSL ${base_url}/mandible-archive-keyring.gpg \\
  -o /usr/share/keyrings/mandible-archive-keyring.gpg</code></pre>

<p>Add the repository:</p>
<pre><code>sudo tee /etc/apt/sources.list.d/mandible.sources &gt;/dev/null &lt;&lt;'EOF'
Types: deb
URIs: ${base_url}
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: /usr/share/keyrings/mandible-archive-keyring.gpg
EOF</code></pre>

<p>Then:</p>
<pre><code>sudo apt-get update
sudo apt-get install mandible</code></pre>

<h2>Signing key</h2>
<p>Every <code>Release</code> here is clear-signed (<code>InRelease</code>) and
detached-signed (<code>Release.gpg</code>) by:</p>
<pre><code>${fpr}</code></pre>
<p>Also available <a href="mandible-archive-keyring.asc">armored</a>.</p>

<h2>Versions currently indexed</h2>
<pre><code>$(printf '%s\n' "$versions")</code></pre>

<footer>
  Rebuilt from the release assets of
  <a href="https://github.com/AS-FOSS/mandible/releases">AS-FOSS/mandible</a>
  on every release. Source for this repository:
  <a href="https://github.com/AS-FOSS/mandible-apt">AS-FOSS/mandible-apt</a>.
</footer>
HTML
