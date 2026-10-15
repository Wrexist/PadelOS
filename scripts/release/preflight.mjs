#!/usr/bin/env node
// scripts/release/preflight.mjs
//
// The questions only Apple can answer, asked in seconds on a cheap runner
// before an archive is paid for:
//
//   1. Are the API key secrets present and does the .p8 decode?   (hard fail)
//   2. Does Apple accept the key?                                   (hard fail on 401/403)
//   3. Is there an App Store Connect app record for the bundle id?  (fail when uploading)
//   4. Is the marketing version still open for builds?             (hard fail if released/in review)
//   5. Are the four bundle ids registered on the developer portal?  (warning — the
//      export with -allowProvisioningUpdates registers missing ones itself)
//
// Fail-open on anything it cannot determine (network, unexpected shapes): a
// preflight that blocks a release for a reason it cannot name is worse than none.
//
// Usage: node scripts/release/preflight.mjs [--version 1.0.0] [--upload]

import { readFileSync } from 'node:fs'
import {
  AppStoreConnect, OPEN_VERSION_STATES, compareVersionStrings, findApp, findBundleId, listVersions, versionState,
} from './lib/asc.mjs'
import { readProject } from './lib/project.mjs'

const args = process.argv.slice(2)
const wantedVersion = args.includes('--version') ? args[args.indexOf('--version') + 1] : null
const uploading = args.includes('--upload')

const project = readProject()
const bundleId = process.env.BUNDLE_ID?.trim() || project.app.bundleId
const problems = []

function inconclusive(reason) {
  console.warn(`⚠︎ Preflight could not finish: ${reason}`)
  console.warn('  Passing anyway; the build itself remains the source of truth.')
  process.exit(0)
}

let client
try {
  client = AppStoreConnect.fromEnv(process.env, (path) => readFileSync(path, 'utf8'))
} catch (error) {
  console.error(`✗ ${error.message}`)
  console.error('  Add them under Settings → Secrets and variables → Actions (docs/RELEASE.md §3).')
  process.exit(1)
}
console.log('✓ App Store Connect key present and decodes to a private key.')

let app
try {
  app = await findApp(client, bundleId)
} catch (error) {
  if (error.status === 401 || error.status === 403) {
    console.error(`✗ Apple rejected the API key (HTTP ${error.status}).`)
    console.error('  Key id, issuer id and .p8 must all come from the SAME key, and the key needs')
    console.error('  the Admin role for cloud-managed signing (App Manager is enough for uploads).')
    console.error(`  ${error.message}`)
    process.exit(1)
  }
  inconclusive(error.message)
}

if (!app) {
  const message =
    `No App Store Connect app record for ${bundleId}. Create it once: App Store Connect → Apps → + → New App, ` +
    `platform iOS, bundle id ${bundleId} (docs/RELEASE.md §2).`
  if (uploading) {
    console.error(`✗ ${message}`)
    process.exit(1)
  }
  console.warn(`⚠︎ ${message} Archive-only runs still work.`)
} else {
  console.log(`✓ App record "${app.attributes?.name}" (id ${app.id}).`)
  try {
    const versions = await listVersions(client, app.id)
    for (const version of versions.slice(0, 5)) {
      console.log(`  · ${version.attributes?.versionString} — ${versionState(version)}`)
    }
    if (wantedVersion) {
      const existing = versions.find((v) => compareVersionStrings(v.attributes?.versionString, wantedVersion) === 0)
      const highestClosed = versions
        .filter((v) => !OPEN_VERSION_STATES.has(versionState(v)))
        .map((v) => v.attributes?.versionString)
        .sort(compareVersionStrings)
        .pop()
      if (existing && !OPEN_VERSION_STATES.has(versionState(existing))) {
        problems.push(`Version ${wantedVersion} is ${versionState(existing)} and takes no new builds. Bump the version.`)
      } else if (!existing && highestClosed && compareVersionStrings(wantedVersion, highestClosed) <= 0) {
        problems.push(`Version ${wantedVersion} is not higher than ${highestClosed}, which is already submitted or released.`)
      } else {
        console.log(`✓ Version ${wantedVersion} can take a new build.`)
      }
    }
  } catch (error) {
    console.warn(`⚠︎ Version lookup failed — ${error.message}`)
  }
}

try {
  for (const target of project.shipping) {
    const registered = await findBundleId(client, target.bundleId)
    if (registered) console.log(`✓ Identifier ${target.bundleId} registered.`)
    else console.warn(`⚠︎ Identifier ${target.bundleId} is not registered yet; the export's automatic signing will try to register it.`)
  }
} catch (error) {
  // An App Manager key 403s on the provisioning API and still uploads fine.
  console.warn(`⚠︎ Could not read registered identifiers (${error.status ?? error.message}); skipping.`)
}

if (problems.length) {
  for (const problem of problems) console.error(`✗ ${problem}`)
  process.exit(1)
}
console.log('\n✓ Preflight clear.')
