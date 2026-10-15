// scripts/release/lib/asc.mjs
//
// A dependency-free App Store Connect API client: ES256 JWT minting plus the
// little JSON:API plumbing the release scripts need. Node is preinstalled on
// every GitHub runner and on most Macs, and `node:crypto` signs ES256 out of
// the box, so there is no package.json and nothing here ships in the app.
//
// Ported from Wrexist/Airline-Empire's scripts/asc/lib/asc.mjs, which has
// authenticated against the live API and driven real TestFlight uploads.

import crypto from 'node:crypto'
import { Buffer } from 'node:buffer'

export const ASC_HOST = 'https://api.appstoreconnect.apple.com'

/** Apple rejects a token older than 20 minutes; 19 leaves room for clock skew. */
const TOKEN_TTL_SECONDS = 19 * 60

function b64url(input) {
  return Buffer.from(input).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

/**
 * The .p8 private key, however it was pasted: raw PEM text, base64 of the PEM,
 * either with CRLF line endings. A release must not fail on a stray carriage return.
 */
export function decodePrivateKey(raw) {
  if (!raw || !raw.trim()) return null
  let text = raw.replace(/\r/g, '').trim()
  if (!text.includes('BEGIN')) {
    try {
      text = Buffer.from(text.replace(/\s+/g, ''), 'base64').toString('utf8').replace(/\r/g, '').trim()
    } catch {
      return null
    }
  }
  return text.includes('BEGIN') && text.includes('PRIVATE KEY') ? text : null
}

/**
 * Credentials from the environment, or a list of what is missing.
 *
 * Same secret names as Airline-Empire, so the same three values can be pasted
 * into this repository. Locally, APP_STORE_CONNECT_API_KEY_PATH may point at
 * the AuthKey_XXXX.p8 file instead of carrying its contents.
 */
export function credentialsFromEnv(env = process.env, readFile = null) {
  const keyId = env.APP_STORE_CONNECT_KEY_ID?.trim()
  const issuerId = env.APP_STORE_CONNECT_ISSUER_ID?.trim()
  let raw = env.APP_STORE_CONNECT_API_KEY_BASE64 ?? ''
  if (!raw.trim() && env.APP_STORE_CONNECT_API_KEY_PATH && readFile) {
    try {
      raw = readFile(env.APP_STORE_CONNECT_API_KEY_PATH)
    } catch {
      raw = ''
    }
  }
  const privateKey = decodePrivateKey(raw)

  const missing = []
  if (!keyId) missing.push('APP_STORE_CONNECT_KEY_ID')
  if (!issuerId) missing.push('APP_STORE_CONNECT_ISSUER_ID')
  if (!privateKey) {
    missing.push(
      raw.trim()
        ? 'APP_STORE_CONNECT_API_KEY_BASE64 (set, but did not decode to a PEM private key)'
        : 'APP_STORE_CONNECT_API_KEY_BASE64 (or APP_STORE_CONNECT_API_KEY_PATH)',
    )
  }
  return { keyId, issuerId, privateKey, missing }
}

/**
 * An App Store Connect bearer token. ES256 wants the raw r||s signature, not
 * Node's default DER — hence `dsaEncoding: 'ieee-p1363'`. Getting this wrong
 * yields a well-formed token that Apple rejects with a bare 401.
 */
export function mintToken({ keyId, issuerId, privateKey }, { now = Date.now() } = {}) {
  const issuedAt = Math.floor(now / 1000)
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' }
  const payload = { iss: issuerId, iat: issuedAt, exp: issuedAt + TOKEN_TTL_SECONDS, aud: 'appstoreconnect-v1' }
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`
  const signature = crypto.sign('sha256', Buffer.from(signingInput), {
    key: crypto.createPrivateKey({ key: privateKey, format: 'pem' }),
    dsaEncoding: 'ieee-p1363',
  })
  return `${signingInput}.${b64url(signature)}`
}

/** Apple's JSON:API errors carry the useful part in `errors[].detail`. */
export class AscError extends Error {
  constructor(status, method, path, body) {
    const errors = Array.isArray(body?.errors) ? body.errors : []
    const detail = errors
      .map((e) => [e.title, e.detail, e.source?.pointer ?? e.source?.parameter].filter(Boolean).join(' — '))
      .join('\n  ')
    super(`${method} ${path} → HTTP ${status}${detail ? `\n  ${detail}` : ''}`)
    this.name = 'AscError'
    this.status = status
    this.errors = errors
  }
}

export class AppStoreConnect {
  #credentials
  #token = null
  #tokenExpiresAt = 0

  constructor(credentials) {
    this.#credentials = credentials
  }

  static fromEnv(env = process.env, readFile = null) {
    const credentials = credentialsFromEnv(env, readFile)
    if (credentials.missing.length) {
      const error = new Error(`Missing App Store Connect credentials: ${credentials.missing.join(', ')}`)
      error.missing = credentials.missing
      throw error
    }
    return new AppStoreConnect(credentials)
  }

  token() {
    const now = Date.now()
    if (!this.#token || now > this.#tokenExpiresAt - 60_000) {
      this.#token = mintToken(this.#credentials, { now })
      this.#tokenExpiresAt = now + TOKEN_TTL_SECONDS * 1000
    }
    return this.#token
  }

  /** One request; 429 and 5xx are retried with backoff, any other 4xx is raised at once. */
  async request(method, path, { body, attempts = 4 } = {}) {
    const url = path.startsWith('http') ? path : `${ASC_HOST}${path}`
    let lastError = null
    for (let attempt = 1; attempt <= attempts; attempt++) {
      const response = await fetch(url, {
        method,
        headers: {
          Authorization: `Bearer ${this.token()}`,
          Accept: 'application/json',
          ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      })
      if (response.status === 204) return null
      const text = await response.text()
      const json = text ? safeJson(text) : null
      if (response.ok) return json

      const retryable = response.status === 429 || response.status >= 500
      lastError = new AscError(response.status, method, path, json ?? { errors: [{ detail: text.slice(0, 500) }] })
      if (!retryable || attempt === attempts) throw lastError
      const waitMs = 1000 * 2 ** attempt
      console.error(`[asc] ${method} ${path} → ${response.status}; retrying in ${waitMs / 1000}s`)
      await sleep(waitMs)
    }
    throw lastError
  }

  get(path) {
    return this.request('GET', path)
  }

  post(path, body) {
    return this.request('POST', path, { body })
  }

  /** Follows `links.next`: Apple pages silently, and a truncated list reads as complete. */
  async getAll(path) {
    const items = []
    let next = path
    while (next) {
      const page = await this.get(next)
      items.push(...(page?.data ?? []))
      next = page?.links?.next ?? null
    }
    return items
  }
}

function safeJson(text) {
  try {
    return JSON.parse(text)
  } catch {
    return null
  }
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

/** The app record for a bundle id, or null if App Store Connect has none. */
export async function findApp(client, bundleId) {
  const page = await client.get(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&limit=10`)
  // filter[bundleId] can match more than the exact id; confirm the string.
  return (page?.data ?? []).find((app) => app.attributes?.bundleId === bundleId) ?? null
}

