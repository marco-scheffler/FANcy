"""
FANcy — Variable fan speed control for MacBook Pro (Apple Silicon)

Native macOS look & feel with system light/dark mode support.
Features: manual control, "All Fans" slider, interactive fan curve editor,
          hysteresis, sudo keep-alive.
Requires: smc_helper binary (compiled via `make`) and sudo for write ops.
"""

import atexit
import json
import os
import subprocess
import sys
import threading
import time

import flet as ft
from flet.canvas import Canvas, Circle, Line, Text as CText
from flet import Paint, PaintingStyle

# ── Paths ─────────────────────────────────────────────────────────────────

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SMC_HELPER = os.path.join(SCRIPT_DIR, "smc_helper")
CURVE_FILE = os.path.join(SCRIPT_DIR, "fan_curve.json")

# ── SMC wrappers ──────────────────────────────────────────────────────────


def smc_read() -> dict:
    try:
        r = subprocess.run([SMC_HELPER, "read"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            return json.loads(r.stdout)
    except Exception as e:
        print(f"smc_read error: {e}", file=sys.stderr)
    return {"fans": 0, "cpu_temp": -1, "gpu_temp": -1, "fan_data": []}


def smc_set(fan: int, rpm: float) -> bool:
    try:
        r = subprocess.run(
            ["sudo", "-n", SMC_HELPER, "set", str(fan), str(int(rpm))],
            capture_output=True, text=True, timeout=5,
        )
        return r.returncode == 0
    except Exception:
        return False


def smc_auto() -> bool:
    try:
        r = subprocess.run(
            ["sudo", "-n", SMC_HELPER, "auto"],
            capture_output=True, text=True, timeout=5,
        )
        return r.returncode == 0
    except Exception:
        return False


def prime_sudo():
    print("Fan control requires root access. You may be prompted for your password.")
    subprocess.run(["sudo", "-v"], check=False)


def restore_fans_on_exit():
    try:
        subprocess.run(["sudo", "-n", SMC_HELPER, "auto"],
                       capture_output=True, text=True, timeout=5)
    except Exception:
        pass


atexit.register(restore_fans_on_exit)

# ── Fan curve ─────────────────────────────────────────────────────────────

DEFAULT_CURVE = [(30, 0), (45, 5), (60, 30), (75, 65), (90, 100)]


def load_curve() -> list[tuple[float, float]]:
    try:
        with open(CURVE_FILE) as f:
            return [(p[0], p[1]) for p in json.load(f)]
    except Exception:
        return list(DEFAULT_CURVE)


def save_curve(points: list[tuple[float, float]]):
    try:
        with open(CURVE_FILE, "w") as f:
            json.dump(points, f)
    except Exception:
        pass


def interpolate_curve(points: list[tuple[float, float]], temp: float) -> float:
    if not points:
        return 0
    pts = sorted(points, key=lambda p: p[0])
    if temp <= pts[0][0]:
        return pts[0][1]
    if temp >= pts[-1][0]:
        return pts[-1][1]
    for i in range(len(pts) - 1):
        if pts[i][0] <= temp <= pts[i + 1][0]:
            t = (temp - pts[i][0]) / (pts[i + 1][0] - pts[i][0])
            return pts[i][1] + t * (pts[i + 1][1] - pts[i][1])
    return pts[-1][1]


def pct_to_rpm(pct: float, mn: float, mx: float) -> float:
    return mn + (pct / 100.0) * (mx - mn)


def clamp(val: float, mn: float, mx: float) -> float:
    return max(mn, min(mx, val))


# ── Colors ────────────────────────────────────────────────────────────────

LIGHT = {
    "bg": "#f2f2f7", "card_bg": "#ffffff", "card_border": "#c6c6c8",
    "text_primary": "#000000", "text_secondary": "#6e6e73", "text_tertiary": "#aeaeb2",
    "separator": "#c6c6c8", "accent": "#007aff", "green": "#34c759",
    "orange": "#ff9500", "red": "#ff3b30",
    "slider_track": "#e5e5ea", "grid": "#d1d1d6",
    "seg_bg": "#e5e5ea", "seg_active": "#ffffff",
}
DARK = {
    "bg": "#000000", "card_bg": "#1c1c1e", "card_border": "#38383a",
    "text_primary": "#ffffff", "text_secondary": "#98989d", "text_tertiary": "#636366",
    "separator": "#38383a", "accent": "#0a84ff", "green": "#30d158",
    "orange": "#ff9f0a", "red": "#ff453a",
    "slider_track": "#3a3a3c", "grid": "#3a3a3c",
    "seg_bg": "#3a3a3c", "seg_active": "#636366",
}


def get_colors(page: ft.Page) -> dict:
    if page.theme_mode == ft.ThemeMode.DARK:
        return DARK
    if page.theme_mode == ft.ThemeMode.LIGHT:
        return LIGHT
    if hasattr(page, "platform_brightness") and page.platform_brightness == ft.Brightness.DARK:
        return DARK
    return LIGHT


def temp_color(temp: float, co: dict) -> str:
    if temp < 0:
        return co["text_tertiary"]
    if temp < 50:
        return co["green"]
    if temp < 75:
        return co["orange"]
    return co["red"]


# ── Chart geometry ────────────────────────────────────────────────────────

CHART_W, CHART_H = 396.0, 200.0
CHART_PAD_L, CHART_PAD_R, CHART_PAD_T, CHART_PAD_B = 36.0, 12.0, 12.0, 24.0
PLOT_W = CHART_W - CHART_PAD_L - CHART_PAD_R
PLOT_H = CHART_H - CHART_PAD_T - CHART_PAD_B
TEMP_MIN, TEMP_MAX = 25.0, 105.0


def temp_to_x(t): return CHART_PAD_L + (t - TEMP_MIN) / (TEMP_MAX - TEMP_MIN) * PLOT_W
def pct_to_y(p): return CHART_PAD_T + (1.0 - p / 100.0) * PLOT_H
def x_to_temp(x): return TEMP_MIN + (x - CHART_PAD_L) / PLOT_W * (TEMP_MAX - TEMP_MIN)
def y_to_pct(y): return (1.0 - (y - CHART_PAD_T) / PLOT_H) * 100.0


# ── Main ──────────────────────────────────────────────────────────────────

def main(page: ft.Page):
    page.title = "Fan Control"
    page.theme_mode = ft.ThemeMode.SYSTEM
    page.window.width = 460
    page.window.height = 1060
    page.window.resizable = True
    page.padding = 0
    page.spacing = 0
    page.theme = ft.Theme(color_scheme_seed="#007aff", font_family="Helvetica Neue")
    page.dark_theme = ft.Theme(color_scheme_seed="#0a84ff", font_family="Helvetica Neue")

    # ── Shared state ──
    data = smc_read()
    num_fans = data.get("fans", 0)
    poll_active = True
    current_mode = "auto"       # "auto" | "manual" | "curve"
    curve_points = load_curve()
    dragging_idx = -1
    last_smc = [data]           # cached last read
    last_set_rpm = [0.0]        # last RPM set in curve mode (hysteresis)

    global_min = 2317.0
    global_max = 7826.0
    if data.get("fan_data"):
        global_min = max(fd.get("min", 2317) for fd in data["fan_data"])
        global_max = min(fd.get("max", 7826) for fd in data["fan_data"])

    # Persistent UI refs (survive rebuild)
    fan_sliders: list[ft.Slider] = []
    fan_rpm_labels: list[ft.Text] = []
    both_slider_ref: list[ft.Slider] = [None]
    both_rpm_ref: list[ft.Text] = [None]
    cpu_val_ref: list[ft.Text] = [None]
    gpu_val_ref: list[ft.Text] = [None]
    mode_val_ref: list[ft.Text] = [None]
    curve_status_ref: list[ft.Text] = [None]
    chart_canvas_ref: list[Canvas] = [None]

    def co() -> dict:
        return get_colors(page)

    # ── Build chart shapes ──

    def build_chart_shapes() -> list:
        colors = co()
        shapes = []
        lp = Paint(color=colors["grid"], stroke_width=0.5, style=PaintingStyle.STROKE)
        cp = Paint(color=colors["accent"], stroke_width=2.5, style=PaintingStyle.STROKE)
        dp = Paint(color=colors["accent"], style=PaintingStyle.FILL)
        db = Paint(color=colors["card_bg"], stroke_width=2, style=PaintingStyle.STROKE)
        mp = Paint(color=colors["red"], stroke_width=1.5, style=PaintingStyle.STROKE)

        for pct in [0, 25, 50, 75, 100]:
            y = pct_to_y(pct)
            shapes.append(Line(CHART_PAD_L, y, CHART_W - CHART_PAD_R, y, paint=lp))
            shapes.append(CText(2, y - 6, f"{pct}%",
                           style=ft.TextStyle(size=9, color=colors["text_tertiary"])))
        for tmp in range(30, 101, 10):
            x = temp_to_x(tmp)
            shapes.append(Line(x, CHART_PAD_T, x, CHART_H - CHART_PAD_B, paint=lp))
            shapes.append(CText(x - 8, CHART_H - CHART_PAD_B + 4, f"{tmp}°",
                           style=ft.TextStyle(size=9, color=colors["text_tertiary"])))

        pts = sorted(curve_points, key=lambda p: p[0])
        for i in range(len(pts) - 1):
            shapes.append(Line(temp_to_x(pts[i][0]), pct_to_y(pts[i][1]),
                               temp_to_x(pts[i + 1][0]), pct_to_y(pts[i + 1][1]), paint=cp))
        for t, p in pts:
            x, y = temp_to_x(t), pct_to_y(p)
            shapes.append(Circle(x, y, 7, paint=dp))
            shapes.append(Circle(x, y, 7, paint=db))

        cpu_t = last_smc[0].get("cpu_temp", -1)
        if cpu_t > 0:
            mx = temp_to_x(cpu_t)
            my = pct_to_y(interpolate_curve(curve_points, cpu_t))
            shapes.append(Line(mx, CHART_PAD_T, mx, CHART_H - CHART_PAD_B, paint=mp))
            shapes.append(Circle(mx, my, 4,
                                 paint=Paint(color=colors["red"], style=PaintingStyle.FILL)))
        return shapes

    def refresh_chart():
        if chart_canvas_ref[0]:
            chart_canvas_ref[0].shapes = build_chart_shapes()

    # ── Mode helpers ──

    def set_mode(mode: str):
        nonlocal current_mode
        current_mode = mode
        colors = co()
        mv = mode_val_ref[0]
        cs = curve_status_ref[0]
        if not mv:
            return
        if mode == "auto":
            smc_auto()
            mv.value, mv.color, cs.value = "Automatic", colors["green"], ""
        elif mode == "manual":
            mv.value, mv.color, cs.value = "Manual", colors["orange"], ""
        elif mode == "curve":
            mv.value, mv.color = "Fan Curve", colors["accent"]
            cs.value = "Following curve..."
            last_set_rpm[0] = 0.0  # reset hysteresis

    # ── Build full UI ──

    def build_ui():
        nonlocal dragging_idx
        fan_sliders.clear()
        fan_rpm_labels.clear()

        colors = co()

        def sec(title):
            return ft.Container(
                padding=ft.Padding.only(left=20, right=20, top=16, bottom=4),
                content=ft.Text(title, size=13, weight=ft.FontWeight.W_600,
                                color=colors["text_secondary"]))

        # Temperature
        cpu_t = last_smc[0].get("cpu_temp", -1)
        gpu_t = last_smc[0].get("gpu_temp", -1)
        cpu_str = f"{cpu_t:.0f}°C" if cpu_t > 0 else "--"
        gpu_str = f"{gpu_t:.0f}°C" if gpu_t > 0 else "--"
        cpu_val = ft.Text(cpu_str, size=15, weight=ft.FontWeight.W_600,
                          color=temp_color(cpu_t, colors))
        gpu_val = ft.Text(gpu_str, size=15, weight=ft.FontWeight.W_600,
                          color=temp_color(gpu_t, colors))
        cpu_val_ref[0], gpu_val_ref[0] = cpu_val, gpu_val

        def icon_box(bg, icon):
            return ft.Container(width=32, height=32, border_radius=7, bgcolor=bg,
                                alignment=ft.Alignment.CENTER,
                                content=ft.Icon(icon, color="white", size=18))

        def card(content, pad=0):
            return ft.Container(bgcolor=colors["card_bg"], border_radius=10,
                                border=ft.Border.all(0.5, colors["card_border"]),
                                margin=ft.Margin.symmetric(horizontal=16), padding=pad,
                                content=content)

        def row_pad(content):
            return ft.Container(padding=ft.Padding.symmetric(horizontal=16, vertical=12),
                                content=content)

        temp_card = card(ft.Column([
            row_pad(ft.Row([icon_box(colors["accent"], ft.Icons.THERMOSTAT),
                            ft.Container(width=8),
                            ft.Text("CPU Temperature", size=15, color=colors["text_primary"]),
                            ft.Container(expand=True), cpu_val])),
            ft.Container(height=0.5, bgcolor=colors["separator"],
                         margin=ft.Margin.only(left=52)),
            row_pad(ft.Row([icon_box(colors["orange"], ft.Icons.MEMORY),
                            ft.Container(width=8),
                            ft.Text("GPU Temperature", size=15, color=colors["text_primary"]),
                            ft.Container(expand=True), gpu_val])),
        ], spacing=0))

        # Mode
        mode_val = ft.Text("Automatic", size=15, color=colors["green"])
        curve_status = ft.Text("", size=12, color=colors["text_tertiary"])
        mode_val_ref[0], curve_status_ref[0] = mode_val, curve_status
        # Restore mode display
        if current_mode == "manual":
            mode_val.value, mode_val.color = "Manual", colors["orange"]
        elif current_mode == "curve":
            mode_val.value, mode_val.color = "Fan Curve", colors["accent"]
            curve_status.value = "Following curve..."

        def on_auto_click(e):
            set_mode("auto")
            d = smc_read()
            for i in range(num_fans):
                if i < len(d.get("fan_data", [])):
                    fd = d["fan_data"][i]
                    fan_sliders[i].value = clamp(fd["actual"], fd["min"], fd["max"])
                    fan_rpm_labels[i].value = f"{int(fd['actual'])} RPM"
            if d.get("fan_data"):
                avg = sum(fd["actual"] for fd in d["fan_data"]) / len(d["fan_data"])
                both_slider_ref[0].value = clamp(avg, global_min, global_max)
                both_rpm_ref[0].value = f"{int(avg)} RPM"
            page.update()

        mode_card = card(ft.Column([
            ft.Container(
                padding=ft.Padding.symmetric(horizontal=16, vertical=12),
                content=ft.Row([
                    icon_box(colors["green"], ft.Icons.AUTO_MODE),
                    ft.Container(width=8),
                    ft.Text("Fan Mode", size=15, color=colors["text_primary"]),
                    ft.Container(expand=True), mode_val,
                    ft.Container(width=8),
                    ft.Container(on_click=on_auto_click,
                                 content=ft.Text("Restore", size=13, color=colors["accent"])),
                ])),
        ], spacing=0))

        # Fan sliders
        def on_both_change(e):
            rpm = e.control.value
            for j in range(num_fans):
                fan_sliders[j].value = clamp(rpm, global_min, global_max)
                fan_rpm_labels[j].value = f"{int(rpm)} RPM"
                smc_set(j, rpm)
            both_rpm_ref[0].value = f"{int(rpm)} RPM"
            set_mode("manual")
            page.update()

        def on_fan_change(e):
            idx = int(e.control.data)
            rpm = e.control.value
            fan_rpm_labels[idx].value = f"{int(rpm)} RPM"
            smc_set(idx, rpm)
            set_mode("manual")
            page.update()

        avg_act = global_min
        if data.get("fan_data"):
            avg_act = sum(fd["actual"] for fd in data["fan_data"]) / len(data["fan_data"])

        both_rpm = ft.Text(f"{int(avg_act)} RPM", size=15, weight=ft.FontWeight.W_600,
                           color=colors["text_primary"])
        both_slider = ft.Slider(
            min=global_min, max=global_max, value=clamp(avg_act, global_min, global_max),
            divisions=int((global_max - global_min) / 100),
            active_color=colors["accent"], inactive_color=colors["slider_track"],
            on_change_end=on_both_change, expand=True)
        both_slider_ref[0], both_rpm_ref[0] = both_slider, both_rpm

        both_card = card(ft.Column([
            ft.Container(padding=ft.Padding.symmetric(horizontal=16, vertical=8),
                         content=ft.Row([ft.Text("All Fans", size=15, color=colors["text_primary"]),
                                         ft.Container(expand=True), both_rpm])),
            ft.Container(padding=ft.Padding.only(left=8, right=8), content=both_slider),
            ft.Container(padding=ft.Padding.only(left=20, right=20, bottom=4),
                         content=ft.Row([
                             ft.Text(f"{int(global_min)}", size=11, color=colors["text_tertiary"]),
                             ft.Container(expand=True),
                             ft.Text(f"{int(global_max)}", size=11, color=colors["text_tertiary"])])),
        ], spacing=0), pad=ft.Padding.symmetric(vertical=4))

        fan_items = []
        for i in range(num_fans):
            fd = data["fan_data"][i] if i < len(data.get("fan_data", [])) else {}
            mn, mx = fd.get("min", 2317), fd.get("max", 7826)
            actual = fd.get("actual", mn)
            rl = ft.Text(f"{int(actual)} RPM", size=15, weight=ft.FontWeight.W_600,
                         color=colors["text_primary"])
            fan_rpm_labels.append(rl)
            sl = ft.Slider(min=mn, max=mx, value=clamp(actual, mn, mx),
                           divisions=int((mx - mn) / 100),
                           active_color=colors["accent"], inactive_color=colors["slider_track"],
                           data=str(i), on_change_end=on_fan_change, expand=True)
            fan_sliders.append(sl)
            if i > 0:
                fan_items.append(ft.Container(height=0.5, bgcolor=colors["separator"],
                                              margin=ft.Margin.only(left=16)))
            fan_items.append(ft.Column([
                ft.Container(padding=ft.Padding.symmetric(horizontal=16, vertical=8),
                             content=ft.Row([
                                 ft.Text(f"Fan {i+1}", size=15, color=colors["text_primary"]),
                                 ft.Container(expand=True), rl])),
                ft.Container(padding=ft.Padding.only(left=8, right=8), content=sl),
                ft.Container(padding=ft.Padding.only(left=20, right=20, bottom=4),
                             content=ft.Row([
                                 ft.Text(f"{int(mn)}", size=11, color=colors["text_tertiary"]),
                                 ft.Container(expand=True),
                                 ft.Text(f"{int(mx)}", size=11, color=colors["text_tertiary"])])),
            ], spacing=0))

        fan_card = card(ft.Column(fan_items, spacing=0), pad=ft.Padding.symmetric(vertical=4))

        # Chart
        chart_canvas = Canvas(shapes=build_chart_shapes(), width=CHART_W, height=CHART_H)
        chart_canvas_ref[0] = chart_canvas

        def on_pan_start(e):
            nonlocal dragging_idx
            best_i, best_d = -1, 20.0
            for i, (t, p) in enumerate(curve_points):
                d = ((e.local_x - temp_to_x(t))**2 + (e.local_y - pct_to_y(p))**2)**0.5
                if d < best_d:
                    best_d, best_i = d, i
            dragging_idx = best_i

        def on_pan_update(e):
            if dragging_idx < 0 or dragging_idx >= len(curve_points):
                return
            curve_points[dragging_idx] = (
                round(clamp(x_to_temp(e.local_x), TEMP_MIN, TEMP_MAX), 1),
                round(clamp(y_to_pct(e.local_y), 0, 100), 1))
            refresh_chart()
            page.update()

        def on_pan_end(e):
            nonlocal dragging_idx
            if dragging_idx >= 0:
                save_curve(curve_points)
                dragging_idx = -1

        def on_curve_click(e):
            set_mode("curve")
            page.update()

        def on_add(e):
            pts = sorted(curve_points, key=lambda p: p[0])
            if len(pts) >= 10:
                return
            best_gap, bi = 0, 0
            for i in range(len(pts)-1):
                g = pts[i+1][0] - pts[i][0]
                if g > best_gap:
                    best_gap, bi = g, i
            mt = (pts[bi][0] + pts[bi+1][0]) / 2
            curve_points.append((round(mt, 1), round(interpolate_curve(pts, mt), 1)))
            save_curve(curve_points)
            refresh_chart()
            page.update()

        def on_remove(e):
            if len(curve_points) <= 2:
                return
            pts = sorted(curve_points, key=lambda p: p[0])
            curve_points.remove(pts[len(pts)//2])
            save_curve(curve_points)
            refresh_chart()
            page.update()

        def on_reset(e):
            curve_points.clear()
            curve_points.extend(DEFAULT_CURVE)
            save_curve(curve_points)
            refresh_chart()
            page.update()

        curve_card = ft.Container(
            bgcolor=colors["card_bg"], border_radius=10,
            border=ft.Border.all(0.5, colors["card_border"]),
            margin=ft.Margin.symmetric(horizontal=16),
            padding=ft.Padding.only(top=12, bottom=8, left=8, right=8),
            content=ft.Column([
                ft.Container(padding=ft.Padding.symmetric(horizontal=8),
                             content=ft.Row([
                                 ft.Text("Fan Curve", size=15, weight=ft.FontWeight.W_600,
                                         color=colors["text_primary"]),
                                 ft.Container(expand=True), curve_status])),
                ft.Container(height=8),
                ft.GestureDetector(content=chart_canvas,
                                   on_pan_start=on_pan_start,
                                   on_pan_update=on_pan_update,
                                   on_pan_end=on_pan_end),
                ft.Container(height=4),
                ft.Container(padding=ft.Padding.symmetric(horizontal=4),
                             content=ft.Row([
                    ft.Container(on_click=on_curve_click, border_radius=6,
                                 bgcolor=colors["accent"],
                                 padding=ft.Padding.symmetric(horizontal=12, vertical=6),
                                 content=ft.Text("Activate", size=12, color="white")),
                    ft.Container(width=8),
                    ft.Container(on_click=on_add, border_radius=6, bgcolor=colors["slider_track"],
                                 padding=ft.Padding.symmetric(horizontal=10, vertical=6),
                                 content=ft.Text("+", size=14, weight=ft.FontWeight.BOLD,
                                                 color=colors["text_primary"])),
                    ft.Container(on_click=on_remove, border_radius=6, bgcolor=colors["slider_track"],
                                 padding=ft.Padding.symmetric(horizontal=10, vertical=6),
                                 content=ft.Text("−", size=14, weight=ft.FontWeight.BOLD,
                                                 color=colors["text_primary"])),
                    ft.Container(expand=True),
                    ft.Container(on_click=on_reset,
                                 content=ft.Text("Reset", size=13, color=colors["accent"])),
                ], spacing=4)),
            ], spacing=0))

        # Appearance segmented control
        def seg_btn(label, mode, active):
            return ft.Container(
                expand=True, border_radius=7,
                bgcolor=colors["seg_active"] if active else "transparent",
                padding=ft.Padding.symmetric(vertical=6),
                alignment=ft.Alignment.CENTER,
                on_click=lambda e, m=mode: on_theme(m),
                shadow=[ft.BoxShadow(blur_radius=3, color="#00000022")] if active else None,
                content=ft.Text(label, size=13,
                                weight=ft.FontWeight.W_600 if active else ft.FontWeight.W_400,
                                color=colors["text_primary"] if active else colors["text_tertiary"]))

        tm = page.theme_mode
        seg = ft.Container(
            bgcolor=colors["seg_bg"], border_radius=9, padding=2,
            margin=ft.Margin.symmetric(horizontal=16),
            content=ft.Row([
                seg_btn("System", ft.ThemeMode.SYSTEM, tm == ft.ThemeMode.SYSTEM),
                seg_btn("Light", ft.ThemeMode.LIGHT, tm == ft.ThemeMode.LIGHT),
                seg_btn("Dark", ft.ThemeMode.DARK, tm == ft.ThemeMode.DARK),
            ], spacing=2))

        def on_theme(mode):
            page.theme_mode = mode
            page.bgcolor = get_colors(page)["bg"]
            page.controls.clear()
            build_ui()
            page.update()

        # Layout
        page.bgcolor = colors["bg"]
        page.controls.clear()
        page.add(ft.Column([
            sec("TEMPERATURE"), temp_card,
            sec("MODE"), mode_card,
            sec("FAN CURVE"), curve_card,
            sec("MANUAL CONTROL"), both_card, ft.Container(height=4), fan_card,
            sec("APPEARANCE"), seg,
            ft.Container(height=20),
        ], spacing=0, scroll=ft.ScrollMode.AUTO, expand=True))

    build_ui()

    # ── Background threads ──

    def poll_loop():
        while poll_active:
            time.sleep(2)
            try:
                d = smc_read()
            except Exception:
                continue
            last_smc[0] = d

            cpu_t = d.get("cpu_temp", -1)
            gpu_t = d.get("gpu_temp", -1)
            colors = co()

            cv, gv = cpu_val_ref[0], gpu_val_ref[0]
            if cv:
                cv.value = f"{cpu_t:.0f}°C" if cpu_t > 0 else "--"
                cv.color = temp_color(cpu_t, colors)
            if gv:
                gv.value = f"{gpu_t:.0f}°C" if gpu_t > 0 else "--"
                gv.color = temp_color(gpu_t, colors)

            # Curve mode with hysteresis (±2°C dead zone, ±50 RPM threshold)
            if current_mode == "curve" and cpu_t > 0:
                fan_pct = interpolate_curve(curve_points, cpu_t)
                target_rpm = pct_to_rpm(fan_pct, global_min, global_max)
                # Only send new RPM if it changed by more than 50 RPM
                if abs(target_rpm - last_set_rpm[0]) > 50:
                    for i in range(num_fans):
                        if i < len(d.get("fan_data", [])):
                            fd = d["fan_data"][i]
                            smc_set(i, pct_to_rpm(fan_pct, fd["min"], fd["max"]))
                    last_set_rpm[0] = target_rpm
                if curve_status_ref[0]:
                    curve_status_ref[0].value = f"{cpu_t:.0f}°C → {fan_pct:.0f}%"
                refresh_chart()

            fan_actuals = []
            for i in range(num_fans):
                if i < len(d.get("fan_data", [])):
                    fd = d["fan_data"][i]
                    actual = fd["actual"]
                    fan_actuals.append(actual)
                    if i < len(fan_rpm_labels):
                        fan_rpm_labels[i].value = f"{int(actual)} RPM"
                    if current_mode == "auto" and i < len(fan_sliders):
                        fan_sliders[i].value = clamp(actual, fd["min"], fd["max"])

            if fan_actuals and both_rpm_ref[0]:
                avg = sum(fan_actuals) / len(fan_actuals)
                both_rpm_ref[0].value = f"{int(avg)} RPM"
                if current_mode == "auto" and both_slider_ref[0]:
                    both_slider_ref[0].value = clamp(avg, global_min, global_max)

            try:
                page.update()
            except Exception:
                break

    def sudo_keepalive():
        """Refresh sudo token every 4 minutes to prevent expiry."""
        while poll_active:
            time.sleep(240)
            try:
                subprocess.run(["sudo", "-v"], capture_output=True, timeout=5)
            except Exception:
                pass

    threading.Thread(target=poll_loop, daemon=True).start()
    threading.Thread(target=sudo_keepalive, daemon=True).start()

    def on_window_event(e):
        nonlocal poll_active
        if e.data == "close":
            poll_active = False
            smc_auto()
            page.window.destroy()

    page.window.on_event = on_window_event


if __name__ == "__main__":
    if not os.path.isfile(SMC_HELPER):
        print(f"smc_helper not found at {SMC_HELPER}")
        print("Run 'make' first to compile it.")
        sys.exit(1)
    prime_sudo()
    ft.run(main)
