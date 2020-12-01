#! /usr/bin/env nix-shell
#! nix-shell -i bash images.nix -A shell

set -e

BASEDIR=$(dirname "$0")
cd "$BASEDIR"

nix-build $BASEDIR/images.nix -A site

test -d dist && rm -rf dist
cp -rvL result dist
chmod +rw -R dist

if [[ -n "$NETLIFY_SITE_ID" ]] && [[ -n "$NETLIFY_AUTH_TOKEN" ]]; then
	netlify deploy --dir=dist --prod
fi
