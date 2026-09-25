#!/usr/bin/env python3
"""
dfnix-session-chooser
Forensic Desktop Session Selector (Niri Wayland vs XFCE X11)
Designed for VM appliances (VMware / VirtualBox) and bare-metal live sessions.
"""

import sys
import os
import subprocess
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib

CSS = b"""
* {
    font-family: "DejaVu Sans", "Noto Sans", sans-serif;
}

window {
    background-color: #0b0f19;
    color: #e2e8f0;
}

.header-title {
    font-size: 30px;
    font-weight: 800;
    color: #f8fafc;
}

.header-subtitle {
    font-size: 14px;
    color: #94a3b8;
    margin-top: 4px;
}

.gpu-badge {
    font-size: 12px;
    font-weight: bold;
    padding: 6px 16px;
    border-radius: 16px;
    margin-top: 10px;
}

.gpu-hw {
    background-color: #0e3746;
    color: #22d3ee;
    border: 1px solid #0891b2;
}

.gpu-sw {
    background-color: #3b280c;
    color: #fbbf24;
    border: 1px solid #d97706;
}

.card {
    background-color: #121826;
    border: 2px solid #23304a;
    border-radius: 16px;
    padding: 24px;
    min-width: 380px;
    min-height: 460px;
}

.card:hover, .card:focus {
    background-color: #1a2336;
}

.card-niri:hover, .card-niri:focus {
    border: 2px solid #00e5ff;
}

.card-xfce:hover, .card-xfce:focus {
    border: 2px solid #3b82f6;
}

.card-title {
    font-size: 22px;
    font-weight: 800;
    margin-top: 10px;
    color: #ffffff;
}

.card-subtitle {
    font-size: 13px;
    font-weight: 600;
    color: #38bdf8;
    margin-bottom: 10px;
}

.card-desc {
    font-size: 12px;
    color: #cbd5e1;
    margin-top: 6px;
    margin-bottom: 16px;
}

.rec-badge {
    font-size: 11px;
    font-weight: bold;
    padding: 4px 10px;
    border-radius: 6px;
    margin-bottom: 8px;
}

.rec-recommended {
    background-color: #064e3b;
    color: #34d399;
    border: 1px solid #059669;
}

.rec-optional {
    background-color: #1e293b;
    color: #94a3b8;
    border: 1px solid #475569;
}

.launch-btn {
    font-size: 13px;
    font-weight: 700;
    padding: 10px 20px;
    border-radius: 8px;
    color: #ffffff;
}

.btn-niri {
    background-color: #0284c7;
    border: 1px solid #38bdf8;
}

.btn-niri:hover {
    background-color: #00e5ff;
    color: #04101e;
}

.btn-xfce {
    background-color: #2563eb;
    border: 1px solid #60a5fa;
}

.btn-xfce:hover {
    background-color: #3b82f6;
}

.footer-tip {
    font-size: 12px;
    color: #64748b;
}

.footer-btn {
    font-size: 12px;
    background-color: #1e293b;
    color: #94a3b8;
    border: 1px solid #334155;
    border-radius: 6px;
    padding: 6px 14px;
}

.footer-btn:hover {
    background-color: #334155;
    color: #f1f5f9;
}
"""

