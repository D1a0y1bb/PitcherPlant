import argparse
import os
import socket
import threading
import uuid
import webbrowser
from datetime import datetime
from typing import Any, Dict

from flask import Flask, abort, jsonify, render_template, request, send_file, url_for

from .audit import run_audit


def _dependency_error(exc: Exception) -> RuntimeError:
    return RuntimeError(
        "错误: 缺少 Web 依赖。请先运行 `pip install -r requirements.txt`。\n"
        "如需隔离环境，执行 `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`。\n"
        f"详情: {exc}"
    )


try:
    import tkinter as tk
    from tkinter import filedialog
except Exception:
    tk = None
    filedialog = None


_JOBS: Dict[str, Dict[str, Any]] = {}
_JOBS_LOCK = threading.Lock()


def _now() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _cwd() -> str:
    return os.path.abspath(os.getcwd())


def _normalize_path(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    if not stripped:
        return None
    return os.path.abspath(os.path.expanduser(stripped))


def _list_subdirs(path: str) -> list[dict[str, str]]:
    if not os.path.isdir(path):
        return []
    items = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            items.append({"label": entry, "path": full})
    return items[:24]


def _build_defaults() -> Dict[str, Any]:
    cwd = _cwd()
    default_scan_dir = os.path.join(cwd, "date")
    default_output_dir = os.path.join(cwd, "reports", "full")
    return {
        "cwd": cwd,
        "directory": default_scan_dir if os.path.isdir(default_scan_dir) else cwd,
        "output_dir": default_output_dir,
        "name_template": "{dir}_PitcherPlant_{date}.html",
        "text_thresh": 0.75,
        "img_thresh": 5,
        "dedup_thresh": 0.85,
        "simhash_thresh": 4,
        "db_path": os.path.join(cwd, "PitcherPlant.sqlite"),
        "whitelist_path": "",
        "use_cv": True,
        "whitelist_mode": "mark",
        "scan_presets": _list_subdirs(default_scan_dir),
        "report_presets": _list_subdirs(os.path.join(cwd, "reports")),
    }


def _push_event(job: Dict[str, Any], message: str, progress: int | None = None) -> None:
    if progress is not None:
        job["progress"] = progress
    job["message"] = message
    job["updated_at"] = _now()
    event = {
        "message": message,
        "progress": job["progress"],
        "timestamp": job["updated_at"],
    }
    events = job.setdefault("events", [])
    if events and events[-1]["message"] == event["message"] and events[-1]["progress"] == event["progress"]:
        events[-1]["timestamp"] = event["timestamp"]
        return
    events.append(event)
    del events[:-20]


def _serialize_job(job: Dict[str, Any]) -> Dict[str, Any]:
    payload = {
        "id": job["id"],
        "status": job["status"],
        "progress": job["progress"],
        "message": job["message"],
        "directory": job["directory"],
        "output_dir": job["output_dir"],
        "report_path": job.get("report_path"),
        "error": job.get("error"),
        "created_at": job["created_at"],
        "updated_at": job["updated_at"],
        "events": job.get("events", []),
        "config": job.get("config", {}),
    }
    if job.get("report_path"):
        payload["report_url"] = url_for("serve_report", job_id=job["id"])
    else:
        payload["report_url"] = None
    return payload


def _pick_directory(initial_dir: str | None = None) -> str:
    if tk is None or filedialog is None:
        raise RuntimeError("当前 Python 环境缺少 Tk 目录选择能力。")
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    root.update()
    selected = filedialog.askdirectory(
        initialdir=initial_dir or _cwd(),
        title="选择目录",
        parent=root,
    )
    root.destroy()
    return selected or ""


def _build_job(payload: Dict[str, Any]) -> Dict[str, Any]:
    defaults = _build_defaults()

    directory = _normalize_path(payload.get("directory")) or defaults["directory"]
    if not os.path.isdir(directory):
        raise ValueError(f"目录不存在: {directory}")

    output_dir = _normalize_path(payload.get("output_dir")) or defaults["output_dir"]
    name_template = (payload.get("name_template") or defaults["name_template"]).strip()
    if "{dir}" not in name_template and "{date}" not in name_template and not name_template.endswith(".html"):
        raise ValueError("报告文件名需要包含 .html，建议使用 {dir}_PitcherPlant_{date}.html")

    job = {
        "id": uuid.uuid4().hex[:10],
        "status": "queued",
        "progress": 0,
        "message": "等待开始",
        "created_at": _now(),
        "updated_at": _now(),
        "directory": directory,
        "output_dir": output_dir,
        "report_path": None,
        "error": None,
        "events": [],
        "config": {
            "name_template": name_template,
            "text_thresh": float(payload.get("text_thresh", defaults["text_thresh"])),
            "img_thresh": int(payload.get("img_thresh", defaults["img_thresh"])),
            "dedup_thresh": float(payload.get("dedup_thresh", defaults["dedup_thresh"])),
            "db_path": _normalize_path(payload.get("db_path")) or defaults["db_path"],
            "whitelist_path": _normalize_path(payload.get("whitelist_path")) or None,
            "simhash_thresh": int(payload.get("simhash_thresh", defaults["simhash_thresh"])),
            "whitelist_mode": payload.get("whitelist_mode") or defaults["whitelist_mode"],
            "use_cv": bool(payload.get("use_cv", defaults["use_cv"])),
        },
    }

    if not 0.0 <= job["config"]["text_thresh"] <= 1.0:
        raise ValueError("文本阈值需要在 0.0 到 1.0 之间。")
    if not 0 <= job["config"]["img_thresh"] <= 10:
        raise ValueError("图片阈值需要在 0 到 10 之间。")
    if not 0.0 <= job["config"]["dedup_thresh"] <= 1.0:
        raise ValueError("重复文件阈值需要在 0.0 到 1.0 之间。")
    if job["config"]["whitelist_mode"] not in {"hide", "mark"}:
        raise ValueError("白名单模式只支持 hide 或 mark。")

    _push_event(job, "任务已创建", 0)
    return job


def _run_job(job_id: str) -> None:
    with _JOBS_LOCK:
        job = _JOBS[job_id]
        job["status"] = "running"
        _push_event(job, "任务启动", 1)
        config = dict(job["config"])
        directory = job["directory"]
        output_dir = job["output_dir"]

    def progress_cb(progress: int, message: str) -> None:
        with _JOBS_LOCK:
            current = _JOBS.get(job_id)
            if not current:
                return
            _push_event(current, message, progress)

    try:
        report_path = run_audit(
            directory=directory,
            text_thresh=config["text_thresh"],
            img_thresh=config["img_thresh"],
            output_dir=output_dir,
            name_template=config["name_template"],
            cv_preprocess=config["use_cv"],
            dedup_thresh=config["dedup_thresh"],
            db_path=config["db_path"],
            whitelist_path=config["whitelist_path"],
            simhash_thresh=config["simhash_thresh"],
            whitelist_mode=config["whitelist_mode"],
            progress_cb=progress_cb,
        )
    except Exception as exc:
        with _JOBS_LOCK:
            current = _JOBS.get(job_id)
            if current:
                current["status"] = "failed"
                current["error"] = str(exc)
                _push_event(current, f"任务失败: {exc}", current["progress"])
        return

    with _JOBS_LOCK:
        current = _JOBS.get(job_id)
        if current:
            current["status"] = "succeeded"
            current["report_path"] = report_path
            _push_event(current, "报告生成完成", 100)


def _choose_port(host: str, preferred_port: int) -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((host, preferred_port))
            return preferred_port
        except OSError:
            sock.bind((host, 0))
            return sock.getsockname()[1]


def create_app() -> Flask:
    app = Flask(__name__, template_folder="templates", static_folder="static")

    @app.get("/")
    def index():
        return render_template("index.html")

    @app.get("/api/health")
    def health():
        return jsonify({"ok": True, "timestamp": _now()})

    @app.get("/api/defaults")
    def defaults():
        return jsonify(_build_defaults())

    @app.post("/api/pick-directory")
    def pick_directory():
        payload = request.get_json(silent=True) or {}
        initial_dir = _normalize_path(payload.get("initial"))
        try:
            selected = _pick_directory(initial_dir)
        except Exception as exc:
            return jsonify({"error": str(exc)}), 500
        return jsonify({"path": selected})

    @app.post("/api/jobs")
    def create_job():
        payload = request.get_json(silent=True) or {}
        try:
            job = _build_job(payload)
        except (TypeError, ValueError) as exc:
            return jsonify({"error": str(exc)}), 400

        with _JOBS_LOCK:
            _JOBS[job["id"]] = job

        worker = threading.Thread(target=_run_job, args=(job["id"],), daemon=True)
        worker.start()

        with _JOBS_LOCK:
            current = _JOBS[job["id"]]
            return jsonify(_serialize_job(current)), 202

    @app.get("/api/jobs")
    def list_jobs():
        with _JOBS_LOCK:
            jobs = list(reversed(sorted(_JOBS.values(), key=lambda item: item["created_at"])))
            return jsonify([_serialize_job(job) for job in jobs[:10]])

    @app.get("/api/jobs/<job_id>")
    def get_job(job_id: str):
        with _JOBS_LOCK:
            job = _JOBS.get(job_id)
            if not job:
                return jsonify({"error": "任务不存在"}), 404
            return jsonify(_serialize_job(job))

    @app.get("/reports/<job_id>")
    def serve_report(job_id: str):
        with _JOBS_LOCK:
            job = _JOBS.get(job_id)
            if not job or not job.get("report_path"):
                abort(404)
            report_path = job["report_path"]

        if not os.path.isfile(report_path):
            abort(404)
        return send_file(report_path, mimetype="text/html")

    return app


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PitcherPlant 本地 Web 控制台")
    parser.add_argument("--host", default="127.0.0.1", help="监听地址，默认 127.0.0.1")
    parser.add_argument("--port", type=int, default=8765, help="监听端口，默认 8765")
    parser.add_argument("--no-browser", action="store_true", help="启动后不自动打开浏览器")
    args = parser.parse_args(argv)

    app = create_app()
    port = _choose_port(args.host, args.port)
    url = f"http://{args.host}:{port}"
    print(f"[*] PitcherPlant Web 控制台: {url}")

    if not args.no_browser:
        timer = threading.Timer(0.8, lambda: webbrowser.open(url))
        timer.daemon = True
        timer.start()

    app.run(host=args.host, port=port, debug=False, threaded=True, use_reloader=False)
    return 0

