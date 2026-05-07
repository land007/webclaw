#!/usr/bin/env python3
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib, Pango
import os
import subprocess
import glob
import json
from pathlib import Path

class App:
    def __init__(self, name, exec_cmd, icon, category, file_path):
        self.name = name
        self.exec_cmd = exec_cmd
        self.icon = icon
        self.category = category
        self.file_path = file_path

class LaunchpadWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="应用启动台")
        self.set_default_size(1200, 800)
        self.fullscreen()
        
        # 加载配置
        self.config_dir = Path.home() / '.config' / 'launchpad'
        self.favorites_file = self.config_dir / 'favorites.json'
        self.favorites = self.load_favorites()
        
        # 加载应用
        self.all_apps = self.load_applications()
        self.categorized_apps = self.categorize_apps(self.all_apps)
        self.current_category = '全部'
        
        # 构建 UI
        self.setup_ui()
        
        # ESC 键关闭
        self.connect('key-press-event', self.on_key_press)
    
    def setup_ui(self):
        # 主容器
        main_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self.add(main_box)
        
        # 左侧分类栏
        self.sidebar = self.create_sidebar()
        main_box.pack_start(self.sidebar, False, False, 0)
        
        # 右侧内容区
        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        main_box.pack_start(content_box, True, True, 0)
        
        # 搜索框
        self.search_box = Gtk.Entry()
        self.search_box.set_placeholder_text("🔍 搜索应用...")
        self.search_box.set_margin_start(20)
        self.search_box.set_margin_end(20)
        self.search_box.set_margin_top(20)
        self.search_box.set_margin_bottom(10)
        self.search_box.connect('changed', self.on_search_changed)
        content_box.pack_start(self.search_box, False, False, 0)
        
        # 应用网格
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content_box.pack_start(scroll, True, True, 0)
        
        self.grid = Gtk.Grid()
        self.grid.set_column_spacing(20)
        self.grid.set_row_spacing(20)
        self.grid.set_margin_start(30)
        self.grid.set_margin_end(30)
        self.grid.set_margin_top(20)
        self.grid.set_margin_bottom(20)
        scroll.add(self.grid)
        
        # 显示应用
        self.display_apps(self.all_apps)
    
    def create_sidebar(self):
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        sidebar.set_margin_start(20)
        sidebar.set_margin_top(20)
        sidebar.set_margin_bottom(20)
        sidebar.set_valign(Gtk.Align.START)
        
        categories = ['全部', '收藏', '开发', '办公', '网络', '图形', '音频', '视频', '系统', '其他']
        
        self.category_buttons = {}
        for cat in categories:
            btn = Gtk.Button(label=cat)
            icon = self.get_category_icon(cat)
            if icon:
                label = btn.get_child()
                if isinstance(label, Gtk.Label):
                    label.set_text(f'{icon} {cat}')
            
            btn.connect('clicked', lambda b, c=cat: self.on_category_click(c))
            sidebar.pack_start(btn, False, False, 0)
            self.category_buttons[cat] = btn
        
        # 默认选中"全部"
        self.category_buttons['全部'].get_style_context().add_class('suggested-action')
        
        return sidebar
    
    def get_category_icon(self, category):
        icons = {
            '全部': '📱',
            '收藏': '⭐',
            '开发': '💻',
            '办公': '📄',
            '网络': '🌐',
            '图形': '🎨',
            '音频': '🎵',
            '视频': '🎬',
            '系统': '⚙️',
            '其他': '📦'
        }
        return icons.get(category, '')
    
    def on_category_click(self, category):
        # 更新按钮状态
        for cat, btn in self.category_buttons.items():
            if cat == category:
                btn.get_style_context().add_class('suggested-action')
            else:
                btn.get_style_context().remove_class('suggested-action')
        
        self.current_category = category
        
        if category == '全部':
            apps = self.all_apps
        elif category == '收藏':
            apps = [app for app in self.all_apps if app.name in self.favorites]
        else:
            apps = self.categorized_apps.get(category, [])
        
        # 应用搜索过滤
        search_text = self.search_box.get_text().lower()
        if search_text:
            apps = [app for app in apps if search_text in app.name.lower()]
        
        self.display_apps(apps)
    
    def load_applications(self):
        apps = []
        desktop_dirs = [
            '/usr/share/applications',
            '/usr/local/share/applications',
        ]
        
        seen = set()
        for ddir in desktop_dirs:
            if not os.path.exists(ddir):
                continue
            for dfile in glob.glob(os.path.join(ddir, '*.desktop')):
                if dfile in seen:
                    continue
                seen.add(dfile)
                
                app = self.parse_desktop_file(dfile)
                if app and app.name:
                    apps.append(app)
        
        apps.sort(key=lambda x: x.name.lower())
        return apps[:100]
    
    def parse_desktop_file(self, filepath):
        try:
            name = None
            exec_cmd = None
            icon = None
            categories = []
            
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('Name='):
                        name = line.split('=', 1)[1]
                    elif line.startswith('Name[zh_CN]='):
                        name = line.split('=', 1)[1]
                    elif line.startswith('Exec='):
                        cmd = line.split('=', 1)[1]
                        for token in ['%f', '%F', '%u', '%U', '%d', '%D', '%n', '%N', '%k', '%v', '%c']:
                            cmd = cmd.replace(token, '')
                        exec_cmd = cmd.strip().split()[0]
                    elif line.startswith('Icon='):
                        icon = line.split('=', 1)[1]
                    elif line.startswith('Categories='):
                        categories = line.split('=', 1)[1].split(';')
                    elif line.startswith('NoDisplay=true'):
                        return None
            
            if not name or not exec_cmd:
                return None
            
            if not icon:
                icon = 'application-x-executable'
            
            category = self.map_category(categories)
            return App(name, exec_cmd, icon, category, filepath)
        except:
            return None
    
    def map_category(self, categories):
        cat_map = {
            'Development': '开发',
            'Office': '办公',
            'Network': '网络',
            'Graphics': '图形',
            'Audio': '音频',
            'Video': '视频',
            'System': '系统',
            'Utility': '系统',
            'Settings': '系统',
            'Game': '其他',
            'Education': '其他'
        }
        
        for cat in categories:
            if cat in cat_map:
                return cat_map[cat]
        
        return '其他'
    
    def categorize_apps(self, apps):
        categorized = {}
        for app in apps:
            if app.category not in categorized:
                categorized[app.category] = []
            categorized[app.category].append(app)
        return categorized
    
    def display_apps(self, apps):
        for child in self.grid.get_children():
            self.grid.remove(child)
        
        if not apps:
            label = Gtk.Label()
            label.set_markup('<span size="large">😕 没有找到应用</span>')
            self.grid.attach(label, 0, 0, 1, 1)
            self.grid.show_all()
            return
        
        cols = 8
        for i, app in enumerate(apps):
            row = i // cols
            col = i % cols
            
            card = self.create_app_card(app)
            self.grid.attach(card, col, row, 1, 1)
        
        self.grid.show_all()
    
    def create_app_card(self, app):
        event_box = Gtk.EventBox()
        event_box.connect('button-press-event', lambda w, e: self.on_app_card_click(app, e))
        
        # 卡片容器
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        card.set_margin_start(12)
        card.set_margin_end(12)
        card.set_margin_top(12)
        card.set_margin_bottom(12)
        
        # 图标
        icon = Gtk.Image()
        icon.set_pixel_size(80)
        
        if os.path.exists(app.icon):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(app.icon, 80, 80)
                icon.set_from_pixbuf(pixbuf)
            except:
                icon.set_from_icon_name(app.icon, Gtk.IconSize.DIALOG)
        else:
            icon.set_from_icon_name(app.icon, Gtk.IconSize.DIALOG)
        
        # 名称
        label = Gtk.Label(label=app.name)
        label.set_max_width_chars(12)
        label.set_ellipsize(Pango.EllipsizeMode.END)
        label.set_alignment(0.5, 0.5)
        
        card.pack_start(icon, False, False, 0)
        card.pack_start(label, False, False, 0)
        event_box.add(card)
        
        return event_box
    
    def on_app_card_click(self, app, event):
        if event.button == 1:
            self.launch_app(app)
        elif event.button == 3:
            self.show_context_menu(app, event)
    
    def launch_app(self, app):
        try:
            subprocess.Popen(app.exec_cmd, shell=True,
                           start_new_session=True,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"Failed to launch {app.name}: {e}")
        self.close()
    
    def show_context_menu(self, app, event):
        menu = Gtk.Menu()
        
        is_favorite = app.name in self.favorites
        favorite_item = Gtk.MenuItem("⭐ 取消收藏" if is_favorite else "⭐ 添加到收藏")
        favorite_item.connect('activate', lambda: self.toggle_favorite(app))
        menu.append(favorite_item)
        
        info_item = Gtk.MenuItem(f"ℹ️ {app.category}")
        info_item.set_sensitive(False)
        menu.append(info_item)
        
        menu.show_all()
        menu.popup_at_pointer(event)
    
    def toggle_favorite(self, app):
        if app.name in self.favorites:
            self.favorites.remove(app.name)
        else:
            self.favorites.append(app.name)
        self.save_favorites()
        
        if self.current_category == '收藏':
            self.on_category_click('收藏')
    
    def load_favorites(self):
        try:
            if self.favorites_file.exists():
                with open(self.favorites_file, 'r') as f:
                    return json.load(f)
        except:
            pass
        return []
    
    def save_favorites(self):
        try:
            self.favorites_file.parent.mkdir(parents=True, exist_ok=True)
            with open(self.favorites_file, 'w') as f:
                json.dump(self.favorites, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"Failed to save favorites: {e}")
    
    def on_search_changed(self, entry):
        query = entry.get_text().lower()
        
        if self.current_category == '全部':
            apps = self.all_apps
        elif self.current_category == '收藏':
            apps = [app for app in self.all_apps if app.name in self.favorites]
        else:
            apps = self.categorized_apps.get(self.current_category, [])
        
        if query:
            apps = [app for app in apps if query in app.name.lower()]
        
        self.display_apps(apps)
    
    def on_key_press(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()

def main():
    win = LaunchpadWindow()
    win.connect('destroy', Gtk.main_quit)
    win.show_all()
    Gtk.main()

if __name__ == '__main__':
    main()