/** The registered identifier (Certificates, Identifiers & Profiles) for a bundle id, or null. */
export async function findBundleId(client, identifier) {
  const page = await client.get(`/v1/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&limit=20`)
  return (page?.data ?? []).find((item) => item.attributes?.identifier === identifier) ?? null
}

/** `appVersionState` is current; `appStoreState` is its deprecated twin. */
export function versionState(version) {
  return version?.attributes?.appVersionState ?? version?.attributes?.appStoreState ?? null
}

/** States in which a version still accepts a new build. */
export const OPEN_VERSION_STATES = new Set([
  'PREPARE_FOR_SUBMISSION',
  'DEVELOPER_REJECTED',
  'REJECTED',
  'METADATA_REJECTED',
  'INVALID_BINARY',
])

/** Every iOS App Store version of an app (through the documented relationship endpoint). */
export async function listVersions(client, appId) {
  const versions = await client.getAll(
    `/v1/apps/${appId}/appStoreVersions?limit=50&fields[appStoreVersions]=versionString,appVersionState,appStoreState,platform`,
  )
  return versions.filter((version) => (version.attributes?.platform ?? 'IOS') === 'IOS')
}

/** Numeric comparison of dotted versions ("1.10.0" > "1.9"); missing parts count as zero. */
export function compareVersionStrings(a, b) {
  const pa = String(a).split('.').map((n) => Number.parseInt(n, 10) || 0)
  const pb = String(b).split('.').map((n) => Number.parseInt(n, 10) || 0)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0)
    if (d !== 0) return Math.sign(d)
  }
  return 0
}
