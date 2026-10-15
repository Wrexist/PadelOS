#!/usr/bin/env node
// scripts/release/selftest.mjs — offline tests for the release tooling (runs in CI on Linux).
//
// Proves the JWT crypto (a token signed with a fresh key verifies as ES256),
// the tolerant key decoding, version comparison, and that project.yml still
// parses into the facts the release depends on.

import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import { compareVersionStrings, credentialsFromEnv, decodePrivateKey, mintToken } from './lib/asc.mjs'
import { parseProject, readProject } from './lib/project.mjs'

const tests = []
const test = (name, fn) => tests.push({ name, fn })

const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' })
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' })

test('decodes raw, base64 and CRLF keys', () => {
  assert.equal(decodePrivateKey(pem), pem.trim())
  assert.equal(decodePrivateKey(Buffer.from(pem).toString('base64')), pem.trim())
  assert.equal(decodePrivateKey(pem.replace(/\n/g, '\r\n')), pem.trim())
  const wrapped = Buffer.from(pem).toString('base64').replace(/(.{60})/g, '$1\r\n')
  assert.equal(decodePrivateKey(wrapped), pem.trim())
  assert.equal(decodePrivateKey('not a key'), null)
  assert.equal(decodePrivateKey(''), null)
})

test('reports exactly the missing credentials', () => {
  assert.deepEqual(credentialsFromEnv({}).missing.length, 3)
  const full = credentialsFromEnv({
    APP_STORE_CONNECT_KEY_ID: 'ABC123XYZ9', APP_STORE_CONNECT_ISSUER_ID: 'issuer', APP_STORE_CONNECT_API_KEY_BASE64: pem,
  })
  assert.deepEqual(full.missing, [])
  const fromPath = credentialsFromEnv(
    { APP_STORE_CONNECT_KEY_ID: 'K', APP_STORE_CONNECT_ISSUER_ID: 'I', APP_STORE_CONNECT_API_KEY_PATH: '/k.p8' },
    () => pem,
  )
  assert.deepEqual(fromPath.missing, [])
})

test('mints an ES256 token Apple can verify', () => {
  const now = Date.UTC(2026, 9, 15)
  const token = mintToken({ keyId: 'ABC123XYZ9', issuerId: 'issuer-uuid', privateKey: pem }, { now })
  const [header, payload, signature] = token.split('.')
  const decode = (part) => JSON.parse(Buffer.from(part, 'base64url').toString())
  assert.deepEqual(decode(header), { alg: 'ES256', kid: 'ABC123XYZ9', typ: 'JWT' })
  const claims = decode(payload)
  assert.equal(claims.aud, 'appstoreconnect-v1')
  assert.equal(claims.exp - claims.iat, 19 * 60)
  const raw = Buffer.from(signature, 'base64url')
  assert.equal(raw.length, 64, 'JWS ES256 signatures are raw r||s, 64 bytes')
  assert.ok(crypto.verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, raw))
})

test('compares versions numerically', () => {
  assert.equal(compareVersionStrings('1.10.0', '1.9'), 1)
  assert.equal(compareVersionStrings('1.1', '1.1.0'), 0)
  assert.equal(compareVersionStrings('1.0.0', '1.0.1'), -1)
})

test('project.yml yields the release facts', () => {
  const project = readProject()
  assert.match(project.teamId, /^[A-Z0-9]{10}$/)
  assert.match(project.marketingVersion, /^\d+\.\d+\.\d+$/)
  assert.equal(project.app.bundleId, 'app.padelos.PadelOS')
  assert.equal(project.shipping.length, 4, 'iPhone app, Live Activity widgets, watch app, watch complication')
  for (const target of project.shipping) {
    assert.ok(target.bundleId, `${target.name} has a bundle id`)
    assert.ok(target.info, `${target.name} has an Info.plist`)
    assert.ok(target.sources.length, `${target.name} has sources`)
  }
})

test('parser ignores comments and quoted values', () => {
  const project = parseProject(
    'settings:\n  base:\n    # a comment\n    DEVELOPMENT_TEAM: "AB12CD34EF" # trailing\n    MARKETING_VERSION: \'2.0.0\'\n' +
      'targets:\n  App:\n    type: application\n    platform: iOS\n    sources:\n      - path: Apps/X\n' +
      '    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: a.b.c\n',
  )
  assert.equal(project.teamId, 'AB12CD34EF')
  assert.equal(project.marketingVersion, '2.0.0')
  assert.deepEqual(project.targets.App.sources, ['Apps/X'])
  assert.equal(project.targets.App.bundleId, 'a.b.c')
})

let failed = 0
for (const { name, fn } of tests) {
  try {
    await fn()
    console.log(`✓ ${name}`)
  } catch (error) {
    failed++
    console.error(`✗ ${name}\n  ${error.message}`)
  }
}
console.log(`\n${tests.length - failed}/${tests.length} passed`)
process.exit(failed ? 1 : 0)
