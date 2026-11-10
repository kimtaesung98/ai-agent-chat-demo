#!/usr/bin/env bash
# AWS 리소스를 한 번 만든다 (SPEC F-014, ARCHITECTURE ADR-018). 다시 실행해도 있는 것은 건너뛴다.
#
# 준비: AWS CLI v2로 로그인된 PC (aws login 또는 aws configure sso). 키를 이 파일에 쓰지 않는다.
#   GITHUB_REPO=kimtaesung98/ai-agent-chat-demo ./deploy/provision.sh
# 끝나면 GitHub 저장소 변수(Variables)에 넣을 값 4개를 출력한다. 비밀값은 출력하지 않는다.
set -euo pipefail
cd "$(dirname "$0")"

REGION=${AWS_REGION:-ap-northeast-2}
GITHUB_REPO=${GITHUB_REPO:-kimtaesung98/ai-agent-chat-demo}
INSTANCE_TYPE=${INSTANCE_TYPE:-t4g.small}
export AWS_REGION=$REGION AWS_PAGER=""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "계정 $ACCOUNT_ID · 리전 $REGION · 저장소 $GITHUB_REPO"
fill() { sed -e "s|\${REGION}|$REGION|g" -e "s|\${ACCOUNT_ID}|$ACCOUNT_ID|g" -e "s|\${GITHUB_REPO}|$GITHUB_REPO|g" "$1"; }
exists() { "$@" >/dev/null 2>&1; }

# 1. ECR 저장소 (이미지 10개만 보관)
if ! exists aws ecr describe-repositories --repository-names chatd; then
  aws ecr create-repository --repository-name chatd --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 >/dev/null
  aws ecr put-lifecycle-policy --repository-name chatd --lifecycle-policy-text \
    '{"rules":[{"rulePriority":1,"description":"keep 10","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":10},"action":{"type":"expire"}}]}' >/dev/null
  echo "✓ ECR chatd"
fi
ECR_URI=$(aws ecr describe-repositories --repository-names chatd --query 'repositories[0].repositoryUri' --output text)

# 2. GitHub OIDC 공급자 + 배포 역할 (장기 키 없음, production 환경에서만)
OIDC_ARN="arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
if ! exists aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN"; then
  aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
  echo "✓ GitHub OIDC 공급자"
fi
if ! exists aws iam get-role --role-name chatd-github-deploy; then
  aws iam create-role --role-name chatd-github-deploy \
    --assume-role-policy-document "$(fill github-trust-policy.json)" >/dev/null
  echo "✓ 역할 chatd-github-deploy"
fi
aws iam put-role-policy --role-name chatd-github-deploy --policy-name deploy \
  --policy-document "$(fill github-deploy-policy.json)"
DEPLOY_ROLE_ARN=$(aws iam get-role --role-name chatd-github-deploy --query Role.Arn --output text)

# 3. EC2 역할: SSM 접속, ECR 읽기, /chatd/* 파라미터, Polly·Transcribe
if ! exists aws iam get-role --role-name chatd-ec2; then
  aws iam create-role --role-name chatd-ec2 --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name chatd-ec2 --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam attach-role-policy --role-name chatd-ec2 --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  echo "✓ 역할 chatd-ec2"
fi
aws iam put-role-policy --role-name chatd-ec2 --policy-name chatd --policy-document "$(fill instance-policy.json)"
if ! exists aws iam get-instance-profile --instance-profile-name chatd-ec2; then
  aws iam create-instance-profile --instance-profile-name chatd-ec2 >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name chatd-ec2 --role-name chatd-ec2
  echo "✓ 인스턴스 프로필 chatd-ec2 (IAM 반영 대기 15초)"
  sleep 15
fi

# 4. 보안 그룹: 인바운드 규칙 없음 (F-014 AC3). 기본 VPC 사용
VPC_ID=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=chatd-sg Name=vpc-id,Values="$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group --group-name chatd-sg --vpc-id "$VPC_ID" \
    --description "chatd: no inbound, Cloudflare Tunnel is outbound only" --query GroupId --output text)
  echo "✓ 보안 그룹 $SG_ID (인바운드 없음)"
fi

# 5. EC2 (Amazon Linux 2023 arm64, IMDSv2 필수, 암호화 디스크). Docker만 설치하고 앱은 배포 워크플로가 띄운다
INSTANCE_ID=$(aws ec2 describe-instances --filters Name=tag:app,Values=chatd Name=instance-state-name,Values=pending,running,stopped \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
if [ "$INSTANCE_ID" = "None" ]; then
  AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 --query Parameter.Value --output text)
  USER_DATA=$'#!/bin/bash\nset -e\ndnf install -y docker\nsystemctl enable --now docker\n'
  for try in 1 2 3; do
    INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
      --iam-instance-profile Name=chatd-ec2 --security-group-ids "$SG_ID" \
      --metadata-options HttpTokens=required,HttpEndpoint=enabled \
      --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true}' \
      --user-data "$USER_DATA" \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=chatd},{Key=app,Value=chatd}]' \
      --query 'Instances[0].InstanceId' --output text) && break
    echo "인스턴스 프로필이 아직 반영되지 않았어요. 15초 뒤 다시 ($try/3)"; sleep 15
  done
  echo "✓ EC2 $INSTANCE_ID ($INSTANCE_TYPE)"
fi

cat <<OUT

다음 값을 GitHub 저장소 Settings → Secrets and variables → Actions → Variables 에 넣으세요 (비밀값 아님):
  AWS_REGION            $REGION
  AWS_DEPLOY_ROLE_ARN   $DEPLOY_ROLE_ARN
  ECR_REPOSITORY_URI    $ECR_URI
  EC2_INSTANCE_ID       $INSTANCE_ID

비밀값은 직접 넣으세요 (값이 화면 기록에 남지 않게 read -s 사용):
  read -rs K && aws ssm put-parameter --region $REGION --name /chatd/anthropic-api-key --type SecureString --value "\$K" --overwrite; unset K
  read -rs T && aws ssm put-parameter --region $REGION --name /chatd/cloudflare-tunnel-token --type SecureString --value "\$T" --overwrite; unset T
OUT
