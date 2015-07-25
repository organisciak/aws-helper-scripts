# aws-helper-scripts
Wrappers around the AWS SDK to speed up common EC2 uses

## backupCrowdy.coffee

Script to create and tag image from the newest instance that matches `purpose` in the `config.json` file.

## createCrowdy.coffee

A script to power up an Instance from the newest AMI that matches `tag:purpose` value.
