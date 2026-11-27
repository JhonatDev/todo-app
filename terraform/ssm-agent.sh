#!/bin/bash
set -eu
if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap install amazon-ssm-agent --classic
fi
snap start --enable amazon-ssm-agent
