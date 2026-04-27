import Foundation
@testable import PitcherPlantApp

func testWorkspaceRoot() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath)
    for _ in 0..<12 {
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Fixtures/WriteupSamples/date").path) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

let legacyReportFixtureHTML = """
<html>
<body>
<div class="card"><div class="card-title">报告数</div><div class="card-value">2</div></div>
<div class="card warning"><div class="card-title">高危</div><div class="card-value">1</div></div>
<div class="card"><div class="card-title">文件</div><div class="card-value">4</div></div>
<div id="tab_overview" class="section tab-section"><h2>总览</h2><div class="hint">整体风险可复核</div><table><tr><th>项目</th><th>值</th></tr><tr><td>样例</td><td>1</td></tr></table></div>
<div id="tab_text" class="section tab-section"><h2>文本相似分析</h2><table><tr><th>文件 A</th><th>文件 B</th><th>分数</th></tr><tr><td>a.md</td><td>b.md</td><td>0.91</td></tr></table></div>
<div id="tab_code" class="section tab-section"><h2>代码/脚本抄袭分析</h2><table><tr><th>文件 A</th><th>文件 B</th><th>分数</th></tr><tr><td>a.swift</td><td>b.swift</td><td>0.86</td></tr></table></div>
<div id="tab_image" class="section tab-section"><h2>图片证据详列</h2><table><tr><th>图片 A</th><th>图片 B</th><th>分数</th></tr><tr><td>one.png</td><td>two.png</td><td>0.94</td></tr></table></div>
<div id="tab_meta" class="section tab-section"><h2>元数据碰撞</h2><table><tr><th>字段</th><th>值</th></tr><tr><td>作者</td><td>alice</td></tr></table></div>
<div id="tab_dup" class="section tab-section"><h2>重复提交检测</h2><table><tr><th>文件 A</th><th>文件 B</th></tr><tr><td>same-a.md</td><td>same-b.md</td></tr></table></div>
<div id="tab_cross" class="section tab-section"><h2>跨批次复用</h2><table><tr><th>当前</th><th>历史</th></tr><tr><td>now.md</td><td>old.md</td></tr></table></div>
<div id="tab_summary" class="section tab-section"><h2>结论</h2><table><tr><th>结论</th><th>说明</th></tr><tr><td>复核</td><td>需要人工确认</td></tr></table></div>
</body>
</html>
"""
