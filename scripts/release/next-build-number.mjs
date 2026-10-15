#!/usr/bin/env node
// scripts/release/next-build-number.mjs
//
// The next CFBundleVersion: strictly higher than every build App Store Connect
// holds for the app, so an upload is never refused with "The bundle version
// must be higher than the previously uploaded version" — including after a
// build uploaded by hand from a Mac, which a CI run counter knows nothing about.
//
//   1. App Store Connect: highest numeric build on record + 1 (needs the API
//      key and an existing app record).
//   2. Fallback: epoch seconds. Monotonic and larger than any small build
//      number, so both branches keep the one property that matters.
//
// stdout: the number and nothing else (BUILD=$(node …)); diagnostics on stderr.

import { readFileSync } from 'node:fs'
import { AppStoreConnect, findApp } from './lib/asc.mjs'
import { appBundleId } from './lib/project.mjs'

const log = (...args) => console.error('[next-build-number]', ...args)

function fallback(reason) {
  const value = Math.floor(Date.now() / 1000)
  log(`falling back to epoch seconds (${reason}) → ${value}`)
  console.log(value)
  process.exit(0)
}

const bundleId = appBundleId()
let client
try {
  client = AppStoreConnect.fromEnv(process.env, (path) => readFileSync(path, 'utf8'))
} catch (error) {
  fallback(error.message)
}

try {
  const app = await findApp(client, bundleId)
  if (!app) fallback(`no App Store Connect app record for ${bundleId}`)
  // Apple sorts `version` as text ("9" > "10"), so compare numerically here.
  const builds = await client.getAll(`/v1/builds?filter[app]=${app.id}&limit=200&fields[builds]=version`)
  const highest = builds
    .map((build) => Number.parseInt(build.attributes?.version ?? '', 10))
    .filter(Number.isFinite)
    .reduce((max, value) => Math.max(max, value), 0)
  if (highest === 0 && builds.length > 0) fallback(`${builds.length} build(s) on record but none numeric`)
  log(`App Store Connect holds ${builds.length} build(s) for ${bundleId}; highest ${highest}`)
  console.log(highest + 1)
} catch (error) {
  fallback(`lookup failed — ${error.message}`)
}
