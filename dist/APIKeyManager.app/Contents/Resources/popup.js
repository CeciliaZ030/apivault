const state = {
  activeTab: {
    title: "",
    url: "",
    siteName: ""
  },
  bridgeMode: "unknown",
  savedPlatforms: [],
  keyRowCount: 0,
  usageRowCount: 0
};

const refs = {};

document.addEventListener("DOMContentLoaded", () => {
  cacheRefs();
  bindEvents();
  addKeyRow();
  addUsageRow();
  initialize().catch((error) => {
    setStatus(error.message, "error");
  });
});

function cacheRefs() {
  refs.siteTitle = document.getElementById("siteTitle");
  refs.siteSubtitle = document.getElementById("siteSubtitle");
  refs.statusBanner = document.getElementById("statusBanner");
  refs.keyPanel = document.getElementById("keyPanel");
  refs.usagePanel = document.getElementById("usagePanel");
  refs.logKeyTab = document.getElementById("logKeyTab");
  refs.logUsageTab = document.getElementById("logUsageTab");
  refs.keyForm = document.getElementById("keyForm");
  refs.pageTitleInput = document.getElementById("pageTitleInput");
  refs.platformURLInput = document.getElementById("platformURLInput");
  refs.currentURLInput = document.getElementById("currentURLInput");
  refs.environmentSelect = document.getElementById("environmentSelect");
  refs.customEnvironmentRow = document.getElementById("customEnvironmentRow");
  refs.customEnvironmentInput = document.getElementById("customEnvironmentInput");
  refs.keyRows = document.getElementById("keyRows");
  refs.keyNotesInput = document.getElementById("keyNotesInput");
  refs.addKeyRowButton = document.getElementById("addKeyRowButton");
  refs.openAppButton = document.getElementById("openAppButton");
  refs.saveKeysButton = document.getElementById("saveKeysButton");
  refs.usageForm = document.getElementById("usageForm");
  refs.usagePlatformSelect = document.getElementById("usagePlatformSelect");
  refs.customUsagePlatformRow = document.getElementById("customUsagePlatformRow");
  refs.customUsagePlatformInput = document.getElementById("customUsagePlatformInput");
  refs.usageEnvironmentSelect = document.getElementById("usageEnvironmentSelect");
  refs.customUsageEnvironmentRow = document.getElementById("customUsageEnvironmentRow");
  refs.customUsageEnvironmentInput = document.getElementById("customUsageEnvironmentInput");
  refs.usageRows = document.getElementById("usageRows");
  refs.usageNotesInput = document.getElementById("usageNotesInput");
  refs.addUsageRowButton = document.getElementById("addUsageRowButton");
  refs.saveUsageButton = document.getElementById("saveUsageButton");
}

function bindEvents() {
  refs.logKeyTab.addEventListener("click", () => switchTab("key"));
  refs.logUsageTab.addEventListener("click", () => switchTab("usage"));
  refs.environmentSelect.addEventListener("change", syncKeyEnvironmentVisibility);
  refs.addKeyRowButton.addEventListener("click", addKeyRow);
  refs.openAppButton.addEventListener("click", openDashboard);
  refs.keyForm.addEventListener("submit", submitKeys);
  refs.usagePlatformSelect.addEventListener("change", syncUsagePlatformState);
  refs.usageEnvironmentSelect.addEventListener("change", syncUsageEnvironmentVisibility);
  refs.addUsageRowButton.addEventListener("click", addUsageRow);
  refs.usageForm.addEventListener("submit", submitUsage);
}

async function initialize() {
  const [tab] = await browser.tabs.query({ active: true, lastFocusedWindow: true });
  state.activeTab.title = tab?.title ?? "";
  state.activeTab.url = tab?.url ?? "";
  const host = extractHost(state.activeTab.url);

  refs.siteTitle.textContent = host || "API Key Manager";
  refs.siteSubtitle.textContent = state.activeTab.title || "Manual key and usage logger";

  state.activeTab.siteName = extractSiteName(state.activeTab.url);

  refs.currentURLInput.value = state.activeTab.url;
  refs.pageTitleInput.placeholder = state.activeTab.title || "Example: Anthropic";
  refs.platformURLInput.placeholder = state.activeTab.url || "Example: https://api.anthropic.com";

  syncKeyEnvironmentVisibility();

  try {
    const response = await sendBridgeMessage({
      id: crypto.randomUUID(),
      type: "requestStatus",
      payload: {
        statusRequest: {
          sourceURL: state.activeTab.url,
          pageTitle: state.activeTab.title
        }
      }
    });

    if (!response.ok) {
      setStatus(response.message ?? "Dashboard is not reachable. Open the app first.", "error");
      populateUsagePlatformOptions([]);
      return;
    }

    state.savedPlatforms = response.data?.savedPlatforms ?? [];
    populateUsagePlatformOptions(state.savedPlatforms);
    const unlockState = response.data?.unlockState ?? "locked";
    const bridgeLabel = state.bridgeMode === "localhost" ? "localhost fallback" : "native bridge";
    setStatus(`Connected via ${bridgeLabel}. Vault is ${unlockState}.`, "success");
  } catch (error) {
    populateUsagePlatformOptions([]);
    setStatus("Dashboard is not reachable. Open API Key Manager, then retry.", "error");
  }
}

