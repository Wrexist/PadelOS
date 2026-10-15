#!/usr/bin/env node
// scripts/release/check-release.mjs
//
// The bundle rules App Store Connect enforces, checked from the repository in
// milliseconds on Linux — before a macOS runner is booked, and before a local
// archive is started. Every rule here is a rejection that otherwise arrives
// last: after the archive, the export and the upload, as an email.
//
//   · team id and marketing version are well-formed
//   · every app target has a 1024×1024 icon without alpha
//   · every shipping target that calls a "required reason" API (UserDefaults,
//     file timestamps, boot time, disk space) bundles a PrivacyInfo.xcprivacy
//     declaring it (ITMS-91053), and the iPhone app has a manifest at all
//   · export compliance is answered (ITSAppUsesNonExemptEncryption), so
//     TestFlight does not hold every build for a questionnaire
//   · watch and extension bundle ids nest under their parent and the watch
//     names the right companion
//   · the App Group in the entitlements matches the one the code opens
//   · an iPad-capable target supports every iPad orientation (error 90474)
//
// Usage: node scripts/release/check-release.mjs [--version 1.2.3]
// Exit 1 on any error; warnings never fail.

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { REPO_ROOT, readProject } from './lib/project.mjs'

const args = process.argv.slice(2)
const versionArg = args.includes('--version') ? args[args.indexOf('--version') + 1] : null

const errors = []
const warnings = []
const ok = (message) => console.log(`✓ ${message}`)
const fail = (message) => errors.push(message)
const warn = (message) => warnings.push(message)

const project = readProject()
const read = (path) => readFileSync(join(REPO_ROOT, path), 'utf8')

function walk(dir, out = []) {
  const full = join(REPO_ROOT, dir)
  if (!existsSync(full)) return out
  for (const entry of readdirSync(full)) {
    const rel = join(dir, entry)
    if (statSync(join(REPO_ROOT, rel)).isDirectory()) walk(rel, out)
    else out.push(rel)
  }
  return out
}
const filesOf = (target) => [...new Set(target.sources.flatMap((source) => walk(source)))]

// ── Identity ────────────────────────────────────────────────────────────────
if (/^[A-Z0-9]{10}$/.test(process.env.APPLE_TEAM_ID?.trim() || project.teamId)) {
  ok(`Team id ${process.env.APPLE_TEAM_ID?.trim() || project.teamId}`)
} else {
  fail(`DEVELOPMENT_TEAM in project.yml must be a 10-character team id (found "${project.teamId}").`)
}

for (const [label, version] of [['MARKETING_VERSION', project.marketingVersion], ['--version', versionArg]]) {
  if (version === null) continue
  if (/^\d+\.\d+(\.\d+)?$/.test(version)) ok(`${label} ${version}`)
  else fail(`${label} "${version}" must look like 1.0 or 1.0.0 — App Store Connect refuses anything else, at the very end.`)
}

if (!project.app) fail('project.yml has no iOS application target.')

// ── Icons ───────────────────────────────────────────────────────────────────
for (const target of project.shipping.filter((t) => t.type === 'application')) {
  const iconSet = filesOf(target).find((path) => /AppIcon\.appiconset\/Contents\.json$/.test(path))
  if (!iconSet) {
    fail(`${target.name}: no AppIcon.appiconset in its sources.`)
    continue
  }
  const contents = JSON.parse(read(iconSet))
  const image = (contents.images ?? []).find((entry) => entry.size === '1024x1024' && entry.filename)
  if (!image) {
    fail(`${target.name}: ${iconSet} has no 1024x1024 image.`)
    continue
  }
  const pngPath = join(iconSet, '..', image.filename)
  const png = readFileSync(join(REPO_ROOT, pngPath))
  if (png.subarray(1, 4).toString() !== 'PNG') {
    fail(`${target.name}: ${pngPath} is not a PNG.`)
    continue
  }
  const width = png.readUInt32BE(16)
  const height = png.readUInt32BE(20)
  const colorType = png[25] // 4 = grey+alpha, 6 = RGBA
  const hasTransparencyChunk = png.includes(Buffer.from('tRNS'))
  if (width !== 1024 || height !== 1024) fail(`${target.name}: ${pngPath} is ${width}×${height}, not 1024×1024.`)
  else if (colorType === 4 || colorType === 6 || hasTransparencyChunk) {
    fail(`${target.name}: ${pngPath} has an alpha channel; App Store icons must be opaque (flatten it onto a background).`)
  } else ok(`${target.name} icon 1024×1024, opaque`)
}

// ── Privacy manifests (required-reason APIs) ────────────────────────────────
const REQUIRED_REASON_APIS = [
  { category: 'NSPrivacyAccessedAPICategoryUserDefaults', pattern: /\bUserDefaults\b|@AppStorage\b/ },
  { category: 'NSPrivacyAccessedAPICategoryFileTimestamp', pattern: /\.(creationDate|modificationDate|contentModificationDateKey|creationDateKey)\b|attributesOfItem|\bgetattrlist\b/ },
  { category: 'NSPrivacyAccessedAPICategorySystemBootTime', pattern: /\bsystemUptime\b|\bmach_absolute_time\b/ },
  { category: 'NSPrivacyAccessedAPICategoryDiskSpace', pattern: /volumeAvailableCapacity|systemFreeSize|\bstatfs\b/ },
  { category: 'NSPrivacyAccessedAPICategoryActiveKeyboards', pattern: /\bactiveInputModes\b/ },
]

