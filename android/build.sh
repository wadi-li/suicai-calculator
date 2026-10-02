#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "${JAVA_HOME:-}" ]]; then export PATH="$JAVA_HOME/bin:$PATH"; fi
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${ANDROID_SDK:-}}}"
[[ -n "$SDK" ]] || { echo "Укажите ANDROID_SDK_ROOT." >&2; exit 1; }
BT="$SDK/build-tools/34.0.0"
JAR="$SDK/platforms/android-34/android.jar"
for tool in aapt2 d8 zipalign apksigner; do
  [[ -x "$BT/$tool" ]] || { echo "Не найден $BT/$tool" >&2; exit 1; }
done
[[ -f "$JAR" ]] || { echo "Не найдена Android SDK Platform 34." >&2; exit 1; }
command -v javac >/dev/null
command -v zip >/dev/null

rm -rf build
mkdir -p build/res build/classes build/dex
"$BT/aapt2" compile --dir res -o build/res/res.zip
"$BT/aapt2" link -o build/base.apk -I "$JAR" --manifest AndroidManifest.xml \
  -A assets --java build/gen build/res/res.zip --min-sdk-version 24 --target-sdk-version 34
mapfile -d '' sources < <(find src build/gen -name '*.java' -print0)
javac -source 8 -target 8 -encoding UTF-8 -classpath "$JAR" -d build/classes "${sources[@]}"
mapfile -d '' classes < <(find build/classes -name '*.class' -print0)
"$BT/d8" --release --min-api 24 --lib "$JAR" --output build/dex "${classes[@]}"
cp build/base.apk build/unsigned.apk
(cd build/dex && zip -q -j ../unsigned.apk classes.dex)
"$BT/zipalign" -f -p 4 build/unsigned.apk suicai-unsigned.apk

if [[ -z "${SUICAI_KEYSTORE:-}" ]]; then
  echo "Готово: android/suicai-unsigned.apk (нужна подпись перед установкой)."
  exit 0
fi
[[ -f "$SUICAI_KEYSTORE" ]] || { echo "Файл ключа подписи не найден." >&2; exit 1; }
: "${SUICAI_KEY_ALIAS:?Укажите SUICAI_KEY_ALIAS}"
: "${SUICAI_STORE_PASSWORD:?Укажите SUICAI_STORE_PASSWORD}"
: "${SUICAI_KEY_PASSWORD:?Укажите SUICAI_KEY_PASSWORD}"
export SUICAI_STORE_PASSWORD SUICAI_KEY_PASSWORD
"$BT/apksigner" sign --ks "$SUICAI_KEYSTORE" \
  --ks-pass env:SUICAI_STORE_PASSWORD --key-pass env:SUICAI_KEY_PASSWORD \
  --ks-key-alias "$SUICAI_KEY_ALIAS" --out suicai.apk suicai-unsigned.apk
"$BT/apksigner" verify --print-certs suicai.apk
echo "Готово: android/suicai.apk"
