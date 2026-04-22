const FORM_STORAGE_KEY = "pitcherplant:web-form:v2";

const state = {
  currentJobId: null,
  pollHandle: null,
  jobs: [],
};

function $(id) {
  return document.getElementById(id);
}

function basename(value) {
  if (!value) {
    return "";
  }
  const normalized = String(value).replace(/[\\/]+$/, "");
  const parts = normalized.split(/[\\/]/);
  return parts[parts.length - 1] || normalized;
}

function formatStatus(status) {
  return {
    queued: "排队中",
    running: "运行中",
    succeeded: "执行完成",
    failed: "执行失败",
  }[status] || "待机";
}

function setInteractiveLink(element, href, disabledText = "#") {
  if (!element) {
    return;
  }
  if (href) {
    element.href = href;
    element.classList.remove("disabled");
  } else {
    element.href = disabledText;
    element.classList.add("disabled");
  }
}

function setStatusPill(status) {
  const pill = $("health-pill");
  pill.className = `status-pill ${status}`;
  pill.textContent = {
    queued: "排队中",
    running: "运行中",
    succeeded: "已完成",
    failed: "失败",
  }[status] || "待机";
}

function readForm() {
  return {
    directory: $("directory").value.trim(),
    output_dir: $("output_dir").value.trim(),
    name_template: $("name_template").value.trim(),
    text_thresh: Number($("text_thresh").value),
    img_thresh: Number($("img_thresh").value),
    dedup_thresh: Number($("dedup_thresh").value),
    simhash_thresh: Number($("simhash_thresh").value),
    db_path: $("db_path").value.trim(),
    whitelist_path: $("whitelist_path").value.trim(),
    whitelist_mode: $("whitelist_mode").value,
    use_cv: $("use_cv").checked,
  };
}

function applyFormData(data) {
  if (!data) {
    return;
  }
  const mapping = {
    directory: "directory",
    output_dir: "output_dir",
    name_template: "name_template",
    text_thresh: "text_thresh",
    img_thresh: "img_thresh",
    dedup_thresh: "dedup_thresh",
    simhash_thresh: "simhash_thresh",
    db_path: "db_path",
    whitelist_path: "whitelist_path",
    whitelist_mode: "whitelist_mode",
  };

  for (const [key, elementId] of Object.entries(mapping)) {
    if (Object.prototype.hasOwnProperty.call(data, key) && data[key] !== null && data[key] !== undefined) {
      $(elementId).value = data[key];
    }
  }

  if (Object.prototype.hasOwnProperty.call(data, "use_cv")) {
    $("use_cv").checked = Boolean(data.use_cv);
  }
}

function saveFormDraft() {
  try {
    window.localStorage.setItem(FORM_STORAGE_KEY, JSON.stringify(readForm()));
  } catch (_) {
    // 忽略本地存储异常
  }
}

