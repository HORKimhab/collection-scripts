#!/bin/bash
# Script to clear all AWS credentials and caches

echo "Clearing AWS credentials and config files..."
rm -f ~/.aws/credentials
rm -f ~/.aws/config

echo "Clearing AWS CLI cache..."
rm -rf ~/.aws/cli/cache

echo "Clearing AWS SSO cache..."
rm -rf ~/.aws/sso/cache

echo "Unsetting AWS environment variables..."
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_PROFILE

echo "All AWS credentials cleared!"