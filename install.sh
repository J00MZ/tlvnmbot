#!/usr/bin/env bash

echo "install stuff"
yum update -y && \
yum install -y python3.11 git python3-pip && \
dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo -y && \
#gh auth login
#gh repo clone J00MZ/tlvnmbot
cd tlvnmbot
python3 -p pip3 install poetry
poetry install
mkdir logs
TG_TOKEN=$TG_TOKEN nohup poetry run python3 app.py >> logs/run.log 2>&1 &