function loadFormDraft() {
  try {
    const raw = window.localStorage.getItem(FORM_STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (_) {
    return null;
  }
}

function renderPresets(containerId, items, targetId) {
  const host = $(containerId);
  host.innerHTML = "";
  if (!items || !items.length) {
    const empty = document.createElement("span");
    empty.className = "form-hint";
    empty.textContent = "当前没有可用预设。";
    host.appendChild(empty);
    return;
  }

  for (const item of items) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "chip-button";
    button.textContent = item.label;
    button.addEventListener("click", () => {
      $(targetId).value = item.path;
      saveFormDraft();
    });
    host.appendChild(button);
  }
}

function renderTimeline(events) {
  const timeline = $("timeline");
  timeline.innerHTML = "";
  if (!events || !events.length) {
    const item = document.createElement("li");
    item.className = "timeline-item";
    item.innerHTML = `<span class="timeline-time">--:--:--</span><span class="timeline-message">等待任务</span><span class="timeline-progress">0%</span>`;
    timeline.appendChild(item);
    return;
  }

  for (const event of [...events].reverse()) {
    const item = document.createElement("li");
    item.className = "timeline-item";
    const timeText = (event.timestamp || "").split(" ").pop() || "--:--:--";
    item.innerHTML = `
      <span class="timeline-time">${timeText}</span>
      <span class="timeline-message">${event.message || ""}</span>
      <span class="timeline-progress">${event.progress ?? 0}%</span>
    `;
    timeline.appendChild(item);
  }
}

function resetCurrentView() {
  $("job-status-text").textContent = "待机";
  $("job-message").textContent = "等待任务";
  $("progress-bar").style.width = "0%";
  $("progress-text").textContent = "0%";
  $("job-time").textContent = "";
  $("report-path").textContent = "任务完成后会显示报告路径。";
  setInteractiveLink($("report-link"), null);
  setStatusPill("idle");
  renderTimeline([]);
}

function updateRecentReport(job) {
  const link = $("recent-report-link");
  const shortcut = $("latest-report-shortcut");
  const pathText = $("recent-report-path");

  if (job && job.report_url) {
    setInteractiveLink(link, job.report_url);
    setInteractiveLink(shortcut, job.report_url);
    const sourceName = basename(job.report_path) || basename(job.directory) || job.id;
    pathText.textContent = `${sourceName} · ${job.report_path}`;
  } else {
    setInteractiveLink(link, null);
    setInteractiveLink(shortcut, null);
    pathText.textContent = "历史成功任务会在这里显示最近一份报告。";
  }
}

function updateJobView(job) {
  if (!job) {
    resetCurrentView();
    return;
  }

  $("job-status-text").textContent = formatStatus(job.status);
  $("job-message").textContent = job.message || "等待任务";
  $("progress-bar").style.width = `${job.progress || 0}%`;
  $("progress-text").textContent = `${job.progress || 0}%`;
  $("job-time").textContent = job.updated_at ? `更新时间 ${job.updated_at}` : "";
  setStatusPill(job.status || "idle");

  if (job.report_url) {
    setInteractiveLink($("report-link"), job.report_url);
    $("report-path").textContent = job.report_path || "";
  } else {
    setInteractiveLink($("report-link"), null);
    $("report-path").textContent = job.error || job.report_path || "任务完成后会显示报告路径。";
  }

  renderTimeline(job.events || []);
}

function renderHistoryList(jobs) {
  const host = $("history-list");
  host.innerHTML = "";
  $("history-meta").textContent = `保留最近 ${jobs.length} 条任务`;

  if (!jobs.length) {
    const item = document.createElement("li");
    item.className = "history-item";
    item.innerHTML = `<div class="history-main"><div class="history-name">暂无历史任务</div><div class="history-meta-row"><span>运行过的任务会显示在这里。</span></div></div>`;
    host.appendChild(item);
    return;
  }

  for (const job of jobs) {
    const item = document.createElement("li");
    item.className = "history-item";
    if (job.id === state.currentJobId) {
      item.classList.add("active");
    }

    const main = document.createElement("div");
    main.className = "history-main";

    const title = document.createElement("div");
    title.className = "history-title";

    const badge = document.createElement("span");
    badge.className = `history-badge ${job.status}`;
    badge.textContent = formatStatus(job.status);

    const name = document.createElement("span");
    name.className = "history-name";
    name.textContent = basename(job.directory) || basename(job.report_path) || job.id;

    title.appendChild(badge);
    title.appendChild(name);
    main.appendChild(title);

    const meta = document.createElement("div");
    meta.className = "history-meta-row";
    [
      job.updated_at || "",
      `${job.progress || 0}%`,
      job.message || "",
      job.report_url ? "含报告" : "无报告",
    ]
      .filter(Boolean)
      .forEach((text) => {
        const span = document.createElement("span");
        span.textContent = text;
        meta.appendChild(span);
      });
    main.appendChild(meta);

    const actions = document.createElement("div");
    actions.className = "history-actions";

    const viewButton = document.createElement("button");
    viewButton.type = "button";
    viewButton.className = "history-button";
    viewButton.textContent = "查看";
    viewButton.addEventListener("click", () => {
      state.currentJobId = job.id;
      updateJobView(job);
      renderHistoryList(state.jobs);
      if (job.status === "queued" || job.status === "running") {
        pollJob();
      }
    });
    actions.appendChild(viewButton);

    if (job.report_url) {
      const reportLink = document.createElement("a");
      reportLink.className = "history-button";
      reportLink.href = job.report_url;
      reportLink.target = "_blank";
      reportLink.rel = "noopener noreferrer";
      reportLink.textContent = "报告";
      actions.appendChild(reportLink);
    }

    item.appendChild(main);
    item.appendChild(actions);
    host.appendChild(item);
  }
}

async function fetchDefaults() {
  const response = await fetch("/api/defaults");
  const data = await response.json();
  applyFormData(data);
  $("form-hint").textContent = `当前工作目录: ${data.cwd}`;

  renderPresets("scan-presets", data.scan_presets || [], "directory");
  renderPresets("report-presets", data.report_presets || [], "output_dir");
  updateRecentReport(data.latest_report || null);
}

async function fetchJobsList(options = {}) {
  const { syncCurrent = true } = options;
  const response = await fetch("/api/jobs");
  const jobs = await response.json();
  if (!response.ok) {
    throw new Error(jobs.error || "历史任务读取失败");
  }

  state.jobs = Array.isArray(jobs) ? jobs : [];
  renderHistoryList(state.jobs);

  const latestSuccess = state.jobs.find((job) => job.report_url) || null;
  updateRecentReport(latestSuccess);

  if (!syncCurrent) {
    return;
  }

  if (state.currentJobId) {
    const selected = state.jobs.find((job) => job.id === state.currentJobId);
    if (selected) {
      updateJobView(selected);
      return;
    }
  }

  if (state.jobs.length) {
    state.currentJobId = state.jobs[0].id;
    updateJobView(state.jobs[0]);
  } else {
    resetCurrentView();
  }
}

async function pickDirectory(targetId) {
  const response = await fetch("/api/pick-directory", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ initial: $(targetId).value }),
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "目录选择失败");
  }
  if (data.path) {
    $(targetId).value = data.path;
    saveFormDraft();
  }
}

