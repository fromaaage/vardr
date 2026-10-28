#!/bin/sh
# Install the root helper and polkit rule when running varðr from source.
# Not needed when installed with the PKGBUILD. Run: sudo packaging/polkit/install.sh
set -e
dir=$(dirname "$0")
install -Dm755 "$dir/vardr-root" /usr/lib/vardr/vardr-root
install -Dm755 "$dir/vardr-sudo" /usr/lib/vardr/vardr-sudo
install -Dm644 "$dir/org.vardr.policy" /usr/share/polkit-1/actions/org.vardr.policy
echo "varðr helper installed."
