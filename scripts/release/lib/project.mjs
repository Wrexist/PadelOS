// scripts/release/lib/project.mjs
//
// The release facts the scripts need, read from project.yml so they are
// spelled in exactly one place: team id, marketing version, and each target's
// platform, bundle id, source folders, Info.plist and entitlements.
//
// project.yml is XcodeGen YAML. Rather than pull in a YAML package, this reads
// the small, regular subset the file uses (two-space indentation, `key: value`
// and `- path:` list items). If the file ever outgrows that, selftest.mjs
// fails loudly instead of the release reading a wrong value.

import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..')

const unquote = (value) => value.trim().replace(/^"(.*)"$/, '$1').replace(/^'(.*)'$/, '$1')

export function parseProject(text) {
  const lines = text.split('\n')
  const project = { teamId: '', marketingVersion: '', targets: {} }
  let section = null
  let target = null
  let block = null // which nested block of the current target we are in

  for (const raw of lines) {
    const line = raw.replace(/\s+#.*$/, '').replace(/^\s*#.*$/, '')
    if (!line.trim()) continue
    const indent = line.length - line.trimStart().length
    const text = line.trim()

    if (indent === 0) {
      section = text.replace(/:.*$/, '')
      target = null
      continue
    }

    if (section === 'settings') {
      const match = text.match(/^(DEVELOPMENT_TEAM|MARKETING_VERSION):\s*(.*)$/)
      if (match) {
        if (match[1] === 'DEVELOPMENT_TEAM') project.teamId = unquote(match[2])
        else project.marketingVersion = unquote(match[2])
      }
      continue
    }

    if (section !== 'targets') continue

    if (indent === 2 && text.endsWith(':')) {
      target = {
        name: text.slice(0, -1), type: '', platform: '', bundleId: '', deviceFamily: '', sources: [], info: '', entitlements: '',
      }
      project.targets[target.name] = target
      block = null
      continue
    }
    if (!target) continue

    if (indent === 4) {
      const match = text.match(/^(\w+):\s*(.*)$/)
      if (!match) continue
      block = match[1]
      if (block === 'type') target.type = unquote(match[2])
      if (block === 'platform') target.platform = unquote(match[2])
      continue
    }

    if (block === 'sources') {
      const match = text.match(/^-\s*path:\s*(.+)$/)
      if (match) target.sources.push(unquote(match[1]))
    } else if ((block === 'info' || block === 'entitlements') && indent === 6) {
      const match = text.match(/^path:\s*(.+)$/)
      if (match) target[block] = unquote(match[1])
    } else if (block === 'settings') {
      const match = text.match(/^(PRODUCT_BUNDLE_IDENTIFIER|TARGETED_DEVICE_FAMILY):\s*(.+)$/)
      if (match?.[1] === 'PRODUCT_BUNDLE_IDENTIFIER') target.bundleId = unquote(match[2])
      if (match?.[1] === 'TARGETED_DEVICE_FAMILY') target.deviceFamily = unquote(match[2])
    }
  }
  return project
}

export function readProject(root = REPO_ROOT) {
  const project = parseProject(readFileSync(join(root, 'project.yml'), 'utf8'))
  const shipping = Object.values(project.targets).filter((t) => t.type === 'application' || t.type === 'app-extension')
  const app = shipping.find((t) => t.type === 'application' && t.platform === 'iOS')
  return { ...project, shipping, app }
}

/** The bundle id a release uses: BUNDLE_ID from the environment wins over project.yml. */
export function appBundleId(env = process.env) {
  return env.BUNDLE_ID?.trim() || readProject().app.bundleId
}

// `node scripts/release/lib/project.mjs <field>` prints one value for shell scripts.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const project = readProject()
  const field = process.argv[2]
  const values = {
    team: process.env.APPLE_TEAM_ID?.trim() || project.teamId,
    version: project.marketingVersion,
    bundle: appBundleId(),
    'bundle-ids': project.shipping.map((t) => t.bundleId).join(' '),
  }
  if (!(field in values)) {
    console.error(`usage: node scripts/release/lib/project.mjs ${Object.keys(values).join('|')}`)
    process.exit(2)
  }
  console.log(values[field])
}