function switchTab(tabName) {
  const isKeyTab = tabName === "key";
  refs.keyPanel.classList.toggle("active", isKeyTab);
  refs.usagePanel.classList.toggle("active", !isKeyTab);
  refs.logKeyTab.classList.toggle("active", isKeyTab);
  refs.logUsageTab.classList.toggle("active", !isKeyTab);
  refs.logKeyTab.setAttribute("aria-selected", String(isKeyTab));
  refs.logUsageTab.setAttribute("aria-selected", String(!isKeyTab));
}

function extractHost(urlString) {
  try {
    return new URL(urlString).host;
  } catch {
    return "";
  }
}

function extractSiteName(urlString) {
  try {
    const host = new URL(urlString).hostname;
    const parts = host.replace(/^www\./, "").split(".");
    return parts.length >= 2 ? parts[parts.length - 2] : parts[0];
  } catch {
    return "";
  }
}

function deriveKeyName(siteName) {
  if (!siteName) {
    return "API_KEY";
  }

  return siteName.toUpperCase().replace(/[^A-Z0-9]/g, "_") + "_API_KEY";
}

function syncKeyEnvironmentVisibility() {
  refs.customEnvironmentRow.classList.toggle("hidden", refs.environmentSelect.value !== "custom");
}

function populateUsagePlatformOptions(platforms) {
  refs.usagePlatformSelect.innerHTML = "";

  appendOption(refs.usagePlatformSelect, "", "Select platform");
  platforms.forEach((platform) => {
    appendOption(refs.usagePlatformSelect, platform.identity, platform.displayName);
  });
  appendOption(refs.usagePlatformSelect, "__custom__", "Custom");

  refs.usagePlatformSelect.value = platforms[0]?.identity ?? "";
  syncUsagePlatformState();
}

function syncUsagePlatformState() {
  const isCustom = refs.usagePlatformSelect.value === "__custom__";
  refs.customUsagePlatformRow.classList.toggle("hidden", !isCustom);
  populateUsageEnvironmentOptions();
}

function populateUsageEnvironmentOptions() {
  refs.usageEnvironmentSelect.innerHTML = "";

  const selectedPlatform = state.savedPlatforms.find(
    (platform) => platform.identity === refs.usagePlatformSelect.value
  );

  const environments = selectedPlatform?.environments ?? [];
  if (environments.length === 0) {
    appendOption(refs.usageEnvironmentSelect, "", "Select environment");
  } else {
    environments.forEach((environment) => {
      appendOption(refs.usageEnvironmentSelect, environment, titleCase(environment));
    });
  }

  appendOption(refs.usageEnvironmentSelect, "__custom__", "Custom");
  refs.usageEnvironmentSelect.value = environments[0] ?? "__custom__";
  syncUsageEnvironmentVisibility();
}

function syncUsageEnvironmentVisibility() {
  refs.customUsageEnvironmentRow.classList.toggle("hidden", refs.usageEnvironmentSelect.value !== "__custom__");
}

function appendOption(select, value, label) {
  const option = document.createElement("option");
  option.value = value;
  option.textContent = label;
  select.appendChild(option);
}

