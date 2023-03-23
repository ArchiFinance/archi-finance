#!/bin/bash

rm -rf ./coverage
rm -f ./coverage.json

npx hardhat clean
npx hardhat coverage --network hardhat
