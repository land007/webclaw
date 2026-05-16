#!/usr/bin/env python3
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib, Pango

import glob
import json
import os
import re
import subprocess


class App:
    def __init__(self, app_id, name, exec_cmd, icon, file_path, installed=True):
        self.app_id = app_id
        self.name = name
        self.exec_cmd = exec_cmd
        self.icon = icon
        self.file_path = file_path
        self.installed = installed


class LaunchpadWindow(Gtk.Window):
    ICON_SIZE = 96
    CELL_WIDTH = 150
    CELL_HEIGHT = 154
    MIN_SWIPE = 55

    def __init__(self):
        super().__init__(title="应用启动台")
        self.set_decorated(False)
        self.fullscreen()
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_app_paintable(True)

        self.installed_packages = self.load_installed_packages()
        self.all_apps = self.load_applications()
        self.filtered_apps = self.all_apps
        self.pages = []
        self.current_page = 0
        self.cols = 7
        self.rows = 5
        self.apply_layout_for_size(
            Gdk.Screen.get_default().get_width(),
            Gdk.Screen.get_default().get_height(),
        )
        self.drag_start_x = None
        self.drag_start_y = None
        self.drag_dx = 0
        self.dragging = False
        self.active_app = None
        self.page_width = 1
        self.page_animation_id = None
        self.page_animation_start = 0
        self.page_animation_target = 0
        self.page_animation_step = 0
        self.animating_close = False
        self.background_pixbuf = self.capture_blurred_desktop()
        self.cached_background = None
        self.cached_bg_size = (0, 0)

        self.connect('key-press-event', self.on_key_press)
        self.connect('button-press-event', self.on_background_press)
        self.connect('scroll-event', self.on_scroll)
        self.connect('size-allocate', self.on_size_allocate)

        self.setup_ui()
        self.main.set_opacity(1.0)
        self.search_wrap.set_opacity(1.0)
        self.dot_box.set_opacity(1.0)
        self.show_all()

    def locale_candidates(self):
        candidates = []

        def add(raw):
            before = len(candidates)
            if not raw:
                return False
            locale_name = raw.split('.', 1)[0].split('@', 1)[0].replace('-', '_')
            if not locale_name or locale_name in {'C', 'POSIX'}:
                return False
            if locale_name not in candidates:
                candidates.append(locale_name)
            language = locale_name.split('_', 1)[0]
            if language and language not in candidates:
                candidates.append(language)
            return len(candidates) > before

        found_env_locale = False
        for raw in os.environ.get('LANGUAGE', '').split(':'):
            found_env_locale = add(raw) or found_env_locale
        for key in ('LC_MESSAGES', 'LC_ALL', 'LANG'):
            found_env_locale = add(os.environ.get(key)) or found_env_locale

        if not found_env_locale:
            try:
                with open('/home/ubuntu/.config/gnome-language', 'r', encoding='utf-8') as fh:
                    add(fh.read().strip())
            except Exception:
                pass
        return candidates

    def localized_desktop_value(self, data, key):
        for locale_name in self.locale_candidates():
            value = data.get(f'{key}[{locale_name}]')
            if value:
                return value
        return data.get(key)

    def setup_ui(self):
        css = b"""
        window, #launchpad-root {
            background: rgb(12, 14, 18);
        }
        #search-entry {
            color: rgba(255,255,255,0.92);
            background: rgba(255,255,255,0.13);
            border: 1px solid rgba(255,255,255,0.23);
            border-radius: 5px;
            min-height: 26px;
            padding: 0 14px;
            box-shadow: none;
        }
        #search-entry:focus {
            border-color: rgba(255,255,255,0.36);
            background: rgba(255,255,255,0.18);
        }
        #app-tile {
            background: transparent;
            border: 0;
            border-radius: 12px;
        }
        #app-tile:hover {
            background: rgba(255,255,255,0.10);
        }
        #app-label {
            color: white;
            text-shadow: 0 1px 3px rgba(0,0,0,0.85);
            font-size: 11pt;
        }
        #empty-label {
            color: rgba(255,255,255,0.80);
            font-size: 16pt;
            text-shadow: 0 1px 3px rgba(0,0,0,0.85);
        }
        #page-dot {
            color: rgba(255,255,255,0.35);
            font-size: 22px;
        }
        #page-dot-active {
            color: rgba(255,255,255,0.95);
            font-size: 22px;
        }
        #download-badge {
            color: white;
            background: rgba(0, 122, 255, 0.95);
            border-radius: 12px;
            min-width: 24px;
            min-height: 24px;
            font-size: 13pt;
            font-weight: bold;
            padding: 0;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        self.root = Gtk.EventBox()
        self.root.set_name('launchpad-root')
        self.root.add_events(
            Gdk.EventMask.BUTTON_PRESS_MASK |
            Gdk.EventMask.BUTTON_RELEASE_MASK |
            Gdk.EventMask.POINTER_MOTION_MASK |
            Gdk.EventMask.SCROLL_MASK |
            Gdk.EventMask.SMOOTH_SCROLL_MASK
        )
        self.root.connect('button-press-event', self.on_background_press)
        self.root.connect('motion-notify-event', self.on_motion)
        self.root.connect('button-release-event', self.on_background_release)
        self.root.connect('scroll-event', self.on_scroll)
        self.add(self.root)

        overlay = Gtk.Overlay()
        self.root.add(overlay)

        background = Gtk.DrawingArea()
        background.connect('draw', self.draw_background)
        overlay.add(background)

        self.main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.main.set_opacity(0.0)
        main = self.main
        main.set_hexpand(True)
        main.set_vexpand(True)
        main.set_halign(Gtk.Align.FILL)
        main.set_valign(Gtk.Align.FILL)
        overlay.add_overlay(main)

        self.page_clip = Gtk.ScrolledWindow()
        self.page_clip.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.NEVER)
        self.page_clip.set_shadow_type(Gtk.ShadowType.NONE)
        self.page_clip.set_overlay_scrolling(False)
        self.page_clip.set_hexpand(True)
        self.page_clip.set_vexpand(True)
        self.page_clip.set_halign(Gtk.Align.FILL)
        self.page_clip.set_valign(Gtk.Align.FILL)
        self.page_clip.set_margin_top(44)
        self.page_clip.set_margin_bottom(48)

        self.page_viewport = Gtk.Fixed()
        self.page_viewport.set_hexpand(True)
        self.page_viewport.set_vexpand(True)
        self.page_clip.add(self.page_viewport)
        main.pack_start(self.page_clip, True, True, 0)

        self.search_wrap = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.search_wrap.set_opacity(0.0)
        self.search_wrap.set_halign(Gtk.Align.CENTER)
        self.search_wrap.set_valign(Gtk.Align.START)
        self.search_wrap.set_margin_top(16)
        overlay.add_overlay(self.search_wrap)

        self.search_entry = Gtk.Entry()
        self.search_entry.set_name('search-entry')
        self.search_entry.set_placeholder_text('搜索')
        self.search_entry.set_width_chars(28)
        self.search_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, 'edit-find-symbolic')
        self.search_entry.connect('changed', self.on_search_changed)
        self.search_entry.connect('button-press-event', self.stop_event)
        self.search_wrap.pack_start(self.search_entry, False, False, 0)

        self.dot_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.dot_box.set_opacity(0.0)
        self.dot_box.set_halign(Gtk.Align.CENTER)
        self.dot_box.set_valign(Gtk.Align.END)
        self.dot_box.set_margin_bottom(24)
        self.dot_box.set_size_request(-1, 28)
        overlay.add_overlay(self.dot_box)

        self.rebuild_pages()

    def capture_blurred_desktop(self):
        root = Gdk.get_default_root_window()
        if not root:
            return None

        width = root.get_width()
        height = root.get_height()
        if width <= 0 or height <= 0:
            return None

        try:
            pixbuf = Gdk.pixbuf_get_from_window(root, 0, 0, width, height)
            if not pixbuf:
                return None

            small_w = max(24, width // 18)
            small_h = max(24, height // 18)
            small = pixbuf.scale_simple(small_w, small_h, GdkPixbuf.InterpType.BILINEAR)
            return small.scale_simple(width, height, GdkPixbuf.InterpType.BILINEAR)
        except Exception:
            return None

    def draw_background(self, widget, cr):
        allocation = widget.get_allocation()
        w, h = allocation.width, allocation.height

        if self.background_pixbuf:
            if self.cached_background is None or (w, h) != self.cached_bg_size:
                self.cached_background = self.background_pixbuf.scale_simple(
                    w, h, GdkPixbuf.InterpType.BILINEAR,
                )
                self.cached_bg_size = (w, h)
            Gdk.cairo_set_source_pixbuf(cr, self.cached_background, 0, 0)
            cr.paint()
        else:
            cr.set_source_rgb(0.05, 0.055, 0.07)
            cr.paint()

        cr.set_source_rgba(0.02, 0.025, 0.035, 0.45)
        cr.paint()
        return False

    def close_with_animation(self):
        if self.animating_close:
            return
        self.animating_close = True
        self.destroy()

    def on_size_allocate(self, widget, allocation):
        if allocation.width != self.page_width:
            self.cached_background = None
            self.page_width = max(1, allocation.width)
            self.position_pages()
        cols, rows = self.layout_for_size(allocation.width, allocation.height)
        if cols != self.cols or rows != self.rows:
            self.cols = cols
            self.rows = rows
            self.rebuild_pages()

    def layout_for_size(self, width, height):
        cols = max(4, min(12, (width - 136) // 194))
        rows = max(1, min(5, (height - 190) // 166))
        return cols, rows

    def apply_layout_for_size(self, width, height):
        self.cols, self.rows = self.layout_for_size(width, height)

    def load_applications(self):
        apps_by_id = {}
        desktop_sources = [
            '/home/ubuntu/Desktop',
            '/home/ubuntu/.local/share/desktop-icons/hidden',
            '/home/ubuntu/.local/share/applications',
            '/opt/desktop-shortcuts',
        ]

        for source in desktop_sources:
            if not os.path.isdir(source):
                continue
            for file_path in sorted(glob.glob(os.path.join(source, '*.desktop'))):
                app = self.parse_desktop_file(file_path)
                if not app:
                    continue
                if app.app_id not in apps_by_id:
                    apps_by_id[app.app_id] = app

        return sorted([a for a in apps_by_id.values() if a.installed], key=lambda app: app.name.casefold())

    def load_installed_packages(self):
        try:
            result = subprocess.run(
                ['dpkg-query', '-W', '-f=${binary:Package}\n'],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=False,
                timeout=0.8,
            )
            if result.returncode == 0:
                return set(result.stdout.splitlines())
        except Exception:
            pass
        return set()

    def parse_desktop_file(self, file_path):
        try:
            data = self.read_desktop_entry(file_path)
            desktop_name = os.path.basename(file_path)
            app_id = re.sub(r'^webclaw-install-', '', desktop_name[:-8])
            if app_id in {'launchpad', 'hermes-uninstall'}:
                return None
            if data.get('Type') and data.get('Type') != 'Application':
                return None
            if data.get('NoDisplay', '').lower() == 'true':
                return None
            if data.get('Hidden', '').lower() == 'true':
                return None

            name = self.localized_desktop_value(data, 'Name') or app_id
            name = name.replace('⬇', '').strip()
            exec_cmd = self.clean_exec(data.get('Exec', ''))
            if not exec_cmd:
                return None

            icon = data.get('Icon') or app_id
            installed = self.is_app_installed(app_id, file_path)
            return App(app_id, name, exec_cmd, icon, file_path, installed)
        except Exception:
            return None

    def is_app_installed(self, app_id, file_path):
        if os.path.basename(file_path).startswith('webclaw-install-'):
            return False

        manifest_path = f'/opt/on-demand-apps/{app_id}.json'
        if not os.path.exists(manifest_path):
            return True

        try:
            with open(manifest_path, 'r', encoding='utf-8') as fh:
                manifest = json.load(fh)

            binary = manifest.get('binary')
            install_method = manifest.get('install_method', 'github_release')
            if install_method in {'appimage', 'r2_download', 'direct_download', 'cursor_api', 'custom_script'}:
                return bool(binary and os.access(binary, os.X_OK))

            package = manifest.get('apt_package') or manifest.get('package')
            if package and binary:
                return package in self.installed_packages and os.access(binary, os.X_OK)
        except Exception:
            pass

        return True

    def read_desktop_entry(self, file_path):
        data = {}
        in_entry = False
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as fh:
            for raw_line in fh:
                line = raw_line.strip()
                if line == '[Desktop Entry]':
                    in_entry = True
                    continue
                if line.startswith('[') and in_entry:
                    break
                if not in_entry or '=' not in line or line.startswith('#'):
                    continue
                key, value = line.split('=', 1)
                data[key] = value
        return data

    def clean_exec(self, exec_cmd):
        for token in ['%f', '%F', '%u', '%U', '%d', '%D', '%n', '%N', '%k', '%v', '%c', '%i']:
            exec_cmd = exec_cmd.replace(token, '')
        return re.sub(r'\s+', ' ', exec_cmd).strip()

    def rebuild_pages(self):
        if self.page_animation_id:
            GLib.source_remove(self.page_animation_id)
            self.page_animation_id = None

        for child in self.page_viewport.get_children():
            self.page_viewport.remove(child)
        for child in self.dot_box.get_children():
            self.dot_box.remove(child)

        per_page = max(1, self.cols * self.rows)
        self.pages = [
            self.filtered_apps[i:i + per_page]
            for i in range(0, len(self.filtered_apps), per_page)
        ] or [[]]

        self.current_page = min(self.current_page, len(self.pages) - 1)

        for index, apps in enumerate(self.pages):
            page = self.create_page(apps)
            page.set_size_request(self.page_width, -1)
            self.page_viewport.put(page, index * self.page_width, 0)

        self.drag_dx = 0
        self.position_pages()
        self.update_dots()
        self.show_all()

    def create_page(self, apps):
        wrapper = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        wrapper.set_halign(Gtk.Align.CENTER)
        wrapper.set_valign(Gtk.Align.START)
        wrapper.set_margin_top(44)

        if not apps:
            label = Gtk.Label(label='没有找到应用')
            label.set_name('empty-label')
            wrapper.pack_start(label, True, True, 0)
            return wrapper

        grid = Gtk.Grid()
        grid.set_column_homogeneous(True)
        grid.set_row_homogeneous(True)
        grid.set_column_spacing(44)
        grid.set_row_spacing(30)
        grid.set_halign(Gtk.Align.CENTER)
        grid.set_valign(Gtk.Align.START)
        wrapper.pack_start(grid, False, False, 0)

        for index, app in enumerate(apps):
            row = index // self.cols
            col = index % self.cols
            grid.attach(self.create_app_tile(app), col, row, 1, 1)

        return wrapper

    def create_app_tile(self, app):
        cell = Gtk.Box()
        cell.set_size_request(self.CELL_WIDTH, self.CELL_HEIGHT)
        cell.set_halign(Gtk.Align.CENTER)
        cell.set_valign(Gtk.Align.CENTER)

        event_box = Gtk.EventBox()
        event_box.set_name('app-tile')
        event_box.set_size_request(128, 142)
        event_box.add_events(
            Gdk.EventMask.BUTTON_PRESS_MASK |
            Gdk.EventMask.BUTTON_RELEASE_MASK |
            Gdk.EventMask.POINTER_MOTION_MASK
        )
        event_box.connect('button-press-event', lambda widget, event: self.on_app_press(app, event))
        event_box.connect('motion-notify-event', self.on_motion)
        event_box.connect('button-release-event', lambda widget, event: self.on_app_release(app, event))

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_halign(Gtk.Align.CENTER)
        box.set_valign(Gtk.Align.CENTER)

        icon_overlay = Gtk.Overlay()
        icon_overlay.set_halign(Gtk.Align.CENTER)
        icon_overlay.set_valign(Gtk.Align.CENTER)
        icon = Gtk.Image()
        pixbuf = self.load_icon_pixbuf(app.icon)
        if pixbuf:
            icon.set_from_pixbuf(pixbuf)
        else:
            icon.set_from_icon_name(app.icon, Gtk.IconSize.DIALOG)
            icon.set_pixel_size(self.ICON_SIZE)
        icon_overlay.add(icon)

        if not app.installed:
            badge = Gtk.Label(label='↓')
            badge.set_name('download-badge')
            badge.set_halign(Gtk.Align.END)
            badge.set_valign(Gtk.Align.END)
            badge.set_margin_end(4)
            badge.set_margin_bottom(2)
            icon_overlay.add_overlay(badge)

        label = Gtk.Label(label=app.name)
        label.set_name('app-label')
        label.set_justify(Gtk.Justification.CENTER)
        label.set_lines(2)
        label.set_max_width_chars(14)
        label.set_ellipsize(Pango.EllipsizeMode.END)
        label.set_alignment(0.5, 0.5)

        box.pack_start(icon_overlay, False, False, 0)
        box.pack_start(label, False, False, 0)
        event_box.add(box)
        cell.pack_start(event_box, True, False, 0)
        return cell

    def load_icon_pixbuf(self, icon_name):
        icon_paths = []
        if icon_name.startswith('/'):
            icon_paths.append(icon_name)
        else:
            icon_paths.extend([
                f'/opt/on-demand-icons/{icon_name}.png',
                f'/opt/desktop-icons/{icon_name}.png',
                f'/usr/share/pixmaps/{icon_name}.png',
                f'/usr/share/icons/hicolor/256x256/apps/{icon_name}.png',
                f'/usr/share/icons/hicolor/128x128/apps/{icon_name}.png',
            ])

        for icon_path in icon_paths:
            if os.path.exists(icon_path):
                try:
                    return GdkPixbuf.Pixbuf.new_from_file_at_size(
                        icon_path,
                        self.ICON_SIZE,
                        self.ICON_SIZE,
                    )
                except Exception:
                    pass

        theme = Gtk.IconTheme.get_default()
        try:
            return theme.load_icon(icon_name, self.ICON_SIZE, Gtk.IconLookupFlags.FORCE_SIZE)
        except Exception:
            return None

    def position_pages(self):
        for index, child in enumerate(self.page_viewport.get_children()):
            x = int((index - self.current_page) * self.page_width + self.drag_dx)
            self.page_viewport.move(child, x, 0)
            child.set_size_request(self.page_width, -1)

    def update_dots(self):
        for child in self.dot_box.get_children():
            self.dot_box.remove(child)

        if len(self.pages) <= 1:
            self.dot_box.show_all()
            return

        for index in range(len(self.pages)):
            dot = Gtk.Label(label='•')
            dot.set_name('page-dot-active' if index == self.current_page else 'page-dot')
            self.dot_box.pack_start(dot, False, False, 0)
        self.dot_box.show_all()

    def set_page(self, index):
        index = max(0, min(index, len(self.pages) - 1))
        if index == self.current_page:
            return
        self.current_page = index
        self.drag_dx = 0
        self.position_pages()
        self.update_dots()

    def animate_to_page(self, target_page):
        target_page = max(0, min(target_page, len(self.pages) - 1))
        current_offset = -self.current_page * self.page_width + self.drag_dx
        target_offset = -target_page * self.page_width
        self.page_animation_start = current_offset
        self.page_animation_target = target_offset
        self.page_animation_step = 0

        if self.page_animation_id:
            GLib.source_remove(self.page_animation_id)
        self.page_animation_id = GLib.timeout_add(12, self.animate_page_step, target_page)

    def animate_page_step(self, target_page):
        self.page_animation_step += 1
        progress = min(1.0, self.page_animation_step / 22.0)
        eased = 1 - pow(1 - progress, 3)
        offset = self.page_animation_start + (self.page_animation_target - self.page_animation_start) * eased

        self.current_page = target_page
        self.drag_dx = offset + (self.current_page * self.page_width)
        self.position_pages()

        if progress >= 1.0:
            self.drag_dx = 0
            self.position_pages()
            self.update_dots()
            self.page_animation_id = None
            return False
        return True

    def on_app_press(self, app, event):
        if event.button != 1:
            return True
        self.active_app = app
        return self.on_background_press(self.root, event)

    def on_app_release(self, app, event):
        if event.button != 1:
            return True
        was_dragging = self.dragging
        if was_dragging:
            self.on_background_release(self.root, event)
            self.active_app = None
            return True
        self.drag_start_x = None
        self.drag_start_y = None
        self.active_app = None
        self.launch_app(app)
        return True

    def launch_app(self, app):
        try:
            subprocess.Popen(
                app.exec_cmd,
                shell=True,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as exc:
            print(f'Failed to launch {app.name}: {exc}')
        self.close_with_animation()

    def on_search_changed(self, entry):
        query = entry.get_text().casefold().strip()
        if query:
            self.filtered_apps = [
                app for app in self.all_apps
                if query in app.name.casefold() or query in app.app_id.casefold()
            ]
        else:
            self.filtered_apps = self.all_apps
        self.current_page = 0
        self.rebuild_pages()

    def on_background_press(self, widget, event):
        if self.page_animation_id:
            GLib.source_remove(self.page_animation_id)
            self.page_animation_id = None
        self.drag_start_x = event.x_root
        self.drag_start_y = event.y_root
        self.drag_dx = 0
        self.dragging = False
        return False

    def on_motion(self, widget, event):
        if self.drag_start_x is None:
            return False
        dx = event.x_root - self.drag_start_x
        dy = event.y_root - self.drag_start_y
        if abs(dx) < 4 and abs(dy) < 4:
            return False
        if abs(dx) > abs(dy) * 1.15:
            self.dragging = True
            if (self.current_page == 0 and dx > 0) or (self.current_page == len(self.pages) - 1 and dx < 0):
                dx *= 0.28
            self.drag_dx = dx
            self.position_pages()
            return True
        return False

    def on_background_release(self, widget, event):
        if self.drag_start_x is None:
            return False

        dx = event.x_root - self.drag_start_x
        dy = event.y_root - self.drag_start_y
        self.drag_start_x = None
        self.drag_start_y = None

        if self.dragging or (abs(dx) > self.MIN_SWIPE and abs(dx) > abs(dy) * 1.35):
            page_threshold = self.CELL_WIDTH
            exposed_next = dx < -page_threshold and self.current_page < len(self.pages) - 1
            exposed_prev = dx > page_threshold and self.current_page > 0
            if exposed_next:
                self.animate_to_page(self.current_page + 1)
            elif exposed_prev:
                self.animate_to_page(self.current_page - 1)
            else:
                self.animate_to_page(self.current_page)
            self.dragging = False
            return True

        if abs(dx) < 8 and abs(dy) < 8:
            self.close_with_animation()
            return True

        return False

    def on_scroll(self, widget, event):
        if len(self.pages) <= 1:
            return False

        dx = 0
        dy = 0
        if event.direction == Gdk.ScrollDirection.SMOOTH:
            dx, dy = event.get_scroll_deltas()[1:]
        elif event.direction == Gdk.ScrollDirection.LEFT:
            dx = -1
        elif event.direction == Gdk.ScrollDirection.RIGHT:
            dx = 1
        elif event.direction == Gdk.ScrollDirection.UP:
            dy = -1
        elif event.direction == Gdk.ScrollDirection.DOWN:
            dy = 1

        if abs(dx) >= abs(dy) and abs(dx) > 0:
            self.set_page(self.current_page + (1 if dx > 0 else -1))
            return True

        return False

    def on_key_press(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close_with_animation()
            return True
        if event.keyval in (Gdk.KEY_Left, Gdk.KEY_Page_Up):
            self.set_page(self.current_page - 1)
            return True
        if event.keyval in (Gdk.KEY_Right, Gdk.KEY_Page_Down):
            self.set_page(self.current_page + 1)
            return True
        return False

    def stop_event(self, widget, event):
        return False


def main():
    win = LaunchpadWindow()
    win.connect('destroy', Gtk.main_quit)
    win.show_all()
    Gtk.main()


if __name__ == '__main__':
    main()
