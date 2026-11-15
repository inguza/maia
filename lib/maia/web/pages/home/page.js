/* Home-page usage summary. */
(() => {
    'use strict';

    const summary = document.querySelector('[data-home-usage]');
    if (!summary || !window.maiaApi) return;

    const status = summary.querySelector('[data-home-usage-status]');

    function setPeriod(period, values) {
        for (const category of ['input', 'cached', 'output', 'reasoning']) {
            const node = summary.querySelector(`[data-home-usage="${period}-${category}"]`);
            if (node) node.textContent = (Number(values?.[category]) || 0).toLocaleString();
        }
    }

    async function loadUsage() {
        try {
            const data = await window.maiaApi.request('/api/home/usage');
            setPeriod('home', data.home);
            setPeriod('today', data.today);
            if (status) status.textContent = '';
        } catch (error) {
            if (status) status.textContent = `Usage unavailable: ${error instanceof Error ? error.message : 'Unable to load usage.'}`;
        }
    }

    loadUsage();
})();
