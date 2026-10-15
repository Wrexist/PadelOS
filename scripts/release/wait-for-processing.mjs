#!/usr/bin/env node
// scripts/release/wait-for-processing.mjs
//
// Poll App Store Connect until an uploaded build finishes processing.
// `altool --upload-app` returns when the bytes are transferred; Apple then
// processes the build for minutes to half an hour, and that is where invalid
// binaries surface. This runs on a cheap ubuntu runner so no macOS minutes are
// spent waiting (Airline-Empire measured 53 idle minutes on macOS doing this).
//
// Usage: node scripts/release/wait-for-processing.mjs --version 1.0.0 --build 42 [--timeout 45]
// Exit 0 when VALID; 1 when INVALID/FAILED or on timeout.

import { readFileSync } from 'node:fs'
import { AppStoreConnect, findApp, sleep } from './lib/asc.mjs'
import { appBundleId } from './lib/project.mjs'

const args = process.argv.slice(2)
const valueOf = (flag, fallback = null) => (args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback)
const versionString = valueOf('--version')
const buildNumber = valueOf('--build')
const timeoutMinutes = Number.parseInt(valueOf('--timeout', '40'), 10)

if (!versionString || !buildNumber) {
  console.error('Usage: node scripts/release/wait-for-processing.mjs --version <x.y.z> --build <n> [--timeout <minutes>]')
  process.exit(2)
}

const client = AppStoreConnect.fromEnv(process.env, (path) => readFileSync(path, 'utf8'))
const bundleId = appBundleId()
const app = await findApp(client, bundleId)
if (!app) {
  console.error(`✗ No app record for ${bundleId}; nothing to wait for.`)
  process.exit(1)
}

const deadline = Date.now() + timeoutMinutes * 60_000
let lastState = null
while (Date.now() < deadline) {
  const builds = await client.getAll(
    `/v1/builds?filter[app]=${app.id}&filter[preReleaseVersion.version]=${encodeURIComponent(versionString)}` +
      `&filter[version]=${encodeURIComponent(buildNumber)}&limit=10` +
      '&fields[builds]=version,processingState,usesNonExemptEncryption',
  )
  const build = builds[0]
  if (!build) {
    console.log('… build not visible in App Store Connect yet')
  } else {
    const state = build.attributes?.processingState
    if (state !== lastState) console.log(`… ${versionString} (${buildNumber}): ${state}`)
    lastState = state
    if (state === 'VALID') {
      console.log(`\n✓ Build ${buildNumber} processed and is available in TestFlight.`)
      if (build.attributes?.usesNonExemptEncryption == null) {
        console.warn('⚠︎ Export compliance is unanswered; TestFlight will ask before testers can install it.')
      }
      process.exit(0)
    }
    if (state === 'INVALID' || state === 'FAILED') {
      console.error(`\n✗ Apple rejected build ${buildNumber} during processing (${state}).`)
      console.error('  The reason is emailed to the account holder and shown in App Store Connect → TestFlight.')
      process.exit(1)
    }
  }
  await sleep(60_000)
}
console.error(`\n✗ Build ${buildNumber} was not VALID after ${timeoutMinutes} minutes; check App Store Connect.`)
process.exit(1)