def detect_gpu_renderer():
    """Detect OpenGL renderer name and determine if 3D hardware acceleration is present."""
    renderer = "Unknown GPU"
    try:
        res = subprocess.run(
            ["glxinfo", "-B"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2
        )
        for line in res.stdout.splitlines():
            line_str = line.strip()
            if "OpenGL renderer string:" in line_str:
                renderer = line_str.split(":", 1)[1].strip()
                break
    except Exception:
        # Fallback to checking DRM device
        try:
            with open("/sys/class/drm/card0/device/driver/module/version", "r") as f:
                renderer = f.read().strip()
        except Exception:
            pass

    is_sw = any(term in renderer.lower() for term in ["llvmpipe", "softpipe", "swrast", "software", "unknown"])
    is_hw = not is_sw
    return renderer, is_hw

def find_asset(filename):
    """Locate icon asset in repository or installed system path."""
    search_paths = [
        os.path.join(os.path.dirname(__file__), "..", "..", "configs", "assets", "icons", filename),
        os.path.join(os.path.dirname(__file__), "icons", filename),
        os.path.join("/run/current-system/sw/share/dfnix/icons", filename),
        os.path.join("/etc/xdg/dfnix/icons", filename),
        os.path.join(os.path.dirname(__file__), filename),
    ]
    for p in search_paths:
        abs_p = os.path.abspath(p)
        if os.path.exists(abs_p):
            return abs_p
    return None

class SessionChooserWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="dfnix Forensic OS — Session Chooser")
        self.set_default_size(980, 680)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("destroy", Gtk.main_quit)
        self.connect("key-press-event", self.on_key_press)

        # Detect GPU
        self.renderer, self.is_hw = detect_gpu_renderer()

        # Root vertical layout
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.set_border_width(32)
        self.add(root)

        # 1. Header Section
        header_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        header_box.set_halign(Gtk.Align.CENTER)

        lbl_title = Gtk.Label(label="dfnix Forensic Operating System")
        lbl_title.get_style_context().add_class("header-title")
        header_box.pack_start(lbl_title, False, False, 0)

        lbl_sub = Gtk.Label(label="Select Graphical Desktop Environment for this Forensic Session")
        lbl_sub.get_style_context().add_class("header-subtitle")
        header_box.pack_start(lbl_sub, False, False, 0)

        # GPU Status Badge
        if self.is_hw:
            gpu_text = f"🟢 3D Acceleration: Active ({self.renderer})"
            gpu_class = "gpu-hw"
        else:
            gpu_text = f"🟡 3D Acceleration: Inactive ({self.renderer})"
            gpu_class = "gpu-sw"

        lbl_gpu = Gtk.Label(label=gpu_text)
        lbl_gpu.get_style_context().add_class("gpu-badge")
        lbl_gpu.get_style_context().add_class(gpu_class)
        header_box.pack_start(lbl_gpu, False, False, 0)

        root.pack_start(header_box, False, False, 10)

        # 2. Cards Section (Centered Horizontal Box)
        cards_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=36)
        cards_box.set_halign(Gtk.Align.CENTER)
        cards_box.set_valign(Gtk.Align.CENTER)
        root.pack_start(cards_box, True, True, 20)

        # Card 1: Niri (Wayland)
        self.card_niri = self.create_niri_card()
        cards_box.pack_start(self.card_niri, True, True, 0)

        # Card 2: XFCE (X11)
        self.card_xfce = self.create_xfce_card()
        cards_box.pack_start(self.card_xfce, True, True, 0)

        # 3. Footer Section
        footer_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        footer_box.set_margin_top(16)
        root.pack_start(footer_box, False, False, 0)

        lbl_tip = Gtk.Label(label="⌨ Shortcuts: Press [1] for Niri, [2] for XFCE | [Tab]/[Arrows] to focus, [Enter] to select")
        lbl_tip.get_style_context().add_class("footer-tip")
        lbl_tip.set_halign(Gtk.Align.START)
        footer_box.pack_start(lbl_tip, True, True, 0)

        btn_tty = Gtk.Button(label="Console (TTY)")
        btn_tty.get_style_context().add_class("footer-btn")
        btn_tty.connect("clicked", self.on_console_clicked)
        footer_box.pack_end(btn_tty, False, False, 0)

        btn_reboot = Gtk.Button(label="Reboot")
        btn_reboot.get_style_context().add_class("footer-btn")
        btn_reboot.connect("clicked", self.on_reboot_clicked)
        footer_box.pack_end(btn_reboot, False, False, 0)

        btn_power = Gtk.Button(label="Power Off")
        btn_power.get_style_context().add_class("footer-btn")
        btn_power.connect("clicked", self.on_power_clicked)
        footer_box.pack_end(btn_power, False, False, 0)

        # Focus initial card according to detected hardware
        if self.is_hw:
            self.card_niri.grab_focus()
        else:
            self.card_xfce.grab_focus()

    def create_niri_card(self):
        """Build Card for Niri Wayland Compositor."""
        ev = Gtk.EventBox()
        ev.set_can_focus(True)
        ev.get_style_context().add_class("card")
        ev.get_style_context().add_class("card-niri")
        ev.connect("button-press-event", lambda w, e: self.on_card_button_press(w, e, "niri"))

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        ev.add(box)

        # 3D Icon
        icon_path = find_asset("df-3d.png")
        if icon_path:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon_path, 180, 180, True)
            img = Gtk.Image.new_from_pixbuf(pb)
        else:
            img = Gtk.Image.new_from_icon_name("video-display", Gtk.IconSize.DIALOG)
            img.set_pixel_size(180)
        img.set_halign(Gtk.Align.CENTER)
        box.pack_start(img, False, False, 4)

        # Title & Subtitle
        title = Gtk.Label(label="Niri (Wayland)")
        title.get_style_context().add_class("card-title")
        box.pack_start(title, False, False, 0)

        sub = Gtk.Label(label="Modern Forensic Compositor")
        sub.get_style_context().add_class("card-subtitle")
        box.pack_start(sub, False, False, 0)

        # Recommendation badge
        if self.is_hw:
            rec = Gtk.Label(label="✓ Recommended (3D GPU Detected)")
            rec.get_style_context().add_class("rec-badge")
            rec.get_style_context().add_class("rec-recommended")
        else:
            rec = Gtk.Label(label="Requires 3D Acceleration")
            rec.get_style_context().add_class("rec-badge")
            rec.get_style_context().add_class("rec-optional")
        box.pack_start(rec, False, False, 0)

        # Description
        desc_text = (
            "• Infinite horizontal scrollable tiling layout\n"
            "• Noctalia forensic shell & status center\n"
            "• Requires OpenGL 3.3 / SVGA3D 3D acceleration\n"
            "• Enable 'Accelerate 3D graphics' in VM settings"
        )
        desc = Gtk.Label(label=desc_text)
        desc.get_style_context().add_class("card-desc")
        desc.set_justify(Gtk.Justification.LEFT)
        desc.set_xalign(0.0)
        box.pack_start(desc, False, False, 0)

        # Launch Button
        launch = Gtk.Button(label="🚀 Launch Niri (Press 1)")
        launch.get_style_context().add_class("launch-btn")
        launch.get_style_context().add_class("btn-niri")
        launch.connect("clicked", lambda w: self.select_session("niri"))
        box.pack_end(launch, False, False, 6)

        return ev

    def create_xfce_card(self):
        """Build Card for XFCE X11 Desktop."""
        ev = Gtk.EventBox()
        ev.set_can_focus(True)
        ev.get_style_context().add_class("card")
        ev.get_style_context().add_class("card-xfce")
        ev.connect("button-press-event", lambda w, e: self.on_card_button_press(w, e, "xfce"))

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        ev.add(box)

        # 2D Icon
        icon_path = find_asset("xfce-2d.png")
        if icon_path:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon_path, 180, 180, True)
            img = Gtk.Image.new_from_pixbuf(pb)
        else:
            img = Gtk.Image.new_from_icon_name("desktop", Gtk.IconSize.DIALOG)
            img.set_pixel_size(180)
        img.set_halign(Gtk.Align.CENTER)
        box.pack_start(img, False, False, 4)

        # Title & Subtitle
        title = Gtk.Label(label="XFCE (X11)")
        title.get_style_context().add_class("card-title")
        box.pack_start(title, False, False, 0)

        sub = Gtk.Label(label="Universal Compatibility Desktop")
        sub.get_style_context().add_class("card-subtitle")
        box.pack_start(sub, False, False, 0)

        # Recommendation badge
        if not self.is_hw:
            rec = Gtk.Label(label="✓ Recommended (Software Rendering)")
            rec.get_style_context().add_class("rec-badge")
            rec.get_style_context().add_class("rec-recommended")
        else:
            rec = Gtk.Label(label="Universal Fallback Desktop")
            rec.get_style_context().add_class("rec-badge")
            rec.get_style_context().add_class("rec-optional")
        box.pack_start(rec, False, False, 0)

        # Description
        desc_text = (
            "• Traditional forensic desktop with panel and docks\n"
            "• 100% compatible with software rasterizers (llvmpipe)\n"
            "• Recommended when 3D acceleration is off or unstable\n"
            "• Guaranteed rock-solid fail-safe on any hypervisor"
        )
        desc = Gtk.Label(label=desc_text)
        desc.get_style_context().add_class("card-desc")
        desc.set_justify(Gtk.Justification.LEFT)
        desc.set_xalign(0.0)
        box.pack_start(desc, False, False, 0)

        # Launch Button
        launch = Gtk.Button(label="🛡️ Launch XFCE (Press 2)")
        launch.get_style_context().add_class("launch-btn")
        launch.get_style_context().add_class("btn-xfce")
        launch.connect("clicked", lambda w: self.select_session("xfce"))
        box.pack_end(launch, False, False, 6)

        return ev

    def on_card_button_press(self, widget, event, session_name):
        if event.button == 1:
            self.select_session(session_name)
            return True
        return False

    def select_session(self, session_name):
        """Save selection and exit."""
        print(f"[+] Selected session: {session_name}")
        paths = [
            "/tmp/.dfnix-chosen-session",
            f"/run/user/{os.getuid()}/dfnix-chosen-session" if os.path.exists(f"/run/user/{os.getuid()}") else None
        ]
        for p in paths:
            if p:
                try:
                    with open(p, "w") as f:
                        f.write(session_name + "\n")
                except Exception as e:
                    print(f"[-] Warning: Failed to write to {p}: {e}", file=sys.stderr)
        Gtk.main_quit()
        sys.exit(0)

    def on_key_press(self, widget, event):
        keyval = event.keyval
        if keyval in (Gdk.KEY_1, Gdk.KEY_KP_1, Gdk.KEY_n, Gdk.KEY_N):
            self.select_session("niri")
            return True
        elif keyval in (Gdk.KEY_2, Gdk.KEY_KP_2, Gdk.KEY_x, Gdk.KEY_X):
            self.select_session("xfce")
            return True
        elif keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space):
            focused = self.get_focus()
            if focused in (self.card_niri,):
                self.select_session("niri")
                return True
            elif focused in (self.card_xfce,):
                self.select_session("xfce")
                return True
        elif keyval in (Gdk.KEY_Escape,):
            self.on_console_clicked(None)
            return True
        return False

    def on_console_clicked(self, widget):
        print("[*] User selected console (TTY)")
        self.select_session("console")

    def on_reboot_clicked(self, widget):
        print("[*] User requested system reboot")
        subprocess.run(["systemctl", "reboot"], check=False)

    def on_power_clicked(self, widget):
        print("[*] User requested system poweroff")
        subprocess.run(["systemctl", "poweroff"], check=False)

def main():
    # Load CSS
    screen = Gdk.Screen.get_default()
    if screen:
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            screen,
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    win = SessionChooserWindow()
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
