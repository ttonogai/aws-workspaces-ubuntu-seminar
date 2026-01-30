#!/bin/bash

# Ubuntu Bundle確認スクリプト

set -e

REGION="ap-northeast-1"

echo "=== ap-northeast-1 リージョンの Ubuntu Bundle 確認 ==="
echo

# 利用可能なUbuntu Bundle一覧を取得
echo "利用可能なUbuntu Bundle:"
aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --query "Bundles[?contains(Name, 'Ubuntu')].{BundleId:BundleId,Name:Name,ComputeType:ComputeType.Name,Owner:Owner}" \
    --output table

echo
echo "=== Performance Bundle のみ ==="
aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --query "Bundles[?contains(Name, 'Ubuntu') && ComputeType.Name=='PERFORMANCE'].{BundleId:BundleId,Name:Name,ComputeType:ComputeType.Name,Owner:Owner}" \
    --output table

echo
echo "=== 全Bundle一覧（参考） ==="
aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --query "Bundles[].{BundleId:BundleId,Name:Name,ComputeType:ComputeType.Name,Owner:Owner}" \
    --output table | head -20