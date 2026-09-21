#!/usr/bin/env node
// Inserts (or replaces) one release's <item> in docs/appcast.xml, Sparkle's
// update feed. Run by .github/workflows/release.yml right after a release
// is notarized and its zip is signed with Sparkle's `sign_update` tool —
// this file is generated output, never hand-edited. Newest release is kept
// first. String-templated rather than pulling in an XML library since this
// script is the only thing that ever writes this file.
//
// Usage: node scripts/update-appcast.mjs --version 1.0.1 \
//   --url https://github.com/.../releases/download/v1.0.1/AIUsageMenuBar.zip \
//   --sig-attrs 'sparkle:edSignature="..." length="12345"'

import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const APPCAST_PATH = join(__dirname, '..', 'docs', 'appcast.xml');

function parseArgs() {
	const args = {};
	const argv = process.argv.slice(2);
	for (let i = 0; i < argv.length; i += 2) {
		args[argv[i].replace(/^--/, '')] = argv[i + 1];
	}
	return args;
}

const {
	version,
	url,
	'sig-attrs': sigAttrs,
	'minimum-system-version': minimumSystemVersion = '13.0',
} = parseArgs();

if (!version || !url || !sigAttrs) {
	console.error(
		'Usage: update-appcast.mjs --version X.Y.Z --url <zip url> --sig-attrs \'sparkle:edSignature="..." length="..."\''
	);
	process.exit(1);
}

const item = `    <item>
      <title>Version ${version}</title>
      <pubDate>${new Date().toUTCString()}</pubDate>
      <sparkle:minimumSystemVersion>${minimumSystemVersion}</sparkle:minimumSystemVersion>
      <enclosure url="${url}" sparkle:version="${version}" sparkle:shortVersionString="${version}" type="application/octet-stream" ${sigAttrs} />
    </item>\n`;

const xml = await readFile(APPCAST_PATH, 'utf8');

// Pull out every existing <item>, drop this version's if it's already there
// (re-running a tag republishes it), keep the rest, then prepend the new one.
const itemBlockPattern = /^ {4}<item>[\s\S]*?<\/item>\n/gm;
const remainingItems = [...xml.matchAll(itemBlockPattern)]
	.map((match) => match[0])
	.filter((block) => !block.includes(`sparkle:version="${version}"`));

const output = xml
	.replace(itemBlockPattern, '')
	// Match (and consume) the closing tag's own leading whitespace too, so it
	// doesn't end up prepended onto the newly-inserted item's indentation.
	.replace(/[ \t]*<\/channel>/, `${item}${remainingItems.join('')}  </channel>`);

await writeFile(APPCAST_PATH, output);
console.log(`docs/appcast.xml: added item for version ${version}`);
