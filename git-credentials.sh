#!/usr/bin/env bash

echo "Github personal access token: "
read token
echo "https://$token:x-oauth-basic@github.com" >> ~/.git-credentials
echo "Credentials stored in ~/.git-credentials"