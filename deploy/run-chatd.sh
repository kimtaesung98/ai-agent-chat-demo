#!/usr/bin/env bash
# EC2에서 chatd와 cloudflared 컨테이너를 (다시) 띄운다 (SPEC F-014 상세 동작 2~4).
# 배포 워크플로가 SSM Run Command로 실행한다: IMAGE=<ECR 이미지> bash run-chatd.sh
# 비밀값(API 키·터널 토큰)은 SSM Parameter Store에서 읽어 메모리 위 임시 파일로만 넘기고 바로 지운다.
# 계정 DB(F-026)는 호스트 디스크 /var/lib/chatd에 두고(컨테이너를 바꿔도 남음), 띄우기 전과 매일 새벽 3시에 백업한다 (F-014 AC6).
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

# 작은 인스턴스(t4g.micro 1GB, ADR-037)에서 이미지 받기·백업이 겹쳐도 멈추지 않게 1GB 스왑을 한 번 만든다
if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -lt 2000000 ] && ! swapon --show=NAME --noheadings | grep -q .; then
  [ -f /swapfile ] || { dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none && chmod 600 /swapfile && mkswap /swapfile >/dev/null; }
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
  echo "스왑 1GB 켬"
fi

# 계정 DB 폴더 — 이미지의 nonroot(65532)만 읽고 쓴다
DATA_HOST=/var/lib/chatd
install -d -m 700 -o 65532 -g 65532 "$DATA_HOST" "$DATA_HOST/backups"

# 백업 스크립트와 매일 타이머 (03:00 KST). 서버가 켜진 채로 DB 사본을 뜨고(chatd admin backup),
# 이 기기에 14개를 남기며, SSM /chatd/backup-bucket이 있으면 S3에도 올린다 (deploy/README.md 복구 순서)
cat >/usr/local/bin/chatd-backup.sh <<'BACKUP'
#!/usr/bin/env bash
set -euo pipefail
DATA_HOST=/var/lib/chatd
[ -f "$DATA_HOST/chatd.db" ] || { echo "DB가 아직 없어요 — 백업 건너뜀"; exit 0; }
docker inspect -f '{{.State.Running}}' chatd 2>/dev/null | grep -q true || { echo "chatd가 꺼져 있어요 — 백업 건너뜀"; exit 0; }
name=chatd-$(date -u +%Y%m%dT%H%M%SZ).db
docker exec chatd /chatd admin backup -out "/data/backups/$name"
gzip -f "$DATA_HOST/backups/$name"
ls -1t "$DATA_HOST"/backups/chatd-*.db.gz | tail -n +15 | xargs -r rm -f
TOKEN=$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
REGION=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
if bucket=$(aws ssm get-parameter --region "$REGION" --name /chatd/backup-bucket --query Parameter.Value --output text 2>/dev/null); then
  aws s3 cp --region "$REGION" --only-show-errors --sse AES256 "$DATA_HOST/backups/$name.gz" "s3://$bucket/db/$name.gz"
  echo "백업: $name.gz (기기 + s3://$bucket/db/)"
else
  echo "백업: $name.gz (기기만 — /chatd/backup-bucket이 없어요)"
fi
BACKUP
chmod 755 /usr/local/bin/chatd-backup.sh
cat >/etc/systemd/system/chatd-backup.service <<'UNIT'
[Unit]
Description=chatd DB 백업
After=docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/chatd-backup.sh
UNIT
cat >/etc/systemd/system/chatd-backup.timer <<'UNIT'
[Unit]
Description=chatd DB 매일 백업 (03:00 KST)
[Timer]
OnCalendar=*-*-* 18:00:00 UTC
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now chatd-backup.timer >/dev/null

# 띄우기 전에 지금 DB를 백업한다. 실패해도 배포는 계속하지만 경고를 남긴다
/usr/local/bin/chatd-backup.sh || echo "경고: 배포 전 백업에 실패했어요 — 지난 백업은 $DATA_HOST/backups에 있어요" >&2

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
# Google 로그인(F-026) — 클라이언트 ID는 비밀값이 아니지만 다른 설정과 같이 SSM에 둔다. 없으면 코드 로그인만
if gid=$(param /chatd/google-client-id 2>/dev/null); then
  printf 'GOOGLE_CLIENT_ID=%s\n' "$gid" >>"$envdir/chatd.env"
fi
unset gid
# 모델 바꾸기 (선택, ADR-037) — 비밀값 아님. 없으면 서버 기본값(ANTHROPIC_MODEL → claude-sonnet-5-5, 실시간 음성 → gpt-realtime)
if m=$(param /chatd/anthropic-model 2>/dev/null); then
  printf 'ANTHROPIC_MODEL=%s\n' "$m" >>"$envdir/chatd.env"
fi
if m=$(param /chatd/openai-realtime-model 2>/dev/null); then
  printf 'OPENAI_REALTIME_MODEL=%s\n' "$m" >>"$envdir/chatd.env"
fi
unset m
# 계정·로그인 (F-026·F-030): 파일 DB, 로그인 없는 AI 막기, Cloudflare가 넣는 진짜 IP로 상한 세기
cat >>"$envdir/chatd.env" <<'ENV'
DATA_DIR=/data
REQUIRE_LOGIN=on
CLIENT_IP_HEADER=CF-Connecting-IP
ENV
docker rm -f chatd >/dev/null 2>&1 || true
docker run -d --name chatd --network chatnet --restart unless-stopped \
  --read-only --tmpfs /tmp:rw,size=64m --cap-drop ALL --security-opt no-new-privileges \
  -v "$DATA_HOST:/data" \
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
