#!/usr/bin/env node
import { runHostCli } from "../dist/bin/host.js";

runHostCli(process.argv.slice(2));
