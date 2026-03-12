import type { Plugin } from 'vite';

const THEME_BOOTSTRAP_SCRIPT = `
(function () {
  try {
    var storageKey = 'theme';
    var stored = localStorage.getItem(storageKey);
    var prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    var theme = stored === 'dark' || stored === 'light' ? stored : (prefersDark ? 'dark' : 'light');
    var root = document.documentElement;
    root.classList.remove('light', 'dark');
    root.classList.add(theme);
    root.setAttribute('data-theme', theme);
  } catch (_) {
    // no-op
  }
})();
`;

export function themeStoragePlugin(): Plugin {
  return {
    name: 'theme-storage-plugin',
    transformIndexHtml() {
      return [
        {
          tag: 'script',
          attrs: {
            id: 'theme-storage-bootstrap',
          },
          children: THEME_BOOTSTRAP_SCRIPT,
          injectTo: 'head-prepend',
        },
      ];
    },
  };
}