function setSubmitting(submitting) {
  $("submit-button").disabled = submitting;
  $("submit-button").textContent = submitting ? "正在启动..." : "启动审计";
}

async function createJob(event) {
  event.preventDefault();
  setSubmitting(true);
  saveFormDraft();

  try {
    const response = await fetch("/api/jobs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(readForm()),
    });
    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.error || "任务创建失败");
    }

    state.currentJobId = data.id;
    updateJobView(data);
    await fetchJobsList({ syncCurrent: false });
    pollJob();
  } catch (error) {
    setStatusPill("failed");
    $("job-status-text").textContent = "执行失败";
    $("job-message").textContent = error.message;
    $("report-path").textContent = error.message;
    renderTimeline([{ timestamp: "", message: error.message, progress: 0 }]);
  } finally {
    setSubmitting(false);
  }
}

async function pollJob() {
  if (!state.currentJobId) {
    return;
  }

  if (state.pollHandle) {
    window.clearTimeout(state.pollHandle);
  }

  try {
    const response = await fetch(`/api/jobs/${state.currentJobId}`);
    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.error || "任务查询失败");
    }

    const index = state.jobs.findIndex((job) => job.id === data.id);
    if (index >= 0) {
      state.jobs[index] = data;
    }

    updateJobView(data);
    await fetchJobsList({ syncCurrent: false });
    renderHistoryList(state.jobs);

    if (data.status === "queued" || data.status === "running") {
      state.pollHandle = window.setTimeout(pollJob, 1000);
    }
  } catch (error) {
    setStatusPill("failed");
    $("job-message").textContent = error.message;
  }
}

function bindPickers() {
  document.querySelectorAll("[data-pick-target]").forEach((button) => {
    button.addEventListener("click", async () => {
      const targetId = button.getAttribute("data-pick-target");
      try {
        await pickDirectory(targetId);
      } catch (error) {
        setStatusPill("failed");
        $("job-message").textContent = error.message;
      }
    });
  });
}

function bindDraftPersistence() {
  document.querySelectorAll("#audit-form input, #audit-form select").forEach((element) => {
    const handler = () => saveFormDraft();
    element.addEventListener("input", handler);
    element.addEventListener("change", handler);
  });
}

window.addEventListener("DOMContentLoaded", async () => {
  $("audit-form").addEventListener("submit", createJob);
  bindPickers();
  bindDraftPersistence();
  renderTimeline([]);

  await fetchDefaults();
  const draft = loadFormDraft();
  applyFormData(draft);
  await fetchJobsList();
});
