#!/usr/bin/env bun
/// <reference path="../runner.ts" />

const result = await truapi.resourceAllocation.request({
  resources: [
    { tag: "SmartContractAllowance", value: 0 },
  ],
})

assert(result.isOk(), "Resource allocation request failed")
console.log(result.value)
