import os

# ボリューム名
volume_name = 'MousePollingRateTool'

# フォーマット (UDZO: 圧縮読み取り専用ディスクイメージ)
format = 'UDZO'

# パス解決のための基準ディレクトリ (プロジェクトルート)
base_dir = defines.get('ROOT_DIR', os.getcwd()) if 'defines' in globals() else os.getcwd()
app_path = defines.get('APP_PATH', os.path.join(base_dir, 'MousePollingRateTool.app')) if 'defines' in globals() else os.path.join(base_dir, 'MousePollingRateTool.app')
bg_path = defines.get('BG_PATH', os.path.join(base_dir, 'packaging', 'dmg_background.png')) if 'defines' in globals() else os.path.join(base_dir, 'packaging', 'dmg_background.png')
icon_path = os.path.join(app_path, 'Contents', 'Resources', 'AppIcon.icns')

# コピー対象
files = [ app_path ]

# 作成するシンボリックリンク
symlinks = { 'Applications': '/Applications' }

# ボリュームアイコン
if os.path.exists(icon_path):
    icon = icon_path

# 背景画像
if os.path.exists(bg_path):
    background = bg_path

# ウィンドウ表示位置およびサイズ (x, y), (width, height)
window_rect = ((200, 150), (600, 400))

# 表示設定
default_view = 'icon-view'
icon_size = 120

# アイコン配置座標 (Finder座標系: x, y)
icon_locations = {
    'MousePollingRateTool.app': (160, 200),
    'Applications': (440, 200)
}
