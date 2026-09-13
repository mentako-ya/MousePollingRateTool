#!/bin/bash
# ==============================================================================
# MousePollingRateTool DMG パッケージ生成スクリプト
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="MousePollingRateTool"
PROJECT_FILE="${ROOT_DIR}/${APP_NAME}.xcodeproj"
OUTPUT_DMG="${ROOT_DIR}/${APP_NAME}.dmg"
PACKAGING_DIR="${ROOT_DIR}/packaging"
SETTINGS_FILE="${PACKAGING_DIR}/dmg_settings.py"
BG_IMAGE="${PACKAGING_DIR}/dmg_background.png"

echo "=== MousePollingRateTool DMG パッケージ生成 ==="

# 1. アプリバンドルの準備
# リポジトリ直下に .app がない場合は xcodebuild でビルドする
TEMP_BUILD_DIR=""
APP_PATH="${ROOT_DIR}/${APP_NAME}.app"

cleanup() {
    if [ -n "${TEMP_BUILD_DIR}" ] && [ -d "${TEMP_BUILD_DIR}" ]; then
        echo "一時ビルドディレクトリをクリーンアップ中: ${TEMP_BUILD_DIR}"
        rm -rf "${TEMP_BUILD_DIR}"
    fi
}
trap cleanup EXIT

if [ ! -d "${APP_PATH}" ]; then
    echo "リポジトリ直下に ${APP_NAME}.app が存在しないため、xcodebuild で Release ビルドを実行します..."
    TEMP_BUILD_DIR="$(mktemp -d -t mprt_build_XXXXXX)"
    
    xcodebuild \
        -project "${PROJECT_FILE}" \
        -scheme "${APP_NAME}" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "${TEMP_BUILD_DIR}" \
        build \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        -quiet
    
    BUILT_APP="${TEMP_BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
    if [ ! -d "${BUILT_APP}" ]; then
        echo "エラー: ビルド成果物が見つかりませんでした: ${BUILT_APP}"
        exit 1
    fi
    
    echo "アドホックコード署名を適用しています..."
    codesign --force --deep --sign - "${BUILT_APP}"
    
    APP_PATH="${BUILT_APP}"
    echo "ビルド・署名完了: ${APP_PATH}"
fi

# 既存の .app が指定されている場合も念のためコード署名を確認・適用
if [ -d "${APP_PATH}" ]; then
    codesign --force --deep --sign - "${APP_PATH}" >/dev/null 2>&1 || true
fi

# 2. 背景画像の存在確認・生成
if [ ! -f "${BG_IMAGE}" ]; then
    echo "背景画像を生成しています..."
    if command -v python3 >/dev/null 2>&1; then
        python3 "${PACKAGING_DIR}/generate_background.py"
    else
        echo "警告: python3 が見つからないため背景画像生成をスキップします。"
    fi
fi

# 既存のDMGを削除
rm -f "${OUTPUT_DMG}"

# 3. dmgbuild が利用可能かチェック
HAS_DMGBUILD=false
if command -v dmgbuild >/dev/null 2>&1; then
    HAS_DMGBUILD=true
elif python3 -c "import dmgbuild" >/dev/null 2>&1; then
    HAS_DMGBUILD=true
fi

cd "${ROOT_DIR}"

if [ "${HAS_DMGBUILD}" = true ]; then
    echo "dmgbuild を使用してリッチなDMGパッケージを生成しています..."
    DMG_ARGS=(
        -D "ROOT_DIR=${ROOT_DIR}"
        -D "APP_PATH=${APP_PATH}"
        -D "BG_PATH=${BG_IMAGE}"
        -s "${SETTINGS_FILE}"
        "${APP_NAME}"
        "${OUTPUT_DMG}"
    )
    if command -v dmgbuild >/dev/null 2>&1; then
        dmgbuild "${DMG_ARGS[@]}"
    else
        python3 -m dmgbuild "${DMG_ARGS[@]}"
    fi
else
    echo "注意: dmgbuild が見つかりません。macOS 標準の hdiutil でシンプルDMGを生成します。"
    echo "(背景やアイコンレイアウトを含むリッチDMGを作成する場合は 'pip install dmgbuild' を実行してください)"
    
    STAGING_DIR="$(mktemp -d -t dmg_staging_XXXXXX)"
    
    echo "ステージングディレクトリにファイルをコピー中: ${STAGING_DIR}"
    cp -R "${APP_PATH}" "${STAGING_DIR}/"
    ln -s /Applications "${STAGING_DIR}/Applications"
    
    hdiutil create \
        -volname "${APP_NAME}" \
        -srcfolder "${STAGING_DIR}" \
        -ov \
        -format UDZO \
        -imagekey zlib-level=9 \
        "${OUTPUT_DMG}"
    
    rm -rf "${STAGING_DIR}"
fi

echo "=================================================="
echo "DMGパッケージが正常に生成されました:"
echo "  ${OUTPUT_DMG}"
ls -lh "${OUTPUT_DMG}"
echo "=================================================="
