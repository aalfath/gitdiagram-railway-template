#!/bin/sh
# GitDiagram on Railway: the Next.js server (127.0.0.1:3000), a small
# Upstash-REST bridge to Railway Redis (127.0.0.1:8079) and Caddy on $PORT
# (generated login + open /healthz). Exits non-zero as soon as any of the
# three stops, so Railway's ON_FAILURE policy restarts the service.
set -eu

fail() { echo "gitdiagram-railway: $*" >&2; exit 1; }

[ -n "${OPENAI_API_KEY:-}${OPENROUTER_API_KEY:-}" ] || fail "OPENAI_API_KEY is empty. Add your OpenAI API key (https://platform.openai.com/api-keys) in the service variables."
pw="${GITDIAGRAM_PASSWORD:-}"
[ "${#pw}" -ge 12 ] || fail "GITDIAGRAM_PASSWORD must be set (12+ characters). Refusing to start an open server that spends your API key."
ck="${CACHE_KEY_SECRET:-}"
[ "${#ck}" -ge 32 ] || fail "CACHE_KEY_SECRET must be set (32+ characters)."
[ -n "${REDIS_URL:-}" ] || fail "REDIS_URL is empty (it should reference the Redis service)."
for v in S3_ENDPOINT S3_BUCKET S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY; do
	eval "val=\${$v:-}"
	[ -n "$val" ] || fail "$v is empty (it should reference the Railway Bucket)."
done

export GITDIAGRAM_USERNAME="${GITDIAGRAM_USERNAME:-admin}"

# GitDiagram reads Cloudflare R2 and Upstash settings; point them at the
# Railway Bucket and the local Redis bridge.
export R2_ACCOUNT_ID="${R2_ACCOUNT_ID:-railway}"
export R2_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export R2_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
export R2_PUBLIC_BUCKET="${R2_PUBLIC_BUCKET:-$S3_BUCKET}"
export R2_PRIVATE_BUCKET="${R2_PRIVATE_BUCKET:-$S3_BUCKET}"
export S3_REGION="${S3_REGION:-auto}"
UPSTASH_REDIS_REST_TOKEN=$(node -e 'process.stdout.write(require("crypto").createHmac("sha256", process.env.CACHE_KEY_SECRET).update("redis-rest-shim").digest("hex"))')
export UPSTASH_REDIS_REST_TOKEN
export UPSTASH_REDIS_REST_URL="http://127.0.0.1:${SHIM_PORT:-8079}"
export AI_PROVIDER="${AI_PROVIDER:-openai}"
export OPENAI_MODEL="${OPENAI_MODEL:-gpt-6-luna}"
export GENERATION_RATE_LIMIT_MAX="${GENERATION_RATE_LIMIT_MAX:-60}"
export GITDIAGRAM_SELF_HOSTED=1
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
	export GITDIAGRAM_SITE_URL="${GITDIAGRAM_SITE_URL:-https://${RAILWAY_PUBLIC_DOMAIN}}"
	export OPENROUTER_SITE_URL="${OPENROUTER_SITE_URL:-$GITDIAGRAM_SITE_URL}"
fi
# An empty base URL would break the OpenAI client; drop it.
[ -n "${OPENAI_BASE_URL:-}" ] || unset OPENAI_BASE_URL

# Size the Node heap to the container's memory limit (about 55%, 192-2048 MB).
limit_mb=0
if [ -r /sys/fs/cgroup/memory.max ]; then
	raw=$(cat /sys/fs/cgroup/memory.max)
	[ "$raw" != "max" ] && limit_mb=$((raw / 1048576))
fi
heap=1024
if [ "$limit_mb" -gt 0 ]; then
	heap=$((limit_mb * 55 / 100))
	[ "$heap" -lt 192 ] && heap=192
	[ "$heap" -gt 2048 ] && heap=2048
fi
export UV_THREADPOOL_SIZE="${UV_THREADPOOL_SIZE:-2}"

GITDIAGRAM_PASSWORD_HASH=$(caddy hash-password --algorithm bcrypt --bcrypt-cost 10 --plaintext "$GITDIAGRAM_PASSWORD")
unset GITDIAGRAM_PASSWORD pw ck
export XDG_CONFIG_HOME=/tmp/caddy XDG_DATA_HOME=/tmp/caddy
mkdir -p /tmp/caddy

SHIM_PORT="${SHIM_PORT:-8079}" node --max-old-space-size=48 /opt/redis-rest-shim/redis-rest-shim.mjs &
shim=$!
PORT=3000 HOSTNAME=127.0.0.1 NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=${heap}" node /app/server.js &
app=$!
GITDIAGRAM_PASSWORD_HASH="$GITDIAGRAM_PASSWORD_HASH" GOMEMLIMIT="${GOMEMLIMIT:-48MiB}" GOMAXPROCS="${GOMAXPROCS:-2}" \
	caddy run --adapter caddyfile --config /etc/gitdiagram-railway/Caddyfile &
proxy=$!
unset GITDIAGRAM_PASSWORD_HASH

stopping=0
term() {
	stopping=1
	kill -TERM "$app" "$proxy" "$shim" 2>/dev/null || true
}
trap term TERM INT

echo "gitdiagram-railway: GitDiagram ${GITDIAGRAM_VERSION:-} starting (heap ${heap} MB, model ${OPENAI_MODEL}, login user ${GITDIAGRAM_USERNAME})"
# BusyBox/dash `wait -n` is unreliable, so poll the three processes.
while kill -0 "$app" 2>/dev/null && kill -0 "$proxy" 2>/dev/null && kill -0 "$shim" 2>/dev/null; do
	sleep 2 &
	wait $! || true
done

kill -TERM "$app" "$proxy" "$shim" 2>/dev/null || true
wait "$app" 2>/dev/null || true
wait "$proxy" 2>/dev/null || true
wait "$shim" 2>/dev/null || true
if [ "$stopping" = 1 ]; then
	exit 0
fi
echo "gitdiagram-railway: a process stopped unexpectedly; exiting 1 so Railway restarts the service" >&2
exit 1
