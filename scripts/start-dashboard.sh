#!/usr/bin/env bash
set -euo pipefail

OVERRIDE_DIR="${DASHBOARD_OVERRIDE_DIR:-/opt/dashboard-override}"
OVERRIDE_MAIN="${OVERRIDE_DIR}/dashboard-server.js"
OVERRIDE_HTML="${OVERRIDE_DIR}/dashboard.html"
OVERRIDE_FAVICON="${OVERRIDE_DIR}/dashboard-favicon.ico"
PREPARED_MAIN="/tmp/dashboard-server-override.js"

if [ -f "${OVERRIDE_MAIN}" ]; then
  echo "[dashboard] using override source: ${OVERRIDE_MAIN}"

  export NODE_PATH="${OVERRIDE_DIR}/node_modules:/usr/local/lib/node_modules:/usr/local/lib/node_modules/webclaw-dashboard-server/node_modules:/usr/lib/node_modules:/usr/lib/node_modules/webclaw-dashboard-server/node_modules"

  if [ -f "${OVERRIDE_HTML}" ] && [ -f "${OVERRIDE_FAVICON}" ]; then
    OVERRIDE_MAIN="${OVERRIDE_MAIN}" \
    OVERRIDE_HTML="${OVERRIDE_HTML}" \
    OVERRIDE_FAVICON="${OVERRIDE_FAVICON}" \
    PREPARED_MAIN="${PREPARED_MAIN}" \
    node <<'EOF'
const fs = require('fs');

const sourcePath = process.env.OVERRIDE_MAIN;
const htmlPath = process.env.OVERRIDE_HTML;
const faviconPath = process.env.OVERRIDE_FAVICON;
const outputPath = process.env.PREPARED_MAIN;

let source = fs.readFileSync(sourcePath, 'utf8');
const htmlContent = fs.readFileSync(htmlPath, 'utf8');
const faviconBase64 = fs.readFileSync(faviconPath).toString('base64');

source = source.replace(
  /const DASHBOARD_HTML_CONTENT = null; \/\/ __INLINE_DASHBOARD_HTML__/,
  `const DASHBOARD_HTML_CONTENT = ${JSON.stringify(htmlContent)};`
);

source = source.replace(
  /const FAVICON_CONTENT = null; \/\/ __INLINE_FAVICON__/,
  `const FAVICON_CONTENT = Buffer.from('${faviconBase64}', 'base64');`
);

fs.writeFileSync(outputPath, source, 'utf8');
EOF

    exec /usr/bin/node "${PREPARED_MAIN}"
  fi

  echo "[dashboard] override html/favicon missing, running source directly"
  exec /usr/bin/node "${OVERRIDE_MAIN}"
fi

echo "[dashboard] using packaged server: webclaw-dashboard-server"
export NODE_PATH="/usr/local/lib/node_modules:/usr/lib/node_modules"
exec webclaw-dashboard-server
