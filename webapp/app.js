(function () {
  'use strict';

  const HISTORY_KEY = 'history_items';
  const LANG_KEY = 'language';
  const HISTORY_MAX_ITEMS = 200;
  const HISTORY_MAX_BYTES = 1000000;
  const DEFAULT_LANGUAGE = 'tt';

  const refs = {
    app: document.getElementById('app'),
    boot: document.getElementById('boot-shell'),
    toast: document.getElementById('toast'),
    workspacePage: document.getElementById('workspace-page'),
    historyPage: document.getElementById('history-page'),
    navWorkspace: document.getElementById('nav-workspace'),
    navHistory: document.getElementById('nav-history'),
    brandButton: document.getElementById('brand-button'),
    langButtons: {
      tt: document.getElementById('lang-tt'),
      en: document.getElementById('lang-en'),
      ru: document.getElementById('lang-ru'),
    },
    originalInput: document.getElementById('original-input'),
    correctedOutput: document.getElementById('corrected-output'),
    streamingState: document.getElementById('streaming-state'),
    btnCorrect: document.getElementById('btn-correct'),
    btnStop: document.getElementById('btn-stop'),
    btnCopy: document.getElementById('btn-copy'),
    btnClear: document.getElementById('btn-clear'),
    metricWords: document.getElementById('metric-words'),
    metricChars: document.getElementById('metric-chars'),
    historyList: document.getElementById('history-list'),
  };

  const state = {
    config: {
      baseUrl: '',
      appName: 'Yazam.Tatar',
      buildSha: 'dev',
    },
    strings: {},
    language: DEFAULT_LANGUAGE,
    section: hashToSection(window.location.hash),
    originalText: '',
    correctedText: '',
    errorMessage: '',
    isStreaming: false,
    statusText: '',
    requestId: '',
    activeOriginal: '',
    activeTimestamp: null,
    streamAbort: null,
    history: [],
  };

  function hashToSection(hash) {
    return hash === '#history' ? 'history' : 'workspace';
  }

  function endpoint(path) {
    if (!state.config.baseUrl) {
      return null;
    }
    const base = new URL(state.config.baseUrl, window.location.origin);
    const cleanBasePath = base.pathname.endsWith('/')
      ? base.pathname.slice(0, -1)
      : base.pathname;
    base.pathname = `${cleanBasePath}${path}`;
    return base.toString();
  }

  function t(key, vars) {
    let text = state.strings[key] || key;
    if (vars) {
      Object.entries(vars).forEach(([token, value]) => {
        text = text.replaceAll(`{${token}}`, String(value));
      });
    }
    return text;
  }

  function loadLanguageSetting() {
    const raw = window.localStorage.getItem(LANG_KEY);
    if (raw === 'tt' || raw === 'en' || raw === 'ru') {
      return raw;
    }
    return DEFAULT_LANGUAGE;
  }

  function saveLanguageSetting(value) {
    window.localStorage.setItem(LANG_KEY, value);
  }

  function parseJson(raw, fallback) {
    try {
      return JSON.parse(raw);
    } catch (_) {
      return fallback;
    }
  }

  function encodedSize(value) {
    return new TextEncoder().encode(JSON.stringify(value)).length;
  }

  function normalizeHistoryItem(item) {
    if (!item || typeof item !== 'object') {
      return null;
    }
    const timestamp = new Date(item.timestamp || Date.now());
    if (Number.isNaN(timestamp.getTime())) {
      return null;
    }
    return {
      id: String(item.id || Date.now()),
      original: String(item.original || ''),
      corrected: String(item.corrected || ''),
      timestamp: timestamp.toISOString(),
      latencyMs: Number(item.latencyMs || 0),
      requestId: String(item.requestId || ''),
    };
  }

  function trimHistory(items) {
    let trimmed = items.slice(-HISTORY_MAX_ITEMS);
    while (trimmed.length > 1 && encodedSize(trimmed) > HISTORY_MAX_BYTES) {
      trimmed = trimmed.slice(1);
    }
    return trimmed;
  }

  function loadHistory() {
    const raw = window.localStorage.getItem(HISTORY_KEY);
    if (!raw) {
      return [];
    }
    const parsed = parseJson(raw, []);
    if (!Array.isArray(parsed)) {
      return [];
    }
    const normalized = parsed.map(normalizeHistoryItem).filter(Boolean);
    const trimmed = trimHistory(normalized);
    if (trimmed.length !== normalized.length) {
      window.localStorage.setItem(HISTORY_KEY, JSON.stringify(trimmed));
    }
    return trimmed.reverse();
  }

  function persistHistory() {
    const storageOrder = state.history.slice().reverse();
    const trimmed = trimHistory(storageOrder);
    window.localStorage.setItem(HISTORY_KEY, JSON.stringify(trimmed));
    state.history = trimmed.slice().reverse();
  }

  function countWords(value) {
    const trimmed = value.trim();
    if (!trimmed) {
      return 0;
    }
    return trimmed.split(/\s+/u).length;
  }

  function formatDate(value) {
    const d = new Date(value);
    const day = String(d.getDate()).padStart(2, '0');
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const year = String(d.getFullYear()).padStart(4, '0');
    return `${day}.${month}.${year}`;
  }

  function formatDateTime(value) {
    const d = new Date(value);
    const day = String(d.getDate()).padStart(2, '0');
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const year = String(d.getFullYear()).padStart(4, '0');
    const hours = String(d.getHours()).padStart(2, '0');
    const minutes = String(d.getMinutes()).padStart(2, '0');
    return `${day}.${month}.${year} ${hours}:${minutes}`;
  }

  function showToast(message, isError) {
    refs.toast.textContent = message;
    refs.toast.classList.toggle('error', Boolean(isError));
    refs.toast.hidden = false;
    clearTimeout(showToast.timerId);
    showToast.timerId = setTimeout(() => {
      refs.toast.hidden = true;
    }, 1700);
  }

  async function copyCorrection() {
    const text = state.correctedText.trim();
    if (!text) {
      return;
    }
    try {
      await navigator.clipboard.writeText(text);
      showToast(t('actions.copied'), false);
    } catch (_) {
      showToast(t('errors.copyFailed'), true);
    }
  }

  function setSection(section, pushHash) {
    state.section = section;
    if (pushHash) {
      if (section === 'history') {
        window.location.hash = 'history';
      } else {
        history.pushState('', document.title, window.location.pathname + window.location.search);
      }
    }
    render();
  }

  function resetOutputPane() {
    state.correctedText = '';
    state.errorMessage = '';
    state.statusText = '';
    state.requestId = '';
  }

  function renderText() {
    document.querySelectorAll('[data-i18n]').forEach((element) => {
      const key = element.getAttribute('data-i18n');
      if (!key) {
        return;
      }
      element.textContent = t(key);
    });

    document.querySelectorAll('[data-i18n-title]').forEach((element) => {
      const key = element.getAttribute('data-i18n-title');
      if (!key) {
        return;
      }
      element.setAttribute('title', t(key));
    });

    refs.originalInput.placeholder = t('input.placeholder');
    refs.metricWords.textContent = t('metrics.words', {
      count: countWords(state.originalText),
    }).toUpperCase();
    refs.metricChars.textContent = t('metrics.characters', {
      count: state.originalText.length,
    }).toUpperCase();
  }

  function renderLanguage() {
    Object.entries(refs.langButtons).forEach(([lang, button]) => {
      button.classList.toggle('active', state.language === lang);
    });
  }

  function renderNavigation() {
    const workspaceSelected = state.section === 'workspace';
    refs.navWorkspace.classList.toggle('selected', workspaceSelected);
    refs.navHistory.classList.toggle('selected', !workspaceSelected);
    refs.workspacePage.hidden = !workspaceSelected;
    refs.historyPage.hidden = workspaceSelected;
  }

  function renderOutput() {
    const showStreaming = state.isStreaming;
    refs.streamingState.classList.toggle('is-hidden', !showStreaming);
    refs.streamingState.setAttribute('aria-hidden', String(!showStreaming));

    if (state.errorMessage) {
      refs.correctedOutput.textContent = state.errorMessage;
      refs.correctedOutput.classList.add('error');
      refs.correctedOutput.classList.remove('placeholder');
      return;
    }

    if (state.correctedText.trim()) {
      refs.correctedOutput.textContent = state.correctedText;
      refs.correctedOutput.classList.remove('placeholder');
      refs.correctedOutput.classList.remove('error');
      return;
    }

    if (state.isStreaming) {
      refs.correctedOutput.textContent = '';
      refs.correctedOutput.classList.remove('error');
      refs.correctedOutput.classList.remove('placeholder');
      return;
    }

    refs.correctedOutput.textContent = t('empty.title');
    refs.correctedOutput.classList.add('placeholder');
    refs.correctedOutput.classList.remove('error');
  }

  function renderButtons() {
    const canSubmit = state.originalText.trim().length > 0 && !state.isStreaming;
    const canCopy = state.correctedText.trim().length > 0;

    refs.btnCorrect.hidden = state.isStreaming;
    refs.btnStop.hidden = !state.isStreaming;
    refs.btnCorrect.disabled = !canSubmit;
    refs.btnCopy.disabled = !canCopy;
  }

  function renderHistory() {
    refs.historyList.innerHTML = '';
    if (!state.history.length) {
      const empty = document.createElement('div');
      empty.className = 'history-empty';
      empty.textContent = t('history.empty');
      refs.historyList.appendChild(empty);
      return;
    }

    const grouped = new Map();
    state.history.forEach((item) => {
      const day = formatDate(item.timestamp);
      if (!grouped.has(day)) {
        grouped.set(day, []);
      }
      grouped.get(day).push(item);
    });

    grouped.forEach((items, day) => {
      const block = document.createElement('section');
      block.className = 'history-block';

      const dayLabel = document.createElement('h3');
      dayLabel.className = 'history-day';
      dayLabel.textContent = day;
      block.appendChild(dayLabel);

      items.forEach((item) => {
        const card = document.createElement('article');
        card.className = 'history-card';

        const timestamp = document.createElement('div');
        timestamp.className = 'history-time';
        timestamp.textContent = formatDateTime(item.timestamp);
        card.appendChild(timestamp);

        const original = document.createElement('div');
        original.className = 'history-original';
        original.textContent = item.original.trim();
        card.appendChild(original);

        const corrected = document.createElement('div');
        corrected.className = 'history-corrected';
        corrected.textContent = item.corrected.trim();
        card.appendChild(corrected);

        block.appendChild(card);
      });

      refs.historyList.appendChild(block);
    });
  }

  function render() {
    refs.originalInput.value = state.originalText;
    renderText();
    renderLanguage();
    renderNavigation();
    renderOutput();
    renderButtons();
    renderHistory();
  }

  function addHistoryItem(latencyMs) {
    const timestamp = state.activeTimestamp || new Date().toISOString();
    const item = {
      id: String(Date.now()),
      original: state.activeOriginal,
      corrected: state.correctedText,
      timestamp,
      latencyMs,
      requestId: state.requestId,
    };
    state.history.unshift(item);
    persistHistory();
  }

  function extractErrorMessage(body, status) {
    if (!body) {
      return `stream_failed:${status}`;
    }
    const payload = parseJson(body, null);
    if (payload && typeof payload === 'object') {
      if (typeof payload.detail === 'string') {
        return payload.detail;
      }
      if (payload.detail && typeof payload.detail === 'object') {
        if (payload.detail.message) {
          return String(payload.detail.message);
        }
        if (payload.detail.error) {
          return String(payload.detail.error);
        }
      }
    }
    return `stream_failed:${status}`;
  }

  function handleEvent(eventName, payload, onDone) {
    if (eventName === 'meta') {
      state.requestId = String(payload.request_id || '');
      return;
    }
    if (eventName === 'delta') {
      state.correctedText += String(payload.text || '');
      renderOutput();
      renderButtons();
      return;
    }
    if (eventName === 'done') {
      const latency = Number(payload.latency_ms || 0);
      onDone(Number.isFinite(latency) ? latency : 0);
      return;
    }
    if (eventName === 'error') {
      state.errorMessage = String(payload.message || t('errors.stream'));
      state.isStreaming = false;
      render();
    }
  }

  async function submitCorrection() {
    const text = state.originalText.trim();
    if (!text || state.isStreaming) {
      return;
    }
    const streamUrl = endpoint('/v1/correct/stream');
    if (!streamUrl) {
      state.errorMessage = t('errors.noBackendUrl');
      render();
      return;
    }

    resetOutputPane();
    state.activeOriginal = text;
    state.activeTimestamp = new Date().toISOString();
    state.isStreaming = true;
    render();

    const controller = new AbortController();
    state.streamAbort = controller;

    let doneReceived = false;
    try {
      const response = await fetch(streamUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'text/event-stream',
        },
        body: JSON.stringify({
          text,
          lang: 'tt',
          client: { platform: 'web', version: 'js-1.0' },
        }),
        signal: controller.signal,
      });

      if (!response.ok || !response.body) {
        const body = await response.text();
        throw new Error(extractErrorMessage(body, response.status));
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let currentEvent = 'message';
      let currentData = '';

      const finish = (latency) => {
        if (!state.isStreaming) {
          return;
        }
        state.isStreaming = false;
        doneReceived = true;
        addHistoryItem(latency);
        render();
      };

      while (true) {
        const { value, done } = await reader.read();
        if (done) {
          break;
        }

        buffer += decoder.decode(value, { stream: true });
        while (buffer.includes('\n')) {
          const index = buffer.indexOf('\n');
          const line = buffer.slice(0, index).trimEnd();
          buffer = buffer.slice(index + 1);

          if (!line) {
            if (currentData) {
              const payload = parseJson(currentData, {});
              handleEvent(currentEvent, payload, finish);
            }
            currentEvent = 'message';
            currentData = '';
            continue;
          }

          if (line.startsWith('event:')) {
            currentEvent = line.slice(6).trim();
          } else if (line.startsWith('data:')) {
            const chunk = line.slice(5).trim();
            currentData = currentData ? `${currentData}\n${chunk}` : chunk;
          }
        }
      }

      if (!doneReceived && state.isStreaming) {
        addHistoryItem(0);
      }
      state.isStreaming = false;
      render();
    } catch (error) {
      if (controller.signal.aborted) {
        state.isStreaming = false;
        state.statusText = t('actions.stopped');
        render();
        return;
      }
      state.isStreaming = false;
      state.errorMessage = error && error.message ? error.message : t('errors.stream');
      render();
    } finally {
      if (state.streamAbort === controller) {
        state.streamAbort = null;
      }
    }
  }

  function stopStreaming() {
    if (!state.streamAbort) {
      return;
    }
    state.streamAbort.abort();
  }

  async function loadConfig() {
    try {
      const response = await fetch('assets/config.json', { cache: 'no-store' });
      if (!response.ok) {
        return;
      }
      const payload = await response.json();
      state.config = {
        baseUrl: String(payload.baseUrl || ''),
        appName: String(payload.appName || 'Yazam.Tatar'),
        buildSha: String(payload.buildSha || ''),
      };
      document.title = state.config.appName;
    } catch (_) {
      // keep defaults
    }
  }

  async function loadLanguage(lang) {
    try {
      const response = await fetch(`assets/i18n/${lang}.json`, { cache: 'no-store' });
      if (!response.ok) {
        throw new Error('i18n_not_found');
      }
      state.strings = await response.json();
      state.language = lang;
      saveLanguageSetting(lang);
      document.documentElement.lang = lang;
      render();
    } catch (_) {
      if (lang !== DEFAULT_LANGUAGE) {
        await loadLanguage(DEFAULT_LANGUAGE);
      }
    }
  }

  function bindEvents() {
    refs.originalInput.addEventListener('input', (event) => {
      state.originalText = event.target.value;
      if (state.errorMessage) {
        state.errorMessage = '';
      }
      renderText();
      renderButtons();
    });

    refs.btnCorrect.addEventListener('click', submitCorrection);
    refs.btnStop.addEventListener('click', stopStreaming);
    refs.btnCopy.addEventListener('click', copyCorrection);
    refs.btnClear.addEventListener('click', () => {
      state.originalText = '';
      refs.originalInput.value = '';
      renderText();
      renderButtons();
    });

    refs.navWorkspace.addEventListener('click', () => {
      setSection('workspace', true);
      refs.originalInput.focus();
    });
    refs.navHistory.addEventListener('click', () => {
      setSection('history', true);
    });

    refs.brandButton.addEventListener('click', () => {
      setSection('workspace', true);
      refs.originalInput.focus();
    });

    Object.entries(refs.langButtons).forEach(([lang, button]) => {
      button.addEventListener('click', () => {
        if (state.language === lang) {
          return;
        }
        void loadLanguage(lang);
      });
    });

    window.addEventListener('hashchange', () => {
      setSection(hashToSection(window.location.hash), false);
    });
  }

  function showDeferredAssets() {
    setTimeout(() => {
      document.querySelectorAll('[data-defer-src]').forEach((img) => {
        const src = img.getAttribute('data-defer-src');
        if (!src) {
          return;
        }
        img.addEventListener('load', () => {
          img.classList.add('ready');
        }, { once: true });
        img.src = src;
      });
    }, 450);
  }

  function hideBoot() {
    refs.app.hidden = false;
    refs.boot.classList.add('hide');
    setTimeout(() => {
      refs.boot.remove();
    }, 220);
  }

  async function init() {
    state.history = loadHistory();
    state.originalText = '';

    bindEvents();
    await loadConfig();
    await loadLanguage(loadLanguageSetting());
    setSection(state.section, false);
    showDeferredAssets();
    hideBoot();
    refs.originalInput.focus();
  }

  void init();
})();
