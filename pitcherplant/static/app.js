const state = {
  currentJobId: null,
  pollHandle: null,
};

function $(id) {
  return document.getElementById(id);
}

function setStatusPill(status) {
  const pill = $("health-pill");
  pill.className = `status-pill ${status}`;
  if (status === "running") {
    pill.textContent = "运行中";
  } else if (status === "succeeded") {
    pill.textContent = "已完成";
  } else if (status === "failed") {
    pill.textContent = "失败";
  } else {
    pill.textContent = "待机";
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

function updateJobView(job) {
  $("job-status-text").textContent = {
    queued: "排队中",
    running: "运行中",
    succeeded: "执行完成",
    failed: "执行失败",
  }[job.status] || "待机";

  $("job-message").textContent = job.message || "等待任务";
  $("progress-bar").style.width = `${job.progress || 0}%`;
  $("progress-text").textContent = `${job.progress || 0}%`;
  $("job-time").textContent = job.updated_at ? `更新时间 ${job.updated_at}` : "";
  setStatusPill(job.status || "idle");

  const link = $("report-link");
  const pathText = $("report-path");
  if (job.report_url) {
    link.href = job.report_url;
    link.classList.remove("disabled");
    pathText.textContent = job.report_path || "";
  } else {
    link.href = "#";
    link.classList.add("disabled");
    pathText.textContent = job.error || "任务完成后会显示报告路径。";
  }

  renderTimeline(job.events || []);
}

async function fetchDefaults() {
  const response = await fetch("/api/defaults");
  const data = await response.json();

  $("directory").value = data.directory || "";
  $("output_dir").value = data.output_dir || "";
  $("name_template").value = data.name_template || "";
  $("text_thresh").value = data.text_thresh ?? 0.75;
  $("img_thresh").value = data.img_thresh ?? 5;
  $("dedup_thresh").value = data.dedup_thresh ?? 0.85;
  $("simhash_thresh").value = data.simhash_thresh ?? 4;
  $("db_path").value = data.db_path || "";
  $("whitelist_path").value = data.whitelist_path || "";
  $("whitelist_mode").value = data.whitelist_mode || "mark";
  $("use_cv").checked = Boolean(data.use_cv);
  $("form-hint").textContent = `当前工作目录: ${data.cwd}`;

  renderPresets("scan-presets", data.scan_presets || [], "directory");
  renderPresets("report-presets", data.report_presets || [], "output_dir");
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
  }
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

function setSubmitting(submitting) {
  $("submit-button").disabled = submitting;
  $("submit-button").textContent = submitting ? "正在启动..." : "启动审计";
}

async function createJob(event) {
  event.preventDefault();
  setSubmitting(true);

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

    updateJobView(data);
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

window.addEventListener("DOMContentLoaded", async () => {
  $("audit-form").addEventListener("submit", createJob);
  bindPickers();
  renderTimeline([]);
  await fetchDefaults();
});
