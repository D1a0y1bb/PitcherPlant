import html
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
                        <button class="toggle" onclick="togglePanel('tctx_{idx}')">展开细节</button>
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
                        <button class="toggle" onclick="togglePanel('cctx_{idx}')">展开代码证据</button>
                        <div id="cctx_{idx}" class="panel">
                            <div class="snippet">A代码：{_esc(item.get('evidence_a', ''))}</div>
                            <div class="snippet">B代码：{_esc(item.get('evidence_b', ''))}</div>
                        </div>
                    </td>
                </tr>
                """
            )
        return "".join(rows)

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
                    <button class="toggle" onclick="togglePanel('ictx_{idx}')">展开图片证据</button>
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
                    </div>
                </div>
                """
            )
        return "".join(blocks)

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

        dedup_rows = "".join(
            [
                f"""
                <tr>
                    <td><span class="badge {'high' if item['score'] > 90 else 'med'}">{_esc(item['score'])}%</span></td>
                    <td class="file-name">{_esc(item['file_a'])}</td>
                    <td class="file-name">{_esc(item['file_b'])}</td>
                    <td>{_esc('跨格式' if item['cross_format'] else '')} {_esc(item.get('team_hint', ''))}</td>
                    <td><div class="snippet">{_esc(item['evidence'])}</div></td>
                </tr>
                """
                for item in dedup_res
            ]
        )

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
                @media (max-width: 768px) {{
                    body {{ padding: 0; }}
                    .summary {{ grid-template-columns: 1fr; }}
                    .tabs {{ padding: 12px 16px; }}
                    .section {{ padding: 24px 16px; }}
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
                    <div id="btn_tab_text" class="tab-item" onclick="showTab('tab_text')">文本相似</div>
                    <div id="btn_tab_code" class="tab-item" onclick="showTab('tab_code')">代码相似</div>
                    <div id="btn_tab_img" class="tab-item" onclick="showTab('tab_img')">图片复用</div>
                    <div id="btn_tab_img_detail" class="tab-item" onclick="showTab('tab_img_detail')">图片证据</div>
                    <div id="btn_tab_meta" class="tab-item" onclick="showTab('tab_meta')">元数据</div>
                    <div id="btn_tab_dedup" class="tab-item" onclick="showTab('tab_dedup')">重复文件</div>
                    <div id="btn_tab_fingerprint" class="tab-item" onclick="showTab('tab_fingerprint')">文件指纹</div>
                    <div id="btn_tab_cross" class="tab-item" onclick="showTab('tab_cross')">跨批次复用</div>
                </div>

                <div id="tab_overview" class="section tab-section" style="display:block">
                    <h2>事态总览</h2>
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
                    <h2>代码/脚本抄袭分析</h2>
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