function addKeyRow() {
  state.keyRowCount += 1;
  const defaultKeyName = deriveKeyName(state.activeTab.siteName);
  const row = document.createElement("div");
  row.className = "rowCard";
  row.dataset.rowType = "key";
  row.innerHTML = `
    <div class="rowCardHeader">
      <span class="rowLabel">Key ${state.keyRowCount}</span>
      <button type="button" class="miniButton removeRowButton">-</button>
    </div>
    <div class="rowCardGrid">
      <label>
        <span>Key Name</span>
        <input class="keyNameInput" type="text" placeholder="${defaultKeyName}">
      </label>
      <label>
        <span>Value</span>
        <textarea class="keyValueInput" rows="3" placeholder="Paste key value"></textarea>
      </label>
    </div>
  `;

  row.querySelector(".removeRowButton").addEventListener("click", () => removeRow(row, refs.keyRows, addKeyRow));
  refs.keyRows.appendChild(row);
  syncRemoveButtons(refs.keyRows);
}

function addUsageRow() {
  state.usageRowCount += 1;
  const row = document.createElement("div");
  row.className = "rowCard";
  row.dataset.rowType = "usage";
  row.innerHTML = `
    <div class="rowCardHeader">
      <span class="rowLabel">Usage ${state.usageRowCount}</span>
      <button type="button" class="miniButton removeRowButton">-</button>
    </div>
    <div class="rowCardGrid">
      <label>
        <span>Usage</span>
        <input class="usageLabelInput" type="text" placeholder="Example: ANTHROPIC_API_KEY">
      </label>
      <label>
        <span>Used Site</span>
        <input class="usedSiteInput" type="text" placeholder="Example: Github">
      </label>
      <label>
        <span>Configuration Link</span>
        <input class="configurationLinkInput" type="text" placeholder="Example: github.com/environment">
      </label>
      <label>
        <span>Server IP</span>
        <input class="serverIPInput" type="text" placeholder="Optional">
      </label>
    </div>
  `;

  row.querySelector(".removeRowButton").addEventListener("click", () => removeRow(row, refs.usageRows, addUsageRow));
  refs.usageRows.appendChild(row);
  syncRemoveButtons(refs.usageRows);
}

function removeRow(row, container, addBack) {
  row.remove();
  if (container.children.length === 0) {
    addBack();
  } else {
    syncRemoveButtons(container);
  }
}

function syncRemoveButtons(container) {
  const buttons = container.querySelectorAll(".removeRowButton");
  const disable = buttons.length <= 1;
  buttons.forEach((button) => {
    button.disabled = disable;
  });
}

async function openDashboard() {
  refs.openAppButton.disabled = true;
  try {
    await sendBridgeMessage({
      id: crypto.randomUUID(),
      type: "openApp",
      payload: null
    });
    setStatus("Opening dashboard.", "success");
  } catch (error) {
    setStatus(error.message, "error");
  } finally {
    refs.openAppButton.disabled = false;
  }
}

async function submitKeys(event) {
  event.preventDefault();
  refs.saveKeysButton.disabled = true;

  const pageTitle = refs.pageTitleInput.value.trim() || state.activeTab.title || titleCase(state.activeTab.siteName) || "Untitled";

  const environment = refs.environmentSelect.value === "custom"
    ? (refs.customEnvironmentInput.value.trim() || "production")
    : refs.environmentSelect.value;

  const platformURL = refs.platformURLInput.value.trim() || state.activeTab.url;
  const defaultKeyName = deriveKeyName(state.activeTab.siteName);

  const keyRows = Array.from(refs.keyRows.querySelectorAll(".rowCard"));
  const drafts = [];

  for (const row of keyRows) {
    const keyName = row.querySelector(".keyNameInput").value.trim() || defaultKeyName;
    const apiKey = row.querySelector(".keyValueInput").value.trim();

    if (!apiKey) {
      setStatus("Key value is required.", "error");
      refs.saveKeysButton.disabled = false;
      return;
    }

    drafts.push({
      providerSlug: null,
      providerDisplayName: pageTitle,
      keyName,
      apiKey,
      platformURL,
      sourceURL: refs.currentURLInput.value,
      pageTitle,
      notes: refs.keyNotesInput.value,
      environment,
      capturedAt: new Date().toISOString()
    });
  }

  try {
    for (const draft of drafts) {
      const response = await sendBridgeMessage({
        id: crypto.randomUUID(),
        type: "saveDraft",
        payload: { draft }
      });

      if (!response.ok) {
        throw new Error(response.message ?? "Save failed.");
      }
    }

    clearKeyRows();
    refs.keyNotesInput.value = "";
    setStatus(`Saved ${drafts.length} key${drafts.length === 1 ? "" : "s"}.`, "success");
    await refreshPlatforms();
  } catch (error) {
    setStatus(error.message, "error");
  } finally {
    refs.saveKeysButton.disabled = false;
  }
}

