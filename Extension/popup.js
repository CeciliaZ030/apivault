const state = {
  activeTab: {
    title: "",
    url: "",
    siteName: "",
    host: ""
  },
  bridgeMode: "unknown",
  savedPlatforms: [],
  restoredDraft: null
};

const refs = {};
const DRAFT_STORAGE_KEY = "api-key-manager-popup-drafts-v1";

document.addEventListener("DOMContentLoaded", () => {
  cacheRefs();
  bindEvents();
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
  refs.removeKeyRowButton = document.getElementById("removeKeyRowButton");
  refs.addKeyRowButton = document.getElementById("addKeyRowButton");
  refs.openAppButton = document.getElementById("openAppButton");
  refs.clearKeysButton = document.getElementById("clearKeysButton");
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
  refs.removeUsageRowButton = document.getElementById("removeUsageRowButton");
  refs.addUsageRowButton = document.getElementById("addUsageRowButton");
  refs.clearUsageButton = document.getElementById("clearUsageButton");
  refs.saveUsageButton = document.getElementById("saveUsageButton");
}

function bindEvents() {
  refs.logKeyTab.addEventListener("click", () => switchTab("key"));
  refs.logUsageTab.addEventListener("click", () => switchTab("usage"));
  refs.environmentSelect.addEventListener("change", syncKeyEnvironmentVisibility);
  refs.removeKeyRowButton.addEventListener("click", () => removeLastRow(refs.keyRows, () => createKeyRow()));
  refs.addKeyRowButton.addEventListener("click", () => {
    createKeyRow();
    void persistDraft();
  });
  refs.openAppButton.addEventListener("click", openDashboard);
  refs.clearKeysButton.addEventListener("click", clearKeyDraft);
  refs.keyForm.addEventListener("submit", submitKeys);
  refs.keyForm.addEventListener("input", handleDraftMutation);
  refs.keyForm.addEventListener("change", handleDraftMutation);
  refs.usagePlatformSelect.addEventListener("change", syncUsagePlatformState);
  refs.usageEnvironmentSelect.addEventListener("change", syncUsageEnvironmentVisibility);
  refs.removeUsageRowButton.addEventListener("click", () => removeLastRow(refs.usageRows, () => createUsageRow()));
  refs.addUsageRowButton.addEventListener("click", () => {
    createUsageRow();
    void persistDraft();
  });
  refs.clearUsageButton.addEventListener("click", clearUsageDraft);
  refs.usageForm.addEventListener("submit", submitUsage);
  refs.usageForm.addEventListener("input", handleDraftMutation);
  refs.usageForm.addEventListener("change", handleDraftMutation);
}

async function initialize() {
  const [tab] = await browser.tabs.query({ active: true, lastFocusedWindow: true });
  state.activeTab.title = tab?.title ?? "";
  state.activeTab.url = tab?.url ?? "";
  const host = extractHost(state.activeTab.url);
  state.activeTab.host = host;

  refs.siteTitle.textContent = host || "Apivault";
  refs.siteSubtitle.textContent = state.activeTab.title || "Manual key and usage logger";

  state.activeTab.siteName = extractSiteName(state.activeTab.url);

  refs.currentURLInput.value = state.activeTab.url;
  await restoreDraft();

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
    applyRestoredUsageSelection();
    const unlockState = response.data?.unlockState ?? "locked";
    const bridgeLabel = state.bridgeMode === "localhost" ? "localhost fallback" : "native bridge";
    setStatus(`Connected via ${bridgeLabel}. Vault is ${unlockState}.`, "success");
  } catch (error) {
    populateUsagePlatformOptions([]);
    applyRestoredUsageSelection();
    setStatus("Dashboard is not reachable. Open Apivault, then retry.", "error");
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
  void persistDraft();
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
  refreshAllUsageKeySelects();
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
  refreshAllUsageKeySelects();
}

function appendOption(select, value, label) {
  const option = document.createElement("option");
  option.value = value;
  option.textContent = label;
  select.appendChild(option);
}

function createKeyRow(initialValues = {}) {
  const defaultKeyName = deriveKeyName(state.activeTab.siteName);
  const row = document.createElement("div");
  row.className = "rowCard";
  row.dataset.rowType = "key";
  row.innerHTML = `
    <div class="rowCardGrid">
      <label>
        <span>Key Name</span>
        <input class="keyNameInput" type="text" placeholder="${defaultKeyName}" value="${escapeAttribute(initialValues.keyName ?? "")}">
      </label>
      <label>
        <span>Value</span>
        <textarea class="keyValueInput" rows="3" placeholder="Paste key value">${escapeHTML(initialValues.apiKey ?? "")}</textarea>
      </label>
    </div>
  `;

  refs.keyRows.appendChild(row);
  syncRemoveButtons(refs.keyRows);
  return row;
}

function createUsageRow(initialValues = {}) {
  const row = document.createElement("div");
  row.className = "rowCard";
  row.dataset.rowType = "usage";
  row.innerHTML = `
    <div class="rowCardGrid">
      <label>
        <span>Key</span>
        <select class="usageLabelInput"></select>
      </label>
      <label>
        <span>Usage Profile</span>
        <select class="usageProfileSelect"></select>
      </label>
      <label class="usedSiteLabel">
        <span>Used Site</span>
        <input class="usedSiteInput" type="text" placeholder="Example: Github" value="${escapeAttribute(initialValues.usedSite ?? "")}">
      </label>
      <label class="configurationLinkLabel">
        <span>Configuration Link</span>
        <input class="configurationLinkInput" type="text" placeholder="Example: github.com/environment" value="${escapeAttribute(initialValues.configurationLink ?? "")}">
      </label>
      <label class="serverIPLabel">
        <span>Server IP</span>
        <input class="serverIPInput" type="text" placeholder="Optional" value="${escapeAttribute(initialValues.serverIP ?? "")}">
      </label>
    </div>
  `;

  refs.usageRows.appendChild(row);

  const keySelect = row.querySelector(".usageLabelInput");
  const profileSelect = row.querySelector(".usageProfileSelect");

  populateUsageKeySelect(keySelect, initialValues.usage ?? "");
  populateUsageProfileSelect(profileSelect, initialValues.usageProfile ?? "");
  syncUsageRowVisibility(row);

  profileSelect.addEventListener("change", () => {
    applyUsageProfile(row);
    void persistDraft();
  });

  syncRemoveButtons(refs.usageRows);
  return row;
}

function getUsageProfiles() {
  const platform = state.savedPlatforms.find(
    (p) => p.identity === refs.usagePlatformSelect.value
  );
  const env = refs.usageEnvironmentSelect.value === "__custom__"
    ? refs.customUsageEnvironmentInput.value.trim()
    : refs.usageEnvironmentSelect.value;
  return (platform?.usageProfiles ?? {})[env] ?? [];
}

function populateUsageKeySelect(select, selectedValue) {
  select.innerHTML = "";
  const platform = state.savedPlatforms.find(
    (p) => p.identity === refs.usagePlatformSelect.value
  );
  const env = refs.usageEnvironmentSelect.value === "__custom__"
    ? refs.customUsageEnvironmentInput.value.trim()
    : refs.usageEnvironmentSelect.value;
  const keys = (platform?.keys ?? {})[env] ?? [];

  if (keys.length === 0) {
    appendOption(select, "", "No keys available");
  } else {
    appendOption(select, "", "Select key");
    keys.forEach((key) => appendOption(select, key, key));
  }

  if (selectedValue) {
    select.value = selectedValue;
  }
}

function populateUsageProfileSelect(select, selectedValue) {
  select.innerHTML = "";
  const profiles = getUsageProfiles();

  appendOption(select, "__new__", "New");
  const seen = new Set();
  profiles.forEach((profile, index) => {
    const label = `${profile.usedSite}${profile.configurationLink ? " \u2014 " + profile.configurationLink : ""}`;
    const dedup = label.toLowerCase();
    if (!seen.has(dedup)) {
      seen.add(dedup);
      appendOption(select, String(index), label);
    }
  });

  if (selectedValue) {
    select.value = selectedValue;
  }
}

function applyUsageProfile(row) {
  const profileSelect = row.querySelector(".usageProfileSelect");
  const val = profileSelect.value;
  syncUsageRowVisibility(row);

  if (val === "__new__") {
    return;
  }

  const profiles = getUsageProfiles();
  const profile = profiles[parseInt(val, 10)];
  if (!profile) return;

  row.querySelector(".usedSiteInput").value = profile.usedSite ?? "";
  row.querySelector(".configurationLinkInput").value = profile.configurationLink ?? "";
  row.querySelector(".serverIPInput").value = profile.serverIP ?? "";
}

function syncUsageRowVisibility(row) {
  const isNew = row.querySelector(".usageProfileSelect").value === "__new__";
  const profiles = getUsageProfiles();
  const hasProfiles = profiles.length > 0;

  row.querySelector(".usedSiteLabel").classList.toggle("hidden", !isNew && hasProfiles);
  row.querySelector(".configurationLinkLabel").classList.toggle("hidden", !isNew && hasProfiles);
  row.querySelector(".serverIPLabel").classList.toggle("hidden", !isNew && hasProfiles);
}

function refreshAllUsageKeySelects() {
  const rows = refs.usageRows.querySelectorAll(".rowCard");
  rows.forEach((row) => {
    const keySelect = row.querySelector(".usageLabelInput");
    const profileSelect = row.querySelector(".usageProfileSelect");
    const currentKey = keySelect.value;
    const currentProfile = profileSelect.value;
    populateUsageKeySelect(keySelect, currentKey);
    populateUsageProfileSelect(profileSelect, currentProfile);
    syncUsageRowVisibility(row);
  });
}

function removeLastRow(container, addBack) {
  const lastRow = container.lastElementChild;
  if (lastRow) {
    lastRow.remove();
  }

  if (container.children.length === 0) {
    addBack();
  }

  syncRemoveButtons(container);
  void persistDraft();
}

function syncRemoveButtons(container) {
  const disable = container.children.length <= 1;
  if (container === refs.keyRows) {
    refs.removeKeyRowButton.disabled = disable;
  }
  if (container === refs.usageRows) {
    refs.removeUsageRowButton.disabled = disable;
  }
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

    clearKeyFormFields();
    await persistDraft();
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
    const profileVal = row.querySelector(".usageProfileSelect").value;
    const profiles = getUsageProfiles();
    const isProfileSelected = profileVal !== "__new__" && profiles.length > 0;
    const profile = isProfileSelected ? profiles[parseInt(profileVal, 10)] : null;

    const usedSite = profile ? (profile.usedSite ?? "") : row.querySelector(".usedSiteInput").value.trim();
    const configurationLink = profile ? (profile.configurationLink ?? "") : row.querySelector(".configurationLinkInput").value.trim();
    const serverIP = profile ? (profile.serverIP ?? "") : row.querySelector(".serverIPInput").value.trim();

    if (!usage || !usedSite) {
      setStatus("Every usage row needs both Key and Used Site.", "error");
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

    clearUsageFormFields();
    await persistDraft();
    setStatus(`Logged ${drafts.length} usage entr${drafts.length === 1 ? "y" : "ies"}.`, "success");
    await refreshPlatforms();
  } catch (error) {
    setStatus(error.message, "error");
  } finally {
    refs.saveUsageButton.disabled = false;
  }
}

function clearKeyRows() {
  refs.keyRows.innerHTML = "";
  createKeyRow();
}

function clearUsageRows() {
  refs.usageRows.innerHTML = "";
  createUsageRow();
}

function clearKeyFormFields() {
  refs.pageTitleInput.value = "";
  refs.platformURLInput.value = "";
  refs.environmentSelect.value = "production";
  refs.customEnvironmentInput.value = "";
  refs.keyNotesInput.value = "";
  syncKeyEnvironmentVisibility();
  clearKeyRows();
}

function clearUsageFormFields() {
  refs.customUsagePlatformInput.value = "";
  refs.customUsageEnvironmentInput.value = "";
  refs.usageNotesInput.value = "";
  refs.usagePlatformSelect.value = state.savedPlatforms[0]?.identity ?? "";
  syncUsagePlatformState();
  clearUsageRows();
}

async function clearKeyDraft() {
  clearKeyFormFields();
  await persistDraft();
  setStatus("Cleared key draft.", "success");
}

async function clearUsageDraft() {
  clearUsageFormFields();
  await persistDraft();
  setStatus("Cleared usage draft.", "success");
}

function handleDraftMutation() {
  void persistDraft();
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
      applyRestoredUsageSelection();
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

function restoreDefaults() {
  refs.pageTitleInput.placeholder = state.activeTab.title || "Example: Anthropic";
  refs.platformURLInput.placeholder = state.activeTab.url || "Example: https://api.anthropic.com";
  refs.currentURLInput.value = state.activeTab.url;
  refs.environmentSelect.value = "production";
  syncKeyEnvironmentVisibility();
  if (!refs.keyRows.children.length) {
    createKeyRow();
  }
  if (!refs.usageRows.children.length) {
    createUsageRow();
  }
}

function draftScopeKey() {
  return state.activeTab.host || "_global";
}

async function restoreDraft() {
  let storedDrafts = {};
  try {
    const result = await browser.storage.local.get(DRAFT_STORAGE_KEY);
    storedDrafts = result[DRAFT_STORAGE_KEY] ?? {};
  } catch {
    restoreDefaults();
    return;
  }

  const draft = storedDrafts[draftScopeKey()];
  if (!draft) {
    restoreDefaults();
    return;
  }

  state.restoredDraft = draft;
  applyDraft(draft);
}

function applyDraft(draft) {
  restoreDefaults();

  if (draft.activeTab === "usage") {
    switchTab("usage");
  } else {
    switchTab("key");
  }

  const keyForm = draft.keyForm ?? {};
  refs.pageTitleInput.value = keyForm.pageTitle ?? "";
  refs.platformURLInput.value = keyForm.platformURL ?? "";
  refs.environmentSelect.value = keyForm.environment ?? "production";
  refs.customEnvironmentInput.value = keyForm.customEnvironment ?? "";
  refs.keyNotesInput.value = keyForm.notes ?? "";
  syncKeyEnvironmentVisibility();

  refs.keyRows.innerHTML = "";
  const keyRows = Array.isArray(keyForm.rows) && keyForm.rows.length ? keyForm.rows : [{}];
  keyRows.forEach((row) => createKeyRow(row));

  const usageForm = draft.usageForm ?? {};
  refs.customUsagePlatformInput.value = usageForm.customPlatform ?? "";
  refs.customUsageEnvironmentInput.value = usageForm.customEnvironment ?? "";
  refs.usageNotesInput.value = usageForm.notes ?? "";
  refs.usageRows.innerHTML = "";
  const usageRows = Array.isArray(usageForm.rows) && usageForm.rows.length ? usageForm.rows : [{}];
  usageRows.forEach((row) => createUsageRow(row));

  if (usageForm.platformIdentity) {
    refs.usagePlatformSelect.value = usageForm.platformIdentity;
  }
  syncUsagePlatformState();
  if (usageForm.environment) {
    refs.usageEnvironmentSelect.value = usageForm.environment;
  }
  syncUsageEnvironmentVisibility();
}

function applyRestoredUsageSelection() {
  const usageForm = state.restoredDraft?.usageForm;
  if (!usageForm) {
    return;
  }

  if (usageForm.platformIdentity) {
    refs.usagePlatformSelect.value = usageForm.platformIdentity;
  }
  syncUsagePlatformState();

  if (usageForm.environment) {
    refs.usageEnvironmentSelect.value = usageForm.environment;
  }
  refs.customUsagePlatformInput.value = usageForm.customPlatform ?? refs.customUsagePlatformInput.value;
  refs.customUsageEnvironmentInput.value = usageForm.customEnvironment ?? refs.customUsageEnvironmentInput.value;
  syncUsageEnvironmentVisibility();
}

function collectDraft() {
  return {
    activeTab: refs.logUsageTab.classList.contains("active") ? "usage" : "key",
    keyForm: {
      pageTitle: refs.pageTitleInput.value,
      platformURL: refs.platformURLInput.value,
      environment: refs.environmentSelect.value,
      customEnvironment: refs.customEnvironmentInput.value,
      notes: refs.keyNotesInput.value,
      rows: Array.from(refs.keyRows.querySelectorAll(".rowCard")).map((row) => ({
        keyName: row.querySelector(".keyNameInput").value,
        apiKey: row.querySelector(".keyValueInput").value
      }))
    },
    usageForm: {
      platformIdentity: refs.usagePlatformSelect.value,
      customPlatform: refs.customUsagePlatformInput.value,
      environment: refs.usageEnvironmentSelect.value,
      customEnvironment: refs.customUsageEnvironmentInput.value,
      notes: refs.usageNotesInput.value,
      rows: Array.from(refs.usageRows.querySelectorAll(".rowCard")).map((row) => ({
        usage: row.querySelector(".usageLabelInput").value,
        usageProfile: row.querySelector(".usageProfileSelect").value,
        usedSite: row.querySelector(".usedSiteInput").value,
        configurationLink: row.querySelector(".configurationLinkInput").value,
        serverIP: row.querySelector(".serverIPInput").value
      }))
    }
  };
}

async function persistDraft() {
  try {
    const result = await browser.storage.local.get(DRAFT_STORAGE_KEY);
    const drafts = result[DRAFT_STORAGE_KEY] ?? {};
    drafts[draftScopeKey()] = collectDraft();
    await browser.storage.local.set({ [DRAFT_STORAGE_KEY]: drafts });
  } catch {
    // Ignore storage failures in the popup.
  }
}

function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function escapeAttribute(value) {
  return escapeHTML(value).replaceAll("\"", "&quot;");
}

async function sendNativeMessage(message) {
  state.bridgeMode = "native";
  return browser.runtime.sendNativeMessage(message);
}

async function sendBridgeMessage(message) {
  try {
    return await sendLocalhostBridge(message);
  } catch (localhostError) {
    return sendNativeMessage(message).catch(() => {
      throw localhostError;
    });
  }
}

async function sendLocalhostBridge(message) {
  state.bridgeMode = "localhost";

  const response = await fetch("http://localhost:38173/bridge", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(message)
  }).catch(() => {
    throw new Error("Dashboard is not reachable. Open Apivault, then retry.");
  });

  if (!response.ok) {
    throw new Error("Dashboard is not reachable. Open Apivault, then retry.");
  }

  return response.json();
}
