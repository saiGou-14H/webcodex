#!/usr/bin/env bash
exec /usr/local/bin/tunnel-client run \
  --control-plane.tunnel-id tunnel_6a9913b323108191b1b2cb5e67dfc7bd \
  --control-plane.api-key file:/root/.config/openai/tunnel-api-key \
  --mcp.server-url "url=http://127.0.0.1:8080/mcp,channel=main" \
  --mcp.extra-headers "Authorization: file:/root/.config/openai/webcodex-bearer" \
  --health.listen-addr 127.0.0.1:0 \
  --health.url-file /root/.config/openai/tunnel-health.url \
  --log.file /root/.config/openai/tunnel-client.log \
  --log.level info
