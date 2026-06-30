#!/usr/bin/env python3
import os
import sys
import shutil
import unicodedata
from pathlib import Path

# macOSのダブルクリック起動時はカレントディレクトリがホームディレクトリになるため、
# スクリプトが置かれているフォルダへカレントディレクトリを変更します。
os.chdir(Path(__file__).resolve().parent)

def get_normalized_name(path: Path) -> str:
    return unicodedata.normalize('NFC', path.name)

def get_stem_and_suffix(path: Path):
    normalized_name = get_normalized_name(path)
    if '.' in normalized_name:
        parts = normalized_name.rsplit('.', 1)
        return parts[0], parts[1]
    else:
        return normalized_name, ""

def select_target_directory() -> Path:
    # GUIでのフォルダ選択ダイアログの表示を試みる
    try:
        import tkinter as tk
        from tkinter import filedialog
        
        root = tk.Tk()
        root.withdraw()  # メインウィンドウは非表示にする
        
        # ダイアログを最前面に表示するための設定
        root.lift()
        root.attributes("-topmost", True)
        
        print("フォルダ選択画面を表示しています...")
        folder_selected = filedialog.askdirectory(title="仕分け対象のフォルダを選択してください")
        root.destroy()
        
        if folder_selected:
            return Path(folder_selected).resolve()
            
    except Exception as e:
        # GUIが利用できない環境（ライブラリ不足など）の場合のフォールバック
        pass
        
    # テキスト入力・ドラッグ＆ドロップでのフォールバック
    print("\n------------------------------------------------------------")
    print("仕分け対象のフォルダパスを入力してください。")
    print("（対象のフォルダをこの画面にドラッグ＆ドロップしてもパスを入力できます）")
    print("※何も入力せずにEnterキーを押すと、このスクリプトと同じフォルダを処理します。")
    print("------------------------------------------------------------")
    user_input = input("対象フォルダパス: ").strip()
    
    if not user_input:
        return Path(__file__).resolve().parent
        
    # ドラッグ＆ドロップされた際に付くクォーテーションや、Mac等のスペース用のエスケープ（\ ）をクリーニング
    clean_path = user_input.replace('\\ ', ' ').strip('\'"')
    return Path(clean_path).resolve()

def main():
    # コマンドライン引数で直接指定されている場合はそれを使用
    if len(sys.argv) > 1:
        target_dir = Path(sys.argv[1]).resolve()
    else:
        # ダブルクリック起動などの場合はフォルダ選択関数を呼ぶ
        target_dir = select_target_directory()

    print(f"\n対象フォルダ: {target_dir}")
    if not target_dir.exists():
        print(f"エラー: フォルダ {target_dir} が存在しません。")
        input("\nEnterキーを押して終了します...")
        os._exit(1)

    # 自身を移動しないようにパスを特定
    script_path = Path(__file__).resolve()

    # フォルダのプレフィックス名（最上位のプロジェクト名）を動的に判定
    def get_project_name(t_dir: Path) -> str:
        try:
            home = Path.home().resolve()
            system_markers = {"Desktop", "Documents", "Downloads", "Desktop-Local", "Desktop - Local"}
            t_dir_res = t_dir.resolve()
            if t_dir_res.is_relative_to(home):
                relative_parts = t_dir_res.relative_to(home).parts
                if relative_parts:
                    if relative_parts[0] in system_markers and len(relative_parts) > 1:
                        return relative_parts[1]
                    return relative_parts[0]
        except Exception:
            pass
        return t_dir.name

    prefix = get_project_name(target_dir)
    print(f"プロジェクト名として「{prefix}」を使用します。")

    items = sorted(list(target_dir.iterdir()))
    
    # 1. ファイルの仕分け
    moves = []
    for item in items:
        # ディレクトリや隠しファイルは無視
        if item.is_dir() or item.name.startswith('.'):
            continue
        # スクリプト自身は除外
        try:
            if item.samefile(script_path):
                continue
        except OSError:
            pass
            
        stem, ext = get_stem_and_suffix(item)
        
        # サンプル判定
        if stem.startswith("サンプル"):
            dest_dir = target_dir / f"{prefix}_サンプル"
        else:
            ext_dir_name = ext.lower() if ext else "no_ext"
            if "SEあり" in stem:
                dest_dir = target_dir / f"{prefix}_音声データ" / ext_dir_name / "SEあり"
            else:
                dest_dir = target_dir / f"{prefix}_音声データ" / ext_dir_name / "SEなし"
                
        dest_path = dest_dir / item.name
        moves.append((item, dest_path))

    if moves:
        print("\n--- ファイルの仕分けを開始します ---")
        for src, dest in moves:
            dest.parent.mkdir(parents=True, exist_ok=True)
            print(f"移動中: {src.name} -> {dest.relative_to(target_dir)}")
            shutil.move(str(src), str(dest))
        print("仕分けが完了しました。")
    else:
        print("\n仕分け対象のファイルが見つかりませんでした。")

    # 2. ファイル名の「SEあり」「SEなし」文字削除
    # 対象フォルダ配下のすべての「SEあり」および「SEなし」フォルダを探索
    target_subdirs = []
    for root, dirs, files in os.walk(target_dir):
        for d in dirs:
            if d in ("SEあり", "SEなし"):
                target_subdirs.append(Path(root) / d)

    renames = []
    for sub_dir in target_subdirs:
        keyword = sub_dir.name  # "SEあり" または "SEなし"
        for item in sorted(list(sub_dir.iterdir())):
            if item.is_dir() or item.name.startswith('.'):
                continue
            try:
                if item.samefile(script_path):
                    continue
            except OSError:
                pass
                
            stem, ext = get_stem_and_suffix(item)
            new_stem = stem
            
            # キーワード（「SEあり」または「SEなし」）を除去。前後のアンダースコアやハイフンも一緒に除去する。
            if keyword in new_stem:
                if new_stem.startswith(f"{keyword}_"):
                    new_stem = new_stem.replace(f"{keyword}_", "", 1)
                elif new_stem.endswith(f"_{keyword}"):
                    new_stem = new_stem[:-len(f"_{keyword}")]
                elif new_stem.startswith(f"{keyword}-"):
                    new_stem = new_stem.replace(f"{keyword}-", "", 1)
                elif new_stem.endswith(f"-{keyword}"):
                    new_stem = new_stem[:-len(f"-{keyword}")]
                else:
                    new_stem = new_stem.replace(keyword, "")
                
                # 完全に空になってしまった場合は元に戻す
                if not new_stem.strip():
                    new_stem = stem
                
            if new_stem != stem:
                new_name = new_stem + (f".{ext}" if ext else "")
                new_path = item.parent / new_name
                renames.append((item, new_path))

    if renames:
        print("\n--- ファイル名からの表記削除を開始します ---")
        for src, dest in renames:
            print(f"リネーム中: {src.relative_to(target_dir)} -> {dest.name}")
            shutil.move(str(src), str(dest))
        print("リネームが完了しました。")
    else:
        print("\nリネーム対象のファイル（SEあり/なし表記あり）が見つかりませんでした。")

    print("\nすべての処理が終了しました。")
    os._exit(0)

if __name__ == "__main__":
    main()
