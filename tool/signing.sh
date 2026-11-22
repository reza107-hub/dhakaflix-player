# Source this to sign Android release builds locally:  . tool/signing.sh
# Reads the keystore and passwords from outside the repository.
# Location can be overridden with DFP_SIGNING_DIR.
dir="${DFP_SIGNING_DIR:-$HOME/.dhakaflix-signing}"
if [ ! -f "$dir/signing.env" ]; then
  echo "No signing setup at $dir (see README: Release signing)." >&2
  return 1 2>/dev/null || exit 1
fi
# shellcheck disable=SC1091
. "$dir/signing.env"
export DFP_KEYSTORE="$dir/release.jks" DFP_KEY_ALIAS DFP_KEYSTORE_PASSWORD DFP_KEY_PASSWORD
