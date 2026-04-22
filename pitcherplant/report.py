import html
import json
import logging
import os
from collections import defaultdict
from datetime import datetime
from typing import Dict, List


logger = logging.getLogger(__name__)


def _esc(value: object) -> str:
    if value is None:
        return ""
    return html.escape(str(value))


class ReportBuilder:
    def __init__(
        self,
        directory: str,
        output_dir: str | None,
        name_template: str | None,
        documents: List[Dict],
        text_threshold: float,
        img_threshold: int,
        dedup_threshold: float,
    ) -> None:
        self.directory = directory
        self.output_dir = output_dir
        self.name_template = name_template
        self.documents = documents
        self.text_threshold = text_threshold
        self.img_threshold = img_threshold
        self.dedup_threshold = dedup_threshold

    def _build_assoc(self, text_res, code_res, img_res, dedup_res, cross_res) -> List[Dict]:
        author_map = {}
        for doc in self.documents:
            author_map[doc.get("filename")] = (doc.get("metadata", {}) or {}).get("author")

        def kpair(a, b):
            return tuple(sorted([a or "-", b or "-"]))

        assoc = {}

        def add_assoc(a, b, reason):
            key = kpair(a, b)
            value = assoc.get(key) or {"a": key[0], "b": key[1], "count": 0, "reasons": defaultdict(int)}
            value["count"] += 1
            value["reasons"][reason] += 1
            assoc[key] = value

        text_high = 90.0
        code_high = 90.0
        dedup_high = max(self.dedup_threshold * 100, 90.0)
        img_group_high = 3
        cross_sev_dist = 2

        for item in text_res or []:
            if item.get("score", 0) >= text_high:
                add_assoc(author_map.get(item["file_a"]), author_map.get(item["file_b"]), "text")
        for item in code_res or []:
            if item.get("score", 0) >= code_high:
                add_assoc(author_map.get(item["file_a"]), author_map.get(item["file_b"]), "code")
        for item in img_res or []:
            if item.get("count", 0) >= img_group_high:
                add_assoc(author_map.get(item["files"][0]), author_map.get(item["files"][1]), "image")
        for item in dedup_res or []:
            if item.get("score", 0) >= dedup_high:
                add_assoc(author_map.get(item["file_a"]), author_map.get(item["file_b"]), "dedup")
        for item in cross_res or []:
            if item.get("dist", 99) <= cross_sev_dist:
                add_assoc(item.get("current_author"), item.get("prev_author"), "cross")

        assoc_list = list(assoc.values())
        assoc_list.sort(key=lambda x: (x["count"], len(x["reasons"])), reverse=True)
        return assoc_list

    @staticmethod
    def _build_graph_data(assoc_list: List[Dict]) -> str:
        node_set = set()
        links = []
        for item in assoc_list[:50]:
            node_set.add(item["a"])
            node_set.add(item["b"])
            primary = (
                sorted(item["reasons"].items(), key=lambda x: -x[1])[0][0]
                if item["reasons"]
                else "text"
            )
            links.append(
                {
                    "source": item["a"],
                    "target": item["b"],
                    "weight": item["count"],
                    "primary": primary,
                    "types": list(item["reasons"].keys()),
                }
            )
        nodes = [{"id": node} for node in sorted(node_set)]
        return json.dumps({"nodes": nodes, "links": links}, ensure_ascii=False)

    def _render_text_rows(self, text_res: List[Dict]) -> str:
        rows = []
        for idx, item in enumerate(text_res):
            badge = "high" if item["score"] > 80 else "med"
            rows.append(
                f"""
                <tr>
                    <td><span class="badge {badge}">{_esc(item['score'])}%</span></td>
                    <td class="file-name">{_esc(item['file_a'])}</td>
                    <td class="file-name">{_esc(item['file_b'])}</td>
                    <td>
                        <div class="snippet">核心匹配：{_esc(item['evidence'])}</div>
                        <button class="toggle" onclick="togglePanel('tctx_{idx}')">展开/折叠上下文</button>
                        <div id="tctx_{idx}" class="panel">
                            <div class="snippet">A上下文：{_esc(item.get('evidence_a', ''))}</div>
                            <div class="snippet">B上下文：{_esc(item.get('evidence_b', ''))}</div>
                        </div>
                    </td>
                </tr>
                """
            )
        return "".join(rows)

    def _render_code_rows(self, code_res: List[Dict]) -> str:
        rows = []
        for idx, item in enumerate(code_res):
            rows.append(
                f"""
                <tr>
                    <td><span class="badge high">{_esc(item['score'])}%</span></td>
                    <td class="file-name">{_esc(item['file_a'])}</td>
                    <td class="file-name">{_esc(item['file_b'])}</td>
                    <td>{_esc(item['type'])}</td>
                    <td>
                        <button class="toggle" onclick="togglePanel('cctx_{idx}')">展开/折叠上下文</button>
                        <div id="cctx_{idx}" class="panel">
                            <div class="snippet">A代码：{_esc(item.get('evidence_a', ''))}</div>
                            <div class="snippet">B代码：{_esc(item.get('evidence_b', ''))}</div>
                        </div>
                    </td>
                </tr>
                """
            )
        return "".join(rows)

    def _render_code_summary(self, code_res: List[Dict]) -> str:
        if not code_res:
            return '<div class="hint" style="font-size:14px">当前批次没有达到阈值的代码结构复用样本。</div>'

        blocks = []
        for idx, item in enumerate(code_res[:12]):
            if item.get("type") == "Code Structural Paraphrase":
                explanation = "基于代码结构片段比对，两份文档中的脚本组织方式高度接近；分数为结构相似度的百分比。"
            else:
                explanation = "基于代码指纹重合与结构片段比对，两份文档中的脚本结构高度一致；分数为指纹/结构相似度的百分比。"
            blocks.append(
                f"""
                <div class="block">
                    <div class="block-title">示例 {idx + 1}</div>
                    <div><strong>原始文件名</strong>: <code>{_esc(item['file_a'])}</code></div>
                    <div><strong>比较文件名</strong>: <code>{_esc(item['file_b'])}</code></div>
                    <div class="hint" style="font-size:13px;margin-top:6px"><strong>相似度</strong>: {_esc(item['score'])}%</div>
                    <div class="hint" style="font-size:13px;margin-top:8px">解释: {_esc(explanation)}</div>
                    <div class="compare-grid">
                        <div>
                            <div class="hint" style="font-size:12px;margin-bottom:4px">A 片段</div>
                            <div class="snippet">{_esc(item.get('evidence_a', ''))}</div>
                        </div>
                        <div>
                            <div class="hint" style="font-size:12px;margin-bottom:4px">B 片段</div>
                            <div class="snippet">{_esc(item.get('evidence_b', ''))}</div>
                        </div>
                    </div>
                </div>
                """
            )
        return "".join(blocks)

    @staticmethod
    def _render_image_gallery(item: Dict) -> str:
        thumbs = item.get("gallery") or []
        if not thumbs:
            for example in item.get("examples", []):
                for key in ("a_thumb", "b_thumb"):
                    thumb = example.get(key)
                    if thumb:
                        thumbs.append({"thumb": thumb, "label": ""})

        if not thumbs:
            return ""

        cells = []
        for thumb in thumbs:
            if isinstance(thumb, dict):
                thumb_b64 = thumb.get("thumb", "")
                label = thumb.get("label", "")
            else:
                thumb_b64 = str(thumb)
                label = ""
            if not thumb_b64:
                continue
            title_attr = f' title="{_esc(label)}"' if label else ""
            cells.append(
                f'<div class="thumb"{title_attr}><img src="data:image/jpeg;base64,{thumb_b64}" /></div>'
            )
        if not cells:
            return ""
        return f'<div class="gallery" style="margin-top:12px">{"".join(cells)}</div>'

    def _render_image_detail(self, img_res: List[Dict]) -> str:
        blocks = []
        for idx, item in enumerate(img_res):
            rows = []
            for ex in item.get("examples", []):
                a_ctx = ex.get("a_ctx") or {}
                b_ctx = ex.get("b_ctx") or {}
                rows.append(
                    f"""
                    <tr>
                        <td>{_esc(ex.get('diff', ''))}</td>
                        <td>
                            <img src="data:image/jpeg;base64,{ex.get('a_thumb', '')}" style="max-width:200px;border:1px solid #eee" />
                            <div class="hint">来源：{_esc(a_ctx.get('type', ''))} {_esc(a_ctx.get('page', ''))} {_esc(a_ctx.get('name', ''))}</div>
                            <div class="snippet">{_esc(ex.get('a_ocr', ''))}</div>
                        </td>
                        <td>
                            <img src="data:image/jpeg;base64,{ex.get('b_thumb', '')}" style="max-width:200px;border:1px solid #eee" />
                            <div class="hint">来源：{_esc(b_ctx.get('type', ''))} {_esc(b_ctx.get('page', ''))} {_esc(b_ctx.get('name', ''))}</div>
                            <div class="snippet">{_esc(ex.get('b_ocr', ''))}</div>
                        </td>
                    </tr>
                    """
                )
            blocks.append(
                f"""
                <div class="block">
                    <div class="block-title">{_esc(item['files'][0])} ↔ {_esc(item['files'][1])}（{_esc(item['count'])} 张）</div>
                    <button class="toggle" onclick="togglePanel('ictx_{idx}')">展开/折叠证据</button>
                    <div id="ictx_{idx}" class="panel">
                        <table>
                            <thead>
                                <tr>
                                    <th width="10%">Diff</th>
                                    <th width="45%">A 证据</th>
                                    <th width="45%">B 证据</th>
                                </tr>
                            </thead>
                            <tbody>{''.join(rows)}</tbody>
                        </table>
                        {self._render_image_gallery(item)}
                    </div>
                </div>
                """
            )
        return "".join(blocks)

    def _render_dedup_rows(self, dedup_res: List[Dict]) -> str:
        rows = []
        for idx, item in enumerate(dedup_res):
            hints = []
            if item.get("cross_format"):
                hints.append("跨格式")
            if item.get("team_hint"):
                hints.append(item["team_hint"])
            hint_text = " · ".join(hints)
            rows.append(
                f"""
                <tr>
                    <td><span class="badge {'high' if item['score'] > 90 else 'med'}">{_esc(item['score'])}%</span></td>
                    <td class="file-name">{_esc(item['file_a'])}</td>
                    <td class="file-name">{_esc(item['file_b'])}</td>
                    <td>{_esc(hint_text)}</td>
                    <td>
                        <div class="snippet">核心匹配：{_esc(item['evidence'])}</div>
                        <button class="toggle" onclick="togglePanel('dctx_{idx}')">展开/折叠上下文</button>
                        <div id="dctx_{idx}" class="panel">
                            <div class="snippet">A上下文：{_esc(item.get('evidence_a', ''))}</div>
                            <div class="snippet">B上下文：{_esc(item.get('evidence_b', ''))}</div>
                        </div>
                    </td>
                </tr>
                """
            )
        return "".join(rows)

    def generate(
        self,
        text_res: List[Dict],
        code_res: List[Dict],
        img_res: List[Dict],
        meta_res: List[Dict],
        dedup_res: List[Dict] | None = None,
        fingerprint_db: List[Dict] | None = None,
        cross_res: List[Dict] | None = None,
    ) -> str:
        logger.info("正在生成审计报告...")
        dedup_res = dedup_res or []
        fingerprint_db = fingerprint_db or []
        cross_res = cross_res or []
        assoc_list = self._build_assoc(text_res, code_res, img_res, dedup_res, cross_res)
        graph_data_js = self._build_graph_data(assoc_list)

        overview_rows = "".join(
            [
                f"""
                <tr>
                    <td class="file-name">{_esc(it['a'])}</td>
                    <td class="file-name">{_esc(it['b'])}</td>
                    <td><span class="badge {'high' if it['count'] >= 3 else 'med'}">{_esc(it['count'])}</span></td>
                    <td>{_esc(', '.join([k for k, _ in sorted(it['reasons'].items(), key=lambda x: -x[1])]))}</td>
                </tr>
                """
                for it in assoc_list[:20]
            ]
        )

        img_rows = "".join(
            [
                f"""
                <tr>
                    <td><span class="badge med">{_esc(item['count'])} 张</span></td>
                    <td class="file-name">{_esc(item['files'][0])}</td>
                    <td class="file-name">{_esc(item['files'][1])}</td>
                </tr>
                """
                for item in img_res
            ]
        )

        meta_rows = "".join(
            [
                f"""
                <tr>
                    <td><strong>{_esc(item['author'])}</strong></td>
                    <td>{_esc(item['count'])}</td>
                    <td>{_esc(', '.join(item.get('teams', [])))}</td>
                    <td>{_esc(', '.join(item['files']))}</td>
                </tr>
                """
                for item in meta_res
            ]
        )

        dedup_rows = self._render_dedup_rows(dedup_res)
        code_summary_blocks = self._render_code_summary(code_res)

        fingerprint_rows = "".join(
            [
                f"""
                <tr>
                    <td class="file-name">{_esc(rec['filename'])}</td>
                    <td>{_esc(rec.get('author', ''))}</td>
                    <td>{_esc(rec.get('ext', ''))}</td>
                    <td class="snippet">{_esc(rec.get('simhash', ''))}</td>
                </tr>
                """
                for rec in fingerprint_db
            ]
        )

        cross_rows = "".join(
            [
                f"""
                <tr>
                    <td><span class="badge {'high' if item['dist'] <= 2 else 'med'}">{_esc(item['dist'])}</span></td>
                    <td class="file-name">{_esc(item['current_file'])} {_esc(item.get('current_author', ''))}</td>
                    <td class="file-name">{_esc(item['prev_file'])} {_esc(item.get('prev_author', ''))}</td>
                    <td>{_esc(item['prev_scan'])}</td>
                    <td>{_esc('白名单(' + item['wl_type'] + ')' if item.get('whitelisted') else '疑似复用')}</td>
                </tr>
                """
                for item in cross_res
            ]
        )

        html_doc = f"""
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <title>PitcherPlant Writeup 审计报告</title>
            <style>
                body {{ font-family: "PingFang SC", "Microsoft YaHei", sans-serif; background: #f4f6f9; color: #333; margin: 0; padding: 20px; }}
                .container {{ max-width: 1440px; margin: 0 auto; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 0 16px rgba(0, 0, 0, 0.06); }}
                .header {{ background: #2c3e50; color: #fff; padding: 24px 32px; border-bottom: 4px solid #3498db; }}
                .header h1 {{ margin: 0; font-size: 26px; }}
                .meta {{ margin-top: 10px; font-size: 14px; opacity: 0.86; }}
                .summary {{ display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; padding: 20px 32px; background: #ecf0f1; }}
                .card {{ background: #fff; padding: 16px; border-radius: 6px; border-left: 4px solid #bdc3c7; }}
                .card.danger {{ border-left-color: #e74c3c; }}
                .card.warning {{ border-left-color: #f39c12; }}
                .card.info {{ border-left-color: #3498db; }}
                .card-title {{ font-size: 12px; color: #7f8c8d; text-transform: uppercase; }}
                .card-value {{ font-size: 28px; font-weight: 700; margin-top: 8px; color: #2c3e50; }}
                .tabs {{ display: flex; flex-wrap: wrap; gap: 10px; padding: 12px 32px; background: #fff; border-bottom: 1px solid #eee; position: sticky; top: 0; z-index: 10; }}
                .tab-item {{ padding: 8px 12px; border: 1px solid #d9dee3; border-radius: 16px; background: #fafafa; cursor: pointer; }}
                .tab-item.active {{ background: #3498db; color: #fff; border-color: #3498db; }}
                .section {{ padding: 30px 32px; border-bottom: 1px solid #eee; }}
                .section h2 {{ margin: 0 0 18px; color: #2c3e50; border-left: 4px solid #3498db; padding-left: 10px; }}
                table {{ width: 100%; border-collapse: collapse; font-size: 14px; }}
                th {{ text-align: left; background: #f8f9fa; padding: 12px 14px; border-bottom: 2px solid #dfe6e9; }}
                td {{ padding: 12px 14px; border-bottom: 1px solid #f1f2f6; vertical-align: top; }}
                tr:hover {{ background: #fafaf0; }}
                .badge {{ display: inline-block; padding: 3px 8px; border-radius: 12px; font-size: 12px; font-weight: 700; }}
                .high {{ background: #ffebeb; color: #d63031; }}
                .med {{ background: #fff3cd; color: #856404; }}
                .snippet {{ font-family: Consolas, Monaco, monospace; font-size: 12px; background: #f7f7f7; padding: 8px; border: 1px solid #eee; border-radius: 4px; white-space: pre-wrap; }}
                .file-name {{ font-weight: 600; color: #0984e3; }}
                .toggle {{ margin-top: 8px; padding: 6px 10px; border: 1px solid #d9dee3; background: #fff; border-radius: 6px; cursor: pointer; }}
                .panel {{ display: none; margin-top: 10px; }}
                .panel.open {{ display: block; }}
                .hint {{ font-size: 12px; color: #666; margin: 6px 0; }}
                .block {{ margin-bottom: 18px; padding: 14px; border: 1px solid #eee; border-radius: 6px; background: #fafafa; }}
                .block-title {{ font-weight: 700; margin-bottom: 10px; color: #2c3e50; }}
                .compare-grid {{ display: flex; gap: 12px; margin-top: 10px; }}
                .compare-grid > div {{ flex: 1; min-width: 0; }}
                .gallery {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; }}
                .thumb {{ border: 1px solid #eee; border-radius: 4px; background: #fff; padding: 6px; }}
                .thumb img {{ width: 100%; height: auto; display: block; }}
                .overview-grid {{ display: flex; gap: 20px; align-items: flex-start; margin-bottom: 18px; }}
                .overview-graph {{ flex: 2; min-height: 480px; }}
                .overview-legend {{ flex: 1; }}
                .legend-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }}
                .legend-item {{ display: flex; align-items: center; gap: 8px; }}
                .legend-swatch {{ display: inline-block; width: 12px; height: 12px; }}
                @media (max-width: 768px) {{
                    body {{ padding: 0; }}
                    .summary {{ grid-template-columns: 1fr; }}
                    .tabs {{ padding: 12px 16px; }}
                    .section {{ padding: 24px 16px; }}
                    .compare-grid {{ flex-direction: column; }}
                    .overview-grid {{ flex-direction: column; }}
                    .overview-graph, .overview-legend {{ width: 100%; min-height: 0; }}
                }}
            </style>
            <script>
                function togglePanel(id) {{
                    var el = document.getElementById(id);
                    if (!el) return;
                    el.classList.toggle('open');
                }}
                function showTab(id) {{
                    var secs = document.getElementsByClassName('tab-section');
                    for (var i = 0; i < secs.length; i++) secs[i].style.display = 'none';
                    var tgt = document.getElementById(id);
                    if (tgt) tgt.style.display = 'block';
                    var items = document.getElementsByClassName('tab-item');
                    for (var j = 0; j < items.length; j++) items[j].classList.remove('active');
                    var btn = document.getElementById('btn_' + id);
                    if (btn) btn.classList.add('active');
                }}
                var GRAPH_DATA = {graph_data_js};
                function initGraph(canvasId, data) {{
                    var canvas = document.getElementById(canvasId);
                    if (!canvas) return;
                    var parent = canvas.parentElement;
                    canvas.width = (parent && parent.clientWidth) ? parent.clientWidth - 20 : window.innerWidth * 0.9;
                    canvas.height = 480;
                    var ctx = canvas.getContext('2d');
                    if (!ctx) return;
                    if (!data || !data.nodes || !data.nodes.length) {{
                        ctx.clearRect(0, 0, canvas.width, canvas.height);
                        ctx.fillStyle = '#7f8c8d';
                        ctx.font = '14px sans-serif';
                        ctx.fillText('暂无可视化关联数据', 24, 40);
                        return;
                    }}

                    var nodes = data.nodes.map(function(n) {{
                        return {{ id: n.id, x: Math.random() * canvas.width, y: Math.random() * canvas.height, vx: 0, vy: 0 }};
                    }});
                    var id2node = {{}};
                    nodes.forEach(function(n) {{ id2node[n.id] = n; }});
                    var links = data.links
                        .map(function(l) {{
                            return {{ source: id2node[l.source], target: id2node[l.target], w: l.weight, p: l.primary }};
                        }})
                        .filter(function(l) {{ return l.source && l.target; }});

                    var colors = {{ text: '#e74c3c', code: '#8e44ad', image: '#f39c12', dedup: '#27ae60', cross: '#2980b9' }};
                    var charge = -180;
                    var spring = 0.02;
                    var damper = 0.85;
                    var dragging = null;

                    function tick() {{
                        for (var i = 0; i < nodes.length; i++) {{
                            for (var j = i + 1; j < nodes.length; j++) {{
                                var a = nodes[i], b = nodes[j];
                                var dx = a.x - b.x, dy = a.y - b.y;
                                var d = Math.sqrt(dx * dx + dy * dy) + 0.01;
                                var f = charge / (d * d);
                                var fx = f * dx / d, fy = f * dy / d;
                                a.vx += fx; a.vy += fy;
                                b.vx -= fx; b.vy -= fy;
                            }}
                        }}
                        links.forEach(function(l) {{
                            var dx = l.target.x - l.source.x, dy = l.target.y - l.source.y;
                            var d = Math.sqrt(dx * dx + dy * dy) + 0.01;
                            var k = spring * (d - 120);
                            var fx = k * dx / d, fy = k * dy / d;
                            l.source.vx += fx; l.source.vy += fy;
                            l.target.vx -= fx; l.target.vy -= fy;
                        }});
                        nodes.forEach(function(n) {{
                            n.vx *= damper; n.vy *= damper;
                            n.x += n.vx; n.y += n.vy;
                            if (!n.fixed) {{
                                if (n.x < 20) n.x = 20;
                                if (n.x > canvas.width - 20) n.x = canvas.width - 20;
                                if (n.y < 20) n.y = 20;
                                if (n.y > canvas.height - 20) n.y = canvas.height - 20;
                            }}
                        }});
                    }}

                    function draw() {{
                        ctx.clearRect(0, 0, canvas.width, canvas.height);
                        links.forEach(function(l) {{
                            ctx.strokeStyle = colors[l.p] || '#95a5a6';
                            ctx.lineWidth = Math.min(1 + l.w, 6);
                            ctx.beginPath();
                            ctx.moveTo(l.source.x, l.source.y);
                            ctx.lineTo(l.target.x, l.target.y);
                            ctx.stroke();
                        }});
                        nodes.forEach(function(n) {{
                            var deg = 0;
                            links.forEach(function(l) {{ if (l.source === n || l.target === n) deg++; }});
                            ctx.fillStyle = '#3498db';
                            ctx.beginPath();
                            ctx.arc(n.x, n.y, Math.min(8 + deg, 18), 0, Math.PI * 2);
                            ctx.fill();
                            ctx.fillStyle = '#2c3e50';
                            ctx.font = '12px sans-serif';
                            ctx.fillText(n.id, n.x + 10, n.y + 4);
                        }});
                    }}

                    canvas.onmousedown = function(e) {{
                        var rect = canvas.getBoundingClientRect();
                        var mx = e.clientX - rect.left;
                        var my = e.clientY - rect.top;
                        var hit = null;
                        for (var i = 0; i < nodes.length; i++) {{
                            var n = nodes[i];
                            var dx = n.x - mx, dy = n.y - my;
                            if (dx * dx + dy * dy < 400) {{
                                hit = n;
                                break;
                            }}
                        }}
                        dragging = hit;
                        if (dragging) dragging.fixed = true;
                    }};
                    canvas.onmousemove = function(e) {{
                        if (!dragging) return;
                        var rect = canvas.getBoundingClientRect();
                        dragging.x = e.clientX - rect.left;
                        dragging.y = e.clientY - rect.top;
                    }};
                    canvas.onmouseup = function() {{
                        if (dragging) dragging.fixed = false;
                        dragging = null;
                    }};

                    function loop() {{
                        tick();
                        draw();
                        requestAnimationFrame(loop);
                    }}
                    loop();
                }}

                window.addEventListener('load', function() {{ initGraph('assoc_graph', GRAPH_DATA); }});
            </script>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>PitcherPlant Writeup 自动化审计报告</h1>
                    <div class="meta">
                        扫描时间: {_esc(datetime.now().strftime('%Y-%m-%d %H:%M:%S'))} |
                        扫描文件数: {_esc(len(self.documents))} |
                        检测引擎: TF-IDF / Jaccard / OpenCV+pHash
                    </div>
                    <div class="meta">PitcherPlant 专业文档相似度检测 · 为 CTF 比赛提供 Writeup 相似度检测与原创性验证</div>
                </div>

                <div class="summary">
                    <div class="card danger">
                        <div class="card-title">文本/代码高危相似</div>
                        <div class="card-value">{_esc(len(text_res) + len(code_res))} 对</div>
                    </div>
                    <div class="card warning">
                        <div class="card-title">图片雷同组合</div>
                        <div class="card-value">{_esc(len(img_res))} 组</div>
                    </div>
                    <div class="card info">
                        <div class="card-title">元数据碰撞</div>
                        <div class="card-value">{_esc(len(meta_res))} 组</div>
                    </div>
                </div>

                <div class="tabs">
                    <div id="btn_tab_overview" class="tab-item active" onclick="showTab('tab_overview')">事态总览</div>
                    <div id="btn_tab_text" class="tab-item" onclick="showTab('tab_text')">文本内容相似度分析</div>
                    <div id="btn_tab_code" class="tab-item" onclick="showTab('tab_code')">代码/脚本抄袭分析</div>
                    <div id="btn_tab_code_summary" class="tab-item" onclick="showTab('tab_code_summary')">[代码审计] 摘要</div>
                    <div id="btn_tab_img" class="tab-item" onclick="showTab('tab_img')">图片盗用/截图复用</div>
                    <div id="btn_tab_img_detail" class="tab-item" onclick="showTab('tab_img_detail')">图片证据详列</div>
                    <div id="btn_tab_meta" class="tab-item" onclick="showTab('tab_meta')">元数据碰撞</div>
                    <div id="btn_tab_dedup" class="tab-item" onclick="showTab('tab_dedup')">重复文件去重报告</div>
                    <div id="btn_tab_fingerprint" class="tab-item" onclick="showTab('tab_fingerprint')">文件指纹数据库</div>
                    <div id="btn_tab_cross" class="tab-item" onclick="showTab('tab_cross')">二次审计（跨批次复用）</div>
                </div>

                <div id="tab_overview" class="section tab-section" style="display:block">
                    <h2>事态总览（严重作弊关联）</h2>
                    <div class="hint" style="font-size:14px;margin-bottom:12px;">
                        基于高分文本/代码/图片相似与重复文件、跨批次复用，汇总队伍间的强关联。
                    </div>
                    <div class="overview-grid">
                        <div class="overview-graph">
                            <canvas id="assoc_graph" style="width:100%"></canvas>
                        </div>
                        <div class="overview-legend">
                            <div class="hint" style="font-size:13px;margin-bottom:8px;">关联类型图例</div>
                            <div class="legend-grid">
                                <div class="legend-item"><span class="legend-swatch" style="background:#e74c3c"></span>文本</div>
                                <div class="legend-item"><span class="legend-swatch" style="background:#8e44ad"></span>代码</div>
                                <div class="legend-item"><span class="legend-swatch" style="background:#f39c12"></span>图片</div>
                                <div class="legend-item"><span class="legend-swatch" style="background:#27ae60"></span>重复</div>
                                <div class="legend-item"><span class="legend-swatch" style="background:#2980b9"></span>跨批次</div>
                            </div>
                        </div>
                    </div>
                    <table>
                        <thead>
                            <tr>
                                <th width="30%">队伍 A</th>
                                <th width="30%">队伍 B</th>
                                <th width="15%">关联次数</th>
                                <th width="25%">关联类型</th>
                            </tr>
                        </thead>
                        <tbody>{overview_rows}</tbody>
                    </table>
                </div>

                <div id="tab_text" class="section tab-section" style="display:none">
                    <h2>文本内容相似度分析 (阈值 &gt; {_esc(self.text_threshold * 100)}%)</h2>
                    <table>
                        <thead>
                            <tr>
                                <th width="10%">相似度</th>
                                <th width="25%">文件 A</th>
                                <th width="25%">文件 B</th>
                                <th width="40%">证据</th>
                            </tr>
                        </thead>
                        <tbody>{self._render_text_rows(text_res)}</tbody>
                    </table>
                </div>

                <div id="tab_code" class="section tab-section" style="display:none">
                    <h2>代码/脚本抄袭分析 (Structure Similarity)</h2>
                    <table>
                        <thead>
                            <tr>
                                <th width="10%">重合度</th>
                                <th width="22%">文件 A</th>
                                <th width="22%">文件 B</th>
                                <th width="16%">类型</th>
                                <th width="30%">证据</th>
                            </tr>
                        </thead>
                        <tbody>{self._render_code_rows(code_res)}</tbody>
                    </table>
                </div>

                <div id="tab_code_summary" class="section tab-section" style="display:none">
                    <h2>[代码审计] 摘要</h2>
                    <div class="hint" style="font-size:14px;margin-bottom:12px">
                        这些代码对的结构性相似，综合代码指纹重合度与证据片段，选择若干代表性示例如下：
                    </div>
                    {code_summary_blocks}
                </div>

                <div id="tab_img" class="section tab-section" style="display:none">
                    <h2>图片盗用/截图复用 (Hamming Dist ≤ {_esc(self.img_threshold)})</h2>
                    <table>
                        <thead>
                            <tr>
                                <th width="15%">雷同图片数量</th>
                                <th width="42%">文件 A</th>
                                <th width="43%">文件 B</th>
                            </tr>
                        </thead>
                        <tbody>{img_rows}</tbody>
                    </table>
                </div>

                <div id="tab_img_detail" class="section tab-section" style="display:none">
                    <h2>图片证据详列</h2>
                    {self._render_image_detail(img_res)}
                </div>

                <div id="tab_meta" class="section tab-section" style="display:none">
                    <h2>元数据碰撞</h2>
                    <table>
                        <thead>
                            <tr>
                                <th width="20%">Author</th>
                                <th width="10%">涉及数量</th>
                                <th width="25%">疑似队伍</th>
                                <th width="45%">文件列表</th>
                            </tr>
                        </thead>
                        <tbody>{meta_rows}</tbody>
                    </table>
                </div>

                <div id="tab_dedup" class="section tab-section" style="display:none">
                    <h2>重复文件去重报告 (阈值 ≥ {_esc(self.dedup_threshold * 100)}%)</h2>
                    <div class="hint" style="font-size:14px;margin-bottom:12px">支持跨格式（PDF/Word）比对，以下列出疑似重复的文件对。</div>
                    <table>
                        <thead>
                            <tr>
                                <th width="10%">相似度</th>
                                <th width="24%">文件 A</th>
                                <th width="24%">文件 B</th>
                                <th width="12%">线索</th>
                                <th width="30%">预览</th>
                            </tr>
                        </thead>
                        <tbody>{dedup_rows}</tbody>
                    </table>
                </div>

                <div id="tab_fingerprint" class="section tab-section" style="display:none">
                    <h2>文件指纹数据库</h2>
                    <table>
                        <thead>
                            <tr>
                                <th width="30%">文件名</th>
                                <th width="15%">作者</th>
                                <th width="15%">扩展名</th>
                                <th width="40%">SimHash</th>
                            </tr>
                        </thead>
                        <tbody>{fingerprint_rows}</tbody>
                    </table>
                </div>

                <div id="tab_cross" class="section tab-section" style="display:none">
                    <h2>二次审计（跨批次复用）</h2>
                    <table>
                        <thead>
                            <tr>
                                <th width="12%">SimHash距</th>
                                <th width="28%">当前文件</th>
                                <th width="28%">历史文件</th>
                                <th width="12%">批次</th>
                                <th width="20%">状态</th>
                            </tr>
                        </thead>
                        <tbody>{cross_rows}</tbody>
                    </table>
                </div>

            </div>
        </body>
        </html>
        """

        scan_name = os.path.basename(self.directory.rstrip(os.sep))
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        filename_template = self.name_template or "{dir}_PitcherPlant_{date}.html"
        filename = filename_template.replace("{dir}", scan_name).replace("{date}", timestamp)
        out_dir = self.output_dir or os.path.join(os.getcwd(), "reports", scan_name)
        os.makedirs(out_dir, exist_ok=True)
        output_path = os.path.join(out_dir, filename)
        with open(output_path, "w", encoding="utf-8") as handle:
            handle.write(html_doc)
        logger.info("审计完成！报告已生成: %s", output_path)
        return output_path