for (const target of project.shipping) {
  const files = filesOf(target)
  const manifests = files.filter((path) => path.endsWith('PrivacyInfo.xcprivacy'))
  const used = new Map()
  for (const path of files.filter((p) => p.endsWith('.swift'))) {
    const source = read(path)
    for (const api of REQUIRED_REASON_APIS) {
      if (api.pattern.test(source) && !used.has(api.category)) used.set(api.category, path)
    }
  }

  if (manifests.length > 1) {
    fail(`${target.name}: ${manifests.length} privacy manifests in its sources (${manifests.join(', ')}); Xcode allows one per bundle.`)
    continue
  }
  if (manifests.length === 0) {
    if (used.size > 0) {
      fail(`${target.name}: uses ${[...used.keys()].join(', ')} (e.g. ${[...used.values()][0]}) but bundles no PrivacyInfo.xcprivacy (ITMS-91053).`)
    } else if (target === project.app) {
      fail(`${target.name}: the app has no PrivacyInfo.xcprivacy. Add one even if it declares nothing.`)
    } else {
      ok(`${target.name} uses no required-reason APIs`)
    }
    continue
  }

  const manifest = read(manifests[0])
  const declared = [...manifest.matchAll(/<string>(NSPrivacyAccessedAPICategory\w+)<\/string>/g)].map((m) => m[1])
  const missing = [...used.keys()].filter((category) => !declared.includes(category))
  if (missing.length) {
    fail(`${target.name}: ${manifests[0]} does not declare ${missing.join(', ')} (used in ${missing.map((c) => used.get(c)).join(', ')}).`)
  } else {
    ok(`${target.name} privacy manifest${declared.length ? ` declares ${declared.map((c) => c.replace('NSPrivacyAccessedAPICategory', '')).join(', ')}` : ''}`)
  }
  if (/<key>NSPrivacyAccessedAPITypeReasons<\/key>\s*<array\/>/.test(manifest)) {
    fail(`${target.name}: ${manifests[0]} declares an API with no reason code.`)
  }
}

// ── Info.plist facts ────────────────────────────────────────────────────────
if (project.app?.info) {
  const plist = read(project.app.info)
  if (/<key>ITSAppUsesNonExemptEncryption<\/key>\s*<false\/>/.test(plist)) ok('Export compliance answered (ITSAppUsesNonExemptEncryption = NO)')
  else warn(`${project.app.info} does not set ITSAppUsesNonExemptEncryption; every TestFlight build will wait for the export-compliance question.`)
}

const watch = project.shipping.find((t) => t.type === 'application' && t.platform === 'watchOS')
if (watch && project.app) {
  const plist = read(watch.info)
  const companion = plist.match(/<key>WKCompanionAppBundleIdentifier<\/key>\s*<string>([^<]+)<\/string>/)?.[1]
  if (companion === project.app.bundleId) ok(`Watch companion is ${companion}`)
  else fail(`${watch.info}: WKCompanionAppBundleIdentifier is "${companion}", expected ${project.app.bundleId}.`)
}

for (const target of project.shipping.filter((t) => t !== project.app)) {
  const parent = target.platform === 'watchOS' && target.type === 'app-extension' ? watch : project.app
  if (parent && !target.bundleId.startsWith(`${parent.bundleId}.`)) {
    fail(`${target.name}: bundle id ${target.bundleId} must start with ${parent.bundleId}. (Apple rejects embedded bundles outside their parent's namespace.)`)
  }
}
if (!errors.some((e) => e.includes('namespace'))) ok('Embedded bundle ids nest under their parents')

// ── App Groups ──────────────────────────────────────────────────────────────
const groupsInEntitlements = new Set()
for (const target of project.shipping.filter((t) => t.entitlements)) {
  const text = read(target.entitlements)
  for (const match of text.matchAll(/<string>(group\.[^<]+)<\/string>/g)) groupsInEntitlements.add(match[1])
}
const groupsInCode = new Set()
for (const path of walk('Apps').filter((p) => p.endsWith('.swift'))) {
  for (const match of read(path).matchAll(/"(group\.[A-Za-z0-9.-]+)"/g)) groupsInCode.add(match[1])
}
for (const group of groupsInCode) {
  if (!groupsInEntitlements.has(group)) fail(`The code opens App Group "${group}", but no entitlements file grants it.`)
}
if (groupsInCode.size && [...groupsInCode].every((g) => groupsInEntitlements.has(g))) ok(`App Group ${[...groupsInCode].join(', ')} matches the entitlements`)

// ── iPad orientations (error 90474) ─────────────────────────────────────────
for (const target of project.shipping.filter((t) => t.platform === 'iOS' && t.type === 'application')) {
  if (!target.deviceFamily.split(',').map((s) => s.trim()).includes('2')) {
    ok(`${target.name} is iPhone-only (no iPad multitasking orientation rule)`)
    continue
  }
  const plist = read(target.info)
  const full = /<key>UIRequiresFullScreen<\/key>\s*<true\/>/.test(plist)
  const ipad = plist.match(/<key>UISupportedInterfaceOrientations~ipad<\/key>\s*<array>([\s\S]*?)<\/array>/)?.[1] ?? ''
  if (!full && (ipad.match(/<string>/g) ?? []).length < 4) {
    fail(`${target.name} runs on iPad but does not support all four iPad orientations or set UIRequiresFullScreen (error 90474).`)
  }
}

// ── Report ──────────────────────────────────────────────────────────────────
for (const message of warnings) console.warn(`⚠︎ ${message}`)
if (errors.length) {
  console.error('')
  for (const message of errors) console.error(`✗ ${message}`)
  process.exit(1)
}
console.log('\n✓ Release checks passed.')
