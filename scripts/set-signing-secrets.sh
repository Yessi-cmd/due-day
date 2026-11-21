#!/usr/bin/env bash
# Uploads the signing material in a certificate folder to GitHub Actions secrets.
#
#   scripts/set-signing-secrets.sh <cert-dir> [owner/repo]
#
# <cert-dir> must contain one *.p12 and one *.mobileprovision. The p12 password is
# taken from $P12_PASSWORD, or else from 密码.txt in that folder ("密码：xxx").
#
# The p12 is re-encoded with 3DES/SHA1 (which macOS `security import` always accepts)
# under a fresh random password, so the original password never reaches CI.
# Nothing secret is printed; the decrypted key only lives in a temp dir removed on exit.
set -euo pipefail

DIR=${1:?usage: $0 <cert-dir> [owner/repo]}
REPO=${2:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}

shopt -s nullglob
p12s=("$DIR"/*.p12)
profiles=("$DIR"/*.mobileprovision)
[ ${#p12s[@]} -eq 1 ] || { echo "expected exactly one .p12 in $DIR" >&2; exit 1; }
[ ${#profiles[@]} -eq 1 ] || { echo "expected exactly one .mobileprovision in $DIR" >&2; exit 1; }
P12=${p12s[0]}
PROFILE=${profiles[0]}

if [ -z "${P12_PASSWORD:-}" ]; then
  [ -f "$DIR/密码.txt" ] || { echo "set P12_PASSWORD or provide 密码.txt" >&2; exit 1; }
  # Separate expressions: a bracket like [：:] would split the multibyte colon into bytes.
  P12_PASSWORD=$(sed -e 's/^密码：//' -e 's/^密码://' -e 's/^[[:space:]]*//' "$DIR/密码.txt" | tr -d '\r\n')
fi
export P12_PASSWORD
export NEW_PASSWORD=$(openssl rand -hex 24)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

openssl pkcs12 -in "$P12" -passin env:P12_PASSWORD -nokeys -out "$WORK/cert.pem"
openssl pkcs12 -in "$P12" -passin env:P12_PASSWORD -nocerts -nodes -out "$WORK/key.pem"
openssl pkcs12 -export -in "$WORK/cert.pem" -inkey "$WORK/key.pem" \
  -passout env:NEW_PASSWORD \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -out "$WORK/legacy.p12"
openssl pkcs12 -in "$WORK/legacy.p12" -passin env:NEW_PASSWORD -info -noout 2>&1 | grep -E 'MAC|Keybag|Encrypted'

echo "Certificate:"
openssl x509 -in "$WORK/cert.pem" -noout -subject -enddate | sed 's/^/  /'

# Profile metadata, so a cert swap can be checked against project.yml / ExportOptions.plist.
PROFILE_XML=$(tr -d '\000' < "$PROFILE" | sed -n '/<?xml/,/<\/plist>/p')
plist_value() { printf '%s\n' "$PROFILE_XML" | grep -A1 "<key>$1</key>" | sed -n 's/.*<\(string\|date\)>\(.*\)<\/\(string\|date\)>.*/\2/p' | head -1; }
PROFILE_NAME=$(plist_value Name)
echo "Profile:"
echo "  Name:     $PROFILE_NAME"
echo "  UUID:     $(plist_value UUID)"
echo "  App ID:   $(plist_value application-identifier)"
echo "  Expires:  $(plist_value ExpirationDate)"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if ! grep -q "$PROFILE_NAME" "$ROOT/project.yml" "$ROOT/ExportOptions.plist"; then
  echo "WARNING: profile name not found in project.yml / ExportOptions.plist — update them (AGENTS.md §2)." >&2
fi

echo "Uploading secrets to $REPO ..."
base64 < "$WORK/legacy.p12" | tr -d '\n' | gh secret set P12_BASE64 -R "$REPO"
printf '%s' "$NEW_PASSWORD" | gh secret set P12_PASSWORD -R "$REPO"
base64 < "$PROFILE" | tr -d '\n' | gh secret set PROVISION_PROFILE_BASE64 -R "$REPO"
printf '%s' "$(openssl rand -hex 24)" | gh secret set KEYCHAIN_PASSWORD -R "$REPO"
gh secret list -R "$REPO"
