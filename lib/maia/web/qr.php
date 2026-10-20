<?php

declare(strict_types=1);

require_once __DIR__ . '/api/web.php';
$webBasePath = maia_web_base_path();

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');
header('Pragma: no-cache');
header('Referrer-Policy: no-referrer');
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>MAIA authentication QR code</title>
    <style>
        :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
        body { margin: 0; padding: 2rem 1rem; }
        main { margin: 0 auto; max-width: 36rem; text-align: center; }
        .qr-container { background: #fff; border: 1px solid #d1d5db; border-radius: .5rem; margin: 1rem auto; max-width: min(80vw, 24rem); padding: 1rem; }
        .qr-container canvas, .qr-container img, .qr-container svg { display: block; height: auto; max-width: 100%; width: 100%; }
        code { overflow-wrap: anywhere; }
        .error { color: #b91c1c; }
    </style>
</head>
<body>
<main>
    <h1>MAIA authentication</h1>
    <p id="status">Preparing QR code...</p>
    <div id="qr" class="qr-container" hidden></div>
    <p id="url" hidden><code></code></p>
</main>
<script src="<?= htmlspecialchars($webBasePath, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>/qrcode.min.js"></script>
<script>
(() => {
    const status = document.getElementById('status');
    const container = document.getElementById('qr');
    const urlContainer = document.getElementById('url');
    const urlCode = urlContainer.querySelector('code');
    const auth = new URLSearchParams(location.hash.slice(1)).get('auth');

    if (!auth || !/^[0-9a-f]+:[0-9a-f]+$/.test(auth)) {
        status.className = 'error';
        status.textContent = 'No valid authentication token was supplied.';
        return;
    }

    const authUrl = `${location.origin}<?= json_encode($webBasePath, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>/#auth=${auth}`;
    urlCode.textContent = authUrl;
    urlContainer.hidden = false;

    if (!window.QRCode) {
        status.className = 'error';
        status.textContent = 'The QR code generator could not be loaded.';
        return;
    }

    try {
        new QRCode(container, {
            text: authUrl,
            width: 512,
            height: 512,
            colorDark: '#000000',
            colorLight: '#ffffff',
            correctLevel: QRCode.CorrectLevel.M
        });
        container.hidden = false;
        status.textContent = 'Scan this code to open MAIA on another device.';
    } catch (_) {
        status.className = 'error';
        status.textContent = 'Unable to generate the QR code.';
    }
})();
</script>
</body>
</html>
