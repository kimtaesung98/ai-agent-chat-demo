#!/usr/bin/env bash
# EC2에서 chatd와 cloudflared 컨테이너를 (다시) 띄운다 (SPEC F-014 상세 동작 2~4).
# 배포 워크플로가 SSM Run Command로 실행한다: IMAGE=<ECR 이미지> bash run-chatd.sh
# 비밀값(API 키·터널 토큰)은 SSM Parameter Store에서 읽어 메모리 위 임시 파일로만 넘기고 바로 지운다.
set -euo pipefail

: "${IMAGE:?IMAGE(ECR 이미지 주소:태그)가 필요해요}"
TOKEN=$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
REGION=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
REGISTRY=${IMAGE%%/*}
CLOUDFLARED_IMAGE=cloudflare/cloudflared:2026.10.7

param() { aws ssm get-parameter --region "$REGION" --with-decryption --name "$1" --query Parameter.Value --output text; }

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
docker pull -q "$IMAGE"
docker pull -q "$CLOUDFLARED_IMAGE"
docker network inspect chatnet >/dev/null 2>&1 || docker network create chatnet >/dev/null

umask 077
envdir=$(mktemp -d /dev/shm/chatd.XXXXXX)
trap 'rm -rf "$envdir"' EXIT

# chatd — 키가 SSM에 없으면 모의 모드로 뜬다
if key=$(param /chatd/anthropic-api-key 2>/dev/null); then
  printf 'ANTHROPIC_API_KEY=%s\n' "$key" >"$envdir/chatd.env"
else
  echo "경고: /chatd/anthropic-api-key가 없어 모의 모드로 띄웁니다" >&2
  : >"$envdir/chatd.env"
fi
unset key
# 실시간 음성(F-024) — SSM에 OpenAI 키가 있을 때만 켠다. 없으면 앱은 글 대화만
if oa=$(param /chatd/openai-api-key 2>/dev/null); then
  printf 'OPENAI_API_KEY=%s\n' "$oa" >>"$envdir/chatd.env"
fi
unset oa
docker rm -f chatd >/dev/null 2>&1 || true
docker run -d --name chatd --network chatnet --restart unless-stopped \
  --read-only --cap-drop ALL --security-opt no-new-privileges \
  --env-file "$envdir/chatd.env" -e AWS_REGION="$REGION" \
  --log-opt max-size=10m --log-opt max-file=3 \
  "$IMAGE" >/dev/null

# cloudflared — 터널 공개 주소의 서비스는 http://chatd:3000 (deploy/README.md)
printf 'TUNNEL_TOKEN=%s\n' "$(param /chatd/cloudflare-tunnel-token)" >"$envdir/cloudflared.env"
docker rm -f cloudflared >/dev/null 2>&1 || true
docker run -d --name cloudflared --network chatnet --restart unless-stopped \
  --read-only --cap-drop ALL --security-opt no-new-privileges \
  --env-file "$envdir/cloudflared.env" \
  --log-opt max-size=10m --log-opt max-file=3 \
  "$CLOUDFLARED_IMAGE" tunnel --no-autoupdate run >/dev/null

# 상태 확인: 호스트에서 chatd 컨테이너 주소로 첫 화면을 받아 본다
ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' chatd)
for _ in $(seq 1 20); do
  if curl -sf -o /dev/null "http://$ip:3000/"; then
    echo "배포 완료: $IMAGE"
    docker image prune -f >/dev/null
    exit 0
  fi
  sleep 1
done
echo "chatd가 응답하지 않아요" >&2
docker logs --tail 50 chatd >&2 || true
exit 1