async function submitUsage(event) {
  event.preventDefault();
  refs.saveUsageButton.disabled = true;

  const selectedIdentity = refs.usagePlatformSelect.value;
  const isCustomPlatform = selectedIdentity === "__custom__";
  const platform = state.savedPlatforms.find((item) => item.identity === selectedIdentity);
  const sourceProviderDisplayName = isCustomPlatform
    ? refs.customUsagePlatformInput.value.trim()
    : platform?.displayName ?? "";

  if (!sourceProviderDisplayName) {
    setStatus("Source platform is required.", "error");
    refs.saveUsageButton.disabled = false;
    return;
  }

  const sourceEnvironment = refs.usageEnvironmentSelect.value === "__custom__"
    ? refs.customUsageEnvironmentInput.value.trim()
    : refs.usageEnvironmentSelect.value;

  if (!sourceEnvironment) {
    setStatus("Source environment is required.", "error");
    refs.saveUsageButton.disabled = false;
    return;
  }

  const usageRows = Array.from(refs.usageRows.querySelectorAll(".rowCard"));
  const drafts = [];

  for (const row of usageRows) {
    const usage = row.querySelector(".usageLabelInput").value.trim();
    const usedSite = row.querySelector(".usedSiteInput").value.trim();
    const configurationLink = row.querySelector(".configurationLinkInput").value.trim();
    const serverIP = row.querySelector(".serverIPInput").value.trim();

    if (!usage || !usedSite) {
      setStatus("Every usage row needs both Usage and Used Site.", "error");
      refs.saveUsageButton.disabled = false;
      return;
    }

    drafts.push({
      sourceProviderIdentity: isCustomPlatform ? null : platform?.identity ?? null,
      sourceProviderDisplayName,
      sourceEnvironment,
      usage,
      usedSite,
      configurationLink,
      serverIP,
      currentURL: state.activeTab.url,
      notes: refs.usageNotesInput.value,
      loggedAt: new Date().toISOString()
    });
  }

  try {
    for (const usageLogDraft of drafts) {
      const response = await sendBridgeMessage({
        id: crypto.randomUUID(),
        type: "saveUsageLog",
        payload: { usageLogDraft }
      });

      if (!response.ok) {
        throw new Error(response.message ?? "Usage log failed.");
      }
    }

    clearUsageRows();
    refs.usageNotesInput.value = "";
    setStatus(`Logged ${drafts.length} usage entr${drafts.length === 1 ? "y" : "ies"}.`, "success");
  } catch (error) {
    setStatus(error.message, "error");
  } finally {
    refs.saveUsageButton.disabled = false;
  }
}

function clearKeyRows() {
  refs.keyRows.innerHTML = "";
  state.keyRowCount = 0;
  addKeyRow();
}

function clearUsageRows() {
  refs.usageRows.innerHTML = "";
  state.usageRowCount = 0;
  addUsageRow();
}

async function refreshPlatforms() {
  try {
    const response = await sendBridgeMessage({
      id: crypto.randomUUID(),
      type: "requestStatus",
      payload: {
        statusRequest: {
          sourceURL: state.activeTab.url,
          pageTitle: state.activeTab.title
        }
      }
    });

    if (response.ok) {
      state.savedPlatforms = response.data?.savedPlatforms ?? [];
      populateUsagePlatformOptions(state.savedPlatforms);
    }
  } catch {
    // Ignore refresh failures and keep the current popup state.
  }
}

function titleCase(value) {
  if (!value) {
    return value;
  }

  return value.charAt(0).toUpperCase() + value.slice(1);
}

function setStatus(message, kind) {
  refs.statusBanner.textContent = message;
  refs.statusBanner.className = "status";
  if (kind) {
    refs.statusBanner.classList.add(kind);
  }
}

async function sendNativeMessage(message) {
  state.bridgeMode = "native";
  return browser.runtime.sendNativeMessage(message);
}

async function sendBridgeMessage(message) {
  try {
    return await sendNativeMessage(message);
  } catch (nativeError) {
    return sendLocalhostBridge(message, nativeError);
  }
}

async function sendLocalhostBridge(message, nativeError) {
  state.bridgeMode = "localhost";

  const response = await fetch("http://localhost:38173/bridge", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(message)
  }).catch(() => {
    throw nativeError ?? new Error("Dashboard is not reachable. Open API Key Manager, then retry.");
  });

  if (!response.ok) {
    throw new Error("Dashboard is not reachable. Open API Key Manager, then retry.");
  }

  return response.json();
}
